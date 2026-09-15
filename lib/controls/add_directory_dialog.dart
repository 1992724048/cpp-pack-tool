import 'package:cpp_nuget_pack/controls/format_selection_dialog.dart';
import 'package:cpp_nuget_pack/controls/license_field.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/util/file_image.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

class AddDirectoryDialog extends StatefulWidget {
  const AddDirectoryDialog({
    super.key,
    required this.directoryPath,
    required this.scanFuture,
    this.initialAuthor = '',
    this.builders = PackageBuilderRegistry.all,
  });

  final String directoryPath;
  final Future<List<FileModel>> scanFuture;

  /// 新包作者预填值（全局默认作者）。
  final String initialAuthor;

  /// 可选的打包格式（测试注入；默认全部注册格式）。
  final List<PackageBuilder> builders;

  @override
  State<AddDirectoryDialog> createState() => _AddDirectoryDialogState();
}

class _AddDirectoryDialogState extends State<AddDirectoryDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String? _license;
  bool _licenseValid = true;
  late final List<String> _enabledFormatIds;
  List<FileModel>? _files;
  Object? _scanError;

  @override
  void initState() {
    super.initState();
    _authorController.text = widget.initialAuthor;
    _enabledFormatIds = <String>[
      for (final PackageBuilder builder in widget.builders) builder.id,
    ];
    _idController.addListener(_refresh);
    _versionController.addListener(_refresh);
    _authorController.addListener(_refresh);
    _scan();
  }

  @override
  void dispose() {
    _idController.dispose();
    _versionController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    super.dispose();
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

  void _refresh() {
    setState(() {});
  }

  bool get _canSubmit =>
      _files != null &&
      _licenseValid &&
      _idController.text.trim().isNotEmpty &&
      _versionController.text.trim().isNotEmpty &&
      _authorController.text.trim().isNotEmpty;

  void _submit() {
    final FileModel? icon = findIconFile(_files);
    final String description = _descriptionController.text.trim();
    Navigator.pop(
      context,
      PackModel(
          name: _idController.text.trim(),
          version: _versionController.text.trim(),
          author: _authorController.text.trim(),
          description: description.isEmpty ? null : description,
          license: _license,
          iconPath: icon?.path,
          sourcePath: widget.directoryPath,
        )
        ..files = _files ?? const <FileModel>[]
        ..enabledFormats = List<String>.of(_enabledFormatIds),
    );
  }

  Future<void> _pickFormats() async {
    final List<String>? selected = await showFormatSelectionDialog(
      context,
      builders: widget.builders,
      enabledIds: _enabledFormatIds,
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _enabledFormatIds
        ..clear()
        ..addAll(selected);
    });
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
              _buildFormFields(),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('确定'),
        ),
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
      return const Row(
        children: [ProgressRing(), SizedBox(width: 12), Text('正在扫描…')],
      );
    }
    final int totalSize = files.fold<int>(
      0,
      (int sum, FileModel file) => sum + file.size,
    );
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
        Expanded(
          child: Text('图标：${iconFile.path}', overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField(
          label: '包 ID',
          child: TextBox(
            key: const Key('packIdField'),
            controller: _idController,
          ),
        ),
        const SizedBox(height: 12),
        _buildField(
          label: '版本',
          child: TextBox(
            key: const Key('packVersionField'),
            controller: _versionController,
            placeholder: '1.0.0',
          ),
        ),
        const SizedBox(height: 12),
        _buildField(
          label: '作者',
          child: TextBox(
            key: const Key('packAuthorField'),
            controller: _authorController,
          ),
        ),
        const SizedBox(height: 12),
        _buildField(
          label: '许可证',
          child: LicenseField(
            value: _license,
            comboBoxKey: const Key('packLicenseField'),
            customFieldKey: const Key('packLicenseCustomField'),
            errorKey: const Key('packLicenseCustomError'),
            onChanged: (String? license, bool isValid) {
              setState(() {
                _license = license;
                _licenseValid = isValid;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildField(
          label: '描述',
          child: TextBox(
            key: const Key('packDescriptionField'),
            controller: _descriptionController,
            minLines: 3,
            maxLines: 3,
          ),
        ),
        const SizedBox(height: 12),
        _buildFormatField(),
      ],
    );
  }

  Widget _buildFormatField() {
    final FluentThemeData theme = FluentTheme.of(context);
    return _buildField(
      label: '打包格式',
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _formatSummary(),
              key: const Key('addPackFormatSummary'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.resources.textFillColorSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Button(
            key: const Key('addPackFormatButton'),
            onPressed: _pickFormats,
            child: const Text('选择…'),
          ),
        ],
      ),
    );
  }

  String _formatSummary() {
    final List<String> names = <String>[
      for (final PackageBuilder builder in widget.builders)
        if (_enabledFormatIds.contains(builder.id)) builder.displayName,
    ];
    return names.isEmpty ? '未启用任何格式' : names.join('、');
  }

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(label), const SizedBox(height: 4), child],
    );
  }
}
