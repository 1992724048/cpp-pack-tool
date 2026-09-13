// ignore_for_file: avoid_print

// OpenVINO 预构建真机验收（P3 L6）：经生产链路 preparePackBuildEnvironment +
// runPackBuild 连跑两次配方——默认 tbb=off（不打包自带 TBB）与 tbb=on（完整保留），
// 第二次复用同一 cacheRoot（无重复大下载）。首次运行真实下载官方 Windows 预构建包
// （2026-09-13 实测 2026.3.1，约 208 MB）并验证 `# source: none` 不调用 git。
//
// 运行：$env:CNP_REAL_LIBRARY_BUILDS='openvino'; flutter test test/build/library_build_openvino_test.dart

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _libraryName = 'openvino';
const String _recipePath = 'test/build/library_recipes/openvino/build.py';

/// gated 运行开关：`CNP_REAL_LIBRARY_BUILDS` 含 `openvino` 或 `all` 才执行。
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
    return "设置 CNP_REAL_LIBRARY_BUILDS='openvino'（或 all）运行真实构建";
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

/// 解压标记绑定的驱动脚本（无需联网）：造小归档 → 调 ensure_unpacked，
/// 覆盖首次解压、同名复用与归档换名后重解压。
const String _unpackMarkerDriverPath =
    'test/build/library_recipes/openvino/unpack_marker_driver.py';

List<String>? _probePython() {
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
        return candidate;
      }
    } on ProcessException {
      // 当前候选不可用，继续探测下一个。
    }
  }
  return null;
}

/// 在临时目录驱动一次 `ensure_unpacked`（配方副本 + 辅助模块 + 驱动脚本），
/// 返回进程结果。
ProcessResult _runUnpackMarkerDriver() {
  final List<String> python = _probePython()!;
  final Directory temp = _createTempDir('cnp_openvino_marks_');
  File(
    joinPath(temp.path, 'build.py'),
  ).writeAsStringSync(File(_recipePath).readAsStringSync(), flush: true);
  File(joinPath(temp.path, 'cnp_build_support.py')).writeAsStringSync(
    File('assets/build/cnp_build_support.py').readAsStringSync(),
    flush: true,
  );
  File(joinPath(temp.path, 'driver.py')).writeAsStringSync(
    File(_unpackMarkerDriverPath).readAsStringSync(),
    flush: true,
  );
  return Process.runSync(
    python.first,
    <String>[...python.sublist(1), 'driver.py'],
    workingDirectory: temp.path,
  );
}

/// 进程执行器包装：转发 `Process.run`、记录调用并打印命令/退出码/耗时；
/// 构建脚本的 stdout/stderr（含 cnp_build_support 证据行）全量输出并留档。
PackProcessRunner _teeRunner(
  List<String> processLog,
  List<String> buildOutputs,
) {
  return (
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
    processLog.add(invocation);
    print(
      '[evidence] process=$invocation '
      'exitCode=${result.exitCode} elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    if (_isBuildScriptInvocation(executable)) {
      final String output = '${result.stdout}\n${result.stderr}'.trim();
      buildOutputs.add(output);
      print('[evidence] build.py output:');
      print(output);
    }
    return result;
  };
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

List<String> _relativeFilesWithExtension(String root, String extension) {
  final String suffix = extension.toLowerCase();
  return _relativeFiles(
    root,
  ).where((String path) => path.toLowerCase().endsWith(suffix)).toList();
}

/// 跑一次配方：写 build.py → 准备环境（声明的工具/选项）→ runPackBuild。
Future<void> _runRecipe({
  required String label,
  required Directory packDir,
  required Directory cacheRoot,
  required Map<String, String> buildOptions,
  required List<String> processLog,
  required List<String> buildOutputs,
}) async {
  final String recipe = File(_recipePath).readAsStringSync();
  File(
    joinPath(packDir.path, 'build.py'),
  ).writeAsStringSync(recipe, flush: true);

  final PackModel pack = PackModel(
    name: _libraryName,
    version: '1.0.0',
    author: 'cnp-test',
    sourcePath: packDir.path,
  );
  pack.files.add(
    FileModel(name: 'build.py', path: 'build.py', size: recipe.length),
  );
  pack.buildOptions = Map<String, String>.of(buildOptions);

  final BuildEnvironment env = await preparePackBuildEnvironment(
    pack,
    priority: const <String>['icx', 'clang-cl', 'msvc'],
    toolsRoot: 'tools',
    loadSupportModule: _loadSupportModule,
  );
  print(
    '[evidence][$label] compiler=${compilerKindId(env.compiler.kind)} '
    '${env.compiler.version}',
  );
  print(
    '[evidence][$label] CNP_COMPILER_KIND=${env.environment['CNP_COMPILER_KIND']}',
  );
  print('[evidence][$label] CNP_OPTION_TBB=${env.environment['CNP_OPTION_TBB']}');
  print('[evidence][$label] packDir=${packDir.path}');

  await runPackBuild(
    pack,
    (PackBuildStage stage) => print('[evidence][$label] stage=$stage'),
    processRunner: _teeRunner(processLog, buildOutputs),
    cacheRoot: cacheRoot.path,
    environment: env.environment,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? gateReason = _gateReason();
  final List<String>? python = _probePython();

  test(
    '解压标记绑定归档：同名复用、归档换名后重解压（无需联网）',
    () {
      final ProcessResult result = _runUnpackMarkerDriver();
      print('[evidence] marker stdout=${result.stdout.toString().trim()}');
      print('[evidence] marker stderr=${result.stderr.toString().trim()}');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(stdout, contains('reuse unpacked tree'));
      expect(stdout, contains('stale unpacked tree'));
      expect(stdout, contains('re-extracting'));
    },
    skip: python == null ? '未检测到可用的 Python（python / py -3 均不可用）' : null,
  );

  test(
    'OpenVINO 预构建真机：source:none 下载分类 + tbb off/on 两路径',
    () async {
      final Stopwatch total = Stopwatch()..start();
      final Directory tempRoot = _createTempDir('cnp_lib_openvino_');
      final Directory cacheRoot = Directory(joinPath(tempRoot.path, 'cache'))
        ..createSync(recursive: true);
      final Directory packOff = Directory(joinPath(tempRoot.path, 'pack-off'))
        ..createSync(recursive: true);
      final Directory packOn = Directory(joinPath(tempRoot.path, 'pack-on'))
        ..createSync(recursive: true);
      final List<String> processLog = <String>[];
      final List<String> buildOutputs = <String>[];

      final Stopwatch first = Stopwatch()..start();
      await _runRecipe(
        label: 'off',
        packDir: packOff,
        cacheRoot: cacheRoot,
        buildOptions: <String, String>{},
        processLog: processLog,
        buildOutputs: buildOutputs,
      );
      first.stop();
      print('[evidence] offElapsed=${first.elapsed.inSeconds}s');

      expect(
        processLog.where((String call) => call.startsWith('git ')),
        isEmpty,
        reason: '# source: none 不应调用 git',
      );
      expect(buildOutputs, hasLength(1), reason: '第一遍应只有一次构建进程输出');
      expect(
        buildOutputs.single,
        contains('downloading:'),
        reason: '首次运行应真实下载归档',
      );
      expect(buildOutputs.single, contains('downloaded: bytes='));

      final Directory downloadsDir = Directory(
        joinPath(cacheRoot.path, 'build/openvino/downloads'),
      );
      final List<File> archives = downloadsDir.existsSync()
          ? downloadsDir
                .listSync()
                .whereType<File>()
                .where((File file) => file.path.toLowerCase().endsWith('.zip'))
                .toList()
          : <File>[];
      expect(archives, hasLength(1), reason: '归档应缓存到 SRC_PATH/downloads');
      final int archiveBytes = archives.single.lengthSync();
      print(
        '[evidence] cachedArchive=${baseName(archives.single.path)} '
        'bytes=$archiveBytes',
      );
      expect(
        archiveBytes,
        greaterThan(100 * 1024 * 1024),
        reason: 'OpenVINO 归档应为 100MB 级',
      );

      final List<String> offAll = _relativeFiles(packOff.path);
      final List<String> offHeaders = offAll
          .where((String path) {
            final String lowered = path.toLowerCase();
            return lowered.endsWith('.h') ||
                lowered.endsWith('.hpp') ||
                lowered.endsWith('.hxx');
          })
          .toList();
      final List<String> offLibs = _relativeFilesWithExtension(
        joinPath(packOff.path, 'release/lib'),
        '.lib',
      );
      final List<String> offBins = _relativeFilesWithExtension(
        joinPath(packOff.path, 'release/bin'),
        '.dll',
      );
      final List<String> offDebugLibs = _relativeFilesWithExtension(
        joinPath(packOff.path, 'debug/lib'),
        '.lib',
      );
      final List<String> offDebugBins = _relativeFilesWithExtension(
        joinPath(packOff.path, 'debug/bin'),
        '.dll',
      );
      final List<String> offTbb = offAll
          .where((String path) => path.toLowerCase().contains('tbb'))
          .toList();
      final String offLicense = joinPath(packOff.path, 'LICENSE');

      print(
        '[evidence] off.mainHeader='
        '${File(joinPath(packOff.path, 'include/openvino/openvino.hpp')).existsSync()}',
      );
      print(
        '[evidence] off.headers=${offHeaders.length} libs=${offLibs.length} '
        'bins=${offBins.length} debugLibs=${offDebugLibs.length} '
        'debugBins=${offDebugBins.length}',
      );
      print('[evidence] off.tbbFiles=$offTbb');
      print('[evidence] off.license=${File(offLicense).existsSync()}');
      print('[evidence] off.lib=${offLibs.take(3).toList()}…');
      print('[evidence] off.bin=${offBins.take(3).toList()}…');

      expect(
        File(joinPath(packOff.path, 'include/openvino/openvino.hpp')).existsSync(),
        isTrue,
        reason: 'include/openvino/openvino.hpp 应存在',
      );
      expect(
        offHeaders.length,
        greaterThanOrEqualTo(100),
        reason: 'OpenVINO 头文件应大量入库',
      );
      expect(
        offLibs,
        isNotEmpty,
        reason: 'Release release/lib 应至少 1 个 .lib',
      );
      expect(
        offBins,
        isNotEmpty,
        reason: 'Release release/bin 应至少 1 个 .dll',
      );
      expect(
        offDebugLibs,
        isNotEmpty,
        reason: '预构建包含 Debug 产物 → debug/lib 应非空',
      );
      expect(
        offDebugBins,
        isNotEmpty,
        reason: '预构建包含 Debug 产物 → debug/bin 应非空',
      );
      expect(offTbb, isEmpty, reason: 'tbb=off 时路径含 tbb 的文件应为 0');
      expect(
        Directory(joinPath(packOff.path, 'lib')).existsSync(),
        isFalse,
        reason: '库类产物不得落 BUILD_OUT 根（打包侧识别 release 分层）',
      );
      expect(
        Directory(joinPath(packOff.path, 'bin')).existsSync(),
        isFalse,
        reason: '库类产物不得落 BUILD_OUT 根（打包侧识别 release 分层）',
      );
      expect(
        File(offLicense).existsSync(),
        isTrue,
        reason: 'Apache-2.0 LICENSE 应落 BUILD_OUT 根',
      );

      final Stopwatch second = Stopwatch()..start();
      await _runRecipe(
        label: 'on',
        packDir: packOn,
        cacheRoot: cacheRoot,
        buildOptions: <String, String>{'tbb': 'on'},
        processLog: processLog,
        buildOutputs: buildOutputs,
      );
      second.stop();
      print('[evidence] onElapsed=${second.elapsed.inSeconds}s');

      final List<String> onAll = _relativeFiles(packOn.path);
      final List<String> onTbb =
          onAll
              .where((String path) => path.toLowerCase().contains('tbb'))
              .toList()
            ..sort();
      final List<String> onTbbDlls = _relativeFilesWithExtension(
        joinPath(packOn.path, 'release/bin'),
        '.dll',
      ).where((String path) => baseName(path).toLowerCase().startsWith('tbb')).toList();

      print(
        '[evidence] on.tbbFiles(count=${onTbb.length})='
        '${onTbb.where((String path) => path.contains('.')).take(10).toList()}…',
      );
      print('[evidence] on.tbbDlls=$onTbbDlls');
      print(
        '[evidence] on.tbbHeader='
        '${File(joinPath(packOn.path, 'include/tbb/tbb.h')).existsSync()} '
        'tbbLib='
        '${File(joinPath(packOn.path, 'release/lib/tbb12.lib')).existsSync()} '
        'tbbLicense='
        '${File(joinPath(packOn.path, 'TBB-LICENSE')).existsSync()}',
      );
      print(
        '[evidence] on.vsOff artifacts: off=${offAll.length} on=${onAll.length}',
      );

      expect(buildOutputs, hasLength(2));
      expect(
        buildOutputs[1],
        contains('reuse cached archive'),
        reason: '第二次运行应复用已下载归档（无大下载）',
      );
      expect(
        buildOutputs[1],
        contains('reuse unpacked tree'),
        reason: '第二次运行应复用已解压树',
      );
      final File marker = File(
        joinPath(cacheRoot.path, 'build/openvino/unpacked/.complete'),
      );
      expect(
        marker.existsSync() &&
            marker.readAsStringSync().trim() == baseName(archives.single.path),
        isTrue,
        reason: '解压标记应绑定归档文件名（版本升级后触发重解压）',
      );
      expect(onTbb, isNotEmpty, reason: 'tbb=on 时应保留自带 TBB 文件');
      expect(
        File(joinPath(packOn.path, 'release/bin/tbb12.dll')).existsSync(),
        isTrue,
        reason: 'TBB 运行库应入 release/bin/（Release 分层）',
      );
      expect(
        File(joinPath(packOn.path, 'include/tbb/tbb.h')).existsSync(),
        isTrue,
        reason: 'TBB 头文件应入 include/tbb/',
      );
      expect(
        File(joinPath(packOn.path, 'release/lib/tbb12.lib')).existsSync(),
        isTrue,
        reason: 'TBB 导入库应入 release/lib/（Release 分层）',
      );
      expect(
        Directory(joinPath(packOn.path, 'lib')).existsSync(),
        isFalse,
        reason: '库类产物不得落 BUILD_OUT 根（打包侧识别 release 分层）',
      );
      expect(
        Directory(joinPath(packOn.path, 'bin')).existsSync(),
        isFalse,
        reason: '库类产物不得落 BUILD_OUT 根（打包侧识别 release 分层）',
      );
      expect(
        File(joinPath(packOn.path, 'TBB-LICENSE')).existsSync(),
        isTrue,
        reason: 'TBB 许可证应随包',
      );

      total.stop();
      print('[evidence] totalElapsed=${total.elapsed.inSeconds}s');
    },
    skip: gateReason,
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
