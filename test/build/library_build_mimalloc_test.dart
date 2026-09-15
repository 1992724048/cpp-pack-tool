// ignore_for_file: avoid_print

// mimalloc 真机构建验收（P3 L5）：经生产链路 preparePackBuildEnvironment + runPackBuild
// 真实 clone https://github.com/microsoft/mimalloc.git（默认分支 main3），以本机编译器
// 构建 Release/Debug 双配置并分类到 BUILD_OUT（release/lib|bin + debug/lib|bin），另断言
// 预构建工具 minject.exe 入 release/bin 与 debug/bin、根目录生成 post.bat 注入脚本。
//
// 运行：$env:CNP_REAL_LIBRARY_BUILDS='mimalloc'; flutter test test/build/library_build_mimalloc_test.dart

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _libraryName = 'mimalloc';
const String _recipePath = 'test/build/library_recipes/mimalloc/build.py';

/// gated 运行开关：`CNP_REAL_LIBRARY_BUILDS` 含 `mimalloc` 或 `all` 才执行。
String? _gateReason() {
  if (!Platform.isWindows) {
    return '仅 Windows 平台执行（依赖本机编译器与 CMake/Ninja 供给）';
  }
  final List<String> selected =
      (Platform.environment['CNP_REAL_LIBRARY_BUILDS'] ?? '')
          .split(',')
          .map((String value) => value.trim().toLowerCase())
          .where((String value) => value.isNotEmpty)
          .toList();
  if (!selected.contains(_libraryName) && !selected.contains('all')) {
    return "设置 CNP_REAL_LIBRARY_BUILDS='mimalloc'（或 all）运行真实构建";
  }
  return null;
}

Future<String> _loadSupportModule() async {
  try {
    return await rootBundle.loadString('assets/build/cnp_build_support.py');
  } catch (_) {
    return File('assets/build/cnp_build_support.py').readAsStringSync();
  }
}

/// 进程执行器包装：转发 `Process.run` 并打印命令/退出码/耗时；构建脚本的
/// stdout/stderr（含 traceback 与 cnp_build_support 证据行）全量输出。
Future<ProcessResult> _teeProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  final ProcessResult result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  stopwatch.stop();
  final String invocation = arguments.isEmpty
      ? executable
      : '$executable ${arguments.join(' ')}';
  print(
    '[evidence] process=$invocation '
    'exitCode=${result.exitCode} elapsed=${stopwatch.elapsedMilliseconds}ms',
  );
  if (_isBuildScriptInvocation(executable)) {
    final String output = '${result.stdout}\n${result.stderr}'.trim();
    print('[evidence] build.py output:');
    print(output);
  }
  return result;
}

bool _isBuildScriptInvocation(String executable) {
  final String name = baseName(executable).toLowerCase();
  return name.startsWith('python') || name == 'py' || name == 'py.exe';
}

Directory _createTempDir(String prefix) {
  final Directory directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

List<String> _filesWithExtension(String directoryPath, String extension) {
  final Directory directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    return <String>[];
  }
  final String suffix = extension.toLowerCase();
  final List<String> files =
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.toLowerCase().endsWith(suffix))
          .map((File file) => baseName(file.path))
          .toList()
        ..sort();
  return files;
}

/// 输出树中的相对文件路径列表（`/` 分隔、排序）；目录不存在时为空。
List<String> _relativeFiles(String root) {
  final Directory directory = Directory(root);
  if (!directory.existsSync()) {
    return <String>[];
  }
  final List<String> files =
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (File file) => file.path
                .substring(root.length + 1)
                .replaceAll(Platform.pathSeparator, '/'),
          )
          .toList()
        ..sort();
  return files;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? gateReason = _gateReason();

  test(
    'mimalloc 真机构建：拉取源码 → Release/Debug 分层构建 → minject/post.bat 入库',
    () async {
      final Stopwatch total = Stopwatch()..start();
      final Directory tempRoot = _createTempDir('cnp_lib_mimalloc_');
      final Directory packDir = Directory(joinPath(tempRoot.path, 'pack'))
        ..createSync(recursive: true);
      final Directory cacheRoot = Directory(joinPath(tempRoot.path, 'cache'))
        ..createSync(recursive: true);

      final String recipe = File(_recipePath).readAsStringSync();
      final File buildScript = File(joinPath(packDir.path, 'build.py'));
      buildScript.writeAsStringSync(recipe, flush: true);

      final PackModel pack = PackModel(
        name: _libraryName,
        version: '1.0.0',
        author: 'cnp-test',
        sourcePath: packDir.path,
      );
      pack.files.add(
        FileModel(name: 'build.py', path: 'build.py', size: recipe.length),
      );

      final BuildEnvironment env = await preparePackBuildEnvironment(
        pack,
        priority: const <String>['icx', 'clang-cl', 'msvc'],
        toolsRoot: 'tools',
        loadSupportModule: _loadSupportModule,
      );
      print('[evidence] compiler.kind=${compilerKindId(env.compiler.kind)}');
      print('[evidence] compiler.version=${env.compiler.version}');
      print('[evidence] compiler.executable=${env.compiler.executablePath}');
      print(
        '[evidence] compiler.environmentScript=${env.compiler.environmentScript}',
      );
      print(
        '[evidence] CNP_COMPILER_KIND=${env.environment['CNP_COMPILER_KIND']}',
      );
      print('[evidence] CNP_CMAKE=${env.environment['CNP_CMAKE']}');
      print('[evidence] CNP_NINJA=${env.environment['CNP_NINJA']}');
      print('[evidence] env.cmakePath=${env.cmakePath}');
      print('[evidence] env.ninjaPath=${env.ninjaPath}');
      print('[evidence] env.toolsDir=${env.toolsDir}');
      print('[evidence] packDir=${packDir.path}');

      await runPackBuild(
        pack,
        (PackBuildStage stage) => print('[evidence] stage=$stage'),
        processRunner: _teeProcessRunner,
        cacheRoot: cacheRoot.path,
        environment: env.environment,
      );

      final String includeDir = joinPath(packDir.path, 'include');
      final List<String> releaseLibs = _filesWithExtension(
        joinPath(packDir.path, 'release/lib'),
        '.lib',
      );
      final List<String> releaseBins = _filesWithExtension(
        joinPath(packDir.path, 'release/bin'),
        '.dll',
      );
      final List<String> debugLibs = _filesWithExtension(
        joinPath(packDir.path, 'debug/lib'),
        '.lib',
      );
      final List<String> debugBins = _filesWithExtension(
        joinPath(packDir.path, 'debug/bin'),
        '.dll',
      );
      final String licensePath = joinPath(packDir.path, 'LICENSE');
      final String releaseMinjectPath = joinPath(
        packDir.path,
        'release/bin/minject.exe',
      );
      final String debugMinjectPath = joinPath(
        packDir.path,
        'debug/bin/minject.exe',
      );
      final String postBatPath = joinPath(packDir.path, 'post.bat');
      final String postBatContent = File(postBatPath).existsSync()
          ? File(postBatPath).readAsStringSync()
          : '';

      print(
        '[evidence] include/mimalloc.h=${File(joinPath(includeDir, 'mimalloc.h')).existsSync()}',
      );
      print(
        '[evidence] include/mimalloc/types.h=${File(joinPath(includeDir, 'mimalloc/types.h')).existsSync()}',
      );
      print('[evidence] release.lib=$releaseLibs');
      print('[evidence] release.dll=$releaseBins');
      print('[evidence] debug.lib=$debugLibs');
      print('[evidence] debug.dll=$debugBins');
      print(
        '[evidence] release/bin/minject.exe=${File(releaseMinjectPath).existsSync()}',
      );
      print(
        '[evidence] debug/bin/minject.exe=${File(debugMinjectPath).existsSync()}',
      );
      print('[evidence] post.bat=${File(postBatPath).existsSync()}');
      print('[evidence] post.bat content:');
      print(postBatContent.trim());
      print('[evidence] LICENSE=${File(licensePath).existsSync()}');
      print('[evidence] artifacts=${_relativeFiles(packDir.path)}');

      expect(
        File(joinPath(includeDir, 'mimalloc.h')).existsSync(),
        isTrue,
        reason: 'include/mimalloc.h 应存在（主头，stage_headers 镜像）',
      );
      expect(
        File(joinPath(includeDir, 'mimalloc/types.h')).existsSync(),
        isTrue,
        reason: 'include/mimalloc/types.h 应存在（mimalloc/ 子目录镜像）',
      );
      expect(
        releaseLibs,
        contains('mimalloc.lib'),
        reason: 'Release release/lib 应含静态库 mimalloc.lib',
      );
      expect(
        releaseLibs,
        contains('mimalloc.dll.lib'),
        reason: 'Release release/lib 应含共享库导入库 mimalloc.dll.lib',
      );
      expect(
        releaseBins,
        contains('mimalloc.dll'),
        reason: 'Release release/bin 应含 mimalloc.dll',
      );
      expect(
        releaseBins,
        contains('mimalloc-redirect.dll'),
        reason:
            'Release release/bin 应含 mimalloc-redirect.dll（MI_WIN_REDIRECT 构建期复制）',
      );
      expect(debugLibs, isNotEmpty, reason: 'debug/lib 应存在且含 .lib');
      expect(debugBins, isNotEmpty, reason: 'debug/bin 应存在且含 .dll');
      expect(
        File(releaseMinjectPath).existsSync(),
        isTrue,
        reason: 'release/bin/minject.exe 应存在（仓库预构建 x64 工具入包）',
      );
      expect(
        File(debugMinjectPath).existsSync(),
        isTrue,
        reason: 'debug/bin/minject.exe 应存在（工具与配置无关，双落位）',
      );
      expect(
        File(postBatPath).existsSync(),
        isTrue,
        reason: 'BUILD_OUT 根应生成 post.bat（消费方注入入口）',
      );
      expect(
        postBatContent.contains('minject.exe'),
        isTrue,
        reason: 'post.bat 应调用包内 minject.exe',
      );
      expect(
        postBatContent.contains(r'%~1'),
        isTrue,
        reason: 'post.bat 应以 %~1 为消费者目标可执行文件路径',
      );
      expect(
        postBatContent.contains(r'release\bin\minject.exe'),
        isTrue,
        reason: 'post.bat 应引用 release/bin/minject.exe 落位',
      );
      expect(
        postBatContent.contains('exit /b 0'),
        isTrue,
        reason: 'post.bat 注入失败不阻断构建（恒 exit /b 0）',
      );
      expect(
        Directory(joinPath(packDir.path, 'lib')).existsSync(),
        isFalse,
        reason: '库类产物不得落 BUILD_OUT 根（打包侧识别 release 分层）',
      );
      expect(
        Directory(joinPath(packDir.path, 'bin')).existsSync(),
        isFalse,
        reason: '库类产物不得落 BUILD_OUT 根（打包侧识别 release 分层）',
      );
      expect(
        File(licensePath).existsSync(),
        isTrue,
        reason: 'mimalloc 源根 LICENSE（MIT）应经 stage_license 落 BUILD_OUT 根',
      );

      total.stop();
      print('[evidence] totalElapsed=${total.elapsed.inSeconds}s');
    },
    skip: gateReason,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
