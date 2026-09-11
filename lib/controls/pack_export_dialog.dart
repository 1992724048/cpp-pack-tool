import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/util/file_opener.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _ExportStage { running, completed, failed }

class PackExportDialog extends StatefulWidget {
  const PackExportDialog({
    super.key,
    required this.pack,
    required this.outputDirectory,
    this.exportPackage = exportNuGetPackage,
    this.revealFile = revealInExplorer,
  });

  final PackModel pack;
  final String outputDirectory;
  final Future<PackageExportResult> Function(
    PackModel pack,
    String outputDirectory,
  )
  exportPackage;
  final Future<bool> Function(String filePath) revealFile;

  @override
  State<PackExportDialog> createState() => _PackExportDialogState();
}

class _PackExportDialogState extends State<PackExportDialog> {
  _ExportStage _stage = _ExportStage.running;
  PackageExportResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _export();
  }

  Future<void> _export() async {
    final PackageExportResult result;
    try {
      result = await widget.exportPackage(widget.pack, widget.outputDirectory);
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
    showFloatingToast(
      context,
      '无法打开所在目录',
      type: FloatingToastType.error,
      duration: const Duration(seconds: 5),
    );
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
          FilledButton(
            key: const Key('packExportRevealButton'),
            onPressed: _reveal,
            child: const Text('打开所在目录'),
          ),
        Button(
          key: const Key('packExportCloseButton'),
          onPressed: _stage == _ExportStage.running
              ? null
              : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildStatus() {
    switch (_stage) {
      case _ExportStage.running:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在打包…')],
        );
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
