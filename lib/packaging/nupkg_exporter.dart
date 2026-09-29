import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_export_job.dart';
import 'package:cpp_nuget_pack/packaging/package_icon.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/format.dart';

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

/// nuget.org 上传上限：图标 1 MB。
const int maxNuGetIconBytes = 1024 * 1024;

/// 杀掉子 isolate 后等它真正退出的宽限。
///
/// 正常路径下退出通知早已在队列里，这个 await 立即返回；只有进度回调失败那条
/// 「worker 仍握着产物句柄」的出口会真的花时间。注意它**不**代表句柄已释放
/// （见 [_deleteIfExists] 的实测），只保证 isolate 不活过 [_runExportJob]。
const Duration _isolateExitGrace = Duration(seconds: 5);

/// 导出取消令牌：置位后导出在下一个条目边界放弃并清理临时文件。
class ExportCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

/// 导出被取消，调用方据此与导出失败区分。
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => '导出已取消';
}

/// 将 [pack] 的打包计划导出为 NuGet 包（.nupkg）到 [outputDirectory]；源文件缺失或
/// 读取失败时抛出异常。
///
/// 压缩与落盘在独立 isolate 内逐条目流式完成（协议见 [ExportJobRequest]），主 isolate
/// 的事件循环全程可响应。[onProgress] 回传按字节加权的 0~1 进度；[cancelToken] 置位后
/// 作业在条目边界放弃，临时文件一律清理。[iconResolver] 为测试注入点，默认
/// [resolvePackageIconPng]。
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
  if (iconBytes.length > maxNuGetIconBytes) {
    throw StateError(
      '图标 ${formatBytes(iconBytes.length)} 超过 nuget.org 上限 '
      '${formatBytes(maxNuGetIconBytes)}',
    );
  }
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
    ExportGeneratedEntry(
      packagePath: _relationshipsPath,
      content: _relationshipsContent(pack),
    ),
    _entrySourceOf(nuspecEntry, sourcePath),
    for (final PackageEntry entry in plan.entries)
      if (entry.packagePath != nuspecPath) _entrySourceOf(entry, sourcePath),
    ExportFileEntry(
      packagePath: _iconPath,
      absolutePath: iconTempPath,
      size: iconBytes.length,
    ),
    ExportGeneratedEntry(
      packagePath: _contentTypesPath,
      content: _contentTypesContent(plan, extraExtensions: const <String>{'png'}),
    ),
    ExportGeneratedEntry(
      packagePath: _corePropertiesPath,
      content: _corePropertiesContent(pack),
    ),
  ];

  try {
    File(iconTempPath).writeAsBytesSync(iconBytes);
    await _runExportJob(
      entries: entries,
      tempPath: tempPath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
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
    // 半成品 .tmp 不留痕：原子改名语义要求「要么完整包、要么什么都没有」。
    await _deleteIfExists(tempPath);
    rethrow;
  } finally {
    await _deleteIfExists(iconTempPath);
  }
}

/// 失败清理的重试上限与退避基数。
///
/// 覆盖的场景是「进度回调失败后强杀 isolate，而 Dart VM 不会为被杀的 isolate 跑
/// finalizer」，其写句柄不随退出信号释放——实测持句柄的 isolate 被 kill 后退出通知
/// 0 ms 抵达，但 30/30 轮产物立即都删不掉，3 秒后仍有 14/30 被占。
const int _cleanupAttempts = 10;
const Duration _cleanupDelay = Duration(milliseconds: 20);

/// 尽力删除临时文件：重试有界，最终失败也不抛。
///
/// 不抛是刻意的——它只在 `on Object` 与 `finally` 里跑，抛出去会顶替掉导出本身的异常
/// （实测把 StateError 换成 PathAccessException），那才是真正掩盖问题。残留的 `.tmp`
/// 是自愈的：临时路径由产物名确定，下次导出覆写同一路径并在自己的清理里删掉。
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

ExportEntrySource _entrySourceOf(PackageEntry entry, String sourcePath) =>
    switch (entry.source) {
      PackageGeneratedSource(:final String content) => ExportGeneratedEntry(
        packagePath: entry.packagePath,
        content: content,
      ),
      PackageFileSource(:final String path) => ExportFileEntry(
        packagePath: entry.packagePath,
        absolutePath: joinPath(sourcePath, path),
        // 按磁盘实际字节数加权：计划里的 size 是扫描时的快照，可能已经过期。
        size: File(joinPath(sourcePath, path)).lengthSync(),
      ),
    };

/// 主 isolate 在此只做端口收发与改名，压缩全程在子 isolate 阻塞，故 UI 不冻结。
/// 取消通道取自子 isolate 公布的 [ExportJobReady.stopPort]，置位后向其投递消息。
Future<void> _runExportJob({
  required List<ExportEntrySource> entries,
  required String tempPath,
  required void Function(double fraction)? onProgress,
  required ExportCancelToken? cancelToken,
}) async {
  // 导出前即已取消：根本不起作业。条目级取消依赖消息往返，短包会在消息送达前跑完，
  // 硬等取消反而会产出一个用户明确不要的包。
  if (cancelToken?.isCancelled ?? false) {
    throw const ExportCancelledException();
  }
  final ReceivePort commands = ReceivePort();
  // 作业退出信号单独一个端口：既要回答「worker 是不是已经死了」（否则主 isolate 永远
  // 等终态），也要回答「它现在确实已经退出」（收尾据此保证 isolate 不活过本函数）。
  // 只能用 spawn 时注册的 onExit 端口——实测 addOnExitListener 对已退出的 isolate
  // 永不投递。
  final ReceivePort workerExit = ReceivePort();
  final Completer<void> completion = Completer<void>();
  final Completer<void> workerGone = Completer<void>();
  Isolate? isolate;
  Timer? cancelWatcher;

  try {
    // spawn 自身可能失败（系统拒绝建 isolate、内存不足），故在 try 内：
    // 放在 try 外的话异常直接上抛，commands 端口永不 close，被 VM 持有到 GC。
    isolate = await Isolate.spawn<ExportJobRequest>(
      _spawnedExportJob,
      ExportJobRequest(
        entries: entries,
        tempPath: tempPath,
        commandPort: commands.sendPort,
      ),
      onExit: workerExit.sendPort,
      onError: commands.sendPort,
    );

    void fail(Object error) {
      if (!completion.isCompleted) {
        completion.completeError(error);
      }
    }

    // worker 带异常退出时终态永远不会来（isolate 内的异常出口只产出
    // ExportJobFailed，意外死亡走 VM 的 onExit/onError），故主 isolate 会永远等终态。
    // ReceivePort 是单订阅流，故这一个监听器同时负责放行主流程与标记「可以碰文件了」。
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
            // onProgress 是公开注入点，第三方实现抛异常若逃出监听器，completion
            // 永不完成。
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
          // onError 回调消息：[错误, 栈]
          fail(pair.first ?? StateError('导出进程异常退出'));
        default:
          // 消息集是 sealed 的、当前穷尽；真出现未预期形状时宁可报错也不要静默
          // 丢弃——那正是主 isolate 永远等终态。
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

      // 进度回调与定时器是主 isolate 在导出期间仅有的执行时机，取消检测挂两处。
      cancelWatcher = Timer.periodic(
        const Duration(milliseconds: 100),
        (Timer _) => watchCancellation(),
      );
      watchCancellation();
    }

    await completion.future;
  } finally {
    // 定时器不靠回调自杀：正常路径下它会越过 finally 多活 100 ms，而 completion
    // 永不完成时它会永久每 100 ms 跑一次。
    cancelWatcher?.cancel();
    if (isolate != null) {
      isolate.kill(priority: Isolate.immediate);
      // 等 worker 确实退出，免得 isolate 活过本函数。它**不**保证文件句柄已释放
      // ——被杀的 isolate 不会被 VM 跑 finalizer，句柄要等到进程退出才回收
      // （见 [_deleteIfExists]）。
      await workerGone.future.timeout(_isolateExitGrace, onTimeout: () {});
    }
    workerExit.close();
    commands.close();
  }
}

/// isolate 入口：顶层函数而非闭包——官方明示闭包可能隐式携带意料之外的状态。
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

/// [extraExtensions] 收录计划外条目（如恒定嵌入的 `images/icon.png`）的扩展名。
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
    )..writeln('  <dc:creator>${_escapeXml(pack.author)}</dc:creator>')..writeln(
        '  <dc:description>${_escapeXml(pack.description ?? '')}</dc:description>')..writeln(
        '  <dc:identifier>${_escapeXml(pack.name)}</dc:identifier>')..writeln(
        '  <version>${_escapeXml(NuGetPackageBuilder.normalizedVersion(pack.version))}</version>')
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
