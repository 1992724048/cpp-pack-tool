import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/nuget/nuget_builder.dart';
import 'package:cpp_nuget_pack/nuget/nupkg_export_job.dart';
import 'package:cpp_nuget_pack/nuget/package_icon.dart';
import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:cpp_nuget_pack/shared/format.dart';

typedef PackageExportResult = ({String outputPath, int fileCount, int packageSize});

const String _contentTypesPath = '[Content_Types].xml';
const String _relationshipsPath = '_rels/.rels';
const String _iconPath = 'images/icon.png';
const String _corePropertiesPath = 'package/services/metadata/core-properties/nuget.psmdcp';
const String _manifestRelationshipType = 'http://schemas.microsoft.com/packaging/2010/07/manifest';
const String _corePropertiesRelationshipType =
    'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties';
const String _relationshipsContentType = 'application/vnd.openxmlformats-package.relationships+xml';
const String _corePropertiesContentType = 'application/vnd.openxmlformats-package.core-properties+xml';
const String _octetContentType = 'application/octet';
const String _corePropertiesNamespace = 'http://schemas.openxmlformats.org/package/2006/metadata/core-properties';
const String _relationshipsNamespace = 'http://schemas.openxmlformats.org/package/2006/relationships';
const int _opcFileCount = 3;
const int _iconFileCount = 1;

const Duration _isolateExitGrace = Duration(seconds: 5);

class ExportCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => '导出已取消';
}

Future<PackageExportResult> exportNuGetPackage(
  PackModel pack,
  String outputDirectory, {
  Future<Uint8List> Function(PackModel pack)? iconResolver,
  void Function(double fraction)? onProgress,
  ExportCancelToken? cancelToken,
}) async {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null) {
    throw ArgumentError('该包缺少源目录信息，无法打包');
  }

  final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(pack);
  final Uint8List iconBytes = await (iconResolver ?? resolvePackageIconPng)(pack);
  final String nuspecPath = '${pack.name}.nuspec';
  final PackageEntry nuspecEntry = plan.entries.firstWhere(
    (PackageEntry entry) => entry.packagePath == nuspecPath,
    orElse: () => throw StateError('打包计划缺少 $nuspecPath'),
  );

  Directory(outputDirectory).createSync(recursive: true);
  final String fileName = '${pack.name}.${NuGetPackageBuilder.normalizedVersion(pack.version)}.nupkg';
  final String outputPath = joinPath(outputDirectory, fileName);
  final String tempPath = '$outputPath.tmp';
  final String iconTempPath = '$outputPath.icon.tmp';

  final List<ExportEntrySource> entries = <ExportEntrySource>[
    ExportGeneratedEntry(packagePath: _relationshipsPath, content: _relationshipsContent(pack)),
    _entrySourceOf(nuspecEntry, sourcePath),
    for (final PackageEntry entry in plan.entries)
      if (entry.packagePath != nuspecPath) _entrySourceOf(entry, sourcePath),
    ExportFileEntry(packagePath: _iconPath, absolutePath: iconTempPath, size: iconBytes.length),
    ExportGeneratedEntry(
      packagePath: _contentTypesPath,
      content: _contentTypesContent(plan, extraExtensions: const <String>{'png'}),
    ),
    ExportGeneratedEntry(packagePath: _corePropertiesPath, content: _corePropertiesContent(pack)),
  ];

  try {
    File(iconTempPath).writeAsBytesSync(iconBytes);
    await _runExportJob(entries: entries, tempPath: tempPath, onProgress: onProgress, cancelToken: cancelToken);
    final int packageSize = File(tempPath).lengthSync();
    final File outputFile = File(outputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
    File(tempPath).renameSync(outputPath);
    return (
      outputPath: outputPath,
      fileCount: plan.fileCount + _opcFileCount + _iconFileCount,
      packageSize: packageSize,
    );
  } on Object {
    await _deleteIfExists(tempPath);
    rethrow;
  } finally {
    await _deleteIfExists(iconTempPath);
  }
}

const int _cleanupAttempts = 10;
const Duration _cleanupDelay = Duration(milliseconds: 20);

Future<void> _deleteIfExists(String path) async {
  final File file = File(path);
  for (int attempt = 1; ; attempt++) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
      return;
    } on FileSystemException {
      if (attempt >= _cleanupAttempts) {
        return;
      }
      await Future<void>.delayed(_cleanupDelay * attempt);
    }
  }
}

ExportEntrySource _entrySourceOf(PackageEntry entry, String sourcePath) => switch (entry.source) {
  PackageGeneratedSource(:final String content) => ExportGeneratedEntry(
    packagePath: entry.packagePath,
    content: content,
  ),
  PackageFileSource(:final String path) => ExportFileEntry(
    packagePath: entry.packagePath,
    absolutePath: joinPath(sourcePath, path),
    size: File(joinPath(sourcePath, path)).lengthSync(),
  ),
};

Future<void> _runExportJob({
  required List<ExportEntrySource> entries,
  required String tempPath,
  required void Function(double fraction)? onProgress,
  required ExportCancelToken? cancelToken,
}) async {
  if (cancelToken?.isCancelled ?? false) {
    throw const ExportCancelledException();
  }
  final ReceivePort commands = ReceivePort();
  final ReceivePort workerExit = ReceivePort();
  final Completer<void> completion = Completer<void>();
  final Completer<void> workerGone = Completer<void>();
  Isolate? isolate;
  Timer? cancelWatcher;

  try {
    isolate = await Isolate.spawn<ExportJobRequest>(
      _spawnedExportJob,
      ExportJobRequest(entries: entries, tempPath: tempPath, commandPort: commands.sendPort),
      onExit: workerExit.sendPort,
      onError: commands.sendPort,
    );

    void fail(Object error) {
      if (!completion.isCompleted) {
        completion.completeError(error);
      }
    }

    workerExit.listen((dynamic _) {
      if (!workerGone.isCompleted) {
        workerGone.complete();
      }
      fail(StateError('导出进程意外退出'));
    });

    SendPort? workerStopPort;
    bool cancelPending = false;
    void deliverCancellation() {
      final SendPort? port = workerStopPort;
      if (port == null) {
        cancelPending = true;
        return;
      }
      if (!cancelPending) {
        return;
      }
      cancelPending = false;
      port.send(null);
    }

    commands.listen((dynamic event) {
      switch (event) {
        case ExportJobReady(:final SendPort stopPort):
          workerStopPort = stopPort;
          deliverCancellation();
        case ExportJobProgress(:final double fraction):
          deliverCancellation();
          try {
            onProgress?.call(fraction);
          } on Object catch (error) {
            fail(error);
          }
        case ExportJobCompleted():
          if (!completion.isCompleted) {
            completion.complete();
          }
        case ExportJobFailed(:final Object error):
          fail(error);
        case ExportJobCancelled():
          fail(const ExportCancelledException());
        case final List<Object?> pair:
          fail(pair.first ?? StateError('导出进程异常退出'));
        default:
          fail(StateError('导出进程回传了未识别的消息：${event.runtimeType}'));
      }
    });

    final ExportCancelToken? token = cancelToken;
    if (token != null) {
      void watchCancellation() {
        if (token.isCancelled) {
          cancelPending = true;
          deliverCancellation();
        }
      }

      cancelWatcher = Timer.periodic(const Duration(milliseconds: 100), (Timer _) => watchCancellation());
      watchCancellation();
    }

    await completion.future;
  } finally {
    cancelWatcher?.cancel();
    if (isolate != null) {
      isolate.kill(priority: Isolate.immediate);
      await workerGone.future.timeout(_isolateExitGrace, onTimeout: () {});
    }
    workerExit.close();
    commands.close();
  }
}

Future<void> _spawnedExportJob(ExportJobRequest request) => runExportJob(request);

String _relationshipsContent(PackModel pack) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<Relationships xmlns="$_relationshipsNamespace">')
    ..writeln(
      '  <Relationship Type="$_manifestRelationshipType" '
      'Target="/${_escapeXml(pack.name)}.nuspec" Id="R1" />',
    )
    ..writeln(
      '  <Relationship Type="$_corePropertiesRelationshipType" '
      'Target="/$_corePropertiesPath" Id="R2" />',
    );
  buffer.writeln('</Relationships>');
  return buffer.toString();
}

String _contentTypesContent(PackagePlan plan, {Set<String> extraExtensions = const <String>{}}) {
  final Set<String> extensions = <String>{...extraExtensions};
  final List<String> overrides = <String>[];
  for (final PackageEntry entry in plan.entries) {
    final String? extension = _extensionOf(entry.packagePath);
    if (extension == null) {
      overrides.add(entry.packagePath);
    } else {
      extensions.add(extension);
    }
  }
  final List<String> sortedExtensions = extensions.toList()..sort();
  overrides.sort(comparePackagePaths);

  final StringBuffer buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..writeln('  <Default Extension="rels" ContentType="$_relationshipsContentType" />')
    ..writeln('  <Default Extension="psmdcp" ContentType="$_corePropertiesContentType" />');
  for (final String extension in sortedExtensions) {
    buffer.writeln(
      '  <Default Extension="${_escapeXml(extension)}" '
      'ContentType="$_octetContentType" />',
    );
  }
  for (final String path in overrides) {
    buffer.writeln(
      '  <Override PartName="/${_escapeXml(path)}" '
      'ContentType="$_octetContentType" />',
    );
  }
  buffer.writeln('</Types>');
  return buffer.toString();
}

String _corePropertiesContent(PackModel pack) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln(
      '<coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xmlns="$_corePropertiesNamespace">',
    )
    ..writeln('  <dc:creator>${_escapeXml(pack.author)}</dc:creator>')
    ..writeln('  <dc:description>${_escapeXml(pack.description ?? '')}</dc:description>')
    ..writeln('  <dc:identifier>${_escapeXml(pack.name)}</dc:identifier>')
    ..writeln('  <version>${_escapeXml(NuGetPackageBuilder.normalizedVersion(pack.version))}</version>')
    ..writeln('  <keywords>native cpp</keywords>')
    ..writeln('  <lastModifiedBy>cpp_nuget_pack</lastModifiedBy>');
  buffer.writeln('</coreProperties>');
  return buffer.toString();
}

String? _extensionOf(String packagePath) {
  final String name = baseName(packagePath);
  final int separator = name.lastIndexOf('.');
  if (separator <= 0 || separator == name.length - 1) {
    return null;
  }
  return name.substring(separator + 1).toLowerCase();
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
