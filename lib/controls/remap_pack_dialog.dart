import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/file_image.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _RemapStage { scanning, applying, completed, scanFailed, applyFailed }

class RemapPackDialog extends StatefulWidget {
  const RemapPackDialog({
    super.key,
    required this.pack,
    required this.scanFuture,
    required this.onApply,
  });

  final PackModel pack;
  final Future<List<FileModel>> scanFuture;
  final Future<void> Function(PackModel pack) onApply;

  @override
  State<RemapPackDialog> createState() => _RemapPackDialogState();
}

class _RemapPackDialogState extends State<RemapPackDialog> {
  _RemapStage _stage = _RemapStage.scanning;
  Object? _error;
  List<FileModel> _files = const <FileModel>[];
  int _addedCount = 0;
  int _removedCount = 0;

  @override
  void initState() {
    super.initState();
    _remap();
  }

  Future<void> _remap() async {
    final List<FileModel> files;
    try {
      files = await widget.scanFuture;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _RemapStage.scanFailed;
        _error = error;
      });
      return;
    }
    if (!mounted) {
      return;
    }

    final Set<String> oldPaths = <String>{
      for (final FileModel file in widget.pack.files) file.path.toLowerCase(),
    };
    final Set<String> newPaths = <String>{
      for (final FileModel file in files) file.path.toLowerCase(),
    };
    final PackModel updated =
        PackModel(
            name: widget.pack.name,
            version: widget.pack.version,
            author: widget.pack.author,
            description: widget.pack.description,
            license: widget.pack.license,
            iconPath: findIconFile(files)?.path,
            sourcePath: widget.pack.sourcePath,
          )
          ..files = files
          ..commands = widget.pack.commands
          ..dependencies = widget.pack.dependencies
          ..macros = widget.pack.macros
          ..libDirectories = widget.pack.libDirectories
          ..libraries = widget.pack.libraries
          ..history = widget.pack.history;

    setState(() {
      _stage = _RemapStage.applying;
      _files = files;
      _addedCount = newPaths.difference(oldPaths).length;
      _removedCount = oldPaths.difference(newPaths).length;
    });

    try {
      await widget.onApply(updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _RemapStage.applyFailed;
        _error = error;
      });
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _stage = _RemapStage.completed);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('remapPackDialog'),
      title: const Text('重新映射'),
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
          key: const Key('remapCloseButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildStatus() {
    switch (_stage) {
      case _RemapStage.scanning:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在扫描…')],
        );
      case _RemapStage.applying:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在更新配置…')],
        );
      case _RemapStage.scanFailed:
        return Text('扫描失败：${formatError(_error!)}');
      case _RemapStage.applyFailed:
        return Text('更新失败：${formatError(_error!)}');
      case _RemapStage.completed:
        return _buildResult();
    }
  }

  Widget _buildResult() {
    final int totalSize = _files.fold<int>(
      0,
      (int sum, FileModel file) => sum + file.size,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('重新映射完成'),
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
