import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';

sealed class ExportEntrySource {
  const ExportEntrySource();
}

final class ExportGeneratedEntry extends ExportEntrySource {
  const ExportGeneratedEntry({required this.packagePath, required this.content});

  final String packagePath;
  final String content;
}

final class ExportFileEntry extends ExportEntrySource {
  const ExportFileEntry({required this.packagePath, required this.absolutePath, required this.size});

  final String packagePath;
  final String absolutePath;
  final int size;
}

final class ExportJobRequest {
  const ExportJobRequest({required this.entries, required this.tempPath, required this.commandPort});

  final List<ExportEntrySource> entries;
  final String tempPath;
  final SendPort commandPort;
}

sealed class ExportJobEvent {
  const ExportJobEvent();
}

final class ExportJobReady extends ExportJobEvent {
  const ExportJobReady(this.stopPort);

  final SendPort stopPort;
}

final class ExportJobProgress extends ExportJobEvent {
  const ExportJobProgress(this.fraction);

  final double fraction;
}

final class ExportJobCompleted extends ExportJobEvent {
  const ExportJobCompleted();
}

final class ExportJobFailed extends ExportJobEvent {
  const ExportJobFailed(this.error);

  final Object error;
}

final class ExportJobCancelled extends ExportJobEvent {
  const ExportJobCancelled();
}

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
      await Future<void>.delayed(Duration.zero);
    }
    if (!cancelled) {
      encoder.endEncode();
    }
    return cancelled ? const ExportJobCancelled() : const ExportJobCompleted();
  } on Object catch (error) {
    return ExportJobFailed(error);
  } finally {
    output.closeSync();
  }
}

ArchiveFile _archiveFileOf(ExportEntrySource entry) => switch (entry) {
  ExportGeneratedEntry(:final String packagePath, :final String content) => ArchiveFile.string(packagePath, content),
  ExportFileEntry(:final String packagePath, :final String absolutePath, :final int size) =>
    buffersSourceInMemory(size)
        ? ArchiveFile.bytes(packagePath, File(absolutePath).readAsBytesSync())
        : ArchiveFile.stream(packagePath, InputFileStream(absolutePath, bufferSize: _sourceReadBufferSize)),
};

const int inMemorySourceLimitBytes = 16 << 20;

bool buffersSourceInMemory(int size) => size < inMemorySourceLimitBytes;
const int _sourceReadBufferSize = 1 << 20;

int _sizeOf(ExportEntrySource entry) => switch (entry) {
  ExportGeneratedEntry(:final String content) => utf8.encode(content).length,
  ExportFileEntry(:final int size) => size,
};

int _totalBytes(List<ExportEntrySource> entries) =>
    entries.fold<int>(0, (int sum, ExportEntrySource entry) => sum + _sizeOf(entry));
