import 'dart:async';

import 'package:cpp_nuget_pack/controls/script_editor/editor_canvas.dart';
import 'package:cpp_nuget_pack/controls/script_editor/node_inspector.dart';
import 'package:cpp_nuget_pack/controls/script_editor/node_library_panel.dart';
import 'package:cpp_nuget_pack/controls/script_editor/output_panel.dart';
import 'package:cpp_nuget_pack/controls/script_editor/script_project_dialogs.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/editor_save_queue.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _topBarHeight = 48;
const double _nodeLibraryWidth = 232;
const double _inspectorWidth = 280;
const double _titleMaxWidth = 240;

/// 节点编辑器全屏页：顶栏（返回 / 标题 / 项目选择器与新建、重命名、删除 /
/// 保存状态 / 生成预览）、左侧节点库、中间画布、右侧检查器与底部输出面板。
///
/// 布局数值与分隔线取自视觉规范 §1/§3（顶栏 48、左 232、右 280、底部收起 34、
/// 1px `surface2` 分隔）。无脚本项目时画布区为空态引导（§5.8，含「新建脚本项目」
/// 按钮）、两侧面板整体禁用。项目 CRUD 见 §8.1-8.3，切换/排序见 §10.5/§10.6：
/// 切换前先收口视口防抖并 flush 保存队列；控制器变更与视口变化经 400ms 防抖保存
/// 队列写回（§10.1/§10.4），返回按钮在队列清空后 pop，保存失败时弹确认对话框（§8.4）。
class ScriptEditorPage extends StatefulWidget {
  const ScriptEditorPage({
    super.key,
    required this.pack,
    required this.onSave,
    this.generator,
    this.packagePaths,
    this.debounce = const Duration(milliseconds: 400),
  });

  final PackModel pack;
  final Future<bool> Function(PackModel pack) onSave;

  /// 代码生成器；null 时由生成预览（T9）回退 `PowerShell5Generator()`。
  final ScriptCodeGenerator? generator;

  /// 包内路径建议（检查器 T8 使用）；null 时由页面经 `NuGetBuilder` 计算。
  final List<String>? packagePaths;

  /// 保存与视口写回的防抖时长（§10.1/§10.4，默认 400ms）；测试注入更短值。
  final Duration debounce;

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  GraphEditorController? _controller;
  final TransformationController _transformation = TransformationController();
  final GlobalKey<OutputPanelState> _outputPanelKey =
      GlobalKey<OutputPanelState>();
  Size? _canvasViewportSize;

  late final EditorSaveQueue _saveQueue;
  Timer? _viewportDebounceTimer;
  Object? _lastSaveError;
  bool _backing = false;

  /// 免脏加载标记：控制器 `loadProject` 的选中清空/诊断重算通知不是编辑，
  /// 不应进入保存队列（切换/重命名/元数据变更共用）。
  bool _suppressSaveMark = false;

  bool get _hasProject => _controller != null;

  /// 会话内的脚本项目工作列表（就地增删改）；保存时经 `_buildUpdatedPack` 拷贝。
  List<ScriptProjectModel> get _scripts => widget.pack.scripts;

  @override
  void initState() {
    super.initState();
    final List<ScriptProjectModel> scripts = widget.pack.scripts;
    _controller = scripts.isEmpty ? null : GraphEditorController(scripts.first);
    _saveQueue = EditorSaveQueue(
      save: _saveProject,
      debounce: widget.debounce,
      onStatusChanged: _handleSaveStatusChanged,
    );
    _controller?.addListener(_handleControllerChanged);
    _transformation.addListener(_handleTransformationChanged);
  }

  @override
  void dispose() {
    _viewportDebounceTimer?.cancel();
    _transformation.removeListener(_handleTransformationChanged);
    _controller?.removeListener(_handleControllerChanged);
    _saveQueue.dispose();
    _transformation.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('nodeEditorPage'),
      color: UCColors.flavor.mantle,
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildBody()),
          _buildOutputBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      key: const Key('editorTopBar'),
      height: _topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: UCColors.flavor.mantle,
        border: Border(bottom: BorderSide(color: UCColors.flavor.surface2)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: '返回包管理',
            child: IconButton(
              icon: _backing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.back, size: 16),
              onPressed: _backing ? null : _handleBack,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _titleMaxWidth),
            child: Text(
              '节点编辑器 — ${widget.pack.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: UCColors.flavor.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: UCColors.flavor.surface2),
          const SizedBox(width: 16),
          _buildScriptProjectSelector(),
          const SizedBox(width: 8),
          _buildScriptActionButton(
            buttonKey: const Key('newScriptButton'),
            icon: FluentIcons.add,
            tooltip: '新建脚本项目',
            onPressed: _handleCreateScriptProject,
          ),
          const SizedBox(width: 8),
          _buildScriptActionButton(
            buttonKey: const Key('renameScriptButton'),
            icon: FluentIcons.rename,
            tooltip: '重命名脚本项目',
            onPressed: _hasProject ? _openRenameScriptProjectDialog : null,
          ),
          const SizedBox(width: 8),
          _buildScriptActionButton(
            buttonKey: const Key('deleteScriptButton'),
            icon: FluentIcons.delete,
            tooltip: '删除脚本项目',
            onPressed: _hasProject ? _handleDeleteScriptProject : null,
          ),
          const Spacer(),
          _buildTopBarActions(),
        ],
      ),
    );
  }

  /// 顶栏动作区（Spacer 之后，§3.1）：保存状态在「生成预览」之前。
  Widget _buildTopBarActions() {
    return Row(
      key: const Key('editorTopBarActions'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildSaveStatus(),
        const SizedBox(width: 16),
        Tooltip(
          message: '生成 PowerShell 代码预览',
          child: SizedBox(
            height: 32,
            child: FilledButton(
              key: const Key('generatePreviewButton'),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (Set<WidgetState> states) =>
                      states.contains(WidgetState.disabled)
                      ? UCColors.flavor.subtext0
                      : UCColors.flavor.crust,
                ),
              ),
              onPressed: _hasProject ? _generatePreview : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(FluentIcons.code, size: 16),
                  const SizedBox(width: 8),
                  const Text('生成预览', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 顶栏项目选择器（§3.1/§3.2）：宽 200、高 32；按钮态显示项目名，
  /// 下拉项含项目名 + 触发时机与构建标签；无项目时禁用。
  Widget _buildScriptProjectSelector() {
    final List<ScriptProjectModel> scripts = _scripts;
    return SizedBox(
      width: 200,
      height: 32,
      child: FluentTheme(
        data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
        child: ComboBox<ScriptProjectModel>(
          key: const Key('scriptProjectComboBox'),
          value: _controller?.project,
          isExpanded: true,
          onChanged: _hasProject
              ? (ScriptProjectModel? next) {
                  if (next != null) {
                    _handleSelectScriptProject(next);
                  }
                }
              : null,
          selectedItemBuilder: (BuildContext context) => <Widget>[
            for (final ScriptProjectModel project in scripts)
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: UCColors.flavor.text),
              ),
          ],
          items: <ComboBoxItem<ScriptProjectModel>>[
            for (final ScriptProjectModel project in scripts)
              ComboBoxItem<ScriptProjectModel>(
                value: project,
                child: Row(
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tag(
                      text: _scriptTriggerLabel(project.trigger),
                      color: _scriptTriggerColor(project.trigger),
                      fontSize: 10,
                    ),
                    const SizedBox(width: 4),
                    Tag(
                      text: buildModelLabel(project.buildModel),
                      color: _scriptBuildModelColor(project.buildModel),
                      fontSize: 10,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScriptActionButton({
    required Key buttonKey,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          key: buttonKey,
          icon: Icon(icon, size: 16),
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidePanel(
          panelKey: const Key('nodeLibraryPanel'),
          width: _nodeLibraryWidth,
          border: Border(right: BorderSide(color: UCColors.flavor.surface2)),
          child: NodeLibraryPanel(
            onAddNode: _hasProject ? _addNodeFromLibrary : null,
          ),
        ),
        Expanded(child: _buildCanvasArea()),
        _buildSidePanel(
          panelKey: const Key('inspectorPanel'),
          width: _inspectorWidth,
          border: Border(left: BorderSide(color: UCColors.flavor.surface2)),
          child: NodeInspector(
            controller: _controller,
            pack: widget.pack,
            packagePaths: widget.packagePaths,
            onSelectProject: _handleSelectScriptProject,
            onRenameProject: _handleRenameScriptProject,
            onTriggerChanged: _handleTriggerChanged,
            onBuildModelChanged: _handleBuildModelChanged,
            onMoveProjectUp: _handleMoveScriptProjectUp,
            onMoveProjectDown: _handleMoveScriptProjectDown,
          ),
        ),
      ],
    );
  }

  Widget _buildSidePanel({
    required Key panelKey,
    required double width,
    required Border border,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Opacity(
        key: panelKey,
        opacity: _hasProject ? 1.0 : 0.5,
        child: IgnorePointer(
          ignoring: !_hasProject,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UCColors.flavor.base,
              border: border,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasArea() {
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return Container(
        color: UCColors.flavor.mantle,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                FluentIcons.power_shell,
                size: 40,
                color: UCColors.flavor.subtext1,
              ),
              const SizedBox(height: 16),
              Text(
                '尚未创建脚本项目',
                style: TextStyle(fontSize: 14, color: UCColors.flavor.text),
              ),
              const SizedBox(height: 8),
              Text(
                '节点图将编译为编译前/后 PowerShell 脚本',
                style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext1),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 32,
                child: FilledButton(
                  key: const Key('emptyNewScriptButton'),
                  onPressed: _handleCreateScriptProject,
                  child: const Text('新建脚本项目', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
          _canvasViewportSize = constraints.biggest;
        }
        return EditorCanvas(
          key: const Key('editorCanvas'),
          controller: controller,
          transformationController: _transformation,
          onFlush: _flushSaveQueue,
        );
      },
    );
  }

  /// 节点库点击添加（§4.2）：落点基于画布可见视口中心的场景坐标。
  void _addNodeFromLibrary(ScriptNodeTypeDescriptor descriptor) {
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return;
    }
    controller.addNode(
      descriptor.typeKey,
      nodeLibraryAddPosition(
        viewportCenterScene: _viewportCenterScene(),
        descriptor: descriptor,
        existingNodeCount: controller.project.nodes.length,
      ),
    );
  }

  /// 画布可见视口中心对应的场景坐标；与画布共用同一 [TransformationController]。
  Offset _viewportCenterScene() {
    final Size? viewport = _canvasViewportSize;
    if (viewport == null) {
      return Offset.zero;
    }
    return _transformation.toScene(viewport.center(Offset.zero));
  }

  /// 新建项目（§8.1）：对话框收集名称与触发/构建配置；id 取 `script_N`
  /// 最大序号 +1，自动放置入口节点 (40, 60)，追加后选中并走保存队列。
  Future<void> _handleCreateScriptProject() async {
    final NewScriptProjectRequest? request =
        await showCreateScriptProjectDialog(context, existing: _scripts);
    if (request == null || !mounted) {
      return;
    }
    final ScriptProjectModel project = ScriptProjectModel(
      id: nextScriptProjectId(_scripts),
      name: request.name,
      trigger: request.trigger,
      buildModel: request.buildModel,
    );
    _scripts.add(project);
    await _activateScriptProject(project, addEntryNode: true);
    if (!mounted) {
      return;
    }
    _saveQueue.markDirty();
    showFloatingToast(context, '已创建');
  }

  /// 顶栏「重命名」（§8.2）：对话框返回新名称后走 [_handleRenameScriptProject]
  /// （检查器内联提交共用同一入口）。
  Future<void> _openRenameScriptProjectDialog() async {
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return;
    }
    final ScriptProjectModel project = controller.project;
    final String? name = await showRenameScriptProjectDialog(
      context,
      project: project,
      existing: _scripts,
    );
    if (name == null || !mounted) {
      return;
    }
    _handleRenameScriptProject(project, name);
  }

  /// 删除项目（§8.3）：确认后移除；选择按「保持索引位 → 越界回退末项 →
  /// 空列表回空态」调整（§8.3/§10.5）。
  Future<void> _handleDeleteScriptProject() async {
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return;
    }
    final ScriptProjectModel project = controller.project;
    final bool confirmed = await showDeleteScriptProjectDialog(
      context,
      project: project,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final int index = _indexOfScript(project);
    if (index < 0) {
      return;
    }
    await _removeScriptAt(index);
    if (!mounted) {
      return;
    }
    showFloatingToast(context, '已删除');
  }

  /// 切换项目入口（顶栏下拉 / 执行顺序行）：先 flush 视口与保存队列再加载新图。
  void _handleSelectScriptProject(ScriptProjectModel project) {
    if (identical(project, _controller?.project)) {
      return;
    }
    unawaited(_switchToScriptProject(project));
  }

  /// 切换项目（§10.5）：保存队列 flush 后加载新图（画布恢复其 viewport、
  /// 清空选中、诊断与底部面板随新图重算）；切换不写历史记录。
  Future<void> _switchToScriptProject(ScriptProjectModel next) async {
    final GraphEditorController? controller = _controller;
    if (controller == null || identical(controller.project, next)) {
      return;
    }
    await _settleFocusBeforeProjectChange();
    if (!mounted || !identical(_controller, controller)) {
      return;
    }
    _flushViewportWriteBack();
    await _saveQueue.flush();
    if (!mounted || !identical(_controller, controller)) {
      return;
    }
    _loadScriptProject(controller, next);
    setState(() {});
  }

  /// 项目切换/替换前的焦点收口：让检查器字段失焦并等焦点变更微任务落地，
  /// 未提交文本经失焦提交写回原项目（否则会残留或提交到新项目上）。
  Future<void> _settleFocusBeforeProjectChange() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await null;
  }

  /// 重命名（检查器内联与顶栏对话框共用）：写回列表、同步控制器并保存。
  void _handleRenameScriptProject(ScriptProjectModel project, String name) {
    if (_replaceScriptProject(project, name: name) == null) {
      return;
    }
    _saveQueue.markDirty();
    showFloatingToast(context, '已重命名');
  }

  void _handleTriggerChanged(
    ScriptProjectModel project,
    ScriptTrigger trigger,
  ) {
    if (_replaceScriptProject(project, trigger: trigger) == null) {
      return;
    }
    _saveQueue.markDirty();
  }

  void _handleBuildModelChanged(
    ScriptProjectModel project,
    BuildModel buildModel,
  ) {
    if (_replaceScriptProject(project, buildModel: buildModel) == null) {
      return;
    }
    _saveQueue.markDirty();
  }

  void _handleMoveScriptProjectUp(ScriptProjectModel project) {
    _moveScriptProject(project, -1);
  }

  void _handleMoveScriptProjectDown(ScriptProjectModel project) {
    _moveScriptProject(project, 1);
  }

  /// 执行顺序排序（§10.6）：列表顺序即同组执行顺序；重排保持当前选中并即时保存。
  void _moveScriptProject(ScriptProjectModel project, int delta) {
    final List<ScriptProjectModel> scripts = _scripts;
    final int index = _indexOfScript(project);
    final int target = index + delta;
    if (index < 0 || target < 0 || target >= scripts.length) {
      return;
    }
    setState(() {
      scripts.removeAt(index);
      scripts.insert(target, project);
    });
    _saveQueue.markDirty();
  }

  /// 激活项目：无控制器时创建（含可选入口节点），否则免脏加载后追加入口节点。
  ///
  /// 激活前先收口视口防抖，避免矩阵尾段变更（fling 惯性终点等）随切换丢失。
  Future<void> _activateScriptProject(
    ScriptProjectModel project, {
    bool addEntryNode = false,
  }) async {
    await _settleFocusBeforeProjectChange();
    if (!mounted) {
      return;
    }
    _flushViewportWriteBack();
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      final GraphEditorController created = GraphEditorController(project);
      created.addListener(_handleControllerChanged);
      _controller = created;
      if (addEntryNode) {
        created.addNode(entryTypeKey, const Offset(40, 60));
      }
      setState(() {});
      return;
    }
    _loadScriptProject(controller, project);
    if (addEntryNode) {
      controller.addNode(entryTypeKey, const Offset(40, 60));
    }
    setState(() {});
  }

  /// 移除列表项并调整选择：保持索引位、越界回退末项、空列表回空态。
  ///
  /// 移除前先收口视口防抖，删除/新建与切换统一收口（矩阵尾段变更不随操作丢失）。
  Future<void> _removeScriptAt(int index) async {
    await _settleFocusBeforeProjectChange();
    if (!mounted) {
      return;
    }
    _flushViewportWriteBack();
    final List<ScriptProjectModel> scripts = _scripts;
    final GraphEditorController? controller = _controller;
    scripts.removeAt(index);
    if (scripts.isEmpty || controller == null) {
      _detachController();
    } else {
      final int nextIndex = index < scripts.length ? index : scripts.length - 1;
      _loadScriptProject(controller, scripts[nextIndex]);
      setState(() {});
    }
    _saveQueue.markDirty();
  }

  /// 回到无项目空态：注销监听并释放控制器（画布/检查器/输出面板随之为 null）。
  void _detachController() {
    final GraphEditorController? controller = _controller;
    _controller = null;
    controller?.removeListener(_handleControllerChanged);
    controller?.dispose();
    setState(() {});
  }

  /// 免脏加载：`loadProject` 的选中清空/诊断重算通知不视为编辑。
  ///
  /// [preserveSelection] 为 true 时加载后恢复原选中（节点/连线仍在时）：
  /// 元数据变更（重命名/触发/构建标签）不改变图，不应打断编辑焦点。
  void _loadScriptProject(
    GraphEditorController controller,
    ScriptProjectModel project, {
    bool preserveSelection = false,
  }) {
    final String? selectedNodeId = controller.selectedNodeId;
    final ScriptEdgeModel? selectedEdge = controller.selectedEdge;
    _suppressSaveMark = true;
    try {
      controller.loadProject(project);
      if (preserveSelection) {
        if (selectedNodeId != null) {
          controller.selectNode(selectedNodeId);
        } else if (selectedEdge != null) {
          controller.selectEdge(selectedEdge);
        }
      }
    } finally {
      _suppressSaveMark = false;
    }
  }

  /// 替换列表中项目实例（名称/触发/构建配置不可变，需全字段拷贝）；
  /// 无实际变化或找不到时返回 null。当前项目同步免脏加载。
  ///
  /// 替换前先收口视口防抖（同切换路径），避免矩阵领先模型时（fling 惯性期/
  /// T9 居中防抖窗）免脏加载把矩阵重置回陈旧模型造成回跳与尾段变更丢失；
  /// 免脏加载恢复原选中，元数据变更不打断编辑焦点。
  ScriptProjectModel? _replaceScriptProject(
    ScriptProjectModel project, {
    String? name,
    ScriptTrigger? trigger,
    BuildModel? buildModel,
  }) {
    _flushViewportWriteBack();
    if ((name == null || name == project.name) &&
        (trigger == null || trigger == project.trigger) &&
        (buildModel == null || buildModel == project.buildModel)) {
      return null;
    }
    final int index = _indexOfScript(project);
    if (index < 0) {
      return null;
    }
    final ScriptProjectModel updated = _copyScriptProject(
      project,
      name: name,
      trigger: trigger,
      buildModel: buildModel,
    );
    setState(() => _scripts[index] = updated);
    final GraphEditorController? controller = _controller;
    if (controller != null && identical(controller.project, project)) {
      _loadScriptProject(controller, updated, preserveSelection: true);
    }
    return updated;
  }

  /// 全字段拷贝（节点/连线/视口保持引用与数值），仅替换可变元数据。
  ScriptProjectModel _copyScriptProject(
    ScriptProjectModel source, {
    String? name,
    ScriptTrigger? trigger,
    BuildModel? buildModel,
  }) {
    final ScriptProjectModel copy = ScriptProjectModel(
      id: source.id,
      name: name ?? source.name,
      trigger: trigger ?? source.trigger,
      buildModel: buildModel ?? source.buildModel,
    );
    copy.nodes = source.nodes;
    copy.edges = source.edges;
    copy.viewX = source.viewX;
    copy.viewY = source.viewY;
    copy.viewScale = source.viewScale;
    return copy;
  }

  int _indexOfScript(ScriptProjectModel project) {
    final List<ScriptProjectModel> scripts = _scripts;
    for (int index = 0; index < scripts.length; index++) {
      if (identical(scripts[index], project) ||
          scripts[index].id == project.id) {
        return index;
      }
    }
    return -1;
  }

  Widget _buildOutputBar() {
    return OutputPanel(
      key: _outputPanelKey,
      controller: _controller,
      pack: widget.pack,
      generator: widget.generator,
      transformationController: _transformation,
      viewportSizeProvider: () => _canvasViewportSize,
    );
  }

  /// 顶栏「生成预览」（§10.8）：交给底部面板编译并呈现。
  void _generatePreview() {
    _outputPanelKey.currentState?.generatePreview();
  }

  /// 顶栏保存状态四态（§3.3）：未保存 / 保存中 / 已保存 / 保存失败 + 重试。
  Widget _buildSaveStatus() {
    final EditorSaveQueue queue = _saveQueue;
    final TextStyle statusStyle = TextStyle(
      fontSize: 12,
      color: queue.status == EditorSaveStatus.failed
          ? UCColors.flavor.red
          : UCColors.flavor.subtext1,
    );
    return Row(
      key: const Key('saveStatus'),
      mainAxisSize: MainAxisSize.min,
      children: switch (queue.status) {
        EditorSaveStatus.unsaved => <Widget>[
          Icon(FluentIcons.save, size: 14, color: UCColors.flavor.subtext0),
          const SizedBox(width: 6),
          Text('未保存', style: statusStyle),
        ],
        EditorSaveStatus.saving => <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: ProgressRing(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text('保存中…', style: statusStyle),
        ],
        EditorSaveStatus.saved => <Widget>[
          Icon(FluentIcons.check_mark, size: 14, color: UCColors.flavor.green),
          const SizedBox(width: 6),
          Text('已保存', style: statusStyle),
        ],
        EditorSaveStatus.failed => <Widget>[
          Icon(FluentIcons.error_badge, size: 14, color: UCColors.flavor.red),
          const SizedBox(width: 6),
          Text('保存失败', style: statusStyle),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: Button(
              key: const Key('retrySaveButton'),
              onPressed: _flushSaveQueue,
              child: Text('重试', style: statusStyle),
            ),
          ),
        ],
      },
    );
  }

  void _handleSaveStatusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 控制器任意变更（参数/节点/选中/视口写回）统一进入防抖保存（§10.4）；
  /// 项目切换/重命名/元数据变更的免脏加载（见 `_suppressSaveMark`）除外。
  void _handleControllerChanged() {
    if (_suppressSaveMark) {
      return;
    }
    _saveQueue.markDirty();
  }

  /// 视口矩阵变化（平移/缩放/fling/T9 程序化居中）重置防抖计时（§10.1）。
  void _handleTransformationChanged() {
    if (_controller == null) {
      return;
    }
    _viewportDebounceTimer?.cancel();
    _viewportDebounceTimer = Timer(
      widget.debounce,
      _persistViewportFromTransformation,
    );
  }

  /// 把变换矩阵的视口写回控制器，经控制器通知进入保存队列。
  ///
  /// 与模型当前值（1e-9 容差）比较后再写：画布 `_lastSyncedViewport` 对账
  /// 会在模型被外部更新时回写同一矩阵，直接写入会自触发保存环路。
  void _persistViewportFromTransformation() {
    _viewportDebounceTimer = null;
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return;
    }
    final Matrix4 matrix = _transformation.value;
    final double x = matrix.storage[12];
    final double y = matrix.storage[13];
    final double scale = matrix.getMaxScaleOnAxis();
    final ScriptProjectModel project = controller.project;
    if (_sameViewport(x, project.viewX) &&
        _sameViewport(y, project.viewY) &&
        _sameViewport(scale, project.viewScale)) {
      return;
    }
    controller.setViewport(x: x, y: y, scale: scale);
  }

  bool _sameViewport(double left, double right) => (left - right).abs() < 1e-9;

  /// 立即收口视口：取消防抖计时并把当前矩阵写回项目（切换/返回前调用），
  /// 避免 400ms 窗口内的矩阵尾段变更（fling 惯性终点等）随操作丢失。
  void _flushViewportWriteBack() {
    _viewportDebounceTimer?.cancel();
    _persistViewportFromTransformation();
  }

  /// 保存回调（队列串行调用）：构造新包并交给 [ScriptEditorPage.onSave]。
  Future<bool> _saveProject() async {
    try {
      final bool saved = await widget.onSave(_buildUpdatedPack());
      _lastSaveError = null;
      return saved;
    } catch (error) {
      _lastSaveError = error;
      return false;
    }
  }

  /// 跳过防抖立即 flush 保存队列（画布 `Ctrl+S` 与顶栏「重试」共用）。
  void _flushSaveQueue() {
    _saveQueue.flush();
  }

  /// 返回（§8.4）：先收口视口并 flush + 等待队列清空；失败未清时弹确认对话框
  /// （重试 / 仍返回），重试成功后照常返回。
  Future<void> _handleBack() async {
    if (_backing) {
      return;
    }
    setState(() => _backing = true);
    _flushViewportWriteBack();
    await _flushAndWait();
    if (!mounted) {
      return;
    }
    setState(() => _backing = false);
    while (_saveQueue.status == EditorSaveStatus.failed) {
      final bool retry = await _showSaveFailedDialog();
      if (!mounted) {
        return;
      }
      if (!retry) {
        break;
      }
      await _flushAndWait();
      if (!mounted) {
        return;
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _flushAndWait() async {
    await _saveQueue.flush();
    await _saveQueue.waitIdle();
  }

  Future<bool> _showSaveFailedDialog() async {
    final String projectName = _controller?.project.name ?? widget.pack.name;
    final Object? error = _lastSaveError;
    final String body = error == null
        ? '脚本项目「$projectName」保存失败'
        : '脚本项目「$projectName」保存失败：${formatError(error)}';
    final bool? retry = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => ContentDialog(
        key: const Key('saveFailedDialog'),
        title: const Text('保存失败'),
        constraints: const BoxConstraints(maxWidth: 440),
        content: Text(body, style: const TextStyle(fontSize: 12)),
        actions: <Widget>[
          Button(
            key: const Key('saveFailedLeaveButton'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('仍返回'),
          ),
          FilledButton(
            key: const Key('saveFailedRetryButton'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
    return retry ?? false;
  }

  /// 全字段拷贝 + 当前控制器项目替换 `scripts` 中所属项（其余列表原样引用）。
  PackModel _buildUpdatedPack() {
    final ScriptProjectModel? current = _controller?.project;
    return PackModel(
        name: widget.pack.name,
        version: widget.pack.version,
        author: widget.pack.author,
        description: widget.pack.description,
        license: widget.pack.license,
        iconPath: widget.pack.iconPath,
        sourcePath: widget.pack.sourcePath,
      )
      ..files = widget.pack.files
      ..commands = widget.pack.commands
      ..dependencies = widget.pack.dependencies
      ..macros = widget.pack.macros
      ..libDirectories = widget.pack.libDirectories
      ..libraries = widget.pack.libraries
      ..history = widget.pack.history
      ..scripts = _scriptsWithCurrent(current);
  }

  List<ScriptProjectModel> _scriptsWithCurrent(ScriptProjectModel? current) {
    final List<ScriptProjectModel> scripts = widget.pack.scripts;
    if (current == null) {
      return scripts;
    }
    final int index = _indexOfScript(current);
    if (index < 0) {
      return <ScriptProjectModel>[...scripts, current];
    }
    final List<ScriptProjectModel> updated = List<ScriptProjectModel>.of(
      scripts,
    );
    updated[index] = current;
    return updated;
  }
}

String _scriptTriggerLabel(ScriptTrigger trigger) =>
    trigger == ScriptTrigger.pre ? '编译前' : '编译后';

/// 触发时机着色（§2.2）：编译前 sky / 编译后 lavender。
Color _scriptTriggerColor(ScriptTrigger trigger) => trigger == ScriptTrigger.pre
    ? UCColors.flavor.sky
    : UCColors.flavor.lavender;

/// 构建标签着色（§2.2）：ALL 蓝 / Release 绿 / Debug 橙。
Color _scriptBuildModelColor(BuildModel buildModel) => switch (buildModel) {
  BuildModel.all => UCColors.flavor.blue,
  BuildModel.release => UCColors.flavor.green,
  BuildModel.debug => UCColors.flavor.peach,
};
