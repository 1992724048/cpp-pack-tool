import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/msbuild_macros.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart'
    show PointerEnterEvent, PointerExitEvent;

final RegExp _environmentNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

const String _environmentNameError = '变量名须以字母或下划线开头，且仅含字母、数字、下划线';
const String _noMatchingPathHint = '无匹配路径，将按手填内容使用';
const String _emptyProjectHint = '请先新建脚本项目';
const String _noParamHint = '该节点没有可编辑参数';

const Map<String, String> _logLevelOptions = <String, String>{
  'info': '信息',
  'warn': '警告',
  'error': '错误',
};

const Map<String, String> _stringOperatorOptions = <String, String>{
  'eq': '等于',
  'ne': '不等于',
  'contains': '包含',
};

/// 右侧检查器面板（视觉规范 §6）：有选中节点 → 节点属性；无选中 → 项目属性。
///
/// 节点参数按注册表声明序渲染并按 [ScriptParamType] 选择控件，编辑即时经
/// [GraphEditorController.updateNodeParam] 写回模型。项目属性中的选中、重命名、
/// 触发时机、构建模型与排序经回调上报页面（保存队列 T10 与项目排序 T11 接入）。
class NodeInspector extends StatefulWidget {
  const NodeInspector({
    super.key,
    this.controller,
    required this.pack,
    this.packagePaths,
    this.onSelectProject,
    this.onRenameProject,
    this.onTriggerChanged,
    this.onBuildModelChanged,
    this.onMoveProjectUp,
    this.onMoveProjectDown,
  });

  /// 编辑器控制器；null 表示无脚本项目（§6.4 空态）。
  final GraphEditorController? controller;

  final PackModel pack;

  /// 包内路径建议（`build/native/` 相对）；null 时由
  /// `NuGetPackageBuilder().buildPlan(pack)` 计算并剥离该前缀。
  final List<String>? packagePaths;

  final ValueChanged<ScriptProjectModel>? onSelectProject;

  final void Function(ScriptProjectModel project, String name)? onRenameProject;

  final void Function(ScriptProjectModel project, ScriptTrigger trigger)?
  onTriggerChanged;

  final void Function(ScriptProjectModel project, BuildModel buildModel)?
  onBuildModelChanged;

  final void Function(ScriptProjectModel project)? onMoveProjectUp;

  final void Function(ScriptProjectModel project)? onMoveProjectDown;

  @override
  State<NodeInspector> createState() => _NodeInspectorState();
}

class _NodeInspectorState extends State<NodeInspector> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _nameEditor = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final Map<String, TextEditingController> _paramEditors =
      <String, TextEditingController>{};

  List<String> _packagePaths = const <String>[];
  String? _activeNodeId;
  String? _nameError;
  String? _notifiedName;

  /// 最近一次与名称框同步的项目实例；用于识别切换项目（含重命名替换）。
  ScriptProjectModel? _nameProject;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_handleNameFocusChange);
    widget.controller?.addListener(_handleControllerChanged);
    _applyPackagePaths();
    _syncNameEditor();
  }

  @override
  void didUpdateWidget(covariant NodeInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerChanged);
      widget.controller?.addListener(_handleControllerChanged);
      _activeNodeId = null;
      _clearParamEditors();
    }
    if (!identical(oldWidget.packagePaths, widget.packagePaths)) {
      _applyPackagePaths();
    }
    _syncNameEditor();
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_handleNameFocusChange);
    _nameFocus.dispose();
    _nameEditor.dispose();
    _scrollController.dispose();
    _clearParamEditors();
    widget.controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GraphEditorController? controller = widget.controller;
    if (controller == null) {
      return Center(
        child: Text(
          _emptyProjectHint,
          style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext1),
        ),
      );
    }
    final ScriptNodeModel? node = _findSelectedNode(controller);
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (node == null)
              _ProjectPanel(
                project: controller.project,
                projects: widget.pack.scripts,
                nameEditor: _nameEditor,
                nameFocus: _nameFocus,
                nameError: _nameError,
                onNameSubmitted: () => _commitProjectName(controller.project),
                onTriggerChanged: widget.onTriggerChanged,
                onBuildModelChanged: widget.onBuildModelChanged,
                onSelectProject: widget.onSelectProject,
                onMoveProjectUp: widget.onMoveProjectUp,
                onMoveProjectDown: widget.onMoveProjectDown,
              )
            else
              ..._buildNodeMode(node),
          ],
        ),
      ),
    );
  }

  void _applyPackagePaths() {
    final List<String>? injected = widget.packagePaths;
    if (injected != null) {
      _packagePaths = injected;
      return;
    }
    _loadPackagePaths();
  }

  /// 建议值取包内 `build/native/` 相对路径：发射侧 `CNP_PackageRoot`
  /// （`Join-Path` 基目录）指向该目录，含前缀会组合出双前缀。
  Future<void> _loadPackagePaths() async {
    final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(
      widget.pack,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _packagePaths = plan.entries
          .map(
            (PackageEntry entry) => buildNativeRelativePath(entry.packagePath),
          )
          .whereType<String>()
          .toList();
    });
  }

  void _handleControllerChanged() {
    final GraphEditorController? controller = widget.controller;
    if (controller == null) {
      return;
    }
    final String? selected = controller.selectedNodeId;
    if (selected != _activeNodeId) {
      _activeNodeId = selected;
      _clearParamEditors();
    }
    _syncNameEditor();
    setState(() {});
  }

  void _syncNameEditor() {
    final ScriptProjectModel? project = widget.controller?.project;
    if (project == null) {
      return;
    }
    final bool projectChanged = !identical(_nameProject, project);
    if (!projectChanged && _nameFocus.hasFocus) {
      return;
    }
    if (projectChanged || _nameEditor.text != project.name) {
      _nameProject = project;
      _nameEditor.text = project.name;
      _nameError = null;
      _notifiedName = null;
    }
  }

  void _clearParamEditors() {
    for (final TextEditingController editor in _paramEditors.values) {
      editor.dispose();
    }
    _paramEditors.clear();
  }

  TextEditingController _paramEditor(
    String nodeId,
    String paramKey,
    String initialText,
  ) {
    return _paramEditors.putIfAbsent(
      '$nodeId/$paramKey',
      () => TextEditingController(text: initialText),
    );
  }

  ScriptNodeModel? _findSelectedNode(GraphEditorController controller) {
    final String? selected = controller.selectedNodeId;
    if (selected == null) {
      return null;
    }
    for (final ScriptNodeModel node in controller.project.nodes) {
      if (node.id == selected) {
        return node;
      }
    }
    return null;
  }

  List<Widget> _buildNodeMode(ScriptNodeModel node) {
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    final List<ScriptParamDescriptor> params =
        descriptor?.params ?? const <ScriptParamDescriptor>[];
    return <Widget>[
      _buildNodeHeader(node, descriptor),
      _divider(),
      if (params.isEmpty)
        Text(
          _noParamHint,
          style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
        )
      else
        for (final ScriptParamDescriptor param in params)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildParamField(node, param),
          ),
    ];
  }

  Widget _buildNodeHeader(
    ScriptNodeModel node,
    ScriptNodeTypeDescriptor? descriptor,
  ) {
    final IconData icon = descriptor == null
        ? FluentIcons.cube_shape
        : nodeTypeIcon(descriptor.typeKey);
    final Color iconColor = descriptor == null
        ? UCColors.flavor.subtext0
        : nodeCategoryColor(descriptor.category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                descriptor?.displayName ?? node.type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: UCColors.flavor.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          node.type,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            color: UCColors.flavor.subtext0,
          ),
        ),
      ],
    );
  }

  Widget _buildParamField(ScriptNodeModel node, ScriptParamDescriptor param) {
    final Object? value = node.params[param.key] ?? param.defaultValue;
    if (param.type == ScriptParamType.boolean) {
      return SizedBox(
        height: 32,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                param.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext1),
              ),
            ),
            ToggleSwitch(
              key: Key('inspectorField_${param.key}'),
              checked: value == true,
              onChanged: (bool next) => _writeParam(node, param.key, next),
            ),
          ],
        ),
      );
    }
    final String? error = _paramError(node, param, value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          param.label,
          style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext1),
        ),
        const SizedBox(height: 4),
        KeyedSubtree(
          key: ValueKey<String>('${node.id}/${param.key}'),
          child: _buildParamControl(node, param, value),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          _buildFieldError(Key('inspectorFieldError_${param.key}'), error),
        ],
      ],
    );
  }

  Widget _buildParamControl(
    ScriptNodeModel node,
    ScriptParamDescriptor param,
    Object? value,
  ) {
    switch (param.type) {
      case ScriptParamType.text:
        return TextBox(
          key: Key('inspectorField_${param.key}'),
          controller: _paramEditor(
            node.id,
            param.key,
            value is String ? value : '',
          ),
          onChanged: (String next) => _writeParam(node, param.key, next),
        );
      case ScriptParamType.macroKey:
        return _denseComboBox(
          context,
          ComboBox<String>(
            key: Key('inspectorField_${param.key}'),
            value: value is String && msbuildMacroKeys.contains(value)
                ? value
                : null,
            isExpanded: true,
            items: <ComboBoxItem<String>>[
              for (final String macro in msbuildMacroKeys)
                ComboBoxItem<String>(value: macro, child: Text('\$($macro)')),
            ],
            onChanged: (String? next) {
              if (next != null) {
                _writeParam(node, param.key, next);
              }
            },
          ),
        );
      case ScriptParamType.logLevel:
        return _denseComboBox(
          context,
          _buildOptionComboBox(
            param: param,
            value: value,
            options: _logLevelOptions,
            onSelected: (String next) => _writeParam(node, param.key, next),
          ),
        );
      case ScriptParamType.stringOperator:
        return _denseComboBox(
          context,
          _buildOptionComboBox(
            param: param,
            value: value,
            options: _stringOperatorOptions,
            onSelected: (String next) => _writeParam(node, param.key, next),
          ),
        );
      case ScriptParamType.packageFilePath:
        return AutoSuggestBox<String>(
          key: Key('inspectorField_${param.key}'),
          controller: _paramEditor(
            node.id,
            param.key,
            value is String ? value : '',
          ),
          items: <AutoSuggestBoxItem<String>>[
            for (final String path in _packagePaths)
              AutoSuggestBoxItem<String>(
                value: path,
                label: path,
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          sorter: _sortPackagePaths,
          noResultsFoundBuilder: (BuildContext context) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _noMatchingPathHint,
              style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
            ),
          ),
          onChanged: (String text, TextChangedReason reason) =>
              _writeParam(node, param.key, text),
          onSelected: (AutoSuggestBoxItem<String> item) =>
              _writeParam(node, param.key, item.value),
        );
      case ScriptParamType.boolean:
        // 开关由 _buildParamField 的行布局处理，此处不可达。
        return const SizedBox.shrink();
      case ScriptParamType.number:
        // TODO: 数值输入控件（可负、可小数、非数字不写入）待实现。
        return const SizedBox.shrink();
    }
  }

  ComboBox<String> _buildOptionComboBox({
    required ScriptParamDescriptor param,
    required Object? value,
    required Map<String, String> options,
    required ValueChanged<String> onSelected,
  }) {
    return ComboBox<String>(
      key: Key('inspectorField_${param.key}'),
      value: value is String && options.containsKey(value) ? value : null,
      isExpanded: true,
      items: <ComboBoxItem<String>>[
        for (final MapEntry<String, String> option in options.entries)
          ComboBoxItem<String>(value: option.key, child: Text(option.value)),
      ],
      onChanged: (String? next) {
        if (next != null) {
          onSelected(next);
        }
      },
    );
  }

  List<AutoSuggestBoxItem<String>> _sortPackagePaths(
    String text,
    List<AutoSuggestBoxItem<String>> items,
  ) {
    final String query = text.trim().toLowerCase();
    if (query.isEmpty) {
      return items;
    }
    return <AutoSuggestBoxItem<String>>[
      for (final AutoSuggestBoxItem<String> item in items)
        if (item.label.toLowerCase().contains(query)) item,
    ];
  }

  String? _paramError(
    ScriptNodeModel node,
    ScriptParamDescriptor param,
    Object? value,
  ) {
    if (node.type != 'context.environment' || param.key != 'name') {
      return null;
    }
    if (value is String && _environmentNamePattern.hasMatch(value)) {
      return null;
    }
    return _environmentNameError;
  }

  void _writeParam(ScriptNodeModel node, String paramKey, Object? value) {
    widget.controller?.updateNodeParam(node.id, paramKey, value);
  }

  void _commitProjectName(ScriptProjectModel project) {
    final String value = _nameEditor.text.trim();
    final String? error = _projectNameError(project, value);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    if (value == project.name || value == _notifiedName) {
      setState(() => _nameError = null);
      return;
    }
    final void Function(ScriptProjectModel, String)? onRename =
        widget.onRenameProject;
    if (onRename == null) {
      // 回调未接入（T11 前）：还原显示，避免界面与模型不一致。
      setState(() {
        _nameError = null;
        _nameEditor.text = project.name;
      });
      return;
    }
    setState(() {
      _nameError = null;
      _notifiedName = value;
    });
    onRename(project, value);
  }

  String? _projectNameError(ScriptProjectModel project, String value) {
    if (value.isEmpty) {
      return '名称不能为空';
    }
    final String lower = value.toLowerCase();
    for (final ScriptProjectModel other in widget.pack.scripts) {
      if (other.id != project.id && other.name.toLowerCase() == lower) {
        return '名称已存在';
      }
    }
    return null;
  }

  void _handleNameFocusChange() {
    if (_nameFocus.hasFocus) {
      return;
    }
    final ScriptProjectModel? project = widget.controller?.project;
    if (project != null) {
      _commitProjectName(project);
    }
  }
}

/// 项目属性分区（无选中节点时显示）：元信息、触发时机/构建标签与执行顺序。
class _ProjectPanel extends StatelessWidget {
  const _ProjectPanel({
    required this.project,
    required this.projects,
    required this.nameEditor,
    required this.nameFocus,
    required this.nameError,
    required this.onNameSubmitted,
    this.onTriggerChanged,
    this.onBuildModelChanged,
    this.onSelectProject,
    this.onMoveProjectUp,
    this.onMoveProjectDown,
  });

  final ScriptProjectModel project;
  final List<ScriptProjectModel> projects;

  /// 名称编辑控制器与焦点由检查器持有（失焦提交与模型同步在检查器侧）。
  final TextEditingController nameEditor;
  final FocusNode nameFocus;
  final String? nameError;

  final VoidCallback onNameSubmitted;

  final void Function(ScriptProjectModel project, ScriptTrigger trigger)?
  onTriggerChanged;

  final void Function(ScriptProjectModel project, BuildModel buildModel)?
  onBuildModelChanged;

  final ValueChanged<ScriptProjectModel>? onSelectProject;

  final void Function(ScriptProjectModel project)? onMoveProjectUp;

  final void Function(ScriptProjectModel project)? onMoveProjectDown;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '脚本项目',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: UCColors.flavor.text,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _labeledField(
          '名称',
          TextBox(
            key: const Key('inspectorProjectName'),
            controller: nameEditor,
            focusNode: nameFocus,
            onSubmitted: (_) => onNameSubmitted(),
          ),
          error: nameError,
          errorKey: const Key('inspectorProjectNameError'),
        ),
        const SizedBox(height: 16),
        _labeledField(
          '触发时机',
          _denseComboBox(
            context,
            ComboBox<ScriptTrigger>(
              key: const Key('inspectorProjectTrigger'),
              value: project.trigger,
              isExpanded: true,
              items: <ComboBoxItem<ScriptTrigger>>[
                ComboBoxItem<ScriptTrigger>(
                  value: ScriptTrigger.pre,
                  child: const Text('编译前'),
                ),
                ComboBoxItem<ScriptTrigger>(
                  value: ScriptTrigger.post,
                  child: const Text('编译后'),
                ),
              ],
              onChanged: (ScriptTrigger? next) {
                if (next != null) {
                  onTriggerChanged?.call(project, next);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _labeledField(
          '构建标签',
          Row(
            children: <Widget>[
              Expanded(
                child: _denseComboBox(
                  context,
                  ComboBox<BuildModel>(
                    key: const Key('inspectorProjectBuildModel'),
                    value: project.buildModel,
                    isExpanded: true,
                    items: <ComboBoxItem<BuildModel>>[
                      for (final BuildModel buildModel in BuildModel.values)
                        ComboBoxItem<BuildModel>(
                          value: buildModel,
                          child: Text(buildModelLabel(buildModel)),
                        ),
                    ],
                    onChanged: (BuildModel? next) {
                      if (next != null) {
                        onBuildModelChanged?.call(project, next);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tag(
                key: const Key('inspectorProjectBuildTag'),
                text: buildModelLabel(project.buildModel),
                color: buildModelColor(project.buildModel),
                fontSize: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '脚本 ID',
          style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext1),
        ),
        const SizedBox(height: 4),
        Text(
          project.id,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            color: UCColors.flavor.subtext0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '导出时决定包内文件名与 Target 名',
          style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
        ),
        _divider(),
        Text(
          '执行顺序',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: UCColors.flavor.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '同组内按列表顺序执行',
          style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
        ),
        const SizedBox(height: 8),
        for (int index = 0; index < projects.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == projects.length - 1 ? 0 : 2,
            ),
            child: _ProjectOrderRow(
              project: projects[index],
              current: projects[index].id == project.id,
              canMoveUp: index > 0,
              canMoveDown: index < projects.length - 1,
              onTap: () => onSelectProject?.call(projects[index]),
              onMoveUp: () => onMoveProjectUp?.call(projects[index]),
              onMoveDown: () => onMoveProjectDown?.call(projects[index]),
            ),
          ),
      ],
    );
  }
}

Widget _labeledField(
  String label,
  Widget control, {
  String? error,
  Key? errorKey,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label,
        style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext1),
      ),
      const SizedBox(height: 4),
      control,
      if (error != null && errorKey != null) ...<Widget>[
        const SizedBox(height: 4),
        _buildFieldError(errorKey, error),
      ],
    ],
  );
}

Widget _buildFieldError(Key key, String message) {
  return Row(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(FluentIcons.error_badge, size: 12, color: UCColors.flavor.red),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          message,
          style: TextStyle(fontSize: 12, color: UCColors.flavor.red),
        ),
      ),
    ],
  );
}

Widget _divider() {
  return Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 12),
    color: UCColors.flavor.surface2,
  );
}

Widget _denseComboBox(BuildContext context, Widget child) {
  return FluentTheme(
    data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
    child: child,
  );
}

class _ProjectOrderRow extends StatefulWidget {
  const _ProjectOrderRow({
    required this.project,
    required this.current,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ScriptProjectModel project;
  final bool current;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onTap;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  State<_ProjectOrderRow> createState() => _ProjectOrderRowState();
}

class _ProjectOrderRowState extends State<_ProjectOrderRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (PointerEnterEvent event) => setState(() => _hovered = true),
      onExit: (PointerExitEvent event) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          key: Key('scriptProjectRow_${widget.project.id}'),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.current
                ? UCColors.accent.withValues(alpha: 0.35)
                : (_hovered ? UCColors.flavor.surface0 : null),
            borderRadius: BorderRadius.circular(4),
            border: widget.current
                ? Border(left: BorderSide(color: UCColors.accent, width: 2))
                : null,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.current
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: UCColors.flavor.text,
                  ),
                ),
              ),
              Tag(
                text: scriptTriggerLabel(widget.project.trigger),
                color: scriptTriggerColor(widget.project.trigger),
                fontSize: 10,
              ),
              const SizedBox(width: 4),
              Tag(
                text: buildModelLabel(widget.project.buildModel),
                color: buildModelColor(widget.project.buildModel),
                fontSize: 10,
              ),
              const SizedBox(width: 4),
              _buildMoveButton(
                key: Key('scriptProjectMoveUp_${widget.project.id}'),
                icon: FluentIcons.chevron_up,
                tooltip: '上移',
                onPressed: widget.canMoveUp ? widget.onMoveUp : null,
              ),
              _buildMoveButton(
                key: Key('scriptProjectMoveDown_${widget.project.id}'),
                icon: FluentIcons.chevron_down,
                tooltip: '下移',
                onPressed: widget.canMoveDown ? widget.onMoveDown : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoveButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
          key: key,
          icon: Icon(icon, size: 14),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
