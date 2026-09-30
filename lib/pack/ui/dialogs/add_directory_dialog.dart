import 'package:cpp_nuget_pack/pack/ui/dialogs/pack_metadata_form.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/pack/file_image.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

class AddDirectoryDialog extends StatefulWidget {
  const AddDirectoryDialog({super.key, required this.directoryPath, required this.scanFuture});

  final String directoryPath;
  final Future<List<FileModel>> scanFuture;

  @override
  State<AddDirectoryDialog> createState() => _AddDirectoryDialogState();
}

class _AddDirectoryDialogState extends State<AddDirectoryDialog> {
  PackMetadataDraft? _draft;
  List<FileModel>? _files;
  Object? _scanError;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    try {
      final List<FileModel> files = await widget.scanFuture;
      if (!mounted) {
        return;
      }
      setState(() => _files = files);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _scanError = error);
    }
  }

  bool get _canSubmit => _files != null && (_draft?.isComplete ?? false);

  void _submit() {
    final FileModel? icon = findIconFile(_files);
    final PackMetadata metadata = _draft!.metadata;
    Navigator.pop(
      context,
      PackModel(
        name: metadata.name,
        version: metadata.version,
        author: metadata.author,
        description: metadata.description,
        license: metadata.license,
        iconPath: icon?.path,
        sourcePath: widget.directoryPath,
      )..files = _files ?? const <FileModel>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('添加包'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('路径：${widget.directoryPath}'),
            const SizedBox(height: 12),
            _buildScanStatus(),
            if (_files != null) ...[
              const SizedBox(height: 12),
              PackMetadataForm(onChanged: (PackMetadataDraft draft) => setState(() => _draft = draft)),
            ],
          ],
        ),
      ),
      actions: [
        Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _canSubmit ? _submit : null, child: const Text('确定')),
      ],
    );
  }

  Widget _buildScanStatus() {
    final Object? error = _scanError;
    if (error != null) {
      return Text('扫描失败：${formatError(error)}');
    }
    final List<FileModel>? files = _files;
    if (files == null) {
      return const Row(children: [ProgressRing(), SizedBox(width: 12), Text('正在扫描…')]);
    }
    final int totalSize = files.fold<int>(0, (int sum, FileModel file) => sum + file.size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('文件数量：${files.length}'),
        const SizedBox(height: 4),
        Text('总大小：${formatBytes(totalSize)}'),
        const SizedBox(height: 12),
        _buildIcon(),
      ],
    );
  }

  Widget _buildIcon() {
    final FileModel? iconFile = findIconFile(_files);
    if (iconFile == null) {
      return const Text('未找到图标文件');
    }
    final Widget preview = buildFileImage(
      joinPath(widget.directoryPath, iconFile.path),
      size: 48,
      fallback: const Icon(WindowsIcons.picture, size: 24),
    );
    return Row(
      children: [
        SizedBox(width: 48, height: 48, child: Center(child: preview)),
        const SizedBox(width: 12),
        Expanded(child: Text('图标：${iconFile.path}', overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
