import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:fluent_ui/fluent_ui.dart';

typedef CompileEntryResult = ({String text, BuildModel buildModel});

const String _packFilesPrefix = r'$(MSBuildThisFileDirectory)files';

const List<String> _msbuildMacros = <String>[
  r'$(Configuration)',
  r'$(Platform)',
  r'$(OutDir)',
  r'$(IntDir)',
  r'$(ProjectDir)',
  r'$(SolutionDir)',
  r'$(TargetPath)',
  r'$(TargetName)',
  r'$(TargetExt)',
  r'$(MSBuildThisFileDirectory)',
  r'$(VCTargetsPath)',
  r'%(Filename)',
  r'%(Extension)',
  r'%(FullPath)',
  r'%(RelativeDir)',
  r'%(RootDir)',
];

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
    this.selectableScripts = const <FileModel>[],
    this.showMacroHelper = false,
  });

  final String title;
  final String label;
  final String? hintText;
  final bool showBrowse;
  final Future<String?> Function()? pickDirectory;
  final String initialText;
  final BuildModel initialBuildModel;
  final List<FileModel> selectableScripts;
  final bool showMacroHelper;

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

  bool get _hasInsertHelpers =>
      widget.selectableScripts.isNotEmpty || widget.showMacroHelper;

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

  void _insertText(String text) {
    final String current = _controller.text;
    final TextSelection selection = _controller.selection;
    final int start = selection.isValid
        ? selection.start.clamp(0, current.length)
        : current.length;
    final int end = selection.isValid
        ? selection.end.clamp(0, current.length)
        : current.length;
    _controller.value = TextEditingValue(
      text: current.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  String _scriptReference(FileModel script) {
    final String relative = script.path.replaceAll('/', '\\');
    final String path = '"$_packFilesPrefix\\$relative"';
    return switch (script.extension) {
      'ps1' => 'powershell -NoProfile -ExecutionPolicy Bypass -File $path',
      'py' => 'python $path',
      _ => path,
    };
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
          if (_hasInsertHelpers) ...[
            const SizedBox(height: 12),
            _buildInsertHelpers(),
          ],
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

  Widget _buildInsertHelpers() {
    final List<Widget> fields = <Widget>[
      if (widget.selectableScripts.isNotEmpty)
        Expanded(child: _buildField('从包中选择', _buildScriptField())),
      if (widget.showMacroHelper)
        Expanded(child: _buildField('插入宏', _buildMacroField())),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int index = 0; index < fields.length; index++) ...[
          if (index > 0) const SizedBox(width: 12),
          fields[index],
        ],
      ],
    );
  }

  Widget _buildScriptField() {
    return _wrapDenseComboBox(
      ComboBox<FileModel>(
        key: const Key('compileEntryScriptField'),
        // 值恒为 null：选中仅插入文本并复位下拉
        value: null,
        placeholder: const Text('请选择脚本'),
        isExpanded: true,
        onChanged: (FileModel? script) {
          if (script != null) {
            _insertText(_scriptReference(script));
          }
        },
        items: <ComboBoxItem<FileModel>>[
          for (final FileModel script in widget.selectableScripts)
            ComboBoxItem<FileModel>(
              value: script,
              child: Text(script.path, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }

  Widget _buildMacroField() {
    return _wrapDenseComboBox(
      ComboBox<String>(
        key: const Key('compileEntryMacroField'),
        // 值恒为 null：选中仅插入文本并复位下拉
        value: null,
        placeholder: const Text('请选择宏'),
        isExpanded: true,
        onChanged: (String? macro) {
          if (macro != null) {
            _insertText(macro);
          }
        },
        items: <ComboBoxItem<String>>[
          for (final String macro in _msbuildMacros)
            ComboBoxItem<String>(
              value: macro,
              child: Text(macro, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }

  Widget _buildBuildModelField() {
    return _wrapDenseComboBox(
      ComboBox<BuildModel>(
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

  Widget _wrapDenseComboBox(Widget child) {
    return FluentTheme(
      data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
      child: child,
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
