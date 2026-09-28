import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_cache.dart';
import 'package:cpp_nuget_pack/build/build_cleanup.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 子进程执行器：与 `Process.run` 同形，便于测试注入。
typedef PackProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// UI 层构建入口：以位置参数 `onStage` 与可选命名参数 `environment`/`onOutput`
/// 调用 [runPackBuild]。
typedef PackBuildRunner = Future<void> Function(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  Map<String, String>? environment,
  void Function(String line)? onOutput,
});

/// 流式子进程执行器：与 `Process.start` 同形的可注入替代（测试用）。
typedef PackStreamingProcessRunner = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// 构建阶段：备源（拷贝预置源码 / 建空工作区）/ 执行构建。
enum PackBuildStage { staging, building }

/// 构建失败异常：[message] 面向用户展示，[outputTail] 为进程输出末尾片段。
class PackBuildException implements Exception {
  const PackBuildException(this.message, {this.outputTail});

  final String message;
  final String? outputTail;

  @override
  String toString() => message;
}

const int _outputTailLineCount = 20;

/// 构建源码准备结果（[preparePackSource] 输出）。
class PackSourcePreparation {
  const PackSourcePreparation({
    required this.sourcePath,
    required this.scriptPath,
    required this.target,
  });

  /// 包源目录（构建脚本工作目录，`BUILD_OUT`）。
  final String sourcePath;

  /// 构建脚本相对包源目录的路径（如 `build.py`）。
  final String scriptPath;

  /// 源码缓存工作目录（`SRC_PATH`）。
  final Directory target;
}

/// 源码准备函数：提权重试路径与测试注入替代实现。
typedef PackSourcePreparer = Future<PackSourcePreparation> Function(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  String cacheRoot,
});

/// 校验 `build.py` 头部、从包内预置源码目录备源并清空包源目录（构建流水线前半段）。
///
/// 流程：根级 `build.py` 存在性检查 → 解析头部（首行为严格锚点源码来源声明，
/// 并校验 `# profile:` 声明为受支持版本，见 [requireSupportedBuildProfile]、
/// 源码目录声明为包源目录下的相对路径，见 [requireValidSourceDirective]——任一
/// 失败即在任何副作用前抛 [PackBuildException]）→ 校验预置源码目录存在且非空
/// → 目标目录（`<cacheRoot>/build/<清洗包ID>`，[cacheRoot] 以绝对路径解析，
/// 保证同一工作目录下缓存稳定命中）备源 → 清空包源目录中白名单外的一切
/// （见 [cleanupBuildOutput]）。
///
/// 备源按源码来源声明分叉，两条分支语义相反、**不得统一**：见
/// [_stageEmptyWorkspace]（`# source: none`）与 [_stagePresetSource]。
Future<PackSourcePreparation> preparePackSource(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  String cacheRoot = 'cache',
}) async {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null) {
    throw const PackBuildException('该包缺少源目录信息');
  }

  final FileModel? scriptFile = findBuildScript(pack.files);
  if (scriptFile == null) {
    throw const PackBuildException('未找到 build.py');
  }
  final File scriptOnDisk = File(joinPath(sourcePath, scriptFile.path));
  if (!await scriptOnDisk.exists()) {
    throw const PackBuildException('源目录中找不到 build.py（可能已被移动）');
  }
  final BuildScriptHeader? header = parseBuildScriptHeader(
    await scriptOnDisk.readAsString(),
  );
  if (header == null) {
    throw PackBuildException(
      buildScriptSourceDeclarationMissingMessage(scriptOnDisk.path),
    );
  }

  // Profile 与源码来源声明的前置校验（fail-closed）：在阶段回调、缓存目录创建、
  // 预置源码拷贝与包源目录清理等一切副作用之前拒绝不合规配方。
  try {
    requireSupportedBuildProfile(header, scriptOnDisk.path);
    requireValidSourceDirective(header, scriptOnDisk.path);
  } on FormatException catch (error) {
    throw PackBuildException(formatError(error));
  }

  // 预置源码目录的存在性与非空性同样在副作用之前校验：否则错误只会指向配方
  // 内部（在空 SRC_PATH 上炸），把排查方向带偏。
  final String? sourceDir = header.sourceDir;
  final Directory? presetSource = sourceDir == null
      ? null
      : Directory(joinPath(sourcePath, sourceDir));
  if (presetSource != null) {
    if (!await presetSource.exists()) {
      throw PackBuildException(
        '找不到包内预置源码目录：${presetSource.absolute.path}'
        '（首行声明 "# source: $sourceDir"）',
      );
    }
    if (!await _treeHasFile(presetSource)) {
      throw PackBuildException(
        '包内预置源码目录为空：${presetSource.absolute.path}'
        '（首行声明 "# source: $sourceDir"）',
      );
    }
  }

  onStage(PackBuildStage.staging);
  final Directory target = packBuildCacheDirectory(
    pack.name,
    cacheRoot: cacheRoot,
  );
  if (presetSource == null) {
    await _stageEmptyWorkspace(target);
  } else {
    await _stagePresetSource(presetSource, target);
  }

  // 源码（或预构建工作区）就绪后、执行脚本前清空包源目录，保证产物不带
  // 上一次构建的残留；备源失败时不触碰源目录。
  try {
    await cleanupBuildOutput(sourcePath);
  } on BuildCleanupException catch (error) {
    throw PackBuildException(error.message);
  }

  return PackSourcePreparation(
    sourcePath: sourcePath,
    scriptPath: scriptFile.path,
    target: target,
  );
}

/// 目录树内是否至少含一个文件（目录递归下探；不跟随链接）。
Future<bool> _treeHasFile(Directory directory) async {
  await for (final FileSystemEntity entry in directory.list(
    followLinks: false,
  )) {
    if (entry is File) {
      return true;
    }
    if (entry is Directory && await _treeHasFile(entry)) {
      return true;
    }
  }
  return false;
}

/// 备源（`# source: none`，无预置源码）：只把 [target] 创建为 `SRC_PATH` 工作区，
/// **绝不清理缓存目录**——脚本自行下载/解压的产物（可达数百 MB）须跨构建复用，
/// 误清会让每次构建退化为全量重下且不报任何错。
///
/// 与 [_stagePresetSource] 语义相反，不得统一为同一条路径。
Future<void> _stageEmptyWorkspace(Directory target) =>
    target.create(recursive: true);

/// 备源（声明了包内预置源码目录）：先删 [target] 残留再把 [source] 整树拷入
/// （含空目录），每次构建从干净状态开始（等价原 `git clean -ffdx`）。
///
/// 与 [_stageEmptyWorkspace] 语义相反，不得统一为同一条路径。
Future<void> _stagePresetSource(Directory source, Directory target) async {
  await _deleteResidual(target.path);
  await target.create(recursive: true);
  try {
    await _copyTree(source, target);
  } on FileSystemException catch (error) {
    throw PackBuildException(
      '准备源码失败：无法把 ${source.absolute.path} 复制到 '
      '${target.absolute.path}（$error）',
    );
  }
}

/// 递归拷贝目录树（源目录 → 目标目录，含空目录）。
///
/// 与 `FileScan` 的扫描口径一致：不跟随符号链接/目录联接，避免把目录外的树
/// 拖进缓存。
Future<void> _copyTree(Directory from, Directory to) async {
  await for (final FileSystemEntity entry in from.list(followLinks: false)) {
    final String destination = joinPath(to.path, baseName(entry.path));
    if (entry is Directory) {
      await Directory(destination).create(recursive: true);
      await _copyTree(entry, Directory(destination));
      continue;
    }
    if (entry is File) {
      await entry.copy(destination);
      continue;
    }
  }
}

/// 执行包内 `build.py`（源码准备见 [preparePackSource]）。
///
/// 覆盖整条构建流水线：[preparePackSource]（备源 + 包源目录清理）→
/// 以 `SRC_PATH`（目标目录）与 `BUILD_OUT`（包源目录）环境变量运行
/// `python build.py`；python 子进程固定注入 `PYTHONIOENCODING=utf-8`，保证
/// 管道中的 stdout/stderr 恒为 UTF-8（中文 Windows 下默认按 GBK 编码，会与
/// 流式解码口径不一致）。提权重试路径（见 elevated_build.dart）复用同一
/// 源码准备实现，仅构建脚本阶段不同，避免两条路径行为漂移。
///
/// 其余参数口径与 [preparePackSource] 一致：[onOutput] 逐行转发 python 输出；
/// [streamRunner] 为 null 时保持一次性捕获，非 null 时以其为流式执行器
/// （生产经 [runPackBuildStreaming] 注入 `Process.start`）。源码准备失败
/// （备源/清理）抛 [PackBuildException]，构建脚本非零退出抛
/// [PackBuildException]（携带输出尾部）。
Future<void> runPackBuild(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner? streamRunner,
  void Function(String line)? onOutput,
  String cacheRoot = 'cache',
  Map<String, String>? environment,
}) async {
  final PackSourcePreparation source = await preparePackSource(
    pack,
    onStage,
    cacheRoot: cacheRoot,
  );
  onStage(PackBuildStage.building);
  await _runBuildScript(
    processRunner,
    streamRunner,
    onOutput,
    source.sourcePath,
    source.scriptPath,
    source.target,
    environment,
  );
}

/// 生产构建入口：[runPackBuild] 的流式变体，默认以 `Process.start` 逐行转发
/// python 子进程输出（UI 实时显示）；其余参数口径与 [runPackBuild]
/// 完全一致。测试可经 [streamRunner] 注入替代执行器。
Future<void> runPackBuildStreaming(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner streamRunner = Process.start,
  void Function(String line)? onOutput,
  String cacheRoot = 'cache',
  Map<String, String>? environment,
}) {
  return runPackBuild(
    pack,
    onStage,
    processRunner: processRunner,
    streamRunner: streamRunner,
    onOutput: onOutput,
    cacheRoot: cacheRoot,
    environment: environment,
  );
}

Future<void> _deleteResidual(String path) async {
  final FileSystemEntityType type = await FileSystemEntity.type(path);
  if (type == FileSystemEntityType.notFound) {
    return;
  }
  final FileSystemEntity entity = type == FileSystemEntityType.directory
      ? Directory(path)
      : File(path);
  await entity.delete(recursive: true);
}

Future<void> _runBuildScript(
  PackProcessRunner processRunner,
  PackStreamingProcessRunner? streamRunner,
  void Function(String line)? onOutput,
  String sourcePath,
  String scriptPath,
  Directory target,
  Map<String, String>? environment,
) async {
  final ProcessResult result = await _runPython(
    processRunner,
    streamRunner,
    onOutput,
    sourcePath,
    scriptPath,
    target,
    environment,
  );
  if (result.exitCode != 0) {
    throw PackBuildException(
      '构建失败（退出码 ${result.exitCode}）',
      outputTail: _outputTail(result),
    );
  }
}

Future<ProcessResult> _runPython(
  PackProcessRunner processRunner,
  PackStreamingProcessRunner? streamRunner,
  void Function(String line)? onOutput,
  String sourcePath,
  String scriptPath,
  Directory target,
  Map<String, String>? environment,
) async {
  final Map<String, String> variables = <String, String>{
    ...?environment,
    'SRC_PATH': target.absolute.path,
    'BUILD_OUT': Directory(sourcePath).absolute.path,
    'PYTHONIOENCODING': 'utf-8',
  };
  final _PythonLauncher launcher = _PythonLauncher(scriptPath);
  if (streamRunner != null) {
    return _runStreamingPython(
      streamRunner,
      launcher,
      onOutput,
      sourcePath,
      variables,
    );
  }
  try {
    return await processRunner(
      launcher.executable,
      launcher.arguments,
      workingDirectory: sourcePath,
      environment: variables,
    );
  } on ProcessException {
    return _runFallbackPython(processRunner, launcher, sourcePath, variables);
  }
}

/// Python 启动命令：首选 `python -u <script>`，回退 `py -3 -u <script>`；
/// `-u` 关闭 stdout/stderr 缓冲，保证输出经流式管道即时到达。
class _PythonLauncher {
  const _PythonLauncher(this.scriptPath);

  final String scriptPath;

  String get executable => 'python';

  List<String> get arguments => <String>['-u', scriptPath];

  String get fallbackExecutable => 'py';

  List<String> get fallbackArguments => <String>['-3', '-u', scriptPath];
}

Future<ProcessResult> _runStreamingPython(
  PackStreamingProcessRunner streamRunner,
  _PythonLauncher launcher,
  void Function(String line)? onOutput,
  String sourcePath,
  Map<String, String> environment,
) async {
  try {
    return await _runStreamingProcess(
      streamRunner,
      launcher.executable,
      launcher.arguments,
      sourcePath,
      environment,
      onOutput,
    );
  } on ProcessException {
    return _runFallbackStreamingPython(
      streamRunner,
      launcher,
      onOutput,
      sourcePath,
      environment,
    );
  }
}

Future<ProcessResult> _runFallbackStreamingPython(
  PackStreamingProcessRunner streamRunner,
  _PythonLauncher launcher,
  void Function(String line)? onOutput,
  String sourcePath,
  Map<String, String> environment,
) async {
  try {
    return await _runStreamingProcess(
      streamRunner,
      launcher.fallbackExecutable,
      launcher.fallbackArguments,
      sourcePath,
      environment,
      onOutput,
    );
  } on ProcessException {
    throw const PackBuildException('未找到 Python（python / py），无法执行构建');
  }
}

Future<ProcessResult> _runFallbackPython(
  PackProcessRunner processRunner,
  _PythonLauncher launcher,
  String sourcePath,
  Map<String, String> environment,
) async {
  try {
    return await processRunner(
      launcher.fallbackExecutable,
      launcher.fallbackArguments,
      workingDirectory: sourcePath,
      environment: environment,
    );
  } on ProcessException {
    throw const PackBuildException('未找到 Python（python / py），无法执行构建');
  }
}

Future<ProcessResult> _runStreamingProcess(
  PackStreamingProcessRunner streamRunner,
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String> environment,
  void Function(String line)? onOutput,
) async {
  final Process process = await streamRunner(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final List<String> stdoutLines = <String>[];
  final List<String> stderrLines = <String>[];
  final Future<void> stdoutDone = _collectProcessLines(
    process.stdout,
    stdoutLines,
    onOutput,
  );
  final Future<void> stderrDone = _collectProcessLines(
    process.stderr,
    stderrLines,
    onOutput,
  );
  final int exitCode = await process.exitCode;
  await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  return ProcessResult(
    process.pid,
    exitCode,
    _withTrailingNewline(stdoutLines),
    _withTrailingNewline(stderrLines),
  );
}

/// 逐行收集单流输出：无效 UTF-8 字节按替换字符（U+FFFD）容错解码，不抛
/// 异常、不丢行——本地化工具输出（GBK 中文、非 ASCII 路径）不得让整次
/// 构建误判失败或掩盖失败诊断。
Future<void> _collectProcessLines(
  Stream<List<int>> stream,
  List<String> lines,
  void Function(String line)? onOutput,
) async {
  await for (final String line
      in stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())) {
    lines.add(line);
    onOutput?.call(line);
  }
}

/// 还原单流末尾换行的原始文本形态（与 `ProcessResult.stdout` 语义一致）。
String _withTrailingNewline(List<String> lines) =>
    lines.isEmpty ? '' : '${lines.join('\n')}\n';

String? _outputTail(ProcessResult result) {
  final List<String> lines = '${result.stdout}\n${result.stderr}'.split(
    RegExp(r'\r\n|\r|\n'),
  );
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  final List<String> tail = lines.length <= _outputTailLineCount
      ? lines
      : lines.sublist(lines.length - _outputTailLineCount);
  final String text = tail.join('\n').trim();
  return text.isEmpty ? null : text;
}
