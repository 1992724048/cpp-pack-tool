import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:cpp_nuget_pack/controls/script_editor/edge_painter.dart';
import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerExitEvent, PointerHoverEvent;

const double _minSceneWidth = 1600;
const double _minSceneHeight = 1200;
const double _scenePadding = 600;
const double _minScale = 0.5;
const double _maxScale = 2.0;
const double _pinLabelMinScale = 0.75;
const double _dragClickThreshold = 3;
const double _connectDragThreshold = 3;
const int _rejectFlashDurationMs = 300;
const double _pinHitRadiusMin = 8;
const double _pinHitRadiusMax = 22;

/// 编辑器画布：网格背景、节点卡渲染与平移/缩放/拖动视口
/// （视觉规范 §5.1/§5.2/§5.7/§10.1/§10.2）。
///
/// [controller] 是图状态的唯一来源；[transformationController] 与 [focusNode]
/// 可注入（T9 视口定位 / T12 键盘复用），为 null 时由本组件创建并负责释放。
/// 拖动期间的位移只做视图层跟随，释放时才写回 `moveNode`。
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    super.key,
    required this.controller,
    this.transformationController,
    this.focusNode,
  });

  final GraphEditorController controller;
  final TransformationController? transformationController;
  final FocusNode? focusNode;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  late final TransformationController _transformation =
      widget.transformationController ?? TransformationController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  final GlobalKey _viewerKey = GlobalKey();

  ScriptProjectModel? _projectRef;
  bool _showPinLabels = true;

  /// 最近一次与变换矩阵对齐的模型视口；模型值与其不同时才视为外部改写。
  late ({double x, double y, double scale}) _lastSyncedViewport;

  String? _dragNodeId;
  Offset _dragNodeStart = Offset.zero;
  Offset _dragStartScene = Offset.zero;
  Offset _dragSceneDelta = Offset.zero;
  Offset _dragDownGlobal = Offset.zero;
  double _dragMaxScreenDistance = 0;

  _PinRef? _connectSource;
  Offset _connectDownGlobal = Offset.zero;
  double _connectScreenDistance = 0;
  bool _connectActive = false;
  Offset? _connectPointerScene;
  _PinRef? _connectHover;
  ({String nodeId, String pinId})? _rejectFlash;
  Timer? _rejectFlashTimer;
  ScriptEdgeModel? _hoveredEdge;

  @override
  void initState() {
    super.initState();
    _projectRef = widget.controller.project;
    _applyProjectViewport();
    _showPinLabels = _labelsVisible(_transformation.value.getMaxScaleOnAxis());
    _transformation.addListener(_onTransformChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(EditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _projectRef = widget.controller.project;
      _dragNodeId = null;
      _resetConnectState();
      _hoveredEdge = null;
      _transformation.removeListener(_onTransformChanged);
      _applyProjectViewport();
      _showPinLabels = _labelsVisible(
        _transformation.value.getMaxScaleOnAxis(),
      );
      _transformation.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    _rejectFlashTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _transformation.removeListener(_onTransformChanged);
    if (widget.transformationController == null) {
      _transformation.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ScriptProjectModel project = widget.controller.project;
    final String? selectedNodeId = widget.controller.selectedNodeId;
    final Map<String, Set<String>> connectedPins = _connectedPins(project);
    final Map<String, Set<String>> errorPins = errorPinsByNode(
      project.nodes,
      widget.controller.diagnostics,
    );
    final _ConnectHighlights highlights = _connectHighlights(project);
    final List<ScriptNodeModel> orderedNodes = _orderedNodes(
      project.nodes,
      selectedNodeId,
    );
    final Size sceneSize = _sceneSize(project.nodes);
    final ScriptEdgeModel? hoveredEdge = _validHoveredEdge(project);

    return Container(
      color: UCColors.flavor.mantle,
      child: Focus(
        focusNode: _focusNode,
        child: Listener(
          onPointerDown: (PointerDownEvent event) => _focusNode.requestFocus(),
          child: InteractiveViewer(
            key: _viewerKey,
            transformationController: _transformation,
            constrained: false,
            minScale: _minScale,
            maxScale: _maxScale,
            boundaryMargin: const EdgeInsets.all(80),
            onInteractionEnd: (ScaleEndDetails details) => _persistViewport(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleSceneTap,
              child: MouseRegion(
                opaque: true,
                cursor: hoveredEdge == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                onHover: _handleSceneHover,
                onExit: (PointerExitEvent event) => _setHoveredEdge(null),
                child: SizedBox(
                  key: const Key('editorScene'),
                  width: sceneSize.width,
                  height: sceneSize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          key: const Key('editorGrid'),
                          painter: EditorGridPainter(
                            color: UCColors.flavor.overlay0,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          key: const Key('editorEdges'),
                          painter: EdgePainter(
                            edges: _edgeVisuals(project, hoveredEdge),
                            preview: _previewVisual(),
                          ),
                        ),
                      ),
                      for (final ScriptNodeModel node in orderedNodes)
                        Positioned(
                          left: _nodePosition(node).dx - nodeCardOverflow,
                          top: _nodePosition(node).dy - nodeCardOverflow,
                          child: NodeCard(
                            nodeId: node.id,
                            typeKey: node.type,
                            descriptor: NodeRegistry.byType(node.type),
                            selected: node.id == selectedNodeId,
                            dragging: node.id == _dragNodeId,
                            // 节点错误红点接线由 T9 完成；引脚错误红环在本任务接入。
                            hasError: false,
                            connectedPins:
                                connectedPins[node.id] ?? const <String>{},
                            errorPins: errorPins[node.id] ?? const <String>{},
                            candidatePins:
                                highlights.candidate[node.id] ??
                                const <String>{},
                            rejectedPins:
                                highlights.rejected[node.id] ??
                                const <String>{},
                            dimmedPins:
                                highlights.dimmed[node.id] ?? const <String>{},
                            showPinLabels: _showPinLabels,
                            onTap: () => widget.controller.selectNode(node.id),
                            onDragStart: (DragStartDetails details) =>
                                _beginNodeDrag(node.id, details),
                            onDragUpdate: (DragUpdateDetails details) =>
                                _updateNodeDrag(node.id, details),
                            onDragEnd: (DragEndDetails details) =>
                                _endNodeDrag(node.id, details),
                            onDragCancel: () => _cancelNodeDrag(node.id),
                            onPinDragStart: (
                              String pinId,
                              DragStartDetails details,
                            ) => _beginPinDrag(node.id, pinId, details),
                            onPinDragUpdate: (
                              String pinId,
                              DragUpdateDetails details,
                            ) => _updatePinDrag(node.id, pinId, details),
                            onPinDragEnd: (
                              String pinId,
                              DragEndDetails details,
                            ) => _endPinDrag(node.id, pinId, details),
                            onPinDragCancel: (String pinId) =>
                                _cancelPinDrag(node.id, pinId),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onControllerChanged() {
    final ScriptProjectModel project = widget.controller.project;
    if (!identical(project, _projectRef)) {
      _projectRef = project;
      _dragNodeId = null;
      _applyProjectViewport();
    } else {
      _syncViewportFromProject(project);
    }
    setState(() {});
  }

  void _onTransformChanged() {
    final bool show = _labelsVisible(_transformation.value.getMaxScaleOnAxis());
    if (show == _showPinLabels) {
      return;
    }
    setState(() => _showPinLabels = show);
  }

  bool _labelsVisible(double scale) => scale >= _pinLabelMinScale;

  void _applyProjectViewport() {
    final ScriptProjectModel project = widget.controller.project;
    final double scale = project.viewScale
        .clamp(_minScale, _maxScale)
        .toDouble();
    _lastSyncedViewport = (
      x: project.viewX,
      y: project.viewY,
      scale: project.viewScale,
    );
    _transformation.value = Matrix4.identity()
      ..translateByDouble(project.viewX, project.viewY, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// 模型视口被外部直接写入时（T9 诊断居中 / T11 恢复），同步到变换矩阵。
  ///
  /// 以「模型值 vs 上次同步缓存」判断，而非与当前矩阵比较：fling 的
  /// `onInteractionEnd` 在惯性动画开始前触发，惯性会令矩阵领先于模型，
  /// 与矩阵比较会把惯性终点误判为外部改写并把视口回跳。
  void _syncViewportFromProject(ScriptProjectModel project) {
    final ({double x, double y, double scale}) synced = _lastSyncedViewport;
    if (project.viewX == synced.x &&
        project.viewY == synced.y &&
        project.viewScale == synced.scale) {
      return;
    }
    _applyProjectViewport();
  }

  void _persistViewport() {
    final Matrix4 matrix = _transformation.value;
    final double x = matrix.storage[12];
    final double y = matrix.storage[13];
    final double scale = matrix.getMaxScaleOnAxis();
    _lastSyncedViewport = (x: x, y: y, scale: scale);
    widget.controller.setViewport(x: x, y: y, scale: scale);
  }

  Offset? _toScene(Offset globalPosition) {
    final RenderObject? renderObject = _viewerKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }
    return _transformation.toScene(renderObject.globalToLocal(globalPosition));
  }

  void _beginNodeDrag(String nodeId, DragStartDetails details) {
    final ScriptNodeModel? node = _findNode(nodeId);
    final Offset? scenePoint = _toScene(details.globalPosition);
    if (node == null || scenePoint == null) {
      return;
    }
    widget.controller.selectNode(nodeId);
    setState(() {
      _dragNodeId = nodeId;
      _dragNodeStart = Offset(node.x, node.y);
      _dragStartScene = scenePoint;
      _dragSceneDelta = Offset.zero;
      _dragDownGlobal = details.globalPosition;
      _dragMaxScreenDistance = 0;
    });
  }

  void _updateNodeDrag(String nodeId, DragUpdateDetails details) {
    if (_dragNodeId != nodeId) {
      return;
    }
    final Offset? scenePoint = _toScene(details.globalPosition);
    if (scenePoint == null) {
      return;
    }
    final double distance = (details.globalPosition - _dragDownGlobal).distance;
    setState(() {
      _dragSceneDelta = scenePoint - _dragStartScene;
      if (distance > _dragMaxScreenDistance) {
        _dragMaxScreenDistance = distance;
      }
    });
  }

  void _endNodeDrag(String nodeId, DragEndDetails details) {
    if (_dragNodeId != nodeId) {
      return;
    }
    final bool moved = _dragMaxScreenDistance >= _dragClickThreshold;
    final Offset target = _dragNodeStart + _dragSceneDelta;
    setState(() => _dragNodeId = null);
    if (moved) {
      widget.controller.moveNode(nodeId, target);
    }
  }

  void _cancelNodeDrag(String nodeId) {
    if (_dragNodeId != nodeId) {
      return;
    }
    setState(() => _dragNodeId = null);
  }

  void _beginPinDrag(String nodeId, String pinId, DragStartDetails details) {
    final ScriptNodeModel? node = _findNode(nodeId);
    final ScriptPinDescriptor? pin = node == null ? null : _pinOf(node, pinId);
    if (pin == null || pin.isInput) {
      return; // v1 仅支持从输出引脚拖出
    }
    setState(() {
      _connectSource = (nodeId: nodeId, pinId: pinId, pin: pin);
      _connectDownGlobal = details.globalPosition;
      _connectScreenDistance = 0;
      _connectActive = false;
      _connectPointerScene = null;
      _connectHover = null;
    });
  }

  void _updatePinDrag(String nodeId, String pinId, DragUpdateDetails details) {
    final _PinRef? source = _connectSource;
    if (source == null || source.nodeId != nodeId || source.pinId != pinId) {
      return;
    }
    final double distance =
        (details.globalPosition - _connectDownGlobal).distance;
    final Offset? scenePoint = _toScene(details.globalPosition);
    final double scale = _transformation.value.getMaxScaleOnAxis();
    setState(() {
      if (distance > _connectScreenDistance) {
        _connectScreenDistance = distance;
      }
      if (!_connectActive && _connectScreenDistance >= _connectDragThreshold) {
        _connectActive = true;
      }
      _connectPointerScene = scenePoint;
      if (_connectActive && scenePoint != null) {
        _connectHover = _pinTargetAt(scenePoint, scale, inputsOnly: true);
      }
    });
  }

  void _endPinDrag(String nodeId, String pinId, DragEndDetails details) {
    final _PinRef? source = _connectSource;
    if (source == null || source.nodeId != nodeId || source.pinId != pinId) {
      return;
    }
    final bool active = _connectActive;
    final Offset? scenePoint = active ? _toScene(details.globalPosition) : null;
    final _PinRef? target = scenePoint == null
        ? null
        : _pinTargetAt(scenePoint, _transformation.value.getMaxScaleOnAxis());
    setState(_resetConnectState);
    if (!active || target == null) {
      return; // 空白/节点处释放：静默取消
    }
    final String? reason = widget.controller.connect(
      from: ScriptEdgeEndpoint(node: source.nodeId, pin: source.pinId),
      to: ScriptEdgeEndpoint(node: target.nodeId, pin: target.pinId),
    );
    if (reason == null) {
      return; // 成功（含静默替换）
    }
    _flashRejectedPin(target);
    showFloatingToast(context, reason, type: FloatingToastType.error);
  }

  void _cancelPinDrag(String nodeId, String pinId) {
    final _PinRef? source = _connectSource;
    if (source == null || source.nodeId != nodeId || source.pinId != pinId) {
      return;
    }
    setState(_resetConnectState);
  }

  /// 清空进行中的连线拖拽状态（落点红闪由 [_rejectFlash] 独立管理）。
  void _resetConnectState() {
    _connectSource = null;
    _connectDownGlobal = Offset.zero;
    _connectScreenDistance = 0;
    _connectActive = false;
    _connectPointerScene = null;
    _connectHover = null;
  }

  void _flashRejectedPin(_PinRef target) {
    _rejectFlashTimer?.cancel();
    setState(() => _rejectFlash = (nodeId: target.nodeId, pinId: target.pinId));
    _rejectFlashTimer = Timer(
      const Duration(milliseconds: _rejectFlashDurationMs),
      () {
        if (!mounted) {
          return;
        }
        setState(() => _rejectFlash = null);
      },
    );
  }

  void _handleSceneTap(TapUpDetails details) {
    final Offset? scenePoint = _toScene(details.globalPosition);
    if (scenePoint == null) {
      return;
    }
    final double scale = _transformation.value.getMaxScaleOnAxis();
    if (_pinTargetAt(scenePoint, scale) != null ||
        _nodeAt(scenePoint) != null) {
      return; // 命中优先级：引脚 > 节点 > 连线（§5.4）
    }
    final ScriptEdgeModel? edge = _edgeAt(scenePoint, scale);
    if (edge != null) {
      widget.controller.selectEdge(edge);
      return;
    }
    widget.controller.clearSelection();
  }

  void _handleSceneHover(PointerHoverEvent event) {
    if (_connectActive || _dragNodeId != null) {
      return;
    }
    final Offset? scenePoint = _toScene(event.position);
    if (scenePoint == null) {
      return;
    }
    final double scale = _transformation.value.getMaxScaleOnAxis();
    ScriptEdgeModel? next;
    if (_pinTargetAt(scenePoint, scale) == null &&
        _nodeAt(scenePoint) == null) {
      next = _edgeAt(scenePoint, scale);
    }
    _setHoveredEdge(next);
  }

  void _setHoveredEdge(ScriptEdgeModel? edge) {
    if (identical(edge, _hoveredEdge)) {
      return;
    }
    setState(() => _hoveredEdge = edge);
  }

  ScriptEdgeModel? _validHoveredEdge(ScriptProjectModel project) {
    final ScriptEdgeModel? hovered = _hoveredEdge;
    if (hovered == null) {
      return null;
    }
    for (final ScriptEdgeModel edge in project.edges) {
      if (identical(edge, hovered)) {
        return hovered;
      }
    }
    return null;
  }

  /// 拖拽建连时的引脚高亮：兼容 → 候选环；悬停不兼容 → 红环；其余输入 → 弱化。
  _ConnectHighlights _connectHighlights(ScriptProjectModel project) {
    final Map<String, Set<String>> candidate = <String, Set<String>>{};
    final Map<String, Set<String>> rejected = <String, Set<String>>{};
    final Map<String, Set<String>> dimmed = <String, Set<String>>{};
    final _PinRef? source = _connectSource;
    if (_connectActive && source != null) {
      for (final ScriptNodeModel node in project.nodes) {
        final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(
          node.type,
        );
        if (descriptor == null) {
          continue;
        }
        for (final ScriptPinDescriptor pin in descriptor.pins) {
          if (!pin.isInput) {
            continue;
          }
          final bool compatible = canConnectPins(
            fromNodeId: source.nodeId,
            fromPin: source.pin,
            toNodeId: node.id,
            toPin: pin,
          );
          if (compatible) {
            (candidate[node.id] ??= <String>{}).add(pin.id);
          } else if (_connectHover?.nodeId == node.id &&
              _connectHover?.pinId == pin.id) {
            (rejected[node.id] ??= <String>{}).add(pin.id);
          } else {
            (dimmed[node.id] ??= <String>{}).add(pin.id);
          }
        }
      }
    }
    final ({String nodeId, String pinId})? flash = _rejectFlash;
    if (flash != null) {
      (rejected[flash.nodeId] ??= <String>{}).add(flash.pinId);
    }
    return _ConnectHighlights(
      candidate: candidate,
      rejected: rejected,
      dimmed: dimmed,
    );
  }

  List<EdgeVisual> _edgeVisuals(
    ScriptProjectModel project,
    ScriptEdgeModel? hoveredEdge,
  ) {
    final ScriptEdgeModel? selectedEdge = widget.controller.selectedEdge;
    final List<EdgeVisual> visuals = <EdgeVisual>[];
    for (final ScriptEdgeModel edge in project.edges) {
      final EdgeVisual? visual = _edgeVisualOf(edge);
      if (visual == null) {
        continue;
      }
      visuals.add((
        from: visual.from,
        to: visual.to,
        kind: visual.kind,
        dataType: visual.dataType,
        selected: identical(edge, selectedEdge),
        hovered: identical(edge, hoveredEdge),
      ));
    }
    return visuals;
  }

  EdgeVisual? _edgeVisualOf(ScriptEdgeModel edge) {
    final ScriptNodeModel? fromNode = _findNode(edge.from.node);
    final ScriptNodeModel? toNode = _findNode(edge.to.node);
    if (fromNode == null || toNode == null) {
      return null;
    }
    final ScriptPinDescriptor? fromPin = _pinOf(fromNode, edge.from.pin);
    final ScriptPinDescriptor? toPin = _pinOf(toNode, edge.to.pin);
    if (fromPin == null || toPin == null) {
      return null;
    }
    return (
      from: _pinAnchor(fromNode, fromPin),
      to: _pinAnchor(toNode, toPin),
      kind: fromPin.kind,
      dataType: fromPin.dataType,
      selected: false,
      hovered: false,
    );
  }

  EdgePreviewVisual? _previewVisual() {
    final _PinRef? source = _connectSource;
    if (!_connectActive || source == null) {
      return null;
    }
    final ScriptNodeModel? node = _findNode(source.nodeId);
    if (node == null) {
      return null;
    }
    final Offset from = _pinAnchor(node, source.pin);
    final EdgePreviewState state;
    final _PinRef? hover = _connectHover;
    if (hover == null) {
      state = EdgePreviewState.normal;
    } else {
      final bool compatible = canConnectPins(
        fromNodeId: source.nodeId,
        fromPin: source.pin,
        toNodeId: hover.nodeId,
        toPin: hover.pin,
      );
      state = compatible
          ? EdgePreviewState.compatible
          : EdgePreviewState.incompatible;
    }
    return (
      from: from,
      to: _connectPointerScene ?? from,
      color: pinStrokeColor(source.pin.kind, source.pin.dataType),
      state: state,
    );
  }

  /// 命中半径内的最近引脚（场景 px）：半径 `clamp(16 / scale, 8, 22)`（§5.7）。
  _PinRef? _pinTargetAt(
    Offset scenePoint,
    double scale, {
    bool inputsOnly = false,
  }) {
    final double radius = (16 / scale).clamp(
      _pinHitRadiusMin,
      _pinHitRadiusMax,
    );
    _PinRef? best;
    double bestDistance = double.infinity;
    for (final ScriptNodeModel node in widget.controller.project.nodes) {
      final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(
        node.type,
      );
      if (descriptor == null) {
        continue;
      }
      for (final ScriptPinDescriptor pin in descriptor.pins) {
        if (inputsOnly && !pin.isInput) {
          continue;
        }
        final double distance = (_pinAnchor(node, pin) - scenePoint).distance;
        if (distance <= radius && distance < bestDistance) {
          best = (nodeId: node.id, pinId: pin.id, pin: pin);
          bestDistance = distance;
        }
      }
    }
    return best;
  }

  ScriptNodeModel? _nodeAt(Offset scenePoint) {
    final List<ScriptNodeModel> nodes = widget.controller.project.nodes;
    for (int index = nodes.length - 1; index >= 0; index--) {
      final ScriptNodeModel node = nodes[index];
      final Offset position = _nodePosition(node);
      final double height = nodeCardHeight(NodeRegistry.byType(node.type));
      if (scenePoint.dx >= position.dx &&
          scenePoint.dx <= position.dx + nodeCardWidth &&
          scenePoint.dy >= position.dy &&
          scenePoint.dy <= position.dy + height) {
        return node;
      }
    }
    return null;
  }

  ScriptEdgeModel? _edgeAt(Offset scenePoint, double scale) {
    final double tolerance = edgeHitTolerance(scale);
    ScriptEdgeModel? best;
    double bestDistance = double.infinity;
    for (final ScriptEdgeModel edge in widget.controller.project.edges) {
      final EdgeVisual? visual = _edgeVisualOf(edge);
      if (visual == null) {
        continue;
      }
      final double distance = distanceToPolyline(
        sampleEdgePolyline(visual.from, visual.to),
        scenePoint,
      );
      if (distance < tolerance && distance < bestDistance) {
        best = edge;
        bestDistance = distance;
      }
    }
    return best;
  }

  ScriptPinDescriptor? _pinOf(ScriptNodeModel node, String pinId) {
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    if (descriptor == null) {
      return null;
    }
    for (final ScriptPinDescriptor pin in descriptor.pins) {
      if (pin.id == pinId) {
        return pin;
      }
    }
    return null;
  }

  /// 引脚锚点（场景坐标）：输入在卡片左缘、输出在右缘，纵向取行中心（§5.3）。
  Offset _pinAnchor(ScriptNodeModel node, ScriptPinDescriptor pin) {
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    int rowIndex = 0;
    if (descriptor != null) {
      for (final ScriptPinDescriptor candidate in descriptor.pins) {
        if (candidate.isInput != pin.isInput) {
          continue;
        }
        if (candidate.id == pin.id) {
          break;
        }
        rowIndex++;
      }
    }
    final Offset position = _nodePosition(node);
    final double anchorX = pin.isInput
        ? position.dx
        : position.dx + nodeCardWidth;
    return Offset(anchorX, position.dy + nodePinRowCenterY(rowIndex));
  }

  ScriptNodeModel? _findNode(String nodeId) {
    for (final ScriptNodeModel node in widget.controller.project.nodes) {
      if (node.id == nodeId) {
        return node;
      }
    }
    return null;
  }

  /// 拖动中的节点渲染在拖动起点 + 场景位移处；其余用模型坐标。
  Offset _nodePosition(ScriptNodeModel node) {
    if (node.id == _dragNodeId) {
      return _dragNodeStart + _dragSceneDelta;
    }
    return Offset(node.x, node.y);
  }

  /// 选中/拖动中的节点最后绘制（置顶，§5.2）。
  List<ScriptNodeModel> _orderedNodes(
    List<ScriptNodeModel> nodes,
    String? selectedNodeId,
  ) {
    if (selectedNodeId == null && _dragNodeId == null) {
      return nodes;
    }
    final List<ScriptNodeModel> others = <ScriptNodeModel>[];
    final List<ScriptNodeModel> top = <ScriptNodeModel>[];
    for (final ScriptNodeModel node in nodes) {
      if (node.id == selectedNodeId || node.id == _dragNodeId) {
        top.add(node);
      } else {
        others.add(node);
      }
    }
    return <ScriptNodeModel>[...others, ...top];
  }

  Map<String, Set<String>> _connectedPins(ScriptProjectModel project) {
    final Map<String, Set<String>> connected = <String, Set<String>>{};
    for (final ScriptEdgeModel edge in project.edges) {
      (connected[edge.from.node] ??= <String>{}).add(edge.from.pin);
      (connected[edge.to.node] ??= <String>{}).add(edge.to.pin);
    }
    return connected;
  }

  /// 场景尺寸 = 节点包围盒四周各加 600，最小 1600×1200（§10.1）。
  Size _sceneSize(List<ScriptNodeModel> nodes) {
    if (nodes.isEmpty) {
      return const Size(_minSceneWidth, _minSceneHeight);
    }
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final ScriptNodeModel node in nodes) {
      final double height = nodeCardHeight(NodeRegistry.byType(node.type));
      minX = math.min(minX, node.x);
      minY = math.min(minY, node.y);
      maxX = math.max(maxX, node.x + nodeCardWidth);
      maxY = math.max(maxY, node.y + height);
    }
    return Size(
      math.max(_minSceneWidth, maxX - minX + _scenePadding * 2),
      math.max(_minSceneHeight, maxY - minY + _scenePadding * 2),
    );
  }
}

/// 画布侧连接兼容判定，与 [GraphEditorController.connect] 判定完全一致：
/// 仅接受 output → input、排除自连、kind 相同、data 需 dataType 相同；
/// 引脚是否已被占用不影响兼容（占用由 connect 静默替换）。
bool canConnectPins({
  required String fromNodeId,
  required ScriptPinDescriptor fromPin,
  required String toNodeId,
  required ScriptPinDescriptor toPin,
}) {
  if (fromPin.isInput || !toPin.isInput) {
    return false;
  }
  if (fromNodeId == toNodeId) {
    return false;
  }
  if (fromPin.kind != toPin.kind) {
    return false;
  }
  if (fromPin.kind == ScriptPinKind.data &&
      fromPin.dataType != toPin.dataType) {
    return false;
  }
  return true;
}

/// 从诊断中提取每个节点的错误引脚（§10.7）。
///
/// 诊断模型不含引脚字段，按消息形态定位：「<节点>.<引脚>」端点引用、
/// 「不存在引脚「<引脚>」」以及必填输入的「「<标签>」未连接」。
Map<String, Set<String>> errorPinsByNode(
  List<ScriptNodeModel> nodes,
  List<ScriptDiagnostic> diagnostics,
) {
  final Map<String, Set<String>> result = <String, Set<String>>{};
  for (final ScriptDiagnostic diagnostic in diagnostics) {
    if (!diagnostic.isError) {
      continue;
    }
    final String? nodeId = diagnostic.nodeId;
    if (nodeId == null) {
      continue;
    }
    final ScriptNodeModel? node = _findNodeById(nodes, nodeId);
    if (node == null) {
      continue;
    }
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    if (descriptor == null) {
      continue;
    }
    for (final ScriptPinDescriptor pin in descriptor.pins) {
      if (_diagnosticTargetsPin(diagnostic, node.id, pin)) {
        (result[node.id] ??= <String>{}).add(pin.id);
      }
    }
  }
  return result;
}

ScriptNodeModel? _findNodeById(List<ScriptNodeModel> nodes, String nodeId) {
  for (final ScriptNodeModel node in nodes) {
    if (node.id == nodeId) {
      return node;
    }
  }
  return null;
}

bool _diagnosticTargetsPin(
  ScriptDiagnostic diagnostic,
  String nodeId,
  ScriptPinDescriptor pin,
) {
  final String message = diagnostic.message;
  if (message.contains('「$nodeId.${pin.id}」')) {
    return true;
  }
  if (message.contains('不存在引脚「${pin.id}」')) {
    return true;
  }
  return pin.isInput && message.contains('必填输入「${pin.label}」未连接');
}

typedef _PinRef = ({String nodeId, String pinId, ScriptPinDescriptor pin});

class _ConnectHighlights {
  const _ConnectHighlights({
    required this.candidate,
    required this.rejected,
    required this.dimmed,
  });

  final Map<String, Set<String>> candidate;
  final Map<String, Set<String>> rejected;
  final Map<String, Set<String>> dimmed;
}

/// 画布网格点背景（§5.1）：小格 24（r=1.2，α0.35）、每 5 格一个大点（r=1.8，α0.50）。
class EditorGridPainter extends CustomPainter {
  const EditorGridPainter({required this.color});

  final Color color;

  static const double smallSpacing = 24;
  static const double largeSpacing = 120;
  static const double smallRadius = 1.2;
  static const double largeRadius = 1.8;
  static const double smallAlpha = 0.35;
  static const double largeAlpha = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint smallPaint = Paint()
      ..color = color.withValues(alpha: smallAlpha)
      ..strokeWidth = smallRadius * 2
      ..strokeCap = StrokeCap.round;
    final Paint largePaint = Paint()
      ..color = color.withValues(alpha: largeAlpha);
    final List<Offset> smallPoints = <Offset>[];
    for (double x = 0; x <= size.width; x += smallSpacing) {
      for (double y = 0; y <= size.height; y += smallSpacing) {
        if (x % largeSpacing == 0 && y % largeSpacing == 0) {
          canvas.drawCircle(Offset(x, y), largeRadius, largePaint);
        } else {
          smallPoints.add(Offset(x, y));
        }
      }
    }
    canvas.drawPoints(PointMode.points, smallPoints, smallPaint);
  }

  @override
  bool shouldRepaint(EditorGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
