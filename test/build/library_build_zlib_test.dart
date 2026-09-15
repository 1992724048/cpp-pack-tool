// ignore_for_file: avoid_print

// zlib 真机构建验收（P3 L1）：经生产链路 preparePackBuildEnvironment + runPackBuild
// 真实 clone https://github.com/madler/zlib.git，以本机编译器构建 Release/Debug
// 双配置并分类到 BUILD_OUT。
//
// 运行：$env:CNP_REAL_LIBRARY_BUILDS='zlib'; flutter test test/build/library_build_zlib_test.dart

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _libraryName = 'zlib';
const String _recipePath = 'test/build/library_recipes/zlib/build.py';

/// gated 运行开关：`CNP_REAL_LIBRARY_BUILDS` 含 `zlib` 或 `all` 才执行。
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
    return "设置 CNP_REAL_LIBRARY_BUILDS='zlib'（或 all）运行真实构建";
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
    'zlib 真机构建：拉取源码 → Release/Debug 构建 → 分类入库',
    () async {
      final Stopwatch total = Stopwatch()..start();
      final Directory tempRoot = _createTempDir('cnp_lib_zlib_');
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
        priority: const <String>['icx', 'clang', 'msvc'],
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
      final String releaseLibDir = joinPath(packDir.path, 'release/lib');
      final String releaseBinDir = joinPath(packDir.path, 'release/bin');
      final List<String> releaseLibs = _filesWithExtension(releaseLibDir, '.lib');
      final List<String> releaseBins = _filesWithExtension(releaseBinDir, '.dll');
      final List<String> debugLibs = _filesWithExtension(
        joinPath(packDir.path, 'debug/lib'),
        '.lib',
      );
      final List<String> debugBins = _filesWithExtension(
        joinPath(packDir.path, 'debug/bin'),
        '.dll',
      );
      final String licensePath = joinPath(packDir.path, 'LICENSE');

      final List<String> releaseTree = _relativeFiles(
        joinPath(packDir.path, 'release'),
      );
      final List<String> debugTree = _relativeFiles(
        joinPath(packDir.path, 'debug'),
      );

      print(
        '[evidence] include/zlib.h=${File(joinPath(includeDir, 'zlib.h')).existsSync()}',
      );
      print(
        '[evidence] include/zconf.h=${File(joinPath(includeDir, 'zconf.h')).existsSync()}',
      );
      print('[evidence] release.lib=$releaseLibs');
      print('[evidence] release.dll=$releaseBins');
      print('[evidence] debug.lib=$debugLibs');
      print('[evidence] debug.dll=$debugBins');
      print('[evidence] LICENSE=${File(licensePath).existsSync()}');
      print('[evidence] artifacts=${_relativeFiles(packDir.path)}');
      print('[evidence] release.tree=$releaseTree');
      print('[evidence] debug.tree=$debugTree');

      expect(
        File(joinPath(includeDir, 'zlib.h')).existsSync(),
        isTrue,
        reason: 'include/zlib.h 应存在',
      );
      expect(
        File(joinPath(includeDir, 'zconf.h')).existsSync(),
        isTrue,
        reason: 'include/zconf.h 应存在（CMake 生成版）',
      );
      expect(
        Directory(releaseLibDir).existsSync(),
        isTrue,
        reason: 'Release 产物应分层到 release/lib',
      );
      expect(
        releaseLibs,
        isNotEmpty,
        reason: 'release/lib 应至少 1 个 .lib',
      );
      expect(
        releaseBins,
        isNotEmpty,
        reason: 'release/bin 应至少 1 个 .dll',
      );
      expect(
        debugLibs,
        isNotEmpty,
        reason: 'debug/lib 应存在且含 .lib',
      );
      expect(debugBins, isNotEmpty, reason: 'debug/bin 应存在且含 .dll');
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
        reason: 'zlib 源根 LICENSE 应经 stage_license 落 BUILD_OUT 根',
      );

      // 纯度守卫：release 段只允许 Release 产物，杜绝 Debug 混入与去重改名残留。
      // 命名口径来自配方对上游 CMake 输出目标名的补丁（z/zs → zlib/zlibs）。
      expect(
        releaseLibs,
        <String>['zlib.lib', 'zlibs.lib'],
        reason: 'release/lib 精确集合：仅 Release 静态库（zlibs）与导入库（zlib）',
      );
      expect(
        releaseBins,
        <String>['zlib.dll'],
        reason: 'release/bin 精确集合：仅 Release 动态库',
      );
      expect(
        debugLibs,
        <String>['zlibd.lib', 'zlibsd.lib'],
        reason: 'debug/lib 精确集合：仅 Debug 静态库（zlibsd）与导入库（zlibd）',
      );
      expect(
        debugBins,
        <String>['zlibd.dll'],
        reason: 'debug/bin 精确集合：仅 Debug 动态库',
      );
      expect(
        releaseTree.where(
          (String path) => path.toLowerCase().endsWith('.pdb'),
        ),
        isEmpty,
        reason: 'release 段不得含 .pdb（调试符号属 Debug 配置）',
      );
      for (final String marker in <String>['zlibd', 'zlibsd', '_build-']) {
        expect(
          releaseTree.where(
            (String path) => baseName(path).toLowerCase().contains(marker),
          ),
          isEmpty,
          reason: 'release 段不得含 "$marker"（Debug 混入或去重改名残留）',
        );
      }
      expect(
        debugTree.where(
          (String path) => baseName(path).toLowerCase().contains('_build-'),
        ),
        isEmpty,
        reason: 'debug 段不得含去重改名残留',
      );

      total.stop();
      print('[evidence] totalElapsed=${total.elapsed.inSeconds}s');
    },
    skip: gateReason,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
