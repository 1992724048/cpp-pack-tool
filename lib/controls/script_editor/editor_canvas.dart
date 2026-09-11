import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _minSceneWidth = 1600;
const double _minSceneHeight = 1200;
const double _scenePadding = 600;
const double _minScale = 0.5;
const double _maxScale = 2.0;
const double _pinLabelMinScale = 0.75;
const double _dragClickThreshold = 3;

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

  String? _dragNodeId;
  Offset _dragNodeStart = Offset.zero;
  Offset _dragStartScene = Offset.zero;
  Offset _dragSceneDelta = Offset.zero;
  Offset _dragDownGlobal = Offset.zero;
  double _dragMaxScreenDistance = 0;

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
    final List<ScriptNodeModel> orderedNodes = _orderedNodes(
      project.nodes,
      selectedNodeId,
    );
    final Size sceneSize = _sceneSize(project.nodes);

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
                        // 错误红点接线（controller.diagnostics）由 T6 完成。
                        hasError: false,
                        connectedPins:
                            connectedPins[node.id] ?? const <String>{},
                        showPinLabels: _showPinLabels,
                        onTap: () => widget.controller.selectNode(node.id),
                        onDragStart: (DragStartDetails details) =>
                            _beginNodeDrag(node.id, details),
                        onDragUpdate: (DragUpdateDetails details) =>
                            _updateNodeDrag(node.id, details),
                        onDragEnd: (DragEndDetails details) =>
                            _endNodeDrag(node.id, details),
                        onDragCancel: () => _cancelNodeDrag(node.id),
                      ),
                    ),
                ],
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
    _transformation.value = Matrix4.identity()
      ..translateByDouble(project.viewX, project.viewY, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// 模型视口被外部直接写入时（T9 诊断居中 / T11 恢复），同步到变换矩阵。
  void _syncViewportFromProject(ScriptProjectModel project) {
    final Matrix4 matrix = _transformation.value;
    if (matrix.storage[12] == project.viewX &&
        matrix.storage[13] == project.viewY &&
        matrix.getMaxScaleOnAxis() == project.viewScale) {
      return;
    }
    _applyProjectViewport();
  }

  void _persistViewport() {
    final Matrix4 matrix = _transformation.value;
    widget.controller.setViewport(
      x: matrix.storage[12],
      y: matrix.storage[13],
      scale: matrix.getMaxScaleOnAxis(),
    );
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
