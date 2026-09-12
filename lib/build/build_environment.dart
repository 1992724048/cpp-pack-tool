import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
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

/// 构建设备释放到 `tools/` 的分类辅助模块文件名。
const String _supportModuleFileName = 'cnp_build_support.py';

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
  if (script == null) {
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

/// 编译器环境捕获函数；默认 [captureToolchainEnvironment]，仅测试注入替代实现。
typedef ToolchainEnvironmentCapture = Future<Map<String, String>> Function(
  DetectedCompiler compiler, {
  PackProcessRunner runner,
  Map<String, String>? baseEnvironment,
});

/// 构建子进程环境与工具信息。
class BuildEnvironment {
  const BuildEnvironment({
    required this.compiler,
    required this.environment,
    required this.cmakePath,
    required this.ninjaPath,
    required this.toolsDir,
  });

  final DetectedCompiler compiler;

  /// 完整子进程环境（含捕获的编译器环境、`PATH` 与 `CNP_*`）。
  final Map<String, String> environment;

  /// CMake 可执行文件路径；本地在 PATH 时为命令名 `cmake`。
  final String? cmakePath;

  /// Ninja 可执行文件路径；本地在 PATH 时为命令名 `ninja`。
  final String? ninjaPath;

  /// `tools/` 目录绝对路径。
  final String toolsDir;
}

/// 装配子进程环境：复制 [environment]，写入 `CNP_*` 与选项变量并前置工具目录。
///
/// PATH 键大小写不敏感（保留原键名与值），前置顺序为 Ninja 目录 → CMake 目录 →
/// 未能归属的工具目录 → [pythonPathEntries]（Python 解释器目录） →
/// [toolPathEntries]（`# tool` 声明的工具） →
/// [DetectedCompiler.extraPathEntries]（如 LLVM bin），条目大小写不敏感去重；
/// [options] 按名写入 `CNP_OPTION_<NAME大写>`（未传入的选项不下发）；
/// `PYTHONPATH` 前置 [toolsRoot] 绝对路径（保留原值）；[environment] 不被修改。
BuildEnvironment assembleBuildEnvironment({
  required DetectedCompiler compiler,
  required Map<String, String> environment,
  required CmakeNinja cmakeNinja,
  required String toolsRoot,
  List<String> pythonPathEntries = const <String>[],
  List<String> toolPathEntries = const <String>[],
  Map<String, String> options = const <String, String>{},
}) {
  final String toolsDir = Directory(toolsRoot).absolute.path;
  final Map<String, String> child = Map<String, String>.of(environment);
  _setEnvironmentValue(child, 'CNP_CMAKE', cmakeNinja.cmakeExecutable);
  _setEnvironmentValue(child, 'CNP_NINJA', cmakeNinja.ninjaExecutable);
  _setEnvironmentValue(child, 'CNP_TOOLS_DIR', toolsDir);
  _setEnvironmentValue(child, 'CNP_C_COMPILER', compiler.executablePath);
  _setEnvironmentValue(child, 'CNP_CXX_COMPILER', compiler.executablePath);
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
    _orderedToolPathEntries(
      cmakeNinja,
      pythonPathEntries,
      toolPathEntries,
      compiler.extraPathEntries,
    ),
  );
  _prependEnvironmentValue(child, 'PYTHONPATH', toolsDir);
  return BuildEnvironment(
    compiler: compiler,
    environment: child,
    cmakePath: cmakeNinja.cmakeExecutable,
    ninjaPath: cmakeNinja.ninjaExecutable,
    toolsDir: toolsDir,
  );
}

/// 准备构建环境：检测编译器 → 按 [priority] 选择 → 捕获编译器环境 →
/// 供给 CMake/Ninja、Python（本机优先，缺失下载 embeddable 版）与 [tools]
/// 声明的工具 → 释放 [supportModule] → 装配 `PATH`、`CNP_*` 与选项变量。
///
/// [baseEnvironment] 默认 `Platform.environment` 且全程只读（环境仅注入子进程，
/// 不改动本进程与系统）；[detect]/[capture] 为测试注入点。无可用编译器或
/// 任一环节失败时抛 [BuildPreparationException]。
Future<BuildEnvironment> prepareBuildEnvironment({
  List<String> priority = const <String>['icx', 'clang-cl', 'msvc'],
  PackProcessRunner runner = Process.run,
  ToolProvisioner? provisioner,
  String toolsRoot = 'tools',
  Map<String, String>? baseEnvironment,
  List<BuildScriptTool> tools = const <BuildScriptTool>[],
  Map<String, String> options = const <String, String>{},
  String? supportModule,
  CompilerDetector? detect,
  ToolchainEnvironmentCapture? capture,
}) async {
  final Map<String, String> base = baseEnvironment ?? Platform.environment;
  final CompilerDetector detector =
      detect ?? (() => detectCompilers(runner: runner));
  final DetectedCompiler? compiler = selectCompiler(await detector(), priority);
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

  final ToolProvisioner toolProvisioner =
      provisioner ??
      ToolProvisioner(
        toolsRoot: toolsRoot,
        runner: runner,
        environment: captured,
      );
  final CmakeNinja cmakeNinja = await toolProvisioner.ensureCmakeNinja();
  final ProvisionedPython python = await toolProvisioner.ensurePython();

  final List<String> toolPathEntries = <String>[];
  for (final BuildScriptTool tool in tools) {
    final ProvisionedTool provisioned = await _ensureDeclaredTool(
      toolProvisioner,
      tool,
    );
    toolPathEntries.addAll(provisioned.pathEntries);
  }
  if (supportModule != null) {
    await _releaseSupportModule(toolsRoot, supportModule);
  }

  return assembleBuildEnvironment(
    compiler: compiler,
    environment: captured,
    cmakeNinja: cmakeNinja,
    toolsRoot: toolsRoot,
    pythonPathEntries: python.pathEntries,
    toolPathEntries: toolPathEntries,
    options: options,
  );
}

Future<ProvisionedTool> _ensureDeclaredTool(
  ToolProvisioner provisioner,
  BuildScriptTool tool,
) async {
  try {
    return await provisioner.ensureTool(
      name: tool.name,
      url: tool.url,
      binSubdir: tool.binSubdir,
    );
  } on BuildPreparationException {
    rethrow;
  } catch (error) {
    throw BuildPreparationException('工具 ${tool.name} 准备失败：$error');
  }
}

Future<void> _releaseSupportModule(String toolsRoot, String content) async {
  try {
    await Directory(toolsRoot).create(recursive: true);
    await File(
      joinPath(toolsRoot, _supportModuleFileName),
    ).writeAsString(content);
  } on FileSystemException catch (error) {
    throw BuildPreparationException('释放构建辅助模块失败：$error');
  }
}

/// 依据包声明准备构建环境：读取 build.py 头部 → 解析选项 → 供给声明工具与
/// CMake/Ninja/Python → 释放 [loadSupportModule] 内容（缺省 null 跳过）。
///
/// [loadHeader] 缺省使用 [loadBuildScriptHeader]；其 IO 异常包装为
/// [BuildPreparationException]。其余参数透传 [prepareBuildEnvironment]。
Future<BuildEnvironment> preparePackBuildEnvironment(
  PackModel pack, {
  required List<String> priority,
  PackProcessRunner runner = Process.run,
  ToolProvisioner? provisioner,
  String toolsRoot = 'tools',
  Map<String, String>? baseEnvironment,
  Future<BuildScriptHeader?> Function(PackModel pack)? loadHeader,
  Future<String> Function()? loadSupportModule,
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
  final String? supportModule = await _loadSupportModule(loadSupportModule);
  return prepareBuildEnvironment(
    priority: priority,
    runner: runner,
    provisioner: provisioner,
    toolsRoot: toolsRoot,
    baseEnvironment: baseEnvironment,
    tools: header?.tools ?? const <BuildScriptTool>[],
    options: resolveBuildOptions(
      header?.options ?? const <BuildScriptOption>[],
      pack.buildOptions,
    ),
    supportModule: supportModule,
    detect: detect,
    capture: capture,
  );
}

Future<String?> _loadSupportModule(Future<String> Function()? loader) async {
  if (loader == null) {
    return null;
  }
  try {
    return await loader();
  } catch (_) {
    // 辅助模块缺失/加载失败不阻断构建：脚本可自行回退。
    return null;
  }
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

/// 工具目录前置排序：Ninja → CMake → 未能归属的目录 → Python 解释器目录 →
/// 声明工具目录 → 编译器附加目录。
///
/// [CmakeNinja.pathEntries] 不区分工具归属（供给顺序为先 CMake 后 Ninja），
/// 这里按可执行文件路径归属分组，使 PATH 结构稳定。
List<String> _orderedToolPathEntries(
  CmakeNinja cmakeNinja,
  List<String> pythonPathEntries,
  List<String> toolPathEntries,
  List<String> extraPathEntries,
) {
  final List<String> ninjaEntries = <String>[];
  final List<String> cmakeEntries = <String>[];
  final List<String> unknownEntries = <String>[];
  for (final String entry in cmakeNinja.pathEntries) {
    if (_containsExecutable(entry, cmakeNinja.ninjaExecutable)) {
      ninjaEntries.add(entry);
    } else if (_containsExecutable(entry, cmakeNinja.cmakeExecutable)) {
      cmakeEntries.add(entry);
    } else {
      unknownEntries.add(entry);
    }
  }
  return <String>[
    ...ninjaEntries,
    ...cmakeEntries,
    ...unknownEntries,
    ...pythonPathEntries,
    ...toolPathEntries,
    ...extraPathEntries,
  ];
}

bool _containsExecutable(String directory, String executable) {
  final String normalizedDirectory = directory
      .replaceAll('/', '\\')
      .toLowerCase();
  final String normalizedExecutable = executable
      .replaceAll('/', '\\')
      .toLowerCase();
  return normalizedExecutable.startsWith('$normalizedDirectory\\');
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

/// 将 [value] 前置到 [key]（大小写不敏感匹配、保留原键名），原值以 `;` 连接；
/// 无原值时仅写入 [value]。
void _prependEnvironmentValue(
  Map<String, String> environment,
  String key,
  String value,
) {
  final String? existingKey = _findKeyIgnoreCase(environment, key);
  final String existing = existingKey == null ? '' : environment[existingKey]!;
  environment[existingKey ?? key] = existing.isEmpty
      ? value
      : '$value;$existing';
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
