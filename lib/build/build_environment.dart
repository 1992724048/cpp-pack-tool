import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 构建环境准备失败异常：[message] 面向用户展示。
class BuildPreparationException implements Exception {
  const BuildPreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

final RegExp _lineSeparator = RegExp(r'\r?\n');

/// 注入子进程的 CMake 可执行文件名；由子进程按 `PATH` 解析。
const String _cmakeCommandName = 'cmake';

/// 注入子进程的 Ninja 可执行文件名；由子进程按 `PATH` 解析。
const String _ninjaCommandName = 'ninja';

/// 捕获编译器环境（vcvars/setvars）并与 [baseEnvironment] 合并。
///
/// 无环境脚本时返回 base 拷贝；有脚本时把 `call <脚本> >nul 2>&1 && set` 写入
/// 临时批处理包装文件后经 `cmd /c` 执行（脚本路径作为文件内容传递，避免内嵌
/// 引号被 Dart 的 Windows 参数转义破坏），再按 Windows 语义（键大小写
/// 不敏感）覆盖同名键。脚本失败时 `&&` 短路使非零退出码保留到 cmd 进程
/// （见 [_runEnvironmentScript]），这里抛出 [BuildPreparationException]。
Future<Map<String, String>> captureToolchainEnvironment(
  DetectedCompiler compiler, {
  PackProcessRunner runner = Process.run,
  Map<String, String>? baseEnvironment,
}) async {
  final Map<String, String> base = baseEnvironment ?? Platform.environment;
  final String? script = compiler.environmentScript;
  if (script == null || script.isEmpty) {
    return Map<String, String>.of(base);
  }

  final ProcessResult result = await _runEnvironmentScript(
    runner,
    script,
    base,
  );
  if (result.exitCode != 0) {
    throw BuildPreparationException(
      '捕获编译器环境失败（退出码 ${result.exitCode}）：$script',
    );
  }
  return _mergeEnvironment(base, _parseEnvironmentOutput('${result.stdout}'));
}

/// 编译器检测函数；默认 [detectCompilers]，仅测试注入替代实现。
typedef CompilerDetector = Future<List<DetectedCompiler>> Function();

/// 新编译器检测结果回调：缓存缺失或失效并完成重检时触发，供调用方写回配置。
typedef CompilerDetectionCallback = void Function(
  List<DetectedCompiler> compilers,
);

/// 编译器环境捕获函数；默认 [captureToolchainEnvironment]，仅测试注入替代实现。
typedef ToolchainEnvironmentCapture = Future<Map<String, String>> Function(
  DetectedCompiler compiler, {
  PackProcessRunner runner,
  Map<String, String>? baseEnvironment,
});

/// 只读检测本机编译器：不建目录、不改写 `TMP`/`TEMP`、不注入额外环境变量。
///
/// 子进程直接使用 [baseEnvironment]（缺省 `Platform.environment`），故宿主
/// `TMP`/`TEMP` 不可用或指向他人所有目录时 ICX 仍可能报 `error #10026`（见
/// [detectIcx]）——本入口不再为此改写环境。探测只起子进程跑 `--version` 与
/// `vswhere`，不写任何文件。[detect] 为测试注入点。
Future<List<DetectedCompiler>> detectCompilersReadOnly({
  PackProcessRunner runner = Process.run,
  Map<String, String>? baseEnvironment,
  CompilerDetector? detect,
}) async {
  if (detect != null) {
    return await detect();
  }
  return detectCompilers(
    runner: runner,
    environment: baseEnvironment ?? Platform.environment,
  );
}

/// 构建子进程环境与工具信息。
class BuildEnvironment {
  const BuildEnvironment({
    required this.compiler,
    required this.environment,
    required this.toolsDir,
  });

  final DetectedCompiler compiler;

  /// 完整子进程环境（含捕获的编译器环境、`PATH` 与 `CNP_*`）。
  final Map<String, String> environment;

  /// `tools/` 目录绝对路径。
  final String toolsDir;
}

/// 装配子进程环境：复制 [environment]，写入 `CNP_*` 与选项变量并前置工具目录。
///
/// PATH 键大小写不敏感（保留原键名与值），前置顺序为 [toolPathEntries] →
/// [DetectedCompiler.extraPathEntries]（如 LLVM bin），条目大小写不敏感去重；
/// [options] 按名写入 `CNP_OPTION_<NAME大写>`（未传入的选项不下发）；
/// [environment] 不被修改。
///
/// 编译参数（指令集、优化等级、链接时优化、运行库家族与语言标准）一律不由本层
/// 决定，配方可经 `cmake_configure(extra_args=…)` 自定任何 `-D` 参数。
///
/// `CNP_CMAKE` / `CNP_NINJA` 固定为命令名 `cmake` / `ninja`，由子进程按 `PATH`
/// 解析。`CNP_C_COMPILER` 取 [DetectedCompiler.executablePath]、
/// `CNP_CXX_COMPILER` 取 [DetectedCompiler.cxxCompilerPath]。`CNP_RC_COMPILER`
/// 不做推导：它只在输入 [environment] 已显式声明时随子进程透传，缺失即不下发，
/// CMake 可经 PATH 自行解析。
BuildEnvironment assembleBuildEnvironment({
  required DetectedCompiler compiler,
  required Map<String, String> environment,
  required String toolsRoot,
  List<String> toolPathEntries = const <String>[],
  Map<String, String> options = const <String, String>{},
}) {
  final String toolsDir = Directory(toolsRoot).absolute.path;
  final Map<String, String> child = Map<String, String>.of(environment);
  _setEnvironmentValue(child, 'CNP_CMAKE', _cmakeCommandName);
  _setEnvironmentValue(child, 'CNP_NINJA', _ninjaCommandName);
  _setEnvironmentValue(child, 'CNP_TOOLS_DIR', toolsDir);
  _setEnvironmentValue(child, 'CNP_C_COMPILER', compiler.executablePath);
  _setEnvironmentValue(child, 'CNP_CXX_COMPILER', compiler.cxxCompilerPath);
  _setEnvironmentValue(
    child,
    'CNP_COMPILER_KIND',
    compilerKindId(compiler.kind),
  );
  for (final MapEntry<String, String> option in options.entries) {
    _setEnvironmentValue(child, optionEnvName(option.key), option.value);
  }
  _prependPathEntries(
    child,
    <String>[...toolPathEntries, ...compiler.extraPathEntries],
  );
  return BuildEnvironment(
    compiler: compiler,
    environment: child,
    toolsDir: toolsDir,
  );
}

/// 准备构建环境：复用 [cachedCompilers] 中有效且匹配 [priority] 的编译器，缓存
/// 缺失/失效时按 [priority] 检测 → 捕获编译器环境 → 装配 `PATH`、`CNP_*` 与选项
/// 变量。全部落空或任一环节失败时抛 [BuildPreparationException]（不再下载、不再
/// 释放任何工具链）。
///
/// [baseEnvironment] 默认 `Platform.environment` 且全程只读（环境仅注入子进程，
/// 不改动本进程与系统，也不改写其中的 `TMP`/`TEMP`）；[cachedCompilers] 为上次
/// 检测的持久化结果（见 `SettingsModel.detectedCompilers`，设置页与构建共用），
/// 条目经 [isCompilerUsable] 校验后才参与选择；[onCompilersDetected] 在缓存
/// 缺失/失效并完成重检时收到新检测列表（调用方写回配置）；[detect]/[capture] 为
/// 测试注入点，不传缓存与回调时行为与不启用缓存完全一致。
Future<BuildEnvironment> prepareBuildEnvironment({
  List<String> priority = const <String>['icx', 'clang-cl', 'msvc'],
  PackProcessRunner runner = Process.run,
  String toolsRoot = 'tools',
  Map<String, String>? baseEnvironment,
  Map<String, String> options = const <String, String>{},
  List<DetectedCompiler> cachedCompilers = const <DetectedCompiler>[],
  CompilerDetectionCallback? onCompilersDetected,
  CompilerDetector? detect,
  ToolchainEnvironmentCapture? capture,
}) async {
  final Map<String, String> base = baseEnvironment ?? Platform.environment;
  DetectedCompiler? compiler = selectCompiler(
    _usableCachedCompilers(cachedCompilers),
    priority,
  );
  if (compiler == null) {
    final CompilerDetector detector =
        detect ?? (() => detectCompilers(runner: runner, environment: base));
    final List<DetectedCompiler> detected = await detector();
    onCompilersDetected?.call(detected);
    compiler = selectCompiler(detected, priority);
  }
  if (compiler == null) {
    throw BuildPreparationException(_noCompilerMessage(priority));
  }

  final ToolchainEnvironmentCapture captureEnvironment =
      capture ?? captureToolchainEnvironment;
  final Map<String, String> captured = await captureEnvironment(
    compiler,
    runner: runner,
    baseEnvironment: base,
  );

  return assembleBuildEnvironment(
    compiler: compiler,
    environment: captured,
    toolsRoot: toolsRoot,
    options: options,
  );
}

/// 过滤出仍可继续使用的缓存条目（可执行文件与环境脚本仍在，经
/// [isCompilerUsable] 校验）。
List<DetectedCompiler> _usableCachedCompilers(
  List<DetectedCompiler> cachedCompilers,
) {
  return <DetectedCompiler>[
    for (final DetectedCompiler compiler in cachedCompilers)
      if (isCompilerUsable(compiler)) compiler,
  ];
}

/// 依据包声明准备构建环境：读取 build.py 头部 → 解析选项 → 透传
/// [prepareBuildEnvironment]。
///
/// 编译参数不经本层下发：配方自行决定并可经 `cmake_configure(extra_args=…)`
/// 传入任意 `-D` 参数。
///
/// [loadHeader] 缺省使用 [loadBuildScriptHeader]；其 IO 异常包装为
/// [BuildPreparationException]。其余参数透传 [prepareBuildEnvironment]。
Future<BuildEnvironment> preparePackBuildEnvironment(
  PackModel pack, {
  required List<String> priority,
  PackProcessRunner runner = Process.run,
  String toolsRoot = 'tools',
  Map<String, String>? baseEnvironment,
  Future<BuildScriptHeader?> Function(PackModel pack)? loadHeader,
  List<DetectedCompiler> cachedCompilers = const <DetectedCompiler>[],
  CompilerDetectionCallback? onCompilersDetected,
  CompilerDetector? detect,
  ToolchainEnvironmentCapture? capture,
}) async {
  final Future<BuildScriptHeader?> Function(PackModel pack) headerLoader =
      loadHeader ?? loadBuildScriptHeader;
  final BuildScriptHeader? header;
  try {
    header = await headerLoader(pack);
  } catch (error) {
    throw BuildPreparationException('读取 build.py 失败：$error');
  }
  return prepareBuildEnvironment(
    priority: priority,
    runner: runner,
    toolsRoot: toolsRoot,
    baseEnvironment: baseEnvironment,
    options: resolveBuildOptions(
      header?.options ?? const <BuildScriptOption>[],
      pack.buildOptions,
    ),
    cachedCompilers: cachedCompilers,
    onCompilersDetected: onCompilersDetected,
    detect: detect,
    capture: capture,
  );
}

/// 脚本路径可能含空格；直接内嵌进 `cmd /c` 参数字符串会被 Dart 的 Windows
/// 参数引号转义破坏，改为写入临时批处理包装文件后按单一参数传递。
///
/// 包装内容为 `call "<脚本>" >nul 2>&1 && set`：脚本失败（非零退出码）时
/// `&&` 短路跳过 `set`，退出码保留到 cmd 进程结束，调用方据此判定失败；
/// 脚本成功时执行 `set` 输出完整环境变量表作为捕获结果。`set` 若另起一行
/// 无条件执行，会把脚本的失败退出码重置为 0，失败被静默吞掉。
Future<ProcessResult> _runEnvironmentScript(
  PackProcessRunner runner,
  String script,
  Map<String, String> base,
) async {
  final Directory tempRoot = await Directory.systemTemp.createTemp('cnp-env-');
  try {
    final File wrapper = File(joinPath(tempRoot.path, 'capture.cmd'));
    await wrapper.writeAsString(
      '@echo off\r\ncall "$script" >nul 2>&1 && set\r\n',
    );
    return await runner('cmd', <String>['/c', wrapper.path], environment: base);
  } on ProcessException {
    throw BuildPreparationException('无法启动 cmd 捕获编译器环境：$script');
  } finally {
    await _deleteQuietly(tempRoot);
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

Map<String, String> _mergeEnvironment(
  Map<String, String> base,
  Map<String, String> captured,
) {
  final Map<String, String> merged = Map<String, String>.of(base);
  final Map<String, String> casing = <String, String>{
    for (final String key in merged.keys) key.toLowerCase(): key,
  };
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

void _prependPathEntries(
  Map<String, String> environment,
  List<String> entries,
) {
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
  environment[pathKey ?? 'Path'] = existing.isEmpty
      ? prefix
      : '$prefix;$existing';
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

void _setEnvironmentValue(
  Map<String, String> environment,
  String key,
  String value,
) {
  final String? existing = _findKeyIgnoreCase(environment, key);
  if (existing != null && existing != key) {
    environment.remove(existing);
  }
  environment[key] = value;
}
