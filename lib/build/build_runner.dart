import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/shared/format.dart';

typedef PackProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// 构建配方。成功构建后回调 `onVersion`：值是配方最后一条 `CNP_VERSION=`
/// 声明（去首尾空白），空串表示声明了却没给值，null（不回调）表示没声明。
typedef PackBuildRunner = Future<void> Function(
  PackModel pack, {
  Map<String, String>? environment,
  void Function(String line)? onOutput,
  void Function(String version)? onVersion,
});

typedef PackStreamingProcessRunner = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

class PackBuildException implements Exception {
  const PackBuildException(this.message, {this.outputTail});

  final String message;
  final String? outputTail;

  @override
  String toString() => message;
}

const int _outputTailLineCount = 20;

/// 配方声明包版本的协议前缀，必须位于行首。
const String _versionDeclarationPrefix = 'CNP_VERSION=';

/// 输出行里最后一条版本声明的值（去首尾空白）；未声明时为 null。空串表示
/// 配方声明了版本却没给值，与「没声明」是两种语义，不可混同。
String? _declaredRecipeVersion(Iterable<String> lines) {
  String? declared;
  for (final String line in lines) {
    if (line.startsWith(_versionDeclarationPrefix)) {
      declared = line.substring(_versionDeclarationPrefix.length).trim();
    }
  }
  return declared;
}

String _resolveSourcePath(PackModel pack) {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null) {
    throw const PackBuildException('该包缺少源目录信息');
  }
  return sourcePath;
}

Future<String> _resolveScriptPath(PackModel pack, String sourcePath) async {
  final FileModel? scriptFile = findBuildScript(pack.files);
  if (scriptFile == null) {
    throw const PackBuildException('未找到 build.py');
  }
  if (!await File(joinPath(sourcePath, scriptFile.path)).exists()) {
    throw const PackBuildException('源目录中找不到 build.py（可能已被移动）');
  }
  return scriptFile.path;
}

Future<void> runPackBuild(
  PackModel pack, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner? streamRunner,
  void Function(String line)? onOutput,
  void Function(String version)? onVersion,
  Map<String, String>? environment,
}) async {
  final String sourcePath = _resolveSourcePath(pack);
  final String scriptPath = await _resolveScriptPath(pack, sourcePath);
  try {
    await clearPackTmpDirectory(sourcePath);
  } on FileSystemException catch (error) {
    throw PackBuildException('清空中间产物目录失败：$error');
  }

  final ProcessResult result = await _runPython(
    processRunner,
    streamRunner,
    onOutput,
    sourcePath,
    scriptPath,
    environment,
  );
  if (result.exitCode != 0) {
    throw PackBuildException('构建失败（退出码 ${result.exitCode}）', outputTail: _outputTail(result));
  }
  // 置于退出码检查之后：失败构建的输出来自半途中断的配方，它声明的版本没有
  // 构建结果作背书，让版本通道保持「成功构建才可能触发」这条不变量。
  _reportRecipeVersion(result, onVersion);
}

/// 版本协议只在本文件解析，是唯一解析者：空声明也照样回调空串，由调用方决定
/// 显式告知用户「忽略了空版本」，而不是与「没声明」同样静默。调用方的输出
/// 缓冲不作数——非流式路径根本没有它，它本身又会被行数上限裁剪。
void _reportRecipeVersion(ProcessResult result, void Function(String version)? onVersion) {
  if (onVersion == null) {
    return;
  }
  final String? declared = _declaredRecipeVersion(_outputLines(result));
  if (declared == null) {
    return;
  }
  onVersion(declared);
}

Future<void> runPackBuildStreaming(
  PackModel pack, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner streamRunner = Process.start,
  void Function(String line)? onOutput,
  void Function(String version)? onVersion,
  Map<String, String>? environment,
}) {
  return runPackBuild(
    pack,
    processRunner: processRunner,
    streamRunner: streamRunner,
    onOutput: onOutput,
    onVersion: onVersion,
    environment: environment,
  );
}

Future<ProcessResult> _runPython(
  PackProcessRunner processRunner,
  PackStreamingProcessRunner? streamRunner,
  void Function(String line)? onOutput,
  String sourcePath,
  String scriptPath,
  Map<String, String>? environment,
) async {
  final Map<String, String> variables = <String, String>{...?environment, 'PYTHONIOENCODING': 'utf-8'};
  final _PythonLauncher launcher = _PythonLauncher(scriptPath);
  if (streamRunner != null) {
    return _runStreamingPython(streamRunner, launcher, onOutput, sourcePath, variables);
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
    return _runFallbackStreamingPython(streamRunner, launcher, onOutput, sourcePath, environment);
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
  final Future<void> stdoutDone = _collectProcessLines(process.stdout, stdoutLines, onOutput);
  final Future<void> stderrDone = _collectProcessLines(process.stderr, stderrLines, onOutput);
  final int exitCode = await process.exitCode;
  await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  return ProcessResult(process.pid, exitCode, _withTrailingNewline(stdoutLines), _withTrailingNewline(stderrLines));
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
      in stream.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
    lines.add(line);
    onOutput?.call(line);
  }
}

/// 还原单流末尾换行的原始文本形态（与 `ProcessResult.stdout` 语义一致）。
String _withTrailingNewline(List<String> lines) => lines.isEmpty ? '' : '${lines.join('\n')}\n';

List<String> _outputLines(ProcessResult result) => '${result.stdout}\n${result.stderr}'.split(RegExp(r'\r\n|\r|\n'));

String? _outputTail(ProcessResult result) {
  final List<String> lines = _outputLines(result);
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  final List<String> tail = lines.length <= _outputTailLineCount
      ? lines
      : lines.sublist(lines.length - _outputTailLineCount);
  final String text = tail.join('\n').trim();
  return text.isEmpty ? null : text;
}
