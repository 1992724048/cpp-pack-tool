import 'dart:math' as math;

import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _minCanvasWidth = 640;
const double _minCanvasHeight = 400;
const double _canvasPadding = 40;
const double _columnWidth = 220;
const double _rowHeight = 64;
const double _nodeWidth = 160;
const double _nodeHeight = 56;
const double _edgeStrokeWidth = 1.5;
const double _arrowLength = 8;
const double _arrowHalfWidth = 4;

Future<void> showDependencyGraphDialog(
  BuildContext context, {
  required List<PackModel> packs,
  String? selectedPackName,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        DependencyGraphDialog(packs: packs, selectedPackName: selectedPackName),
  );
}

class DependencyGraphDialog extends StatefulWidget {
  const DependencyGraphDialog({
    super.key,
    required this.packs,
    this.selectedPackName,
  });

  final List<PackModel> packs;
  final String? selectedPackName;

  @override
  State<DependencyGraphDialog> createState() => _DependencyGraphDialogState();
}

class _DependencyGraphDialogState extends State<DependencyGraphDialog> {
  late final _DependencyGraphLayout _layout;

  @override
  void initState() {
    super.initState();
    _layout = _DependencyGraphLayout.fromPacks(
      widget.packs,
      widget.selectedPackName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('dependencyGraphDialog'),
      title: const Text('依赖关系图'),
      constraints: const BoxConstraints(maxWidth: 960),
      content: SizedBox(
        width: 880,
        height: 560,
        child: widget.packs.isEmpty
            ? const Center(child: Text('暂无包'))
            : _buildGraph(),
      ),
      actions: [
        Button(
          key: const Key('dependencyGraphCloseButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildGraph() {
    final FluentThemeData theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.resources.cardBackgroundFillColorSecondary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.resources.controlStrokeColorDefault,
              ),
            ),
            child: InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 0.5,
              maxScale: 2.0,
              boundaryMargin: const EdgeInsets.all(80),
              constrained: false,
              child: SizedBox(
                width: _layout.width,
                height: _layout.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DependencyGraphPainter(
                          edges: _layout.edges,
                          lineColor: theme.resources.controlStrokeColorDefault,
                        ),
                      ),
                    ),
                    for (final _GraphNode node in _layout.nodes)
                      Positioned(
                        left: node.left,
                        top: node.top,
                        child: _buildNodeCard(theme, node),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(FluentThemeData theme) {
    final TextStyle style = TextStyle(
      fontSize: 12,
      color: theme.resources.textFillColorSecondary,
    );
    return Row(
      children: [
        Expanded(child: Text('拖拽平移、滚轮缩放；红色为缺失依赖', style: style)),
        _buildLegendItem(
          '普通',
          theme.resources.controlStrokeColorDefault,
          style,
        ),
        const SizedBox(width: 12),
        _buildLegendItem('当前包', theme.accentColor, style),
        const SizedBox(width: 12),
        _buildLegendItem('缺失', AppColors.critical(theme.brightness), style),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, TextStyle style) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
  }

  Widget _buildNodeCard(FluentThemeData theme, _GraphNode node) {
    final bool emphasized = node.isMissing || node.isSelected;
    return Container(
      key: Key('dependencyGraphNode_${node.name}'),
      width: _nodeWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _nodeBorderColor(node, theme),
          width: emphasized ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: theme.resources.textFillColorPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (node.version != null)
                Flexible(
                  child: Text(
                    node.version!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ),
              if (node.isMissing) ...[
                if (node.version != null) const SizedBox(width: 6),
                Tag(text: '缺失', color: MarkerColors.red, fontSize: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

Color _nodeBorderColor(_GraphNode node, FluentThemeData theme) {
  if (node.isMissing) {
    return AppColors.critical(theme.brightness);
  }
  if (node.isSelected) {
    return theme.accentColor;
  }
  return theme.resources.controlStrokeColorDefault;
}

class _DependencyGraphLayout {
  _DependencyGraphLayout._({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  });

  factory _DependencyGraphLayout.fromPacks(
    List<PackModel> packs,
    String? selectedPackName,
  ) {
    final String? selectedKey = selectedPackName?.toLowerCase();
    final Map<String, _GraphNode> nodesByKey = <String, _GraphNode>{};
    for (final PackModel pack in packs) {
      final String key = pack.name.toLowerCase();
      if (nodesByKey.containsKey(key)) {
        continue;
      }
      nodesByKey[key] = _GraphNode(
        key: key,
        name: pack.name,
        version: pack.version,
        isMissing: false,
        isSelected: key == selectedKey,
      );
    }

    final List<_GraphEdge> edges = <_GraphEdge>[];
    final Set<String> processedPacks = <String>{};
    for (final PackModel pack in packs) {
      final String sourceKey = pack.name.toLowerCase();
      final _GraphNode? source = nodesByKey[sourceKey];
      if (source == null || !processedPacks.add(sourceKey)) {
        continue;
      }
      final Set<String> seenDependencies = <String>{};
      for (final DependencyModel dependency in pack.dependencies) {
        final String key = dependency.name.toLowerCase();
        if (key.isEmpty || key == sourceKey || !seenDependencies.add(key)) {
          continue;
        }
        final _GraphNode target = nodesByKey.putIfAbsent(
          key,
          () => _GraphNode(
            key: key,
            name: dependency.name,
            version: null,
            isMissing: true,
            isSelected: false,
          ),
        );
        if (!target.isMissing) {
          source.dependencies.add(key);
        }
        edges.add(_GraphEdge(from: target, to: source));
      }
    }

    final Map<String, int> levels = _resolveLevels(nodesByKey);
    final List<_GraphNode> nodes = nodesByKey.values.toList()
      ..sort(_compareGraphNodes);
    final _CanvasBounds bounds = _layoutNodes(nodes, levels);
    return _DependencyGraphLayout._(
      nodes: nodes,
      edges: edges,
      width: bounds.width,
      height: bounds.height,
    );
  }

  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final double width;
  final double height;
}

/// 层号 = 1 + 本地依赖的最大层号（无本地依赖为 0）。
/// 显式栈迭代求值，`resolving` 集合守卫环上的边（配置异常时不至于死循环）。
Map<String, int> _resolveLevels(Map<String, _GraphNode> nodesByKey) {
  final Map<String, int> levels = <String, int>{};
  final Set<String> resolving = <String>{};
  final List<_LevelFrame> stack = <_LevelFrame>[];
  final List<String> roots = nodesByKey.keys.toList()..sort();

  for (final String root in roots) {
    if (levels.containsKey(root)) {
      continue;
    }
    stack.add(_LevelFrame(key: root));
    resolving.add(root);
    while (stack.isNotEmpty) {
      final _LevelFrame frame = stack.last;
      final _GraphNode node = nodesByKey[frame.key]!;
      if (frame.next < node.dependencies.length) {
        final String dependency = node.dependencies[frame.next];
        frame.next++;
        if (levels.containsKey(dependency) || !resolving.add(dependency)) {
          continue;
        }
        stack.add(_LevelFrame(key: dependency));
        continue;
      }
      stack.removeLast();
      resolving.remove(frame.key);
      int level = 0;
      for (final String dependency in node.dependencies) {
        final int candidate = (levels[dependency] ?? 0) + 1;
        if (candidate > level) {
          level = candidate;
        }
      }
      levels[frame.key] = level;
    }
  }
  return levels;
}

_CanvasBounds _layoutNodes(List<_GraphNode> nodes, Map<String, int> levels) {
  final Map<int, List<_GraphNode>> rowsByLevel = <int, List<_GraphNode>>{};
  for (final _GraphNode node in nodes) {
    rowsByLevel
        .putIfAbsent(levels[node.key] ?? 0, () => <_GraphNode>[])
        .add(node);
  }

  double maxRight = 0;
  double maxBottom = 0;
  for (final MapEntry<int, List<_GraphNode>> entry in rowsByLevel.entries) {
    final List<_GraphNode> row = entry.value..sort(_compareGraphNodes);
    for (int index = 0; index < row.length; index++) {
      final _GraphNode node = row[index];
      node.left = _canvasPadding + entry.key * _columnWidth;
      node.top = _canvasPadding + index * _rowHeight;
      maxRight = math.max(maxRight, node.left + _nodeWidth);
      maxBottom = math.max(maxBottom, node.top + _nodeHeight);
    }
  }

  return _CanvasBounds(
    width: math.max(_minCanvasWidth, maxRight + _canvasPadding),
    height: math.max(_minCanvasHeight, maxBottom + _canvasPadding),
  );
}

int _compareGraphNodes(_GraphNode a, _GraphNode b) {
  final int byLowerName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byLowerName != 0) {
    return byLowerName;
  }
  return a.name.compareTo(b.name);
}

class _CanvasBounds {
  const _CanvasBounds({required this.width, required this.height});

  final double width;
  final double height;
}

class _GraphNode {
  _GraphNode({
    required this.key,
    required this.name,
    required this.version,
    required this.isMissing,
    required this.isSelected,
  });

  final String key;
  final String name;
  final String? version;
  final bool isMissing;
  final bool isSelected;

  /// 本地（非缺失）依赖节点的 key，用于层号计算。
  final List<String> dependencies = <String>[];

  double left = 0;
  double top = 0;
}

class _GraphEdge {
  const _GraphEdge({required this.from, required this.to});

  /// 被依赖者。
  final _GraphNode from;

  /// 依赖者。
  final _GraphNode to;
}

class _LevelFrame {
  _LevelFrame({required this.key});

  final String key;
  int next = 0;
}

class _DependencyGraphPainter extends CustomPainter {
  const _DependencyGraphPainter({required this.edges, required this.lineColor});

  final List<_GraphEdge> edges;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = _edgeStrokeWidth
      ..style = PaintingStyle.stroke;
    final Paint arrowPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    for (final _GraphEdge edge in edges) {
      final Offset start = _nodeBorderPoint(edge.from, edge.to);
      final Offset end = _nodeBorderPoint(edge.to, edge.from);
      canvas.drawLine(start, end, linePaint);
      _drawArrowHead(
        canvas,
        tip: end,
        direction: end - start,
        paint: arrowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DependencyGraphPainter oldDelegate) {
    return oldDelegate.edges != edges || oldDelegate.lineColor != lineColor;
  }
}

Offset _nodeBorderPoint(_GraphNode from, _GraphNode to) {
  final Offset center = Offset(
    from.left + _nodeWidth / 2,
    from.top + _nodeHeight / 2,
  );
  final Offset target = Offset(
    to.left + _nodeWidth / 2,
    to.top + _nodeHeight / 2,
  );
  final Offset delta = target - center;
  if (delta.dx == 0 && delta.dy == 0) {
    return center;
  }
  final double scaleX = delta.dx == 0
      ? double.infinity
      : _nodeWidth / 2 / delta.dx.abs();
  final double scaleY = delta.dy == 0
      ? double.infinity
      : _nodeHeight / 2 / delta.dy.abs();
  final double scale = scaleX < scaleY ? scaleX : scaleY;
  return center + delta * scale;
}

void _drawArrowHead(
  Canvas canvas, {
  required Offset tip,
  required Offset direction,
  required Paint paint,
}) {
  final double length = direction.distance;
  if (length == 0) {
    return;
  }
  final Offset unit = direction / length;
  final Offset normal = Offset(-unit.dy, unit.dx);
  final Offset base = tip - unit * _arrowLength;
  final Path arrow = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      base.dx + normal.dx * _arrowHalfWidth,
      base.dy + normal.dy * _arrowHalfWidth,
    )
    ..lineTo(
      base.dx - normal.dx * _arrowHalfWidth,
      base.dy - normal.dy * _arrowHalfWidth,
    )
    ..close();
  canvas.drawPath(arrow, paint);
}
