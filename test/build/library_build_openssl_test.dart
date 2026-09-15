// ignore_for_file: avoid_print

// OpenSSL 真机构建验收（P3 L7）：经生产链路 preparePackBuildEnvironment + runPackBuild
// 真实 clone https://github.com/openssl/openssl.git；NASM 与 Strawberry Perl 由
// build.py 头部的 `# tool` 声明在准备阶段自动下载到 tools/ 并注入 PATH，随后
// `perl Configure VC-WIN64A` + `nmake build_libs` 构建 Release/Debug 双配置并分类
// 到 BUILD_OUT。
//
// 运行：$env:CNP_REAL_LIBRARY_BUILDS='openssl'; flutter test test/build/library_build_openssl_test.dart

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _libraryName = 'openssl';
const String _recipePath = 'test/build/library_recipes/openssl/build.py';

/// gated 运行开关：`CNP_REAL_LIBRARY_BUILDS` 含 `openssl` 或 `all` 才执行。
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
    return "设置 CNP_REAL_LIBRARY_BUILDS='openssl'（或 all）运行真实构建";
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

String _readTextOrEmpty(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return '(missing)';
  }
  return file.readAsStringSync().trim();
}

/// 运行工具版本探针并打印首行摘要（下载机制证据）。
Future<void> _printToolProbe(
  String label,
  String executable,
  List<String> arguments,
) async {
  try {
    final ProcessResult result = await Process.run(executable, arguments);
    final String output = '${result.stdout}\n${result.stderr}'.trim();
    final List<String> lines = output
        .split(RegExp(r'\r?\n'))
        .where((String line) => line.trim().isNotEmpty)
        .take(2)
        .toList();
    print(
      '[evidence] $label exitCode=${result.exitCode} '
      'output=${lines.join(' | ')}',
    );
  } on ProcessException catch (error) {
    print('[evidence] $label launch failed: $error');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? gateReason = _gateReason();

  test(
    'openssl 真机构建：NASM/Perl 工具下载 → Perl Configure + nmake → 分类入库',
    () async {
      final Stopwatch total = Stopwatch()..start();
      final Directory tempRoot = _createTempDir('cnp_lib_openssl_');
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
      print('[evidence] env.toolsDir=${env.toolsDir}');
      print('[evidence] packDir=${packDir.path}');

      final File nasm = File(joinPath(env.toolsDir, 'nasm/nasm.exe'));
      final File perl = File(joinPath(env.toolsDir, 'perl/perl/bin/perl.exe'));
      final File nasmMarker = File(joinPath(env.toolsDir, 'nasm/.source'));
      final File perlMarker = File(joinPath(env.toolsDir, 'perl/.source'));
      print('[evidence] nasm.exists=${nasm.existsSync()} path=${nasm.path}');
      print('[evidence] perl.exists=${perl.existsSync()} path=${perl.path}');
      print('[evidence] nasm.source=${_readTextOrEmpty(nasmMarker.path)}');
      print('[evidence] perl.source=${_readTextOrEmpty(perlMarker.path)}');
      await _printToolProbe('nasm -v', nasm.path, <String>['-v']);
      await _printToolProbe('perl -v', perl.path, <String>['-v']);

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
      final File licenseFile = File(joinPath(packDir.path, 'LICENSE.txt'));

      print(
        '[evidence] include/openssl/ssl.h='
        '${File(joinPath(includeDir, 'openssl/ssl.h')).existsSync()}',
      );
      print(
        '[evidence] include/openssl/configuration.h='
        '${File(joinPath(includeDir, 'openssl/configuration.h')).existsSync()}',
      );
      print('[evidence] release.lib=$releaseLibs');
      print('[evidence] release.dll=$releaseBins');
      print('[evidence] debug.lib=$debugLibs');
      print('[evidence] debug.dll=$debugBins');
      print('[evidence] LICENSE.txt=${licenseFile.existsSync()}');
      print('[evidence] artifacts=${_relativeFiles(packDir.path)}');

      expect(
        nasm.existsSync(),
        isTrue,
        reason: 'NASM 应经 # tool 下载到 tools/nasm/nasm.exe',
      );
      expect(
        perl.existsSync(),
        isTrue,
        reason: 'Perl 应经 # tool 下载到 tools/perl/perl/bin/perl.exe',
      );
      expect(
        File(joinPath(includeDir, 'openssl/ssl.h')).existsSync(),
        isTrue,
        reason: 'include/openssl/ssl.h 应存在（构建树生成头）',
      );
      expect(
        File(joinPath(includeDir, 'openssl/configuration.h')).existsSync(),
        isTrue,
        reason: 'include/openssl/configuration.h 应存在（Configure 生成头）',
      );
      expect(
        releaseLibs,
        isNotEmpty,
        reason: 'Release release/lib 应至少 1 个 .lib',
      );
      expect(
        releaseBins,
        isNotEmpty,
        reason: 'Release release/bin 应至少 1 个 .dll',
      );
      expect(debugLibs, isNotEmpty, reason: 'debug/lib 应存在且含 .lib');
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
        licenseFile.existsSync(),
        isTrue,
        reason: 'OpenSSL 源根 LICENSE.txt 应经 stage_license 落 BUILD_OUT 根',
      );

      total.stop();
      print('[evidence] totalElapsed=${total.elapsed.inSeconds}s');
    },
    skip: gateReason,
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
