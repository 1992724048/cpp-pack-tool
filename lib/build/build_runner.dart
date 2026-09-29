import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// UI 层构建入口：可传 [environment] 捕获好的子进程环境与 [onOutput] 逐行回调。
typedef PackBuildRunner = Future<void> Function(
  PackModel pack, {
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

/// 构建失败异常：[message] 面向用户展示，[outputTail] 为进程输出末尾片段。
class PackBuildException implements Exception {
  const PackBuildException(this.message, {this.outputTail});

  final String message;
  final String? outputTail;

  @override
  String toString() => message;
}

const int _outputTailLineCount = 20;

/// 取包源目录；缺失时抛 [PackBuildException]。
String _resolveSourcePath(PackModel pack) {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null) {
    throw const PackBuildException('该包缺少源目录信息');
  }
  return sourcePath;
}

/// 取根级 `build.py` 的包内相对路径，并确认它确实落在包源目录中；缺任一环
/// 抛 [PackBuildException]——脚本不在磁盘上时后续只会报一句难以定位的
/// python 错误。
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

/// 执行包内 `build.py`（单段流水线，无备源阶段）。
///
/// 流程：校验包源目录与根级 `build.py` → 清空 `.cache/tmp`（`.cache` 其余部分
/// 归配方自己管）→ 在**包源目录**中执行 `python build.py`。产物落点、源码区与
/// 中间产物区一律由 `CNP_*` 变量告诉配方（见 `assembleBuildEnvironment`），
/// 本层不下发任何位置变量，也不替用户搬任何文件。
///
/// python 子进程固定注入 `PYTHONIOENCODING=utf-8`，保证管道中的 stdout/stderr
/// 恒为 UTF-8（中文 Windows 下默认按 GBK 编码，会与流式解码口径不一致）。
///
/// [onOutput] 逐行转发 python 输出；[streamRunner] 为 null 时保持一次性捕获，
/// 非 null 时以其为流式执行器（生产经 [runPackBuildStreaming] 注入
/// `Process.start`）。前置校验、tmp 清理失败抛 [PackBuildException]，
/// 构建脚本非零退出抛 [PackBuildException]（携带输出尾部）。
Future<void> runPackBuild(
  PackModel pack, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner? streamRunner,
  void Function(String line)? onOutput,
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
    throw PackBuildException(
      '构建失败（退出码 ${result.exitCode}）',
      outputTail: _outputTail(result),
    );
  }
}

/// 生产构建入口：[runPackBuild] 的流式变体，默认以 `Process.start` 逐行转发
/// python 子进程输出（UI 实时显示）；其余参数口径与 [runPackBuild]
/// 完全一致。测试可经 [streamRunner] 注入替代执行器。
Future<void> runPackBuildStreaming(
  PackModel pack, {
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner streamRunner = Process.start,
  void Function(String line)? onOutput,
  Map<String, String>? environment,
}) {
  return runPackBuild(
    pack,
    processRunner: processRunner,
    streamRunner: streamRunner,
    onOutput: onOutput,
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
  final Map<String, String> variables = <String, String>{
    ...?environment,
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
