import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/config/pack_store.dart';
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

/// UI 层构建入口：以位置参数 `onStage` 与可选命名参数 `environment`/`onOutput`/
/// `onSourceVersion` 调用 [runPackBuild]。
typedef PackBuildRunner = Future<void> Function(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  Map<String, String>? environment,
  void Function(String line)? onOutput,
  void Function(String version)? onSourceVersion,
});

/// 流式子进程执行器：与 `Process.start` 同形的可注入替代（测试用）。
typedef PackStreamingProcessRunner = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// 构建阶段：下载源码 / 执行构建。
enum PackBuildStage { downloading, building }

/// 构建失败异常：[message] 面向用户展示，[outputTail] 为进程输出末尾片段。
class PackBuildException implements Exception {
  const PackBuildException(this.message, {this.outputTail});

  final String message;
  final String? outputTail;

  @override
  String toString() => message;
}

const int _outputTailLineCount = 20;
const String _gitPromptEnvironmentKey = 'GIT_TERMINAL_PROMPT';

/// 拉取源码并执行包内 `build.py`。
///
/// 流程：解析 `build.py` 头部（仓库地址 + 可选 `# source: none`）→ 目标目录
/// （`<cacheRoot>/build/<清洗包ID>`）克隆或拉取（声明 `# source: none` 时跳过
/// git，仅创建目录作为 `SRC_PATH` 工作区）→ 以 `SRC_PATH`（目标目录）与
/// `BUILD_OUT`（包源目录）环境变量运行 `python build.py`。
///
/// [environment] 为子进程环境的附加覆盖层（null 时不注入额外变量）；
/// 与 `GIT_TERMINAL_PROMPT`/`SRC_PATH`/`BUILD_OUT` 同名的键恒以本函数计算的值为准。
/// [onOutput] 非空时逐行转发子进程输出（git 源码拉取与 python 构建进程），
/// 同时汇聚完整输出用于失败诊断；git 调用恒追加 `--progress` 以强制输出进度。
/// [streamRunner] 为 null 时保持一次性捕获（无流式；[onOutput] 被忽略），
/// 非 null 时以其为流式执行器（生产经 [runPackBuildStreaming] 注入
/// `Process.start`，测试注入替代实现）。
/// [onSourceVersion] 非空时在源码就绪后查询仓库版本（`git describe --tags
/// --abbrev=0`，失败回退 `git rev-parse --short HEAD`）并回调；查询失败静默
/// 跳过，`# source: none` 包不查询。为 null 时不产生任何额外 git 调用。
Future<void> runPackBuild(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner? streamRunner,
  void Function(String line)? onOutput,
  void Function(String version)? onSourceVersion,
  String cacheRoot = 'cache',
  Map<String, String>? environment,
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
    throw const PackBuildException('build.py 首行缺少 git 仓库地址（格式：# <仓库地址>）');
  }

  onStage(PackBuildStage.downloading);
  final Directory target = Directory(
    joinPath(cacheRoot, 'build/${PackStore.sanitizeFileName(pack.name)}'),
  );
  if (header.sourceNone) {
    // 预构建配方（`# source: none`）：跳过 git 源码拉取；缓存目录仍会创建并
    // 作为 `SRC_PATH` 注入，供脚本自行下载/解压（二次构建复用其中缓存）。
    await target.create(recursive: true);
  } else {
    await target.parent.create(recursive: true);
    if (await _hasGitDirectory(target)) {
      await _pullRepository(
        processRunner,
        streamRunner,
        target,
        environment,
        onOutput,
      );
    } else {
      await _cloneRepository(
        processRunner,
        streamRunner,
        target,
        header.repo,
        environment,
        onOutput,
      );
    }
    if (onSourceVersion != null) {
      final String? version = await _querySourceVersion(
        processRunner,
        target,
        environment,
      );
      if (version != null) {
        onSourceVersion(version);
      }
    }
  }

  onStage(PackBuildStage.building);
  await _runBuildScript(
    processRunner,
    streamRunner,
    onOutput,
    sourcePath,
    scriptFile.path,
    target,
    environment,
  );
}

/// 生产构建入口：[runPackBuild] 的流式变体，默认以 `Process.start` 逐行转发
/// git 与 python 子进程输出（UI 实时显示）；其余参数口径与 [runPackBuild]
/// 完全一致。测试可经 [streamRunner] 注入替代执行器。
Future<void> runPackBuildStreaming(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner streamRunner = Process.start,
  void Function(String line)? onOutput,
  void Function(String version)? onSourceVersion,
  String cacheRoot = 'cache',
  Map<String, String>? environment,
}) {
  return runPackBuild(
    pack,
    onStage,
    processRunner: processRunner,
    streamRunner: streamRunner,
    onOutput: onOutput,
    onSourceVersion: onSourceVersion,
    cacheRoot: cacheRoot,
    environment: environment,
  );
}

Future<bool> _hasGitDirectory(Directory target) async {
  final FileSystemEntityType type = await FileSystemEntity.type(
    '${target.path}/.git',
  );
  return type != FileSystemEntityType.notFound;
}

Future<void> _pullRepository(
  PackProcessRunner processRunner,
  PackStreamingProcessRunner? streamRunner,
  Directory target,
  Map<String, String>? environment,
  void Function(String line)? onOutput,
) async {
  final ProcessResult result = await _runGit(
    processRunner,
    streamRunner,
    const <String>['pull', '--ff-only', '--progress'],
    workingDirectory: target.path,
    environment: environment,
    onOutput: onOutput,
  );
  if (result.exitCode != 0) {
    throw PackBuildException(
      '拉取源码失败（退出码 ${result.exitCode}）',
      outputTail: _outputTail(result),
    );
  }
}

Future<void> _cloneRepository(
  PackProcessRunner processRunner,
  PackStreamingProcessRunner? streamRunner,
  Directory target,
  String repository,
  Map<String, String>? environment,
  void Function(String line)? onOutput,
) async {
  await _deleteResidual(target.path);
  final ProcessResult result = await _runGit(
    processRunner,
    streamRunner,
    <String>['clone', '--progress', repository, target.path],
    environment: environment,
    onOutput: onOutput,
  );
  if (result.exitCode == 0) {
    return;
  }
  await _deleteResidual(target.path);
  throw PackBuildException(
    '克隆源码失败（退出码 ${result.exitCode}）',
    outputTail: _outputTail(result),
  );
}

Future<ProcessResult> _runGit(
  PackProcessRunner processRunner,
  PackStreamingProcessRunner? streamRunner,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  void Function(String line)? onOutput,
}) {
  final Map<String, String> gitEnvironment = <String, String>{
    ...?environment,
    _gitPromptEnvironmentKey: '0',
  };
  if (streamRunner != null) {
    return _runStreamingProcess(
      streamRunner,
      'git',
      arguments,
      workingDirectory,
      gitEnvironment,
      onOutput,
    );
  }
  return processRunner(
    'git',
    arguments,
    workingDirectory: workingDirectory,
    environment: gitEnvironment,
  );
}

/// 查询仓库版本：`git describe --tags --abbrev=0`，失败回退短哈希；均失败返回 null。
Future<String?> _querySourceVersion(
  PackProcessRunner processRunner,
  Directory target,
  Map<String, String>? environment,
) async {
  final String? tag = await _describeTag(processRunner, target, environment);
  if (tag != null) {
    return tag;
  }
  return _shortHead(processRunner, target, environment);
}

Future<String?> _describeTag(
  PackProcessRunner processRunner,
  Directory target,
  Map<String, String>? environment,
) async {
  try {
    final ProcessResult result = await _runGit(
      processRunner,
      null,
      const <String>['describe', '--tags', '--abbrev=0'],
      workingDirectory: target.path,
      environment: environment,
    );
    if (result.exitCode != 0) {
      return null;
    }
    final String tag = '${result.stdout}'.trim();
    return tag.isEmpty ? null : tag;
  } on ProcessException {
    return null;
  }
}

Future<String?> _shortHead(
  PackProcessRunner processRunner,
  Directory target,
  Map<String, String>? environment,
) async {
  try {
    final ProcessResult result = await _runGit(
      processRunner,
      null,
      const <String>['rev-parse', '--short', 'HEAD'],
      workingDirectory: target.path,
      environment: environment,
    );
    if (result.exitCode != 0) {
      return null;
    }
    final String hash = '${result.stdout}'.trim();
    return hash.isEmpty ? null : hash;
  } on ProcessException {
    return null;
  }
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

Future<void> _collectProcessLines(
  Stream<List<int>> stream,
  List<String> lines,
  void Function(String line)? onOutput,
) async {
  await for (final String line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
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
