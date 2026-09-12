import 'package:cpp_nuget_pack/controls/compile_entry_dialog.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/pages/script_editor.dart';
import 'package:cpp_nuget_pack/script_editor/graph_validation.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/script_files.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _buildModelColumnWidth = 96;
const double _triggerColumnWidth = 96;
const double _statusColumnWidth = 80;
const double _actionColumnWidth = 80;

class PackCompileSettings extends StatefulWidget {
  const PackCompileSettings({
    super.key,
    required this.pack,
    required this.onSave,
    this.pickDirectory = getDirectoryPath,
  });

  final PackModel pack;
  final Future<bool> Function(PackModel pack) onSave;
  final Future<String?> Function() pickDirectory;

  @override
  State<PackCompileSettings> createState() => _PackCompileSettingsState();
}

class _PackCompileSettingsState extends State<PackCompileSettings> {
  bool _saving = false;

  Future<void> _addMacro() async {
    final CompileEntryResult? result = await _openEntryDialog(
      title: '添加宏定义',
      label: '宏定义',
      hintText: 'MY_MACRO=1',
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        macros: <MacroModel>[
          ...pack.macros,
          MacroModel(value: result.text, buildModel: result.buildModel),
        ],
      ),
      '已添加',
    );
  }

  Future<void> _editMacro(int index) async {
    final MacroModel macro = widget.pack.macros[index];
    final CompileEntryResult? result = await _openEntryDialog(
      title: '编辑宏定义',
      label: '宏定义',
      hintText: 'MY_MACRO=1',
      initialText: macro.value,
      initialBuildModel: macro.buildModel,
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        macros: <MacroModel>[
          for (int i = 0; i < pack.macros.length; i++)
            if (i == index)
              MacroModel(value: result.text, buildModel: result.buildModel)
            else
              pack.macros[i],
        ],
      ),
      '已保存',
    );
  }

  Future<void> _removeMacro(int index) async {
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        macros: <MacroModel>[
          for (int i = 0; i < pack.macros.length; i++)
            if (i != index) pack.macros[i],
        ],
      ),
      '已删除',
    );
  }

  Future<void> _addCommand(CmdType type) async {
    final bool preBuild = type == CmdType.preBuild;
    final CompileEntryResult? result = await _openEntryDialog(
      title: preBuild ? '添加编译前命令' : '添加编译后命令',
      label: '命令',
      selectableScripts: _commandScripts(),
      showMacroHelper: true,
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        commands: <CmdModel>[
          ...pack.commands,
          CmdModel(
            command: result.text,
            type: type,
            buildModel: result.buildModel,
          ),
        ],
      ),
      '已添加',
    );
  }

  Future<void> _editCommand(int index) async {
    final CmdModel command = widget.pack.commands[index];
    final bool preBuild = command.type == CmdType.preBuild;
    final CompileEntryResult? result = await _openEntryDialog(
      title: preBuild ? '编辑编译前命令' : '编辑编译后命令',
      label: '命令',
      initialText: command.command,
      initialBuildModel: command.buildModel,
      selectableScripts: _commandScripts(),
      showMacroHelper: true,
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        commands: <CmdModel>[
          for (int i = 0; i < pack.commands.length; i++)
            if (i == index)
              CmdModel(
                command: result.text,
                type: command.type,
                buildModel: result.buildModel,
              )
            else
              pack.commands[i],
        ],
      ),
      '已保存',
    );
  }

  Future<void> _removeCommand(int index) async {
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        commands: <CmdModel>[
          for (int i = 0; i < pack.commands.length; i++)
            if (i != index) pack.commands[i],
        ],
      ),
      '已删除',
    );
  }

  Future<void> _addLibDirectory() async {
    final CompileEntryResult? result = await _openEntryDialog(
      title: '添加附加库目录',
      label: '目录路径',
      hintText: r'third_party\lib',
      showBrowse: true,
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        libDirectories: <LibDirModel>[
          ...pack.libDirectories,
          LibDirModel(path: result.text, buildModel: result.buildModel),
        ],
      ),
      '已添加',
    );
  }

  Future<void> _editLibDirectory(int index) async {
    final LibDirModel libDirectory = widget.pack.libDirectories[index];
    final CompileEntryResult? result = await _openEntryDialog(
      title: '编辑附加库目录',
      label: '目录路径',
      hintText: r'third_party\lib',
      showBrowse: true,
      initialText: libDirectory.path,
      initialBuildModel: libDirectory.buildModel,
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        libDirectories: <LibDirModel>[
          for (int i = 0; i < pack.libDirectories.length; i++)
            if (i == index)
              LibDirModel(path: result.text, buildModel: result.buildModel)
            else
              pack.libDirectories[i],
        ],
      ),
      '已保存',
    );
  }

  Future<void> _removeLibDirectory(int index) async {
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        libDirectories: <LibDirModel>[
          for (int i = 0; i < pack.libDirectories.length; i++)
            if (i != index) pack.libDirectories[i],
        ],
      ),
      '已删除',
    );
  }

  Future<void> _addLibrary() async {
    final CompileEntryResult? result = await _openEntryDialog(
      title: '添加附加库',
      label: '库名称',
      hintText: 'mylib.lib',
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        libraries: <LibraryModel>[
          ...pack.libraries,
          LibraryModel(name: result.text, buildModel: result.buildModel),
        ],
      ),
      '已添加',
    );
  }

  Future<void> _editLibrary(int index) async {
    final LibraryModel library = widget.pack.libraries[index];
    final CompileEntryResult? result = await _openEntryDialog(
      title: '编辑附加库',
      label: '库名称',
      hintText: 'mylib.lib',
      initialText: library.name,
      initialBuildModel: library.buildModel,
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        libraries: <LibraryModel>[
          for (int i = 0; i < pack.libraries.length; i++)
            if (i == index)
              LibraryModel(name: result.text, buildModel: result.buildModel)
            else
              pack.libraries[i],
        ],
      ),
      '已保存',
    );
  }

  Future<void> _removeLibrary(int index) async {
    await _persist(
      (PackModel pack) => _updatedPack(
        pack,
        libraries: <LibraryModel>[
          for (int i = 0; i < pack.libraries.length; i++)
            if (i != index) pack.libraries[i],
        ],
      ),
      '已删除',
    );
  }

  Future<CompileEntryResult?> _openEntryDialog({
    required String title,
    required String label,
    String? hintText,
    bool showBrowse = false,
    String initialText = '',
    BuildModel initialBuildModel = BuildModel.all,
    List<FileModel> selectableScripts = const <FileModel>[],
    bool showMacroHelper = false,
  }) {
    return showDialog<CompileEntryResult>(
      context: context,
      builder: (_) => CompileEntryDialog(
        title: title,
        label: label,
        hintText: hintText,
        showBrowse: showBrowse,
        pickDirectory: widget.pickDirectory,
        initialText: initialText,
        initialBuildModel: initialBuildModel,
        selectableScripts: selectableScripts,
        showMacroHelper: showMacroHelper,
      ),
    );
  }

  List<FileModel> _commandScripts() {
    return <FileModel>[
      for (final FileModel file in widget.pack.files)
        if (scriptFileExtensions.contains(file.extension.toLowerCase())) file,
    ];
  }

  Future<void> _persist(
    PackModel Function(PackModel pack) update,
    String message,
  ) async {
    if (_saving) {
      return;
    }
    _saving = true;
    final bool saved;
    try {
      saved = await widget.onSave(update(widget.pack));
    } finally {
      _saving = false;
    }
    if (!mounted || !saved) {
      return;
    }
    showFloatingToast(context, message);
  }

  PackModel _updatedPack(
    PackModel pack, {
    List<CmdModel>? commands,
    List<MacroModel>? macros,
    List<LibDirModel>? libDirectories,
    List<LibraryModel>? libraries,
  }) {
    return PackModel(
        name: pack.name,
        version: pack.version,
        author: pack.author,
        description: pack.description,
        license: pack.license,
        iconPath: pack.iconPath,
        sourcePath: pack.sourcePath,
      )
      ..files = pack.files
      ..commands = commands ?? pack.commands
      ..dependencies = pack.dependencies
      ..macros = macros ?? pack.macros
      ..libDirectories = libDirectories ?? pack.libDirectories
      ..libraries = libraries ?? pack.libraries
      ..history = pack.history
      ..scripts = pack.scripts;
  }

  List<_CompileEntry> _macroEntries() {
    final List<MacroModel> macros = widget.pack.macros;
    return <_CompileEntry>[
      for (int index = 0; index < macros.length; index++)
        _CompileEntry(
          text: macros[index].value,
          buildModel: macros[index].buildModel,
          editKey: Key('macroEditButton_$index'),
          deleteKey: Key('macroDeleteButton_$index'),
          onEdit: () => _editMacro(index),
          onDelete: () => _removeMacro(index),
        ),
    ];
  }

  List<_CompileEntry> _commandEntries(CmdType type, String keyPrefix) {
    final List<CmdModel> commands = widget.pack.commands;
    return <_CompileEntry>[
      for (int index = 0; index < commands.length; index++)
        if (commands[index].type == type)
          _CompileEntry(
            text: commands[index].command,
            buildModel: commands[index].buildModel,
            editKey: Key('${keyPrefix}EditButton_$index'),
            deleteKey: Key('${keyPrefix}DeleteButton_$index'),
            onEdit: () => _editCommand(index),
            onDelete: () => _removeCommand(index),
          ),
    ];
  }

  List<_CompileEntry> _libDirectoryEntries() {
    final List<LibDirModel> libDirectories = widget.pack.libDirectories;
    return <_CompileEntry>[
      for (int index = 0; index < libDirectories.length; index++)
        _CompileEntry(
          text: libDirectories[index].path,
          buildModel: libDirectories[index].buildModel,
          editKey: Key('libDirEditButton_$index'),
          deleteKey: Key('libDirDeleteButton_$index'),
          onEdit: () => _editLibDirectory(index),
          onDelete: () => _removeLibDirectory(index),
        ),
    ];
  }

  List<_CompileEntry> _libraryEntries() {
    final List<LibraryModel> libraries = widget.pack.libraries;
    return <_CompileEntry>[
      for (int index = 0; index < libraries.length; index++)
        _CompileEntry(
          text: libraries[index].name,
          buildModel: libraries[index].buildModel,
          editKey: Key('libraryEditButton_$index'),
          deleteKey: Key('libraryDeleteButton_$index'),
          onEdit: () => _editLibrary(index),
          onDelete: () => _removeLibrary(index),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSection(
                title: '宏定义',
                columnLabel: '宏定义',
                emptyText: '暂无宏定义',
                addKey: const Key('addMacroButton'),
                onAdd: _addMacro,
                entries: _macroEntries(),
              ),
              const SizedBox(height: 24),
              _buildSection(
                title: '编译前命令',
                columnLabel: '命令',
                emptyText: '暂无编译前命令',
                addKey: const Key('addPreBuildCmdButton'),
                onAdd: () => _addCommand(CmdType.preBuild),
                entries: _commandEntries(CmdType.preBuild, 'preBuildCmd'),
              ),
              const SizedBox(height: 24),
              _buildSection(
                title: '编译后命令',
                columnLabel: '命令',
                emptyText: '暂无编译后命令',
                addKey: const Key('addPostBuildCmdButton'),
                onAdd: () => _addCommand(CmdType.postBuild),
                entries: _commandEntries(CmdType.postBuild, 'postBuildCmd'),
              ),
              const SizedBox(height: 24),
              _buildScriptSection(),
              const SizedBox(height: 24),
              _buildSection(
                title: '附加库目录',
                columnLabel: '目录路径',
                emptyText: '暂无附加库目录',
                addKey: const Key('addLibDirButton'),
                onAdd: _addLibDirectory,
                entries: _libDirectoryEntries(),
              ),
              const SizedBox(height: 24),
              _buildSection(
                title: '附加库',
                columnLabel: '库名称',
                emptyText: '暂无附加库',
                addKey: const Key('addLibraryButton'),
                onAdd: _addLibrary,
                entries: _libraryEntries(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String columnLabel,
    required String emptyText,
    required Key addKey,
    required VoidCallback onAdd,
    required List<_CompileEntry> entries,
  }) {
    return _buildSectionFrame(
      title: title,
      action: FilledButton(
        key: addKey,
        onPressed: _saving ? null : onAdd,
        child: const Text('添加'),
      ),
      body: entries.isEmpty
          ? _buildEmptyText(emptyText)
          : _buildEntryList(entries, columnLabel),
    );
  }

  Widget _buildScriptSection() {
    final List<ScriptProjectModel> scripts = widget.pack.scripts;
    return _buildSectionFrame(
      sectionKey: const Key('nodeScriptsSection'),
      title: '节点脚本',
      action: FilledButton(
        key: const Key('openScriptEditorButton'),
        onPressed: _saving ? null : _openScriptEditor,
        child: const Text('打开节点编辑器'),
      ),
      body: scripts.isEmpty
          ? _buildEmptyText('暂无节点脚本')
          : _buildScriptList(scripts),
    );
  }

  Widget _buildSectionFrame({
    required String title,
    required Widget action,
    required Widget body,
    Key? sectionKey,
  }) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: FluentTheme.of(context).typography.body?.color,
                ),
              ),
            ),
            action,
          ],
        ),
        const SizedBox(height: 4),
        body,
      ],
    );
  }

  Widget _buildEmptyText(String text) {
    return Text(
      text,
      style: TextStyle(
        color: FluentTheme.of(context).resources.textFillColorSecondary,
      ),
    );
  }

  void _openScriptEditor() {
    Navigator.of(context).push<void>(
      FluentPageRoute(
        builder: (_) =>
            ScriptEditorPage(pack: widget.pack, onSave: widget.onSave),
      ),
    );
  }

  Widget _buildScriptList(List<ScriptProjectModel> scripts) {
    return _buildTable(
      header: _buildScriptHeaderRow(),
      rows: <Widget>[
        for (final ScriptProjectModel script in scripts)
          _buildScriptRow(script),
      ],
    );
  }

  Widget _buildScriptHeaderRow() {
    final TextStyle style = _headerTextStyle();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text('名称', style: style)),
          SizedBox(
            width: _triggerColumnWidth,
            child: Text('触发时机', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _buildModelColumnWidth,
            child: Text('构建标签', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _statusColumnWidth,
            child: Text('状态', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptRow(ScriptProjectModel script) {
    final (String statusText, Color statusColor) = _scriptStatus(script);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(script.name, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: _triggerColumnWidth,
            child: Center(
              child: Tag(
                text: scriptTriggerLabel(script.trigger),
                color: scriptTriggerColor(script.trigger),
                fontSize: 10,
              ),
            ),
          ),
          SizedBox(
            width: _buildModelColumnWidth,
            child: Center(
              child: Tag(
                text: buildModelLabel(script.buildModel),
                color: buildModelColor(script.buildModel),
                fontSize: 10,
              ),
            ),
          ),
          SizedBox(
            width: _statusColumnWidth,
            child: Center(
              child: Text(
                statusText,
                style: TextStyle(fontSize: 12, color: statusColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _scriptStatus(ScriptProjectModel script) {
    final List<ScriptDiagnostic> diagnostics = GraphValidator.validate(script);
    final int errors = diagnostics
        .where((ScriptDiagnostic diagnostic) => diagnostic.isError)
        .length;
    final int warnings = diagnostics.length - errors;
    if (errors > 0) {
      return ('$errors 个错误', UCColors.flavor.red);
    }
    if (warnings > 0) {
      return ('$warnings 个警告', UCColors.flavor.yellow);
    }
    return ('正常', UCColors.flavor.green);
  }

  Widget _buildEntryList(List<_CompileEntry> entries, String columnLabel) {
    return _buildTable(
      header: _buildHeaderRow(columnLabel),
      rows: <Widget>[
        for (final _CompileEntry entry in entries) _buildEntryRow(entry),
      ],
    );
  }

  Widget _buildTable({required Widget header, required List<Widget> rows}) {
    final FluentThemeData theme = FluentTheme.of(context);
    final DividerThemeData dividerTheme = theme.dividerTheme;
    return FluentTheme(
      data: theme.copyWith(
        // 全局分割线自带 8px 水平边距，覆盖为 0 使线与列表内容同宽
        dividerTheme: DividerThemeData(
          decoration: dividerTheme.decoration,
          verticalMargin: dividerTheme.verticalMargin,
          horizontalMargin: EdgeInsets.zero,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const Divider(),
          for (int index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(),
            rows[index],
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderRow(String columnLabel) {
    final TextStyle style = _headerTextStyle();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(columnLabel, style: style)),
          SizedBox(
            width: _buildModelColumnWidth,
            child: Text('构建配置', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _actionColumnWidth,
            child: Text('操作', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  TextStyle _headerTextStyle() {
    return TextStyle(
      fontSize: 12,
      color: FluentTheme.of(context).resources.textFillColorSecondary,
    );
  }

  Widget _buildEntryRow(_CompileEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(entry.text, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: _buildModelColumnWidth,
            child: Center(
              child: Tag(
                text: buildModelLabel(entry.buildModel),
                color: buildModelColor(entry.buildModel),
                fontSize: 10,
              ),
            ),
          ),
          SizedBox(
            width: _actionColumnWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: '编辑',
                  child: IconButton(
                    key: entry.editKey,
                    icon: const Icon(FluentIcons.edit, size: 16),
                    onPressed: _saving ? null : entry.onEdit,
                  ),
                ),
                Tooltip(
                  message: '删除',
                  child: IconButton(
                    key: entry.deleteKey,
                    icon: const Icon(FluentIcons.delete, size: 16),
                    onPressed: _saving ? null : entry.onDelete,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompileEntry {
  const _CompileEntry({
    required this.text,
    required this.buildModel,
    required this.editKey,
    required this.deleteKey,
    required this.onEdit,
    required this.onDelete,
  });

  final String text;
  final BuildModel buildModel;
  final Key editKey;
  final Key deleteKey;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
}
