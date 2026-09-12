// ignore_for_file: avoid_print

// googletest 真机验收（P3 L3）：经生产链路 preparePackBuildEnvironment + runPackBuild
// 真实 clone https://github.com/google/googletest.git，以源码分发配方分类头文件与源码
// （不编译、无 lib/dll），断言 include/gtest/**、include/gmock/**、src/gtest/**、
// src/gmock/** 与根 LICENSE 落位。
//
// 运行：$env:CNP_REAL_LIBRARY_BUILDS='gtest'; flutter test test/build/library_build_gtest_test.dart

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _libraryName = 'gtest';
const String _recipePath = 'test/build/library_recipes/gtest/build.py';

/// gated 运行开关：`CNP_REAL_LIBRARY_BUILDS` 含 `gtest` 或 `all` 才执行。
String? _gateReason() {
  if (!Platform.isWindows) {
    return '仅 Windows 平台执行（依赖生产链路的环境准备）';
  }
  final List<String> selected =
      (Platform.environment['CNP_REAL_LIBRARY_BUILDS'] ?? '')
          .split(',')
          .map((String value) => value.trim().toLowerCase())
          .where((String value) => value.isNotEmpty)
          .toList();
  if (!selected.contains(_libraryName) && !selected.contains('all')) {
    return "设置 CNP_REAL_LIBRARY_BUILDS='gtest'（或 all）运行真实构建";
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
/// stdout/stderr（含 cnp_build_support 证据行）全量输出。
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

/// [root] 下指定扩展名的相对路径列表（扩展名不区分大小写）。
List<String> _relativeWithExtension(String root, String extension) {
  final String suffix = extension.toLowerCase();
  return _relativeFiles(root)
      .where((String path) => path.toLowerCase().endsWith(suffix))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? gateReason = _gateReason();

  test(
    'googletest 真机验收：拉取源码 → 源码分发分类 → include 与 src 落位',
    () async {
      final Stopwatch total = Stopwatch()..start();
      final Directory tempRoot = _createTempDir('cnp_lib_gtest_');
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

      final String includeRoot = joinPath(packDir.path, 'include');
      final String srcRoot = joinPath(packDir.path, 'src');
      final List<String> gtestHeaders = _relativeWithExtension(
        joinPath(includeRoot, 'gtest'),
        '.h',
      );
      final List<String> gmockHeaders = _relativeWithExtension(
        joinPath(includeRoot, 'gmock'),
        '.h',
      );
      final List<String> gtestInternalHeaders = _relativeWithExtension(
        joinPath(includeRoot, 'gtest/internal'),
        '.h',
      );
      final List<String> gmockInternalHeaders = _relativeWithExtension(
        joinPath(includeRoot, 'gmock/internal'),
        '.h',
      );
      final List<String> gtestSourceFiles = _relativeFiles(
        joinPath(srcRoot, 'gtest'),
      );
      final List<String> gmockSourceFiles = _relativeFiles(
        joinPath(srcRoot, 'gmock'),
      );
      final List<String> gtestCompilationUnits =
          _relativeWithExtension(joinPath(srcRoot, 'gtest'), '.cc');
      final List<String> gmockCompilationUnits =
          _relativeWithExtension(joinPath(srcRoot, 'gmock'), '.cc');
      final bool gtestHeader = File(
        joinPath(includeRoot, 'gtest/gtest.h'),
      ).existsSync();
      final bool gmockHeader = File(
        joinPath(includeRoot, 'gmock/gmock.h'),
      ).existsSync();
      final bool license = File(joinPath(packDir.path, 'LICENSE')).existsSync();

      print('[evidence] include/gtest/gtest.h=$gtestHeader');
      print('[evidence] include/gmock/gmock.h=$gmockHeader');
      print(
        '[evidence] include/gtest headers=${gtestHeaders.length} $gtestHeaders',
      );
      print(
        '[evidence] include/gmock headers=${gmockHeaders.length} $gmockHeaders',
      );
      print(
        '[evidence] include/gtest/internal headers=${gtestInternalHeaders.length} $gtestInternalHeaders',
      );
      print(
        '[evidence] include/gmock/internal headers=${gmockInternalHeaders.length} $gmockInternalHeaders',
      );
      print(
        '[evidence] src/gtest files=${gtestSourceFiles.length} $gtestSourceFiles',
      );
      print(
        '[evidence] src/gtest cc=${gtestCompilationUnits.length} $gtestCompilationUnits',
      );
      print(
        '[evidence] src/gmock files=${gmockSourceFiles.length} $gmockSourceFiles',
      );
      print(
        '[evidence] src/gmock cc=${gmockCompilationUnits.length} $gmockCompilationUnits',
      );
      print('[evidence] LICENSE=$license');
      final List<String> artifacts = _relativeFiles(packDir.path);
      print(
        '[evidence] counts totalFiles=${artifacts.length} '
        'headers=${gtestHeaders.length + gmockHeaders.length} '
        'sources=${gtestSourceFiles.length + gmockSourceFiles.length}',
      );
      print('[evidence] artifacts=$artifacts');

      expect(
        gtestHeader,
        isTrue,
        reason: 'include/gtest/gtest.h 应存在（stage_headers 镜像 googletest/include）',
      );
      expect(
        gmockHeader,
        isTrue,
        reason: 'include/gmock/gmock.h 应存在（stage_headers 镜像 googlemock/include）',
      );
      expect(
        gtestInternalHeaders,
        isNotEmpty,
        reason: 'include/gtest/internal 应有内部头文件',
      );
      expect(
        gmockInternalHeaders,
        isNotEmpty,
        reason: 'include/gmock/internal 应有内部头文件',
      );
      expect(
        gtestCompilationUnits.any(
          (String name) => name == 'gtest-all.cc' || name == 'gtest.cc',
        ),
        isTrue,
        reason: 'src/gtest 应含 gtest-all.cc 或 gtest.cc',
      );
      expect(
        gmockCompilationUnits.any(
          (String name) => name == 'gmock-all.cc' || name == 'gmock.cc',
        ),
        isTrue,
        reason: 'src/gmock 应含 gmock-all.cc 或 gmock.cc',
      );
      expect(
        gtestSourceFiles.any((String path) => path.toLowerCase().endsWith('.h')),
        isTrue,
        reason: 'src/gtest 整树复制应含内部 .h（如 gtest-internal-inl.h）',
      );
      expect(
        license,
        isTrue,
        reason: 'googletest 源根 LICENSE 应经 stage_license 落 BUILD_OUT 根',
      );

      total.stop();
      print('[evidence] totalElapsed=${total.elapsed.inSeconds}s');
    },
    skip: gateReason,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
