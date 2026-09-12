import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/pack_remap.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _BuildStage { downloading, building, remapping, completed, failed }

class BuildPackDialog extends StatefulWidget {
  const BuildPackDialog({
    super.key,
    required this.pack,
    this.build = runPackBuild,
    required this.scanFiles,
    required this.onApply,
  });

  final PackModel pack;
  final PackBuildRunner build;
  final Future<List<FileModel>> Function(String sourcePath) scanFiles;
  final Future<void> Function(PackModel pack) onApply;

  @override
  State<BuildPackDialog> createState() => _BuildPackDialogState();
}

class _BuildPackDialogState extends State<BuildPackDialog> {
  static const TextStyle _monoTextStyle = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: <String>['Courier New', 'monospace'],
    fontSize: 13,
  );

  _BuildStage _stage = _BuildStage.downloading;
  Object? _error;
  String? _outputTail;
  List<FileModel> _files = const <FileModel>[];
  int _addedCount = 0;
  int _removedCount = 0;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    try {
      await widget.build(widget.pack, _onBuildStage);
    } catch (error) {
      _showFailure(error, outputTail: _tailOf(error));
      return;
    }
    if (!mounted) {
      return;
    }

    final String? sourcePath = widget.pack.sourcePath;
    if (sourcePath == null) {
      _showFailure(const PackBuildException('该包缺少源目录信息'));
      return;
    }
    setState(() => _stage = _BuildStage.remapping);

    final List<FileModel> files;
    try {
      files = await widget.scanFiles(sourcePath);
    } catch (error) {
      _showFailure(error);
      return;
    }
    if (!mounted) {
      return;
    }

    final PackFilesDiff diff = comparePackFiles(widget.pack.files, files);
    final PackModel updated = copyPackWithFiles(widget.pack, files);
    setState(() {
      _files = files;
      _addedCount = diff.added;
      _removedCount = diff.removed;
    });

    try {
      await widget.onApply(updated);
    } catch (error) {
      _showFailure(error);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _stage = _BuildStage.completed);
  }

  void _onBuildStage(PackBuildStage stage) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = switch (stage) {
        PackBuildStage.downloading => _BuildStage.downloading,
        PackBuildStage.building => _BuildStage.building,
      };
    });
  }

  void _showFailure(Object error, {String? outputTail}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = _BuildStage.failed;
      _error = error;
      _outputTail = outputTail;
    });
  }

  static String? _tailOf(Object error) =>
      error is PackBuildException ? error.outputTail : null;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('buildPackDialog'),
      title: const Text('构建'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('包名：${widget.pack.name}'),
            const SizedBox(height: 4),
            Text('源目录：${widget.pack.sourcePath ?? '未知'}'),
            const SizedBox(height: 12),
            _buildStatus(),
          ],
        ),
      ),
      actions: [
        Button(
          key: const Key('buildCloseButton'),
          onPressed: _isRunning ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  bool get _isRunning =>
      _stage == _BuildStage.downloading ||
      _stage == _BuildStage.building ||
      _stage == _BuildStage.remapping;

  Widget _buildStatus() {
    switch (_stage) {
      case _BuildStage.downloading:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在下载源码…')],
        );
      case _BuildStage.building:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在执行构建…')],
        );
      case _BuildStage.remapping:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在重新映射…')],
        );
      case _BuildStage.failed:
        return _buildFailure();
      case _BuildStage.completed:
        return _buildResult();
    }
  }

  Widget _buildFailure() {
    final String? outputTail = _outputTail;
    final FluentThemeData theme = FluentTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('构建失败：${formatError(_error!)}'),
        if (outputTail != null && outputTail.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: theme.resources.cardBackgroundFillColorSecondary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.resources.cardStrokeColorDefault),
            ),
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(12),
              child: Text(outputTail, style: _monoTextStyle),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResult() {
    final int totalSize = totalFileSize(_files);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('构建完成'),
        const SizedBox(height: 8),
        Text('文件数量：${_files.length}'),
        const SizedBox(height: 4),
        Text('总大小：${formatBytes(totalSize)}'),
        const SizedBox(height: 4),
        Text('新增：$_addedCount 个文件'),
        const SizedBox(height: 4),
        Text('移除：$_removedCount 个文件'),
      ],
    );
  }
}
