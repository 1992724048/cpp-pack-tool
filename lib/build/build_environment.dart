import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/shared/format.dart';

/// 构建环境准备失败异常：[message] 面向用户展示。
class BuildPreparationException implements Exception {
  const BuildPreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

final RegExp _lineSeparator = RegExp(r'\r?\n');

Future<Map<String, String>> captureToolchainEnvironment(
  DetectedCompiler compiler, {
  PackProcessRunner runner = Process.run,
  Map<String, String>? baseEnvironment,
  required String scratchDirectory,
}) async {
  final Map<String, String> base = baseEnvironment ?? Platform.environment;
  final String? script = compiler.environmentScript;
  if (script == null || script.isEmpty) {
    return Map<String, String>.of(base);
  }

  final ProcessResult result = await _runEnvironmentScript(runner, script, base, scratchDirectory);
  if (result.exitCode != 0) {
    throw BuildPreparationException('捕获编译器环境失败（退出码 ${result.exitCode}）：$script');
  }
  return _mergeEnvironment(base, _parseEnvironmentOutput('${result.stdout}'));
}

/// 编译器检测函数；默认 [detectCompilers]，仅测试注入替代实现。
typedef CompilerDetector = Future<List<DetectedCompiler>> Function();

/// 新编译器检测结果回调：缓存缺失或失效并完成重检时触发，供调用方写回配置。
typedef CompilerDetectionCallback = void Function(List<DetectedCompiler> compilers);

/// 编译器环境捕获函数；默认 [captureToolchainEnvironment]，仅测试注入替代实现。
typedef ToolchainEnvironmentCapture = Future<Map<String, String>> Function(
  DetectedCompiler compiler, {
  PackProcessRunner runner,
  Map<String, String>? baseEnvironment,
  required String scratchDirectory,
});

Future<List<DetectedCompiler>> detectCompilersReadOnly({
  PackProcessRunner runner = Process.run,
  Map<String, String>? baseEnvironment,
  CompilerDetector? detect,
}) async {
  if (detect != null) {
    return await detect();
  }
  return detectCompilers(runner: runner, environment: baseEnvironment ?? Platform.environment);
}

/// 构建子进程环境与工具信息。
class BuildEnvironment {
  const BuildEnvironment({required this.compiler, required this.environment, required this.toolsDir});

  final DetectedCompiler compiler;

  /// 完整子进程环境（含捕获的编译器环境、`PATH` 与 `CNP_*`）。
  final Map<String, String> environment;

  /// `tools/` 目录绝对路径。
  final String toolsDir;
}

BuildEnvironment assembleBuildEnvironment({
  required DetectedCompiler compiler,
  required Map<String, String> environment,
  required String toolsRoot,
  required String packageRoot,
}) {
  final String toolsDir = Directory(toolsRoot).absolute.path;
  final String packageDir = Directory(packageRoot).absolute.path;
  final String buildTmp = packTmpDirectory(packageDir);
  final Map<String, String> child = Map<String, String>.of(environment);
  _setEnvironmentValue(child, 'CNP_PACKAGE_ROOT', packageDir);
  _setEnvironmentValue(child, 'CNP_SRC_DIR', packSourceDirectory(packageDir));
  _setEnvironmentValue(child, 'CNP_TMP_DIR', buildTmp);
  _setEnvironmentValue(child, 'TMP', buildTmp);
  _setEnvironmentValue(child, 'TEMP', buildTmp);
  _setEnvironmentValue(child, 'CNP_TOOLS_DIR', toolsDir);
  _setEnvironmentValue(child, 'CNP_COMPILER', compiler.executablePath);
  _prependPathEntries(child, <String>[
    ..._toolsDirectoryEntries(toolsDir),
    if (_parentDirectoryOf(compiler.executablePath) case final String compilerDir) compilerDir,
    ...compiler.extraPathEntries,
  ]);
  return BuildEnvironment(compiler: compiler, environment: child, toolsDir: toolsDir);
}

Future<BuildEnvironment> prepareBuildEnvironment({
  required String packageRoot,
  List<String> priority = const <String>['icx', 'clang-cl', 'msvc'],
  PackProcessRunner runner = Process.run,
  String toolsRoot = 'tools',
  Map<String, String>? baseEnvironment,
  List<DetectedCompiler> cachedCompilers = const <DetectedCompiler>[],
  CompilerDetectionCallback? onCompilersDetected,
  CompilerDetector? detect,
  ToolchainEnvironmentCapture? capture,
}) async {
  final String buildTmp = packTmpDirectory(Directory(packageRoot).absolute.path);
  await _createBuildTmpDirectory(buildTmp);
  final Map<String, String> base = _withBuildTmpDirectory(baseEnvironment ?? Platform.environment, buildTmp);
  DetectedCompiler? compiler = selectCompiler(_usableCachedCompilers(cachedCompilers), priority);
  if (compiler == null) {
    final CompilerDetector detector = detect ?? (() => detectCompilers(runner: runner, environment: base));
    final List<DetectedCompiler> detected = await detector();
    onCompilersDetected?.call(detected);
    compiler = selectCompiler(detected, priority);
  }
  if (compiler == null) {
    throw BuildPreparationException(_noCompilerMessage(priority));
  }

  final ToolchainEnvironmentCapture captureEnvironment = capture ?? captureToolchainEnvironment;
  final Map<String, String> captured = await captureEnvironment(
    compiler,
    runner: runner,
    baseEnvironment: base,
    scratchDirectory: buildTmp,
  );

  return assembleBuildEnvironment(
    compiler: compiler,
    environment: captured,
    toolsRoot: toolsRoot,
    packageRoot: packageRoot,
  );
}

List<DetectedCompiler> _usableCachedCompilers(List<DetectedCompiler> cachedCompilers) {
  return <DetectedCompiler>[
    for (final DetectedCompiler compiler in cachedCompilers)
      if (isCompilerUsable(compiler)) compiler,
  ];
}

Map<String, String> _withBuildTmpDirectory(Map<String, String> environment, String buildTmp) {
  final Map<String, String> rewritten = Map<String, String>.of(environment);
  _setEnvironmentValue(rewritten, 'TMP', buildTmp);
  _setEnvironmentValue(rewritten, 'TEMP', buildTmp);
  return rewritten;
}

Future<void> _createBuildTmpDirectory(String buildTmp) async {
  try {
    await Directory(buildTmp).create(recursive: true);
  } on FileSystemException catch (error) {
    throw BuildPreparationException('无法创建中间产物目录 $buildTmp：$error');
  }
}

Future<BuildEnvironment> preparePackBuildEnvironment(
  PackModel pack, {
  required List<String> priority,
  PackProcessRunner runner = Process.run,
  String toolsRoot = 'tools',
  Map<String, String>? baseEnvironment,
  List<DetectedCompiler> cachedCompilers = const <DetectedCompiler>[],
  CompilerDetectionCallback? onCompilersDetected,
  CompilerDetector? detect,
  ToolchainEnvironmentCapture? capture,
}) async {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null || sourcePath.isEmpty) {
    throw const BuildPreparationException('该包缺少源目录信息');
  }
  return prepareBuildEnvironment(
    packageRoot: sourcePath,
    priority: priority,
    runner: runner,
    toolsRoot: toolsRoot,
    baseEnvironment: baseEnvironment,
    cachedCompilers: cachedCompilers,
    onCompilersDetected: onCompilersDetected,
    detect: detect,
    capture: capture,
  );
}

Future<ProcessResult> _runEnvironmentScript(
  PackProcessRunner runner,
  String script,
  Map<String, String> base,
  String scratchDirectory,
) async {
  final Directory tempRoot = await _createScratchDirectory(scratchDirectory);
  try {
    final File wrapper = File(joinPath(tempRoot.path, 'capture.cmd'));
    await wrapper.writeAsString('@echo off\r\ncall "$script" >nul 2>&1 && set\r\n');
    return await runner('cmd', <String>['/c', wrapper.path], environment: base);
  } on ProcessException {
    throw BuildPreparationException('无法启动 cmd 捕获编译器环境：$script');
  } on FileSystemException catch (error) {
    throw BuildPreparationException('无法写入环境捕获包装脚本：$error');
  } finally {
    await _deleteQuietly(tempRoot);
  }
}

Future<Directory> _createScratchDirectory(String scratchDirectory) async {
  try {
    return await Directory(scratchDirectory).createTemp('cnp-env-');
  } on FileSystemException catch (error) {
    throw BuildPreparationException('无法在 $scratchDirectory 下创建环境捕获目录：$error');
  }
}

Future<void> _deleteQuietly(FileSystemEntity entity) async {
  try {
    if (await entity.exists()) {
      await entity.delete(recursive: true);
    }
  } on FileSystemException {
    // 临时残留清理失败不影响本次捕获结果。
  }
}

Map<String, String> _parseEnvironmentOutput(String output) {
  final Map<String, String> captured = <String, String>{};
  for (final String rawLine in output.split(_lineSeparator)) {
    final String line = rawLine.trim();
    if (line.isEmpty || line.startsWith('=')) {
      continue;
    }
    final int separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    captured[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return captured;
}

Map<String, String> _mergeEnvironment(Map<String, String> base, Map<String, String> captured) {
  final Map<String, String> merged = Map<String, String>.of(base);
  final Map<String, String> casing = <String, String>{for (final String key in merged.keys) key.toLowerCase(): key};
  for (final MapEntry<String, String> entry in captured.entries) {
    final String? existing = casing[entry.key.toLowerCase()];
    if (existing != null) {
      merged.remove(existing);
    }
    merged[entry.key] = entry.value;
    casing[entry.key.toLowerCase()] = entry.key;
  }
  return merged;
}

String _noCompilerMessage(List<String> priority) {
  if (priority.isEmpty) {
    return '未检测到可用编译器';
  }
  return '未检测到可用编译器（优先级：${priority.join(' > ')}）';
}

List<String> _toolsDirectoryEntries(String toolsDir) {
  final List<String> entries = <String>[];
  final Set<String> seen = <String>{};
  final List<Directory> queue = <Directory>[Directory(toolsDir)];
  while (queue.isNotEmpty) {
    final Directory current = queue.removeLast();
    final String path = current.absolute.path;
    if (seen.add(path.toLowerCase())) {
      entries.add(path);
    }
    try {
      for (final FileSystemEntity child in current.listSync(followLinks: false)) {
        if (child is Directory) {
          queue.add(child);
        }
      }
    } on FileSystemException {
      continue;
    }
  }
  entries.sort();
  return entries;
}

String? _parentDirectoryOf(String executablePath) {
  final String parent = File(executablePath).parent.path;
  return parent.isEmpty || parent == '.' ? null : parent;
}

void _prependPathEntries(Map<String, String> environment, List<String> entries) {
  final List<String> deduped = <String>[];
  final Set<String> seen = <String>{};
  for (final String entry in entries) {
    final String value = entry.trim();
    if (value.isEmpty || !seen.add(value.toLowerCase())) {
      continue;
    }
    deduped.add(value);
  }
  if (deduped.isEmpty) {
    return;
  }
  final String? pathKey = _findKeyIgnoreCase(environment, 'Path');
  final String existing = pathKey == null ? '' : environment[pathKey]!;
  final String prefix = deduped.join(';');
  environment[pathKey ?? 'Path'] = existing.isEmpty ? prefix : '$prefix;$existing';
}

String? _findKeyIgnoreCase(Map<String, String> environment, String key) {
  final String normalized = key.toLowerCase();
  for (final String candidate in environment.keys) {
    if (candidate.toLowerCase() == normalized) {
      return candidate;
    }
  }
  return null;
}

void _setEnvironmentValue(Map<String, String> environment, String key, String value) {
  final String? existing = _findKeyIgnoreCase(environment, key);
  if (existing != null && existing != key) {
    environment.remove(existing);
  }
  environment[key] = value;
}
