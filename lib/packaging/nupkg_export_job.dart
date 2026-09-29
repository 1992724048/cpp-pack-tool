import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';

/// 只承载小而不可变的数据：isolate 之间不搬运 `Uint8List`，大文件一律凭绝对路径惰性读取。
sealed class ExportEntrySource {
  const ExportEntrySource();
}

final class ExportGeneratedEntry extends ExportEntrySource {
  const ExportGeneratedEntry({required this.packagePath, required this.content});

  final String packagePath;
  final String content;
}

/// 磁盘文件条目：[absolutePath] 指向已存在的源文件。
final class ExportFileEntry extends ExportEntrySource {
  const ExportFileEntry({
    required this.packagePath,
    required this.absolutePath,
    required this.size,
  });

  final String packagePath;
  final String absolutePath;

  /// 源文件字节数，仅用于加权进度。
  final int size;
}

/// 全部字段皆为可跨 isolate 传递的小数据；进度经 [commandPort] 回传（闭包不可跨 isolate 发送）。
final class ExportJobRequest {
  const ExportJobRequest({
    required this.entries,
    required this.tempPath,
    required this.commandPort,
  });

  /// 有序条目，落盘顺序与本列表一致。
  final List<ExportEntrySource> entries;

  /// 产物落盘路径（`.nupkg.tmp`）；改名由调用方在作业成功后完成。
  final String tempPath;

  final SendPort commandPort;
}

sealed class ExportJobEvent {
  const ExportJobEvent();
}

/// 作业已就绪；[stopPort] 是取消通道。取消必须走这层握手——`SendPort` 只能发送、
/// 不能监听，子 isolate 无法直接监听调用方的端口。
final class ExportJobReady extends ExportJobEvent {
  const ExportJobReady(this.stopPort);

  final SendPort stopPort;
}

/// 单个条目落盘后的加权进度（按各条目字节数之和计权），[fraction] 取值 0~1。
final class ExportJobProgress extends ExportJobEvent {
  const ExportJobProgress(this.fraction);

  final double fraction;
}

/// 全部条目已写入 [ExportJobRequest.tempPath]，改名尚未发生。
final class ExportJobCompleted extends ExportJobEvent {
  const ExportJobCompleted();
}

/// 作业失败；[error] 是 isolate 内抛出的原始异常对象，类型得以保留。
final class ExportJobFailed extends ExportJobEvent {
  const ExportJobFailed(this.error);

  final Object error;
}

final class ExportJobCancelled extends ExportJobEvent {
  const ExportJobCancelled();
}

/// 隔离导出作业的入口。顶层函数 + 显式入参、零闭包捕获（闭包不可跨 isolate 发送）。
///
/// 启动后先发出 [ExportJobReady] 公布取消端口，往该端口发消息即置取消位；作业在
/// **下一个条目边界**放弃——原生 deflate 是一次同步原子调用，期间无法注入取消。
///
/// 异常与取消一律转成 [ExportJobEvent] 返回、绝不外抛：isolate 带异常退出时主
/// isolate 收不到终态就会一直等下去。
Future<void> runExportJob(ExportJobRequest request) async {
  final ReceivePort stop = ReceivePort();
  var cancelled = false;
  stop.listen((dynamic _) {
    cancelled = true;
  });
  final SendPort command = request.commandPort;
  command.send(ExportJobReady(stop.sendPort));

  final ExportJobEvent terminal = await _compressEntries(
    request,
    (double fraction) => command.send(ExportJobProgress(fraction)),
    () => cancelled,
  );
  stop.close();
  command.send(terminal);
}

Future<ExportJobEvent> _compressEntries(
  ExportJobRequest request,
  void Function(double fraction) report,
  bool Function() isCancelled,
) async {
  final int totalBytes = _totalBytes(request.entries);
  final OutputFileStream output = OutputFileStream(request.tempPath);
  try {
    final ZipEncoder encoder = ZipEncoder();
    encoder.startEncode(output, level: DeflateLevel.defaultCompression);
    int writtenBytes = 0;
    bool cancelled = false;
    for (final ExportEntrySource entry in request.entries) {
      if (isCancelled()) {
        cancelled = true;
        break;
      }
      encoder.add(_archiveFileOf(entry));
      writtenBytes += _sizeOf(entry);
      report(totalBytes == 0 ? 1 : writtenBytes / totalBytes);
      // 让出事件循环：取消消息与进度回传都靠这条队列。
      await Future<void>.delayed(Duration.zero);
    }
    if (!cancelled) {
      encoder.endEncode();
    }
    return cancelled ? const ExportJobCancelled() : const ExportJobCompleted();
  } on Object catch (error) {
    return ExportJobFailed(error);
  } finally {
    // 句柄必须先于终态释放：主 isolate 收到终态后立刻改名，文件此刻仍被本 isolate
    // 持有会撞上 Windows「另一个程序正在使用此文件」。必须同步关闭——
    // [OutputStream.close] 是 `Future<void> close() async`，不 await 时句柄会越过
    // 终态（实测 300 轮「落地即改名」失败 15 次）。
    output.closeSync();
  }
}

ArchiveFile _archiveFileOf(ExportEntrySource entry) => switch (entry) {
  ExportGeneratedEntry(:final String packagePath, :final String content) =>
    ArchiveFile.string(packagePath, content),
  ExportFileEntry(
    :final String packagePath,
    :final String absolutePath,
    :final int size,
  ) => buffersSourceInMemory(size)
      ? ArchiveFile.bytes(packagePath, File(absolutePath).readAsBytesSync())
      : ArchiveFile.stream(
          packagePath,
          InputFileStream(absolutePath, bufferSize: _sourceReadBufferSize),
        ),
};

/// 严格小于该字节数的源文件整块读入内存后再压缩，更大的走流式读取。
///
/// 依据：`archive` 4.2.0 的 deflate 输入循环硬编码 1 KB 块
/// （`_zlib_encoder_io.dart`），源为 [InputFileStream] 时每块都走 `FileBuffer.sublist`，
/// 即每 1 KB 一次新分配 + 一次拷贝；源在内存时 `InputMemoryStream.toUint8List` 返回
/// `Uint8List.view`，零拷贝。
///
/// 内存源相对流式源多驻留的只有「该条目未压缩字节」一份，故峰值增量的上界就是本阈值
/// 本身；16 MB 让绝大多数条目（头文件、nuspec、常规 `.lib`）走上快路，单个超大 `.lib`
/// 仍走流式，内存依旧有界。
const int inMemorySourceLimitBytes = 16 << 20;

/// 单独成函数而非内联比较，是为了让阈值判据可被直接测。
bool buffersSourceInMemory(int size) => size < inMemorySourceLimitBytes;

/// 源文件读取块大小。
///
/// `archive` 的 [FileBuffer.kDefaultBufferSize] 仅 1 KB，逐 KB 读盘会放大系统调用
/// 数量；1 MB 与 [OutputFileStream] 的默认写缓冲对称。曾试过按条目实际字节数封顶
/// （免得 2000 个 2 KB 头文件各自分配 1 MB），同一合成包实测 4408 ms → 4379 ms，
/// 噪声级差异，故保留恒定值。
const int _sourceReadBufferSize = 1 << 20;

int _sizeOf(ExportEntrySource entry) => switch (entry) {
  ExportGeneratedEntry(:final String content) => utf8.encode(content).length,
  ExportFileEntry(:final int size) => size,
};

int _totalBytes(List<ExportEntrySource> entries) =>
    entries.fold<int>(0, (int sum, ExportEntrySource entry) => sum + _sizeOf(entry));
