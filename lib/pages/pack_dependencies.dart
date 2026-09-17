import 'package:cpp_nuget_pack/controls/dependency_dialog.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _versionColumnWidth = 160;
const double _actionColumnWidth = 80;

const String _systemLockTooltip = '由构建管线注册，禁止修改/删除';

class PackDependencies extends StatefulWidget {
  const PackDependencies({super.key, required this.pack, required this.allPacks, required this.onSave});

  final PackModel pack;
  final List<PackModel> allPacks;
  final Future<bool> Function(PackModel pack) onSave;

  @override
  State<PackDependencies> createState() => _PackDependenciesState();
}

class _PackDependenciesState extends State<PackDependencies> {
  bool _saving = false;

  List<PackModel> get _candidates {
    final String self = widget.pack.name.toLowerCase();
    final Set<String> added = <String>{
      for (final DependencyModel dependency in widget.pack.dependencies) dependency.name.toLowerCase(),
    };
    return <PackModel>[
      for (final PackModel pack in widget.allPacks)
        if (pack.name.toLowerCase() != self && !added.contains(pack.name.toLowerCase())) pack,
    ];
  }

  Future<void> _add() async {
    final DependencyModel? result = await showDialog<DependencyModel>(
      context: context,
      builder: (_) => DependencyDialog(candidates: _candidates),
    );
    if (result == null || !mounted) {
      return;
    }
    await _persist(<DependencyModel>[...widget.pack.dependencies, result], '已添加');
  }

  Future<void> _edit(DependencyModel dependency) async {
    final DependencyModel? result = await showDialog<DependencyModel>(
      context: context,
      builder: (_) => DependencyDialog(editing: dependency),
    );
    if (result == null || !mounted) {
      return;
    }
    final List<DependencyModel> updated = <DependencyModel>[
      for (final DependencyModel item in widget.pack.dependencies)
        item.name.toLowerCase() == dependency.name.toLowerCase() ? result : item,
    ];
    await _persist(updated, '已保存');
  }

  Future<void> _remove(DependencyModel dependency) async {
    final List<DependencyModel> updated = <DependencyModel>[
      for (final DependencyModel item in widget.pack.dependencies)
        if (item.name.toLowerCase() != dependency.name.toLowerCase()) item,
    ];
    await _persist(updated, '已删除');
  }

  Future<void> _persist(List<DependencyModel> dependencies, String message) async {
    if (_saving) {
      return;
    }
    _saving = true;
    final bool saved;
    try {
      saved = await widget.onSave(_withDependencies(widget.pack, dependencies));
    } finally {
      _saving = false;
    }
    if (!mounted || !saved) {
      return;
    }
    showFloatingToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
            child: Row(
              children: [
                Button(
                  key: const Key('addDependencyButton'),
                  onPressed: _saving ? null : _add,
                  child: const Row(
                    mainAxisSize: .min,
                    children: [Icon(FluentIcons.add), SizedBox(width: 5), Text('添加依赖')],
                  ),
                ),
                Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(child: widget.pack.dependencies.isEmpty ? _buildEmptyGuide() : _buildDependencyList()),
        ],
      ),
    );
  }

  Widget _buildDependencyList() {
    final FluentThemeData theme = FluentTheme.of(context);
    final DividerThemeData dividerTheme = theme.dividerTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(),
        Expanded(
          child: ListView.builder(
            itemCount: widget.pack.dependencies.length,
            itemBuilder: (BuildContext context, int index) => _buildRow(context, widget.pack.dependencies[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow() {
    final TextStyle style = TextStyle(fontSize: 12, color: FluentTheme.of(context).resources.textFillColorSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: Card(
        child: Row(
          children: [
            Expanded(child: Text('包名', style: style)),
            SizedBox(
              width: _versionColumnWidth,
              child: Text('版本范围', style: style),
            ),
            SizedBox(
              width: _actionColumnWidth,
              child: Text('操作', style: style, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyGuide() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [Text('暂无依赖'), SizedBox(height: 6), Text('点击「添加依赖」开始')]),
    );
  }

  Widget _buildRow(BuildContext context, DependencyModel dependency) {
    final FluentThemeData theme = FluentTheme.of(context);
    final bool missing = !widget.allPacks.any(
      (PackModel pack) => pack.name.toLowerCase() == dependency.name.toLowerCase(),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Card(
        padding: EdgeInsetsGeometry.fromLTRB(8, 2, 8, 2),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(child: Text(dependency.name, overflow: TextOverflow.ellipsis)),
                  if (dependency.system) ...[
                    const SizedBox(width: 5),
                    Tag(text: '系统', color: theme.resources.solidBackgroundFillColorQuarternary, fontSize: 10),
                  ],
                  if (missing) ...[const SizedBox(width: 5), Tag(text: '缺失', color: MarkerColors.red, fontSize: 10)],
                ],
              ),
            ),
            SizedBox(
              width: _versionColumnWidth,
              child: Text(
                dependency.version,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.resources.textFillColorSecondary),
              ),
            ),
            SizedBox(
              width: _actionColumnWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Tooltip(
                    message: dependency.system ? _systemLockTooltip : '编辑',
                    child: IconButton(
                      key: Key('dependencyEditButton_${dependency.name}'),
                      icon: const Icon(FluentIcons.edit, size: 16),
                      onPressed: _saving || dependency.system ? null : () => _edit(dependency),
                    ),
                  ),
                  SizedBox(width: 3),
                  Tooltip(
                    message: dependency.system ? _systemLockTooltip : '删除',
                    child: IconButton(
                      key: Key('dependencyDeleteButton_${dependency.name}'),
                      icon: const Icon(FluentIcons.delete, size: 16),
                      onPressed: _saving || dependency.system ? null : () => _remove(dependency),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

PackModel _withDependencies(PackModel pack, List<DependencyModel> dependencies) {
  return PackModel(
      name: pack.name,
      version: pack.version,
      author: pack.author,
      description: pack.description,
      license: pack.license,
      iconPath: pack.iconPath,
      sourcePath: pack.sourcePath,
      sourceVersion: pack.sourceVersion,
    )
    ..files = pack.files
    ..commands = pack.commands
    ..dependencies = dependencies
    ..macros = pack.macros
    ..libDirectories = pack.libDirectories
    ..libraries = pack.libraries
    ..history = pack.history
    ..scripts = pack.scripts
    ..buildOptions = pack.buildOptions
    ..enabledFormats = pack.enabledFormats;
}
