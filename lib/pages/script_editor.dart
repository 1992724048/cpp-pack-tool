import 'dart:async';

import 'package:cpp_nuget_pack/controls/script_editor/editor_canvas.dart';
import 'package:cpp_nuget_pack/controls/script_editor/node_inspector.dart';
import 'package:cpp_nuget_pack/controls/script_editor/node_library_panel.dart';
import 'package:cpp_nuget_pack/controls/script_editor/output_panel.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/editor_save_queue.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _topBarHeight = 48;
const double _nodeLibraryWidth = 232;
const double _inspectorWidth = 280;
const double _titleMaxWidth = 240;

/// 节点编辑器全屏页（T4 外壳，各面板经后续任务装配）。
///
/// 布局数值与分隔线取自视觉规范 §1/§3（顶栏 48、左 232、右 280、底部收起 34、
/// 1px `surface2` 分隔）；[pack] 无脚本项目时页面为空态（中区占位文案、两侧面板禁用）。
/// 控制器变更与视口变化经 400ms 防抖保存队列写回（§10.1/§10.4），
/// 返回按钮在队列清空后 pop，保存失败时弹确认对话框（§8.4）。
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

  bool get _hasProject => _controller != null;

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
          child: Text(
            '暂无脚本项目',
            style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
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
              onPressed: _retrySave,
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

  /// 控制器任意变更（参数/节点/选中/视口写回）统一进入防抖保存（§10.4）。
  void _handleControllerChanged() {
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

  void _retrySave() {
    _saveQueue.flush();
  }

  /// 返回（§8.4）：先 flush + 等待队列清空；失败未清时弹确认对话框
  /// （重试 / 仍返回），重试成功后照常返回。
  Future<void> _handleBack() async {
    if (_backing) {
      return;
    }
    setState(() => _backing = true);
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
    for (int index = 0; index < scripts.length; index++) {
      if (identical(scripts[index], current) ||
          scripts[index].id == current.id) {
        final List<ScriptProjectModel> updated = List<ScriptProjectModel>.of(
          scripts,
        );
        updated[index] = current;
        return updated;
      }
    }
    return <ScriptProjectModel>[...scripts, current];
  }
}
