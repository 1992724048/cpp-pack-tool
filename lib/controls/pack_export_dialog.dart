import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/shared/file_opener.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:cpp_nuget_pack/shared/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _ExportStage { running, completed, failed, cancelled }

typedef PackExportRunner = Future<PackageExportResult> Function(
  PackModel pack,
  String outputDirectory, {
  void Function(double fraction)? onProgress,
  ExportCancelToken? cancelToken,
});

class PackExportDialog extends StatefulWidget {
  const PackExportDialog({
    super.key,
    required this.pack,
    required this.outputDirectory,
    this.exportPackage = exportNuGetPackage,
    this.revealFile = revealInExplorer,
    this.onExported,
  });

  final PackModel pack;
  final String outputDirectory;
  final PackExportRunner exportPackage;
  final Future<bool> Function(String filePath) revealFile;
  final ValueChanged<PackageExportResult>? onExported;

  @override
  State<PackExportDialog> createState() => _PackExportDialogState();
}

class _PackExportDialogState extends State<PackExportDialog> {
  _ExportStage _stage = _ExportStage.running;
  PackageExportResult? _result;
  Object? _error;
  final ExportCancelToken _cancelToken = ExportCancelToken();
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _export();
  }

  Future<void> _export() async {
    final PackageExportResult result;
    try {
      result = await widget.exportPackage(
        widget.pack,
        widget.outputDirectory,
        onProgress: _onProgress,
        cancelToken: _cancelToken,
      );
    } on ExportCancelledException {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _ExportStage.cancelled;
      });
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _ExportStage.failed;
        _error = error;
      });
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = _ExportStage.completed;
      _result = result;
    });
    widget.onExported?.call(result);
  }

  void _onProgress(double fraction) {
    if (!mounted || _stage != _ExportStage.running) {
      return;
    }
    setState(() {
      _progress = fraction;
    });
  }

  Future<void> _reveal() async {
    final PackageExportResult? result = _result;
    if (result == null) {
      return;
    }
    final bool revealed = await widget.revealFile(result.outputPath);
    if (!mounted) {
      return;
    }
    if (revealed) {
      return;
    }
    showFloatingToast(context, '无法打开所在目录', type: FloatingToastType.error, duration: const Duration(seconds: 5));
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('packExportDialog'),
      title: const Text('打包文件夹'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('包名：${widget.pack.name}'),
            const SizedBox(height: 4),
            Text('输出目录：${widget.outputDirectory}'),
            const SizedBox(height: 12),
            _buildStatus(),
          ],
        ),
      ),
      actions: [
        if (_stage == _ExportStage.completed)
          FilledButton(key: const Key('packExportRevealButton'), onPressed: _reveal, child: const Text('打开所在目录')),
        if (_stage == _ExportStage.running)
          Button(key: const Key('packExportCancelButton'), onPressed: _cancelToken.cancel, child: const Text('取消')),
        Button(
          key: const Key('packExportCloseButton'),
          onPressed: _stage == _ExportStage.running ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildStatus() {
    switch (_stage) {
      case _ExportStage.running:
        return Row(
          children: [const ProgressRing(), const SizedBox(width: 12), Text('正在打包…${(_progress * 100).round()}%')],
        );
      case _ExportStage.cancelled:
        return const Text('已取消');
      case _ExportStage.failed:
        return Text('打包失败：${formatError(_error!)}');
      case _ExportStage.completed:
        return _buildResult();
    }
  }

  Widget _buildResult() {
    final PackageExportResult result = _result!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('打包完成'),
        const SizedBox(height: 8),
        Text('输出路径：${result.outputPath}'),
        const SizedBox(height: 4),
        Text('文件数量：${result.fileCount}'),
        const SizedBox(height: 4),
        Text('包大小：${formatBytes(result.packageSize)}'),
      ],
    );
  }
}
