// ignore_for_file: avoid_print

// sqlite3 真机构建验收（P3 L4）：经生产链路 preparePackBuildEnvironment + runPackBuild
// 真实 clone https://github.com/sqlite/sqlite.git；镜像无 CMakeLists.txt（已核实），
// 配方改用官方 amalgamation 源（sqlite.org 下载页解析最新 zip）构建 Release/Debug
// 双配置的 sqlite3.dll + 导入库并分类到 BUILD_OUT。
//
// 运行：$env:CNP_REAL_LIBRARY_BUILDS='sqlite3'; flutter test test/build/library_build_sqlite3_test.dart

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _libraryName = 'sqlite3';
const String _recipePath = 'test/build/library_recipes/sqlite3/build.py';

/// gated 运行开关：`CNP_REAL_LIBRARY_BUILDS` 含 `sqlite3` 或 `all` 才执行。
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
    return "设置 CNP_REAL_LIBRARY_BUILDS='sqlite3'（或 all）运行真实构建";
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

List<String> _sqlite3Dlls(String directoryPath) {
  return _filesWithExtension(
    directoryPath,
    '.dll',
  ).where((String name) => name.toLowerCase().startsWith('sqlite3')).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? gateReason = _gateReason();

  test(
    'sqlite3 真机构建：拉取源码 → amalgamation 下载 → Release/Debug 构建 → 分类入库',
    () async {
      final Stopwatch total = Stopwatch()..start();
      final Directory tempRoot = _createTempDir('cnp_lib_sqlite3_');
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
      final String mainHeaderPath = joinPath(includeDir, 'sqlite3.h');
      final String extensionHeaderPath = joinPath(includeDir, 'sqlite3ext.h');
      final List<String> releaseLibs = _filesWithExtension(
        joinPath(packDir.path, 'lib'),
        '.lib',
      );
      final List<String> releaseBins = _sqlite3Dlls(
        joinPath(packDir.path, 'bin'),
      );
      final List<String> debugLibs = _filesWithExtension(
        joinPath(packDir.path, 'debug/lib'),
        '.lib',
      );
      final List<String> debugBins = _sqlite3Dlls(
        joinPath(packDir.path, 'debug/bin'),
      );
      final String licensePath = joinPath(packDir.path, 'LICENSE.md');

      print(
        '[evidence] include/sqlite3.h=${File(mainHeaderPath).existsSync()}',
      );
      print(
        '[evidence] include/sqlite3ext.h=${File(extensionHeaderPath).existsSync()}',
      );
      print('[evidence] release.lib=$releaseLibs');
      print('[evidence] release.dll=$releaseBins');
      print('[evidence] debug.lib=$debugLibs');
      print('[evidence] debug.dll=$debugBins');
      print('[evidence] LICENSE.md=${File(licensePath).existsSync()}');
      print('[evidence] artifacts=${_relativeFiles(packDir.path)}');

      expect(
        File(mainHeaderPath).existsSync(),
        isTrue,
        reason: 'include/sqlite3.h 应存在',
      );
      expect(
        File(extensionHeaderPath).existsSync(),
        isTrue,
        reason: 'include/sqlite3ext.h 应存在',
      );
      expect(releaseLibs, isNotEmpty, reason: 'Release lib/ 应至少 1 个 .lib');
      expect(
        releaseBins,
        isNotEmpty,
        reason: 'Release bin/ 应至少 1 个 sqlite3*.dll',
      );
      expect(debugLibs, isNotEmpty, reason: 'debug/lib 应存在且含 .lib');
      expect(debugBins, isNotEmpty, reason: 'debug/bin 应存在且含 sqlite3*.dll');
      expect(
        File(licensePath).existsSync(),
        isTrue,
        reason: '镜像根 LICENSE.md 应经 stage_license 落 BUILD_OUT 根',
      );

      total.stop();
      print('[evidence] totalElapsed=${total.elapsed.inSeconds}s');
    },
    skip: gateReason,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
