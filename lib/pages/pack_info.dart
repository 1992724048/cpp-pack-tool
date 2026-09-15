import 'package:cpp_nuget_pack/controls/license_field.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PackInfo extends StatefulWidget {
  const PackInfo({super.key, required this.pack, required this.onSave});

  final PackModel pack;
  final Future<bool> Function(PackModel pack) onSave;

  @override
  State<PackInfo> createState() => _PackInfoState();
}

class _PackInfoState extends State<PackInfo> {
  late final TextEditingController _idController;
  late final TextEditingController _versionController;
  late final TextEditingController _authorController;
  late final TextEditingController _licenseController;
  late final TextEditingController _descriptionController;

  bool _editing = false;
  bool _saving = false;
  String? _license;
  bool _licenseValid = true;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController();
    _versionController = TextEditingController();
    _authorController = TextEditingController();
    _licenseController = TextEditingController();
    _descriptionController = TextEditingController();
    _applyPack(widget.pack);
    _versionController.addListener(_refresh);
    _authorController.addListener(_refresh);
    _descriptionController.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant PackInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pack == widget.pack) {
      return;
    }
    _applyPack(widget.pack);
    _editing = false;
    _saving = false;
  }

  @override
  void dispose() {
    _idController.dispose();
    _versionController.dispose();
    _authorController.dispose();
    _licenseController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _applyPack(PackModel pack) {
    _idController.text = pack.name;
    _versionController.text = pack.version;
    _authorController.text = pack.author;
    _licenseController.text = pack.license ?? '';
    _descriptionController.text = pack.description ?? '';
    _license = pack.license;
    _licenseValid = true;
  }

  void _refresh() {
    setState(() {});
  }

  bool get _canSave {
    return _versionController.text.trim().isNotEmpty &&
        _authorController.text.trim().isNotEmpty &&
        _licenseValid &&
        _hasChanges;
  }

  bool get _hasChanges {
    return _versionController.text.trim() != widget.pack.version ||
        _authorController.text.trim() != widget.pack.author ||
        _descriptionController.text.trim() != (widget.pack.description ?? '') ||
        _license != widget.pack.license;
  }

  void _startEditing() {
    setState(() => _editing = true);
  }

  void _cancelEditing() {
    _applyPack(widget.pack);
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final String originName = widget.pack.name;
    final String description = _descriptionController.text.trim();
    final PackModel updated =
        PackModel(
            name: widget.pack.name,
            version: _versionController.text.trim(),
            author: _authorController.text.trim(),
            description: description.isEmpty ? null : description,
            license: _license,
            iconPath: widget.pack.iconPath,
            sourcePath: widget.pack.sourcePath,
            sourceVersion: widget.pack.sourceVersion,
          )
          ..files = widget.pack.files
          ..commands = widget.pack.commands
          ..dependencies = widget.pack.dependencies
          ..macros = widget.pack.macros
          ..libDirectories = widget.pack.libDirectories
          ..libraries = widget.pack.libraries
          ..history = widget.pack.history
          ..scripts = widget.pack.scripts
          ..buildOptions = widget.pack.buildOptions
          ..enabledFormats = widget.pack.enabledFormats;

    setState(() => _saving = true);
    final bool saved = await widget.onSave(updated);
    if (!mounted) {
      return;
    }
    if (widget.pack.name != originName) {
      // 保存挂起期间已切换到其他包，didUpdateWidget 已重置状态，放弃回写
      return;
    }
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    _applyPack(updated);
    setState(() {
      _editing = false;
      _saving = false;
    });
    showFloatingToast(context, '已保存');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _field(
                  '包 ID',
                  _idController,
                  key: const Key('packInfoIdField'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _field(
                  '版本',
                  _versionController,
                  key: const Key('packInfoVersionField'),
                  readOnly: !_editing,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _field(
                  '作者',
                  _authorController,
                  key: const Key('packInfoAuthorField'),
                  readOnly: !_editing,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _licenseField()),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('描述'),
                const SizedBox(height: 4),
                Expanded(
                  child: TextBox(
                    key: const Key('packInfoDescriptionField'),
                    controller: _descriptionController,
                    readOnly: !_editing,
                    maxLines: null,
                    expands: true,
                    placeholder: '无',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: _editing
                ? <Widget>[
                    Button(
                      key: const Key('packInfoCancelButton'),
                      onPressed: _saving ? null : _cancelEditing,
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('packInfoSaveButton'),
                      onPressed: _saving || !_canSave ? null : _save,
                      child: const Text('保存'),
                    ),
                  ]
                : <Widget>[
                    FilledButton(
                      key: const Key('packInfoEditButton'),
                      onPressed: _startEditing,
                      child: const Text('编辑'),
                    ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    Key? key,
    bool readOnly = true,
    String? placeholder,
  }) {
    return InfoLabel(
      label: label,
      child: TextBox(
        key: key,
        controller: controller,
        readOnly: readOnly,
        placeholder: placeholder,
      ),
    );
  }

  Widget _licenseField() {
    if (!_editing) {
      return InfoLabel(
        label: '许可证',
        child: TextBox(
          key: const Key('packInfoLicenseField'),
          controller: _licenseController,
          readOnly: true,
          placeholder: '无',
        ),
      );
    }
    return InfoLabel(
      label: '许可证',
      child: LicenseField(
        value: _license,
        comboBoxKey: const Key('packInfoLicenseField'),
        customFieldKey: const Key('packInfoLicenseCustomField'),
        errorKey: const Key('packInfoLicenseCustomError'),
        onChanged: (String? license, bool isValid) {
          setState(() {
            _license = license;
            _licenseValid = isValid;
          });
        },
      ),
    );
  }
}
