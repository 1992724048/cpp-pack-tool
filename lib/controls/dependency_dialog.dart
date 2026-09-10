import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/util/version_range.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DependencyDialog extends StatefulWidget {
  const DependencyDialog({
    super.key,
    this.candidates = const <PackModel>[],
    this.editing,
  });

  final List<PackModel> candidates;
  final DependencyModel? editing;

  @override
  State<DependencyDialog> createState() => _DependencyDialogState();
}

class _DependencyDialogState extends State<DependencyDialog> {
  late final TextEditingController _versionController;
  String? _package;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _package = widget.editing?.name;
    _versionController = TextEditingController(
      text: widget.editing?.version ?? '',
    );
    _versionController.addListener(_refresh);
  }

  @override
  void dispose() {
    _versionController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  String? get _versionError => versionRangeError(_versionController.text);

  bool get _canSubmit {
    if (_versionError != null) {
      return false;
    }
    return _isEditing || _package != null;
  }

  void _submit() {
    final String? package = _package;
    if (package == null) {
      return;
    }
    Navigator.pop(
      context,
      DependencyModel(name: package, version: _versionController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('dependencyDialog'),
      title: Text(_isEditing ? '编辑依赖' : '添加依赖'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildField('包名', _buildPackageField()),
          const SizedBox(height: 12),
          _buildField('版本范围', _buildVersionField()),
        ],
      ),
      actions: [
        Button(
          key: const Key('dependencyCancelButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('dependencyConfirmButton'),
          onPressed: _canSubmit ? _submit : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildPackageField() {
    if (_isEditing) {
      return Text(widget.editing!.name);
    }
    if (widget.candidates.isEmpty) {
      return const Text('没有可添加的包');
    }
    return FluentTheme(
      data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
      child: ComboBox<String>(
        key: const Key('dependencyPackageField'),
        value: _package,
        placeholder: const Text('请选择包'),
        isExpanded: true,
        onChanged: (String? value) => setState(() => _package = value),
        items: <ComboBoxItem<String>>[
          for (final PackModel pack in widget.candidates)
            ComboBoxItem<String>(value: pack.name, child: Text(pack.name)),
        ],
      ),
    );
  }

  Widget _buildVersionField() {
    final FluentThemeData theme = FluentTheme.of(context);
    final String? error = _versionError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextBox(
          key: const Key('dependencyVersionField'),
          controller: _versionController,
          placeholder: '1.0.0',
        ),
        const SizedBox(height: 4),
        Text(
          '支持 NuGet 区间写法，如 [1.0,2.0)、[1.0]、1.0',
          style: TextStyle(color: theme.resources.textFillColorSecondary),
        ),
        if (error != null && _versionController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            error,
            key: const Key('dependencyVersionError'),
            style: TextStyle(color: theme.resources.systemFillColorCritical),
          ),
        ],
      ],
    );
  }

  Widget _buildField(String label, Widget child) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(label), const SizedBox(height: 4), child],
    );
  }
}
