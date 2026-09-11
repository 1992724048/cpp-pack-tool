import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:fluent_ui/fluent_ui.dart';

typedef CompileEntryResult = ({String text, BuildModel buildModel});

class CompileEntryDialog extends StatefulWidget {
  const CompileEntryDialog({
    super.key,
    required this.title,
    required this.label,
    this.hintText,
    this.showBrowse = false,
    this.pickDirectory,
    this.initialText = '',
    this.initialBuildModel = BuildModel.all,
  });

  final String title;
  final String label;
  final String? hintText;
  final bool showBrowse;
  final Future<String?> Function()? pickDirectory;
  final String initialText;
  final BuildModel initialBuildModel;

  @override
  State<CompileEntryDialog> createState() => _CompileEntryDialogState();
}

class _CompileEntryDialogState extends State<CompileEntryDialog> {
  late final TextEditingController _controller;
  late BuildModel _buildModel;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_refresh);
    _buildModel = widget.initialBuildModel;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  Future<void> _browse() async {
    final Future<String?> Function()? pickDirectory = widget.pickDirectory;
    if (pickDirectory == null || _picking) {
      return;
    }
    setState(() => _picking = true);
    final String? path = await pickDirectory();
    if (!mounted) {
      return;
    }
    if (path != null) {
      _controller.text = path;
    }
    setState(() => _picking = false);
  }

  void _submit() {
    Navigator.pop(context, (
      text: _controller.text.trim(),
      buildModel: _buildModel,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('compileEntryDialog'),
      title: Text(widget.title),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildField(widget.label, _buildTextField()),
          const SizedBox(height: 12),
          _buildField('构建配置', _buildBuildModelField()),
        ],
      ),
      actions: [
        Button(
          key: const Key('compileEntryCancelButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('compileEntryConfirmButton'),
          onPressed: _canSubmit ? _submit : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildTextField() {
    final Widget textBox = TextBox(
      key: const Key('compileEntryTextField'),
      controller: _controller,
      placeholder: widget.hintText,
    );
    if (!widget.showBrowse) {
      return textBox;
    }
    return Row(
      children: [
        Expanded(child: textBox),
        const SizedBox(width: 8),
        Button(
          key: const Key('compileEntryBrowseButton'),
          onPressed: _picking ? null : _browse,
          child: const Text('浏览…'),
        ),
      ],
    );
  }

  Widget _buildBuildModelField() {
    return FluentTheme(
      data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
      child: ComboBox<BuildModel>(
        key: const Key('compileEntryBuildModelField'),
        value: _buildModel,
        isExpanded: true,
        onChanged: (BuildModel? value) {
          if (value != null) {
            setState(() => _buildModel = value);
          }
        },
        items: <ComboBoxItem<BuildModel>>[
          for (final BuildModel buildModel in BuildModel.values)
            ComboBoxItem<BuildModel>(
              value: buildModel,
              child: Text(buildModelLabel(buildModel)),
            ),
        ],
      ),
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
