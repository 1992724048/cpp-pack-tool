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

/// 捕获编译器环境（vcvars/setvars）并与 [baseEnvironment] 合并。
///
/// 无环境脚本时返回 base 拷贝；有脚本时把 `call <脚本> >nul 2>&1 && set` 写入
/// 临时批处理包装文件后经 `cmd /c` 执行（脚本路径作为文件内容传递，避免内嵌
/// 引号被 Dart 的 Windows 参数转义破坏），再按 Windows 语义（键大小写
/// 不敏感）覆盖同名键。脚本失败时 `&&` 短路使非零退出码保留到 cmd 进程
/// （见 [_runEnvironmentScript]），这里抛出 [BuildPreparationException]。
///
/// [scratchDirectory] 是包装文件所在目录的父目录，须已存在且可写。刻意不接受
/// 缺省的 `Directory.systemTemp`：宿主临时位置不可用时那一步会先于 `cmd` 抛出
/// 未包装的文件系统异常，构建根本走不到（宿主 `TMP` 被改写正是为避开这一点）。
/// 捕获用的子目录用完即删，[scratchDirectory] 自身不动。
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

  final ProcessResult result = await _runEnvironmentScript(
    runner,
    script,
    base,
    scratchDirectory,
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
  required String scratchDirectory,
});

/// 只读检测本机编译器：不建目录、不改写 `TMP`/`TEMP`、不注入额外环境变量。
///
/// 本入口没有包源目录，无处可指向包的中间产物区，故子进程直接使用
/// [baseEnvironment]（缺省 `Platform.environment`）：宿主 `TMP`/`TEMP` 指向不可用
/// 的位置、且当前工作目录同样不可写时 ICX 仍会探测失败（见 [detectIcx]）。
/// 构建路径不受此限——那里由 [prepareBuildEnvironment] 把 `TMP`/`TEMP` 改写为
/// 包自带的 `.cache/tmp`。
/// 探测只起子进程跑 `--version` 与 `vswhere`，不写任何文件。
/// [detect] 为测试注入点。
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

/// 装配子进程环境：复制 [environment]，改写 `TMP`/`TEMP`、注入五个 `CNP_*` 变量
/// 并前置工具目录。
///
/// 注入的变量恰为五个：`CNP_PACKAGE_ROOT`（包源目录，产物写这里）、
/// `CNP_SRC_DIR`（`<包源目录>\.cache\src`）、`CNP_TMP_DIR`（`<包源目录>\.cache\tmp`）、
/// `CNP_TOOLS_DIR`（共享工具目录）、`CNP_COMPILER`（首选编译器可执行文件）。
///
/// `TMP`/`TEMP` 无条件改写为 `CNP_TMP_DIR` 的值：不看 [environment] 已声明的
/// 值，不看编译器种类——本层无从排除选中的是 ICX，而宿主临时位置不可用、当前
/// 工作目录同样不可写时它会探测失败（见 [detectIcx]）。收口处必须再写一遍而非
/// 只靠 [baseEnvironment] 那一层，是因为捕获脚本（`setvars.bat` 等）的 `set` 输出
/// 会覆盖 base 里的同名键；不写则脚本把 `TMP`/`TEMP` 换成别的路径就原样漏给了
/// 子进程。
///
/// `CNP_TMP_DIR` 虽名为 tmp，却是**包自带的中间产物目录、归配方自己用**：
/// 本层只算出路径下发，不设权限，目录由 [prepareBuildEnvironment] 在检测前建好。
/// 软件侧对它的干预有两处——建好它、每次构建前清空并重建（见
/// `clearPackTmpDirectory`），保证配方从干净的中间产物区开始；`.cache` 其余部分
/// （`CNP_SRC_DIR` 与配方自行下载的产物）**跨构建保留**——是否复用、复用多少
/// 由配方自己权衡。
///
/// PATH 前置顺序为：共享工具目录自身与其下所有递归子目录 → 编译器所在目录 →
/// [DetectedCompiler.extraPathEntries]（如 LLVM bin），条目大小写不敏感去重；
/// PATH 键大小写不敏感（保留原键名与值）；[environment] 不被修改。
///
/// 编译参数（指令集、优化等级、链接时优化、运行库家族与语言标准）一律不由本层决定，
/// 由配方在构建脚本中自行指定。
///
/// `CNP_RC_COMPILER` 不做推导：它只在输入 [environment] 已显式声明时随子进程透传，
/// 缺失即不下发。
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
  _prependPathEntries(
    child,
    <String>[
      ..._toolsDirectoryEntries(toolsDir),
      if (_parentDirectoryOf(compiler.executablePath) case final String compilerDir) compilerDir,
      ...compiler.extraPathEntries,
    ],
  );
  return BuildEnvironment(
    compiler: compiler,
    environment: child,
    toolsDir: toolsDir,
  );
}

/// 准备构建环境：复用 [cachedCompilers] 中有效且匹配 [priority] 的编译器，缓存
/// 缺失/失效时按 [priority] 检测 → 捕获编译器环境 → 装配 `PATH` 与 `CNP_*`。
/// 全部落空或任一环节失败时抛 [BuildPreparationException]（不下载、不释放任何
/// 工具链）。
///
/// [packageRoot] 为包源目录，配方据此得知产物落点与源码/中间产物区；其下的
/// `.cache/tmp` 在检测前先建好，并把 [baseEnvironment]（缺省
/// `Platform.environment`）中的 `TMP`/`TEMP` 无条件改写为该路径，同一个目录也
/// 交给环境捕获的包装文件用。改写必须早于检测而非只在
/// [assembleBuildEnvironment] 收口：宿主临时位置不可用、当前工作目录同样不可写
/// 时 ICX 在 `icx --version` 探测阶段就已失败（见 [detectIcx]），晚一步则探测已
/// 失败。[baseEnvironment]
/// 本身不被修改，环境仅注入子进程，不改动本进程与系统；[cachedCompilers] 为上次
/// 检测的持久化结果（见 `SettingsModel.detectedCompilers`，设置页与构建共用），
/// 条目经 [isCompilerUsable] 校验后才参与选择；[onCompilersDetected] 在缓存
/// 缺失/失效并完成重检时收到新检测列表（调用方写回配置）；[detect]/[capture] 为
/// 测试注入点，不传缓存与回调时行为与不启用缓存完全一致。
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
  final Map<String, String> base = _withBuildTmpDirectory(
    baseEnvironment ?? Platform.environment,
    buildTmp,
  );
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
    scratchDirectory: buildTmp,
  );

  return assembleBuildEnvironment(
    compiler: compiler,
    environment: captured,
    toolsRoot: toolsRoot,
    packageRoot: packageRoot,
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

/// [environment] 的副本，其中 `TMP`/`TEMP` 指向 [buildTmp]（键大小写不敏感，
/// 旧写法不残留）；入参不被修改。
Map<String, String> _withBuildTmpDirectory(
  Map<String, String> environment,
  String buildTmp,
) {
  final Map<String, String> rewritten = Map<String, String>.of(environment);
  _setEnvironmentValue(rewritten, 'TMP', buildTmp);
  _setEnvironmentValue(rewritten, 'TEMP', buildTmp);
  return rewritten;
}

/// 建好 [buildTmp]：改写后的 `TMP` 若指向尚不存在的目录、且当前工作目录同样不可
/// 写，ICX 会因找不到可用的临时位置而探测失败（见 [detectIcx]）；而检测早于构建
/// 前的清空重建（见 `runPackBuild`），此刻该目录可能尚未诞生。
Future<void> _createBuildTmpDirectory(String buildTmp) async {
  try {
    await Directory(buildTmp).create(recursive: true);
  } on FileSystemException catch (error) {
    throw BuildPreparationException('无法创建中间产物目录 $buildTmp：$error');
  }
}

/// 依据包声明准备构建环境：把 [PackModel.sourcePath]（包源目录）作为
/// [prepareBuildEnvironment] 的 `packageRoot` 透传，其余参数原样透传。
/// 包无源目录时抛 [BuildPreparationException]。
///
/// 编译参数不经本层下发：配方自行决定。
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

/// 脚本路径可能含空格；直接内嵌进 `cmd /c` 参数字符串会被 Dart 的 Windows
/// 参数引号转义破坏，改为写入临时批处理包装文件后按单一参数传递。
///
/// 包装内容为 `call "<脚本>" >nul 2>&1 && set`：脚本失败（非零退出码）时
/// `&&` 短路跳过 `set`，退出码保留到 cmd 进程结束，调用方据此判定失败；
/// 脚本成功时执行 `set` 输出完整环境变量表作为捕获结果。`set` 若另起一行
/// 无条件执行，会把脚本的失败退出码重置为 0，失败被静默吞掉。
///
/// 包装文件建在 [scratchDirectory] 下的 `cnp-env-*` 子目录里并用完即删：宿主
/// `TMP` 被改写为包内路径正是为了「宿主临时位置不可用」这一场景，若包装文件仍
/// 借道 `Directory.systemTemp`，就会在起 `cmd` 之前先以未包装的文件系统异常
/// 失败，把本函数自己建立的 [BuildPreparationException] 契约绕过去。
Future<ProcessResult> _runEnvironmentScript(
  PackProcessRunner runner,
  String script,
  Map<String, String> base,
  String scratchDirectory,
) async {
  final Directory tempRoot = await _createScratchDirectory(scratchDirectory);
  try {
    final File wrapper = File(joinPath(tempRoot.path, 'capture.cmd'));
    await wrapper.writeAsString(
      '@echo off\r\ncall "$script" >nul 2>&1 && set\r\n',
    );
    return await runner('cmd', <String>['/c', wrapper.path], environment: base);
  } on ProcessException {
    throw BuildPreparationException('无法启动 cmd 捕获编译器环境：$script');
  } on FileSystemException catch (error) {
    throw BuildPreparationException('无法写入环境捕获包装脚本：$error');
  } finally {
    await _deleteQuietly(tempRoot);
  }
}

/// 在 [scratchDirectory] 下建本次捕获专用的子目录；失败按本文件既有的
/// [BuildPreparationException] 契约包装，不让原始文件系统异常漏给用户。
Future<Directory> _createScratchDirectory(String scratchDirectory) async {
  try {
    return await Directory(scratchDirectory).createTemp('cnp-env-');
  } on FileSystemException catch (error) {
    throw BuildPreparationException(
      '无法在 $scratchDirectory 下创建环境捕获目录：$error',
    );
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

/// 共享工具目录自身与其下所有子目录（递归、不限深度），排序后返回。
///
/// 目录不可枚举时静默跳过（不抛错）——工具目录的内容由配方自行摆弄，读不动
/// 不应阻断构建。
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

/// 可执行文件所在目录；无父目录或只给出裸文件名（父目录为当前目录 `.`）时返回
/// null——把当前目录放进 `PATH` 会让子进程命中同名的意外可执行文件。
String? _parentDirectoryOf(String executablePath) {
  final String parent = File(executablePath).parent.path;
  return parent.isEmpty || parent == '.' ? null : parent;
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
