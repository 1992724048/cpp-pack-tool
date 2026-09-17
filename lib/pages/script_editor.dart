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

  final ScriptCodeGenerator? generator;

  final List<String>? packagePaths;

  final Duration debounce;

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  GraphEditorController? _controller;
  final TransformationController _transformation = TransformationController();
  final GlobalKey<OutputPanelState> _outputPanelKey = GlobalKey<OutputPanelState>();
  Size? _canvasViewportSize;

  late final EditorSaveQueue _saveQueue;
  Timer? _viewportDebounceTimer;
  Object? _lastSaveError;
  bool _backing = false;

  bool _suppressSaveMark = false;

  bool get _hasProject => _controller != null;

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
      color: FluentTheme.of(context).menuColor,
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
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: '返回包管理',
            child: IconButton(
              icon: _backing
                  ? const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
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
                color: FluentTheme.of(context).resources.textFillColorPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: FluentTheme.of(context).resources.dividerStrokeColorDefault),
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
                style: TextStyle(fontSize: 13, color: FluentTheme.of(context).resources.textFillColorPrimary),
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
                      text: scriptTriggerLabel(project.trigger),
                      color: scriptTriggerColor(project.trigger),
                      fontSize: 10,
                    ),
                    const SizedBox(width: 4),
                    Tag(
                      text: buildModelLabel(project.buildModel),
                      color: buildModelColor(project.buildModel),
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
        child: IconButton(key: buttonKey, icon: Icon(icon, size: 16), onPressed: onPressed),
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
          border: Border(right: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
          child: NodeLibraryPanel(onAddNode: _hasProject ? _addNodeFromLibrary : null),
        ),
        Expanded(child: _buildCanvasArea()),
        _buildSidePanel(
          panelKey: const Key('inspectorPanel'),
          width: _inspectorWidth,
          border: Border(left: BorderSide(color: FluentTheme.of(context).resources.dividerStrokeColorDefault)),
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
            decoration: BoxDecoration(color: FluentTheme.of(context).scaffoldBackgroundColor, border: border),
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
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(FluentIcons.power_shell, size: 40, color: FluentTheme.of(context).resources.textFillColorSecondary),
              const SizedBox(height: 16),
              Text(
                '尚未创建脚本项目',
                style: TextStyle(fontSize: 14, color: FluentTheme.of(context).resources.textFillColorPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '节点图将编译为编译前/后 PowerShell 脚本',
                style: TextStyle(fontSize: 12, color: FluentTheme.of(context).resources.textFillColorSecondary),
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

  Offset _viewportCenterScene() {
    final Size? viewport = _canvasViewportSize;
    if (viewport == null) {
      return Offset.zero;
    }
    return _transformation.toScene(viewport.center(Offset.zero));
  }

  Future<void> _handleCreateScriptProject() async {
    final NewScriptProjectRequest? request = await showCreateScriptProjectDialog(context, existing: _scripts);
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

  Future<void> _openRenameScriptProjectDialog() async {
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return;
    }
    final ScriptProjectModel project = controller.project;
    final String? name = await showRenameScriptProjectDialog(context, project: project, existing: _scripts);
    if (name == null || !mounted) {
      return;
    }
    _handleRenameScriptProject(project, name);
  }

  Future<void> _handleDeleteScriptProject() async {
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return;
    }
    final ScriptProjectModel project = controller.project;
    final bool confirmed = await showDeleteScriptProjectDialog(context, project: project);
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

  void _handleSelectScriptProject(ScriptProjectModel project) {
    if (identical(project, _controller?.project)) {
      return;
    }
    unawaited(_switchToScriptProject(project));
  }

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

  Future<void> _settleFocusBeforeProjectChange() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await null;
  }

  void _handleRenameScriptProject(ScriptProjectModel project, String name) {
    if (_replaceScriptProject(project, name: name) == null) {
      return;
    }
    _saveQueue.markDirty();
    showFloatingToast(context, '已重命名');
  }

  void _handleTriggerChanged(ScriptProjectModel project, ScriptTrigger trigger) {
    if (_replaceScriptProject(project, trigger: trigger) == null) {
      return;
    }
    _saveQueue.markDirty();
  }

  void _handleBuildModelChanged(ScriptProjectModel project, BuildModel buildModel) {
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

  Future<void> _activateScriptProject(ScriptProjectModel project, {bool addEntryNode = false}) async {
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

  void _detachController() {
    final GraphEditorController? controller = _controller;
    _controller = null;
    controller?.removeListener(_handleControllerChanged);
    controller?.dispose();
    setState(() {});
  }

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
      if (identical(scripts[index], project) || scripts[index].id == project.id) {
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

  void _generatePreview() {
    _outputPanelKey.currentState?.generatePreview();
  }

  Widget _buildSaveStatus() {
    final EditorSaveQueue queue = _saveQueue;
    final FluentThemeData theme = FluentTheme.of(context);
    final TextStyle statusStyle = TextStyle(
      fontSize: 12,
      color: queue.status == EditorSaveStatus.failed
          ? AppColors.critical(theme.brightness)
          : theme.resources.textFillColorSecondary,
    );
    return Row(
      key: const Key('saveStatus'),
      mainAxisSize: MainAxisSize.min,
      children: switch (queue.status) {
        EditorSaveStatus.unsaved => <Widget>[
          Icon(FluentIcons.save, size: 14, color: theme.resources.textFillColorTertiary),
          const SizedBox(width: 6),
          Text('未保存', style: statusStyle),
        ],
        EditorSaveStatus.saving => <Widget>[
          const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
          const SizedBox(width: 6),
          Text('保存中…', style: statusStyle),
        ],
        EditorSaveStatus.saved => <Widget>[
          Icon(FluentIcons.check_mark, size: 14, color: AppColors.success(theme.brightness)),
          const SizedBox(width: 6),
          Text('已保存', style: statusStyle),
        ],
        EditorSaveStatus.failed => <Widget>[
          Icon(FluentIcons.error_badge, size: 14, color: AppColors.critical(theme.brightness)),
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

  void _handleControllerChanged() {
    if (_suppressSaveMark) {
      return;
    }
    _saveQueue.markDirty();
  }

  void _handleTransformationChanged() {
    if (_controller == null) {
      return;
    }
    _viewportDebounceTimer?.cancel();
    _viewportDebounceTimer = Timer(widget.debounce, _persistViewportFromTransformation);
  }

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
    if (_sameViewport(x, project.viewX) && _sameViewport(y, project.viewY) && _sameViewport(scale, project.viewScale)) {
      return;
    }
    controller.setViewport(x: x, y: y, scale: scale);
  }

  bool _sameViewport(double left, double right) => (left - right).abs() < 1e-9;

  void _flushViewportWriteBack() {
    _viewportDebounceTimer?.cancel();
    _persistViewportFromTransformation();
  }

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

  void _flushSaveQueue() {
    _saveQueue.flush();
  }

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
    final String body = error == null ? '脚本项目「$projectName」保存失败' : '脚本项目「$projectName」保存失败：${formatError(error)}';
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
        sourceVersion: widget.pack.sourceVersion,
      )
      ..files = widget.pack.files
      ..commands = widget.pack.commands
      ..dependencies = widget.pack.dependencies
      ..macros = widget.pack.macros
      ..libDirectories = widget.pack.libDirectories
      ..libraries = widget.pack.libraries
      ..history = widget.pack.history
      ..scripts = _scriptsWithCurrent(current)
      ..buildOptions = widget.pack.buildOptions
      ..enabledFormats = widget.pack.enabledFormats;
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
    final List<ScriptProjectModel> updated = List<ScriptProjectModel>.of(scripts);
    updated[index] = current;
    return updated;
  }
}
