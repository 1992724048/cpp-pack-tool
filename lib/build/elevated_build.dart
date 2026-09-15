import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 提权构建的工作子目录名（位于本次构建的受控 `TMP` 下，见 `build_environment.dart`）。
const String elevatedBuildDirectoryName = 'elevated';

/// 提权 launcher 文件名（UTF-8 无 BOM、CRLF 行尾，见 [buildElevatedLauncher]）。
const String elevatedBuildLauncherFileName = 'elevated_build.cmd';

/// 提权构建日志文件名（launcher 把构建脚本输出重定向到此）。
const String elevatedBuildLogFileName = 'elevated_build.log';

/// 提权构建退出码标记文件名（launcher 末尾写入 `%ERRORLEVEL%`）。
const String elevatedBuildExitFileName = 'elevated_build.exit';

/// UAC 授权被取消（Win32 `ERROR_CANCELLED`）。
const int elevationCancelledExitCode = 1223;

/// 无法创建提权进程（`Start-Process` 未返回进程句柄）。
const int elevationFailedExitCode = 903;

/// 日志 tail 轮询间隔。
const Duration elevatedBuildPollInterval = Duration(milliseconds: 200);

/// 每次轮询从日志读取的最大字节数。
const int _logReadChunkSize = 64 * 1024;

/// 失败诊断尾部保留的行数（与 [PackBuildException.outputTail] 口径一致）。
const int _tailLineCount = 20;

/// 已知临时目录权限失败特征（大小写不敏感；集中定义便于扩展）。
///
/// - `error #10026`：Intel ICX 在临时目录内被 ACCESS DENIED、无法生成临时文件
///   （`TMP`/`TEMP` 指向他人所有目录等，见 `build_environment.dart` 的 Q7 说明）；
/// - `error #10030` / `cannot open internal argument file`：ICX 无法打开内部参数文件。
final List<RegExp> tempPermissionFailurePatterns = List<RegExp>.unmodifiable(
  <RegExp>[
    RegExp(r'error\s+#?\s*10026\b', caseSensitive: false),
    RegExp(r'error\s+#?\s*10030\b', caseSensitive: false),
    RegExp(r'cannot\s+open\s+internal\s+argument\s+file', caseSensitive: false),
    RegExp(r'error\s+generating\s+temporary\s+file', caseSensitive: false),
  ],
);

/// 文本（构建输出/异常信息）是否命中临时目录权限失败特征。
bool detectTempPermissionFailure(String text) => tempPermissionFailurePatterns
    .any((RegExp pattern) => pattern.hasMatch(text));

/// 提权重试入口（`BuildPackDialog` 的注入点）：以管理员身份重跑构建流水线。
typedef ElevatedPackBuildRunner = Future<void> Function(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  required BuildEnvironment buildEnvironment,
  void Function(String line)? onOutput,
  void Function(String version)? onSourceVersion,
});

/// 日志 tail 的行解码器：字节块 → 完整输出行。
///
/// 与既有流式口径一致：按 `\r\n` / `\r` / `\n` 切分（git 进度行经 `\r` 刷新）、
/// 无效 UTF-8 字节按替换字符容错；跨块的不完整 UTF-8 序列与未终结片段留在内部，
/// 由后续块或 [flush] 补齐。
class LogTailDecoder {
  final List<int> _pendingBytes = <int>[];
  final StringBuffer _pendingText = StringBuffer();

  /// 追加字节块，返回本次可确定的完整行（不含行尾符）。
  List<String> add(List<int> chunk) {
    _pendingBytes.addAll(chunk);
    final int completeBytes = _completeUtf8Length(_pendingBytes);
    final String text =
        _pendingText.toString() +
        utf8.decode(
          _pendingBytes.sublist(0, completeBytes),
          allowMalformed: true,
        );
    _pendingText.clear();
    _pendingBytes.removeRange(0, completeBytes);

    final List<String> lines = <String>[];
    int start = 0;
    for (int index = 0; index < text.length; index++) {
      final int codeUnit = text.codeUnitAt(index);
      if (codeUnit != 0x0A && codeUnit != 0x0D) {
        continue;
      }
      lines.add(text.substring(start, index));
      if (codeUnit == 0x0D &&
          index + 1 < text.length &&
          text.codeUnitAt(index + 1) == 0x0A) {
        index++;
      }
      start = index + 1;
    }
    _pendingText.write(text.substring(start));
    return lines;
  }

  /// 未终结的末尾片段（进程结束后调用，补齐流式口径的最后一行）；无内容返回 null。
  String? flush() {
    if (_pendingBytes.isEmpty && _pendingText.isEmpty) {
      return null;
    }
    final String text =
        _pendingText.toString() +
        utf8.decode(_pendingBytes, allowMalformed: true);
    _pendingBytes.clear();
    _pendingText.clear();
    return text;
  }

  /// 末尾不完整 UTF-8 序列的起始下标（完整/无法判定时返回 `bytes.length`）。
  static int _completeUtf8Length(List<int> bytes) {
    int index = bytes.length;
    int continuation = 0;
    while (index > 0) {
      final int byte = bytes[index - 1];
      if ((byte & 0xC0) == 0x80) {
        continuation++;
        index--;
        if (continuation > 3) {
          return bytes.length;
        }
        continue;
      }
      final int needed = switch (byte) {
        >= 0xF0 => 4,
        >= 0xE0 => 3,
        >= 0xC0 => 2,
        _ => 1,
      };
      if (continuation + 1 >= needed) {
        return bytes.length;
      }
      return index - 1;
    }
    return bytes.length;
  }
}

/// 生成提权构建 launcher（cmd 批处理）内容；生产路径以 UTF-8（无 BOM）写入
/// `.cmd` 文件（文件名见 [elevatedBuildLauncherFileName]）。
///
/// - 首行 `chcp 65001`：cmd 按控制台代码页解析批处理文件，含非 ASCII 路径
///   （中文等）的 UTF-8 文件在 cp936 等代码页下会解析错误；切换代码页后
///   再解析后续行（本机实测 cp936 下有效）。文件须以 CRLF 行尾保存（cmd 对
///   LF-only 批处理会吞字符）。
/// - 全部插值文本把 `%` 转义为 `%%`（批处理解析期展开一次）；`set` 值额外
///   去掉 `"`（值内的引号会破坏 `set "K=V"` 的引号配对，PATH 等值语义不受影响）。
/// - 覆盖写入 [environment] 全部变量（提权进程不依赖环境继承），再执行
///   `python -u <脚本>`（`pythonUsesLauncher` 为真时用 `py -3`）；找不到解释器
///   （errorlevel 9009）回退另一个启动命令。
/// - 末行把 `%ERRORLEVEL%` 写入 [exitCodePath]（完成检测与退出码事实源）。
String buildElevatedLauncher({
  required String sourcePath,
  required String scriptRelativePath,
  required String pythonExecutable,
  bool pythonUsesLauncher = false,
  Map<String, String> environment = const <String, String>{},
  required String logPath,
  required String exitCodePath,
}) {
  final StringBuffer output = StringBuffer();
  output.write('@echo off\r\n');
  output.write('chcp 65001 >nul 2>&1\r\n');
  output.write('title C++ Pack Tool - 管理员构建\r\n');
  output.write('call :main > "${_batchText(logPath)}" 2>&1\r\n');
  output.write('echo %ERRORLEVEL% > "${_batchText(exitCodePath)}"\r\n');
  output.write('exit /b\r\n');
  output.write(':main\r\n');
  output.write('setlocal\r\n');
  for (final MapEntry<String, String> entry in environment.entries) {
    output.write(
      'set "${_batchText(entry.key)}=${_batchSetValue(entry.value)}"\r\n',
    );
  }
  output.write('cd /d "${_batchText(sourcePath)}"\r\n');
  output.write('if errorlevel 1 exit /b %ERRORLEVEL%\r\n');
  final String script = _batchText(scriptRelativePath.replaceAll('/', r'\'));
  final String launcherArguments = pythonUsesLauncher ? '-3 ' : '';
  output.write(
    '"${_batchText(pythonExecutable)}" $launcherArguments-u "$script"\r\n',
  );
  output.write('if errorlevel 9009 goto :fallback_python\r\n');
  output.write('exit /b %ERRORLEVEL%\r\n');
  output.write(':fallback_python\r\n');
  output.write(
    pythonUsesLauncher ? 'python -u "$script"\r\n' : 'py -3 -u "$script"\r\n',
  );
  output.write('exit /b %ERRORLEVEL%\r\n');
  return output.toString();
}

/// 生成提权启动脚本（PowerShell，经 `-EncodedCommand` 传入，见 [runElevatedPackBuild]）。
///
/// 以 `Start-Process -Verb RunAs` 请求 UAC 并等待提权进程结束：
/// - 授权被拒/取消时 `Start-Process` 抛异常，脚本把原始信息写入 stderr 并以
///   [elevationCancelledExitCode] 退出；
/// - 等待用 PID 轮询（`[Process]::GetProcessById`）而非 `$p.ExitCode`——经
///   ShellExecute 启动的批处理进程对象退出码不可靠（本机实测恒为 0），退出码
///   以 launcher 写出的标记文件为准；
/// - 进程不存在（`ArgumentException`）即结束；权限受限等其它查询失败按仍在
///   运行处理，避免把「查不到」误判为「已结束」。
String buildElevatedStarterScript(String launcherPath) {
  final String quotedPath = launcherPath.replaceAll("'", "''");
  return '''
\$ErrorActionPreference = 'Stop'
try {
  \$process = Start-Process -FilePath '$quotedPath' -Verb RunAs -PassThru
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  exit $elevationCancelledExitCode
}
if (\$null -eq \$process) {
  [Console]::Error.WriteLine('Start-Process 未返回提权进程句柄')
  exit $elevationFailedExitCode
}
while (\$true) {
  try {
    [void][System.Diagnostics.Process]::GetProcessById(\$process.Id)
  } catch [ArgumentException] {
    break
  } catch {
  }
  Start-Sleep -Milliseconds 500
}
exit 0
''';
}

/// 以管理员身份重跑构建流水线（临时目录权限失败的 UAC 重试路径）。
///
/// 流程：[prepareSource]（缺省 [preparePackSource]：git 拉取/对齐与包源目录
/// 清理，非提权）→ 生成 [buildElevatedLauncher] 到本次构建受控 `TMP` 下的
/// `elevated/` 目录 → 经 [launcherStarter]（缺省 `Process.run`）运行 PowerShell
/// 提权启动器 → 轮询日志 tail 逐行回调 [onOutput]（[LogTailDecoder] 口径）→
/// 以退出码标记文件判定结果。构建脚本的输出/失败语义与 [runPackBuild] 一致：
/// 非零退出抛 [PackBuildException] 并携带输出尾部。
///
/// [buildEnvironment] 提供与常规构建完全相同的子进程环境（[BuildEnvironment.environment]）
/// 与已解析的 Python 解释器（绝对路径优先嵌入 launcher）。
/// [launcherStarter] 为测试注入点：全部测试替身，绝不触发真实 UAC 弹窗。
Future<void> runElevatedPackBuild(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  required BuildEnvironment buildEnvironment,
  PackProcessRunner processRunner = Process.run,
  PackStreamingProcessRunner? streamRunner = Process.start,
  void Function(String line)? onOutput,
  void Function(String version)? onSourceVersion,
  String cacheRoot = 'cache',
  PackSourcePreparer prepareSource = preparePackSource,
  PackProcessRunner launcherStarter = Process.run,
  Duration pollInterval = elevatedBuildPollInterval,
}) async {
  final PackSourcePreparation source = await prepareSource(
    pack,
    onStage,
    processRunner: processRunner,
    streamRunner: streamRunner,
    onOutput: onOutput,
    onSourceVersion: onSourceVersion,
    cacheRoot: cacheRoot,
    environment: buildEnvironment.environment,
  );
  onStage(PackBuildStage.building);
  await _runElevatedBuildScript(
    buildEnvironment,
    source,
    onOutput: onOutput,
    launcherStarter: launcherStarter,
    pollInterval: pollInterval,
  );
}

Future<void> _runElevatedBuildScript(
  BuildEnvironment buildEnvironment,
  PackSourcePreparation source, {
  required void Function(String line)? onOutput,
  required PackProcessRunner launcherStarter,
  required Duration pollInterval,
}) async {
  final Directory runDirectory = await _createElevatedRunDirectory(
    buildEnvironment.environment,
  );
  final File launcher = File(
    joinPath(runDirectory.path, elevatedBuildLauncherFileName),
  );
  final File log = File(joinPath(runDirectory.path, elevatedBuildLogFileName));
  final File exitCodeFile = File(
    joinPath(runDirectory.path, elevatedBuildExitFileName),
  );
  await _deleteQuietly(log);
  await _deleteQuietly(exitCodeFile);

  final ProvisionedPython? python = buildEnvironment.python;
  await launcher.writeAsString(
    buildElevatedLauncher(
      sourcePath: source.sourcePath,
      scriptRelativePath: source.scriptPath,
      pythonExecutable: python?.executable ?? 'python',
      pythonUsesLauncher: python?.source == PythonSource.launcher,
      environment: <String, String>{
        ...buildEnvironment.environment,
        'SRC_PATH': source.target.absolute.path,
        'BUILD_OUT': Directory(source.sourcePath).absolute.path,
        'PYTHONIOENCODING': 'utf-8',
      },
      logPath: log.path,
      exitCodePath: exitCodeFile.path,
    ),
  );

  final String encodedScript = base64Encode(
    _utf16LeBytes(buildElevatedStarterScript(launcher.path)),
  );
  bool starterDone = false;
  Object? starterError;
  ProcessResult? starterResult;
  final Future<void> starterFuture = () async {
    try {
      starterResult = await launcherStarter('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        encodedScript,
      ]);
    } catch (error) {
      starterError = error;
    } finally {
      starterDone = true;
    }
  }();

  final LogTailDecoder decoder = LogTailDecoder();
  int offset = 0;
  while (!starterDone) {
    offset = await _drainLog(log, offset, decoder, onOutput);
    await Future<void>.delayed(pollInterval);
  }
  await starterFuture;
  await _drainLog(log, offset, decoder, onOutput);
  final String? lastLine = decoder.flush();
  if (lastLine != null) {
    onOutput?.call(lastLine);
  }

  final String? marker = await _readText(exitCodeFile);
  if (marker == null) {
    throw _starterFailure(starterError, starterResult);
  }
  final int? code = int.tryParse(marker.trim());
  if (code == null) {
    throw PackBuildException('提权构建退出码不可解析：${marker.trim()}');
  }
  if (code != 0) {
    throw PackBuildException(
      '以管理员身份构建失败（退出码 $code）',
      outputTail: await _logTail(log),
    );
  }
}

/// 提权进程未写出退出码标记时的错误分类（UAC 取消 / 启动失败 / 异常结束）。
PackBuildException _starterFailure(
  Object? starterError,
  ProcessResult? result,
) {
  if (starterError != null) {
    return PackBuildException('无法启动提权构建：${formatError(starterError)}');
  }
  final int code = result?.exitCode ?? -1;
  final String detail = _firstDiagnosticLine(result);
  final String suffix = detail.isEmpty ? '' : '：$detail';
  if (code == elevationCancelledExitCode) {
    return const PackBuildException('已取消以管理员身份重试（UAC 授权被拒绝）');
  }
  if (code == elevationFailedExitCode) {
    return PackBuildException('无法创建提权构建进程$suffix');
  }
  return PackBuildException('提权构建未写入退出码标记（进程可能被强制结束；启动器退出码 $code）$suffix');
}

/// 从启动器输出中取首个可用诊断行（跳过 CLIXML 噪声与空行）。
String _firstDiagnosticLine(ProcessResult? result) {
  if (result == null) {
    return '';
  }
  for (final String rawLine in '${result.stdout}\n${result.stderr}'.split(
    RegExp(r'\r\n|\r|\n'),
  )) {
    final String line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#<') || line.startsWith('<Objs')) {
      continue;
    }
    return line.length > 200 ? '${line.substring(0, 200)}…' : line;
  }
  return '';
}

/// 读取日志文件末尾若干行作为 [PackBuildException.outputTail]。
Future<String?> _logTail(File log) async {
  final String? text = await _readText(log);
  if (text == null) {
    return null;
  }
  final List<String> lines = text.split(RegExp(r'\r\n|\r|\n'));
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) {
    return null;
  }
  final List<String> tail = lines.length <= _tailLineCount
      ? lines
      : lines.sublist(lines.length - _tailLineCount);
  final String joined = tail.join('\n').trim();
  return joined.isEmpty ? null : joined;
}

/// 读取提权构建工作目录：优先本次构建的受控 `TMP`，不可用时退回系统临时目录。
Future<Directory> _createElevatedRunDirectory(
  Map<String, String> environment,
) async {
  final String? tempRoot =
      _environmentValue(environment, 'TMP') ??
      _environmentValue(environment, 'TEMP');
  if (tempRoot != null && tempRoot.isNotEmpty) {
    try {
      final Directory directory = Directory(
        joinPath(tempRoot, elevatedBuildDirectoryName),
      );
      await directory.create(recursive: true);
      return directory;
    } on FileSystemException {
      // 受控 TMP 不可写（如工作目录只读）：退回系统临时目录。
    }
  }
  return Directory.systemTemp.createTemp('cnp-elevated-');
}

/// 把日志新增字节线性解码为输出行并回调；返回新的读取偏移。
///
/// 文件暂不存在（launcher 尚未写入）或读取竞争失败时原样返回偏移，
/// 由下一轮轮询重试。
Future<int> _drainLog(
  File log,
  int offset,
  LogTailDecoder decoder,
  void Function(String line)? onOutput,
) async {
  if (!await log.exists()) {
    return offset;
  }
  RandomAccessFile? handle;
  try {
    handle = await log.open();
    await handle.setPosition(offset);
    while (true) {
      final List<int> chunk = await handle.read(_logReadChunkSize);
      if (chunk.isEmpty) {
        break;
      }
      offset += chunk.length;
      for (final String line in decoder.add(chunk)) {
        onOutput?.call(line);
      }
    }
  } on FileSystemException {
    return offset;
  } finally {
    await handle?.close();
  }
  return offset;
}

String? _environmentValue(Map<String, String> environment, String key) {
  final String normalized = key.toLowerCase();
  for (final MapEntry<String, String> entry in environment.entries) {
    if (entry.key.toLowerCase() == normalized) {
      return entry.value;
    }
  }
  return null;
}

/// 批处理插值文本：`%` → `%%`（解析期展开一次），去掉换行。
String _batchText(String value) =>
    value.replaceAll('%', '%%').replaceAll(RegExp(r'[\r\n]'), '');

/// 批处理 `set "K=V"` 的值：在 [_batchText] 基础上去掉会破坏引号配对的 `"`。
String _batchSetValue(String value) => _batchText(value).replaceAll('"', '');

/// UTF-16LE 字节（PowerShell `-EncodedCommand` 要求的编码）。
List<int> _utf16LeBytes(String text) {
  final List<int> bytes = <int>[];
  for (final int unit in text.codeUnits) {
    bytes.add(unit & 0xFF);
    bytes.add((unit >> 8) & 0xFF);
  }
  return bytes;
}

/// 读取文本内容；不存在或读取失败返回 null（不做静默吞错的调用方另有处理）。
Future<String?> _readText(File file) async {
  try {
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // 残留文件会在 launcher 重定向时被截断，删除失败不阻断。
  }
}
