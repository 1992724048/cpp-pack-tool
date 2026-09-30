import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/compiler_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/nuget/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/pack/file_scan.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:flutter_test/flutter_test.dart';

const String _targetsEntry = 'build/native/demo.targets';

/// 1×1 透明 PNG，供导出替代真实图标渲染（与 `nupkg_exporter_test` 同款）。
final Uint8List _fakeIconPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 最小配方：产物落点与源码区**只**认 `CNP_*`，不硬编码任何绝对路径，也不
/// 依赖子进程工作目录。
const String _recipe = '''
import os
import shutil

root = os.environ['CNP_PACKAGE_ROOT']
src = os.environ['CNP_SRC_DIR']

for folder in ('include', 'lib', 'src'):
    os.makedirs(os.path.join(root, folder), exist_ok=True)
for name, folder in (('demo.h', 'include'), ('demo.lib', 'lib'),
                     ('demo.dll', 'lib'), ('main.cpp', 'src')):
    shutil.copyfile(os.path.join(src, name), os.path.join(root, folder, name))
print('CNP_PACKAGE_ROOT=' + root)
print('CNP_SRC_DIR=' + src)
''';

/// 配方种子：`CNP_SRC_DIR` 下由软件放好的「源码」，构建前的既有状态。
const Map<String, String> _seeds = <String, String>{
  'demo.h': '#pragma once\n',
  'demo.lib': 'MZlib',
  'demo.dll': 'MZdll',
  'main.cpp': 'int main() {}\n',
};

void main() {
  final Object? pythonSkipReason = _pythonSkipReason();

  test('一个最小配方产出的 .nupkg 结构正确：include 与 files 分类与 runtimes 都对', () async {
    final Directory root = Directory.systemTemp.createTempSync('cnp-e2e-');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    // 包源目录固定名 `demo`：include 命名空间取自包源目录名，包内路径才稳定。
    final String packageRoot = joinPath(root.path, 'demo');
    Directory(packageRoot).createSync(recursive: true);
    File(joinPath(packageRoot, 'build.py')).writeAsStringSync(_recipe);
    final String sourceArea = packSourceDirectory(packageRoot);
    Directory(sourceArea).createSync(recursive: true);
    for (final MapEntry<String, String> seed in _seeds.entries) {
      File(joinPath(sourceArea, seed.key)).writeAsStringSync(seed.value);
    }

    final PackModel pack = _pack(packageRoot);
    final BuildEnvironment env = assembleBuildEnvironment(
      compiler: _fakeCompiler,
      environment: Platform.environment,
      toolsRoot: joinPath(root.path, 'tools'),
      packageRoot: packageRoot,
    );

    // 1) 真实构建：真实 python 子进程、真实工作目录、真实 CNP_* 注入。
    await runPackBuildStreaming(pack, environment: env.environment);

    expect(
      File(joinPath(packageRoot, 'include/demo.h')).existsSync(),
      isTrue,
      reason: '配方产物应落到包源目录（靠 CNP_PACKAGE_ROOT 定位）',
    );
    expect(File(joinPath(packageRoot, 'lib/demo.lib')).existsSync(), isTrue);
    expect(File(joinPath(packageRoot, 'lib/demo.dll')).existsSync(), isTrue);
    expect(File(joinPath(packageRoot, 'src/main.cpp')).existsSync(), isTrue);

    // 2) 构建后按生产链路重新扫描源目录，再走真实导出。
    pack.files = await FileScan.scan(packageRoot);
    final PackageExportResult result = await exportNuGetPackage(
      pack,
      joinPath(root.path, 'out'),
      iconResolver: (PackModel pack) async => _fakeIconPng,
    );

    // 3) 断言全部落在导出的 zip 内容上。
    final Archive archive = ZipDecoder().decodeBytes(
      File(result.outputPath).readAsBytesSync(),
    );
    final List<String> entries = archive.files
        .map((ArchiveFile file) => file.name)
        .toList();

    expect(entries, hasLength(10), reason: '包内条目不多不少：4 份产物 + nuspec/targets + OPC 三件套 + 图标');
    expect(entries, containsAll(<String>[
      'build/native/include/demo/demo.h',
      'build/native/files/library/demo.lib',
      'build/native/files/library/demo.dll',
      'build/native/files/source/src/main.cpp',
      _targetsEntry,
    ]));
    expect(
      entries,
      isNot(contains('build/native/files/build.py')),
      reason: 'build.py 是配方入口，不进包',
    );

    expect(
      _textOf(archive, 'build/native/include/demo/demo.h'),
      '#pragma once\n',
      reason: '包内载荷应是配方产出的字节，而非种子目录里的残留',
    );
    expect(
      _textOf(archive, 'build/native/files/library/demo.lib'),
      'MZlib',
      reason: '静态库按二进制原样入包',
    );
    expect(
      _textOf(archive, 'build/native/files/source/src/main.cpp'),
      'int main() {}\n',
    );

    final String targets = _textOf(archive, _targetsEntry);
    expect(
      targets,
      contains(r'$(MSBuildThisFileDirectory)include'),
      reason: '.targets 应把包内 include 目录交给消费者编译器',
    );
    expect(
      targets,
      contains(r'$(MSBuildThisFileDirectory)files\library'),
      reason: r'.targets 应把包内 files\library 目录交给消费者链接器',
    );
    expect(targets, contains('demo.lib'));
    expect(
      targets,
      contains(
        r'PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)files\library\demo.dll"',
      ),
      reason: 'files/library 下的 dll 应作为运行时二进制随包部署',
    );
  }, skip: pythonSkipReason);

  test('nupkg 内载荷按 FileType 分类落位且 build/native/lib 不再存在', () async {
    final Directory root = Directory.systemTemp.createTempSync('cnp-e2e-classify-');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    // 源目录固定名 `demo`：include 命名空间取自包源目录名，包内路径才稳定。
    final String source = joinPath(root.path, 'demo');
    const Map<String, String> sources = <String, String>{
      'src/a.cpp': 'int a() {}\n',
      'lib/x64/foo.lib': 'MZlib',
      'bin/bar.dll': 'MZdll',
      'res/app.rc': '1 ICON "app.ico"\n',
      'res/app.ico': 'ICO',
      'tools/pre.bat': '@echo off\n',
      'include/demo/demo.h': '#pragma once\n',
      'LICENSE': 'MIT\n',
    };
    for (final MapEntry<String, String> entry in sources.entries) {
      final String absolute = joinPath(source, entry.key);
      Directory(parentDirectory(absolute)).createSync(recursive: true);
      File(absolute).writeAsStringSync(entry.value);
    }

    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      license: 'MIT',
      sourcePath: source,
    )..files = await FileScan.scan(source);

    final PackageExportResult result = await exportNuGetPackage(
      pack,
      joinPath(root.path, 'out'),
      iconResolver: (PackModel pack) async => _fakeIconPng,
    );
    final Archive archive = ZipDecoder().decodeBytes(
      File(result.outputPath).readAsBytesSync(),
    );
    final Set<String> names = archive.files
        .map((ArchiveFile file) => file.name)
        .toSet();

    expect(
      names,
      containsAll(<String>[
        'build/native/files/source/src/a.cpp',
        'build/native/files/library/x64/foo.lib',
        'build/native/files/library/bar.dll',
        'build/native/files/resource/res/app.rc',
        'build/native/files/resource/res/app.ico',
        'build/native/files/script/tools/pre.bat',
        'build/native/include/demo/demo.h',
        'build/native/files/LICENSE',
      ]),
    );
    expect(
      names.any((String name) => name.startsWith('build/native/lib/')),
      isFalse,
      reason: 'build/native/lib/ 已取消',
    );
  });
}

/// 编译器的可执行文件与本测试无关（配方不做真实编译），只需一个合法条目供
/// `assembleBuildEnvironment` 拼 `CNP_COMPILER` 与 PATH。
const DetectedCompiler _fakeCompiler = DetectedCompiler(
  kind: CompilerKind.clangCl,
  version: '18.1.8',
  executablePath: r'C:\fake\toolchain\clang-cl.exe',
  environmentScript: null,
);

PackModel _pack(String sourcePath) {
  return PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      description: '端到端演示包',
      license: 'MIT',
      sourcePath: sourcePath,
    )
      ..files = <FileModel>[
        FileModel(name: 'build.py', path: 'build.py', size: 0),
      ];
}

/// 真实进程测试的跳过原因（与 `build_runner_test` 口径一致）：
/// 非 Windows 或无可用 Python（`python` / `py -3`）时返回文案，否则 null。
Object? _pythonSkipReason() {
  if (!Platform.isWindows) {
    return '仅 Windows 平台执行（依赖真实 Python 进程）';
  }
  for (final List<String> candidate in <List<String>>[
    <String>['python'],
    <String>['py', '-3'],
  ]) {
    try {
      final ProcessResult result = Process.runSync(candidate.first, <String>[
        ...candidate.sublist(1),
        '--version',
      ]);
      if (result.exitCode == 0) {
        return null;
      }
    } on ProcessException {
      // 当前候选不可用，继续探测下一个。
    }
  }
  return '未检测到可用的 Python（python / py -3 均不可用）';
}

String _textOf(Archive archive, String name) =>
    utf8.decode(_bytesOf(archive, name));

List<int> _bytesOf(Archive archive, String name) =>
    archive.files.firstWhere((ArchiveFile file) => file.name == name).content;
