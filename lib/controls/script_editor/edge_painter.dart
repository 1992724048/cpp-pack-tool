import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// 连线命中采样段数（§5.4：贝塞尔按 16 段采样为折线）。
const int edgeHitSampleSegments = 16;

/// 三次贝塞尔控制点水平偏移：k = clamp(|dx| × 0.5 + 24, 48, 160)（§5.4）。
double edgeControlOffset(Offset from, Offset to) {
  return ((to.dx - from.dx).abs() * 0.5 + 24).clamp(48.0, 160.0);
}

/// 水平控制点三次贝塞尔路径（§5.4）。
Path edgePath(Offset from, Offset to) {
  final double offset = edgeControlOffset(from, to);
  return Path()
    ..moveTo(from.dx, from.dy)
    ..cubicTo(from.dx + offset, from.dy, to.dx - offset, to.dy, to.dx, to.dy);
}

/// 贝塞尔曲线在参数 [t]（0..1）处的点。
Offset edgePointAt(Offset from, Offset to, double t) {
  final double offset = edgeControlOffset(from, to);
  final double inverse = 1 - t;
  final double a = inverse * inverse * inverse;
  final double b = 3 * inverse * inverse * t;
  final double c = 3 * inverse * t * t;
  final double d = t * t * t;
  return Offset(
    a * from.dx + b * (from.dx + offset) + c * (to.dx - offset) + d * to.dx,
    a * from.dy + b * from.dy + c * to.dy + d * to.dy,
  );
}

/// 把贝塞尔按 [segments] 段采样为折线（含首尾，共 segments + 1 个点）。
List<Offset> sampleEdgePolyline(
  Offset from,
  Offset to, {
  int segments = edgeHitSampleSegments,
}) {
  return <Offset>[
    for (int index = 0; index <= segments; index++)
      edgePointAt(from, to, index / segments),
  ];
}

/// 点到折线的最短距离（场景 px）。
double distanceToPolyline(List<Offset> polyline, Offset point) {
  double best = double.infinity;
  for (int index = 0; index < polyline.length - 1; index++) {
    final double distance = _distanceToSegment(
      polyline[index],
      polyline[index + 1],
      point,
    );
    if (distance < best) {
      best = distance;
    }
  }
  return best;
}

double _distanceToSegment(Offset start, Offset end, Offset point) {
  final Offset segment = end - start;
  final double lengthSquared =
      segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared == 0) {
    return (point - start).distance;
  }
  final Offset relative = point - start;
  final double t =
      ((relative.dx * segment.dx + relative.dy * segment.dy) / lengthSquared)
          .clamp(0.0, 1.0);
  return (point - (start + segment * t)).distance;
}

/// 连线命中容差：clamp(8 / scale, 4, 16) 场景 px（§5.4/§5.7）。
double edgeHitTolerance(double scale) => (8 / scale).clamp(4.0, 16.0);

/// 引脚/连线的数据类型色（§2.2）：exec `text`、string `blue`、bool `peach`、
/// `list<string>` `mauve`，未知 data 类型回退 `overlay1`。
Color pinStrokeColor(ScriptPinKind kind, ScriptDataType? dataType) {
  if (kind == ScriptPinKind.exec) {
    return UCColors.flavor.text;
  }
  return switch (dataType) {
    ScriptDataType.string => UCColors.flavor.blue,
    ScriptDataType.boolean => UCColors.flavor.peach,
    ScriptDataType.listString => UCColors.flavor.mauve,
    null => UCColors.flavor.overlay1,
  };
}

/// 单条连线的绘制输入（场景坐标）。
typedef EdgeVisual = ({
  Offset from,
  Offset to,
  ScriptPinKind kind,
  ScriptDataType? dataType,
  bool selected,
  bool hovered,
});

/// 拖拽预览线的悬停状态（§5.4 样式表）。
enum EdgePreviewState { normal, compatible, incompatible }

/// 拖拽预览线：起点 = 源引脚锚点，终点 = 指针位置。
typedef EdgePreviewVisual = ({
  Offset from,
  Offset to,
  Color color,
  EdgePreviewState state,
});

/// 连线与拖拽预览线绘制器（视觉规范 §5.4）。
///
/// exec 常规 2.5px `flavor.text` α0.70、data 常规 2.0px 类型色 α0.95；
/// hover 原色 α1.0 且线宽 +0.5；选中 accent 3.0px + 两端 r=4 实心圆点；
/// 预览线按状态取源类型色（normal α0.85 / compatible 转实）
/// 或 `flavor.red` α0.90（incompatible），指针端均为 r=4 空心圆。
class EdgePainter extends CustomPainter {
  const EdgePainter({this.edges = const <EdgeVisual>[], this.preview});

  final List<EdgeVisual> edges;
  final EdgePreviewVisual? preview;

  static const double execWidth = 2.5;
  static const double dataWidth = 2.0;
  static const double selectedWidth = 3.0;
  static const double endpointDotRadius = 4.0;
  static const double normalExecAlpha = 0.70;
  static const double normalDataAlpha = 0.95;
  static const double hoverWidthDelta = 0.5;
  static const double previewAlpha = 0.85;
  static const double previewCompatibleWidth = 2.5;
  static const double previewIncompatibleAlpha = 0.90;
  static const double previewIncompatibleWidth = 2.5;
  static const double previewPointerRadius = 4.0;
  static const double previewPointerStrokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final EdgeVisual edge in edges) {
      _paintEdge(canvas, edge);
    }
    final EdgePreviewVisual? preview = this.preview;
    if (preview != null) {
      _paintPreview(canvas, preview);
    }
  }

  void _paintEdge(Canvas canvas, EdgeVisual edge) {
    final Color base = pinStrokeColor(edge.kind, edge.dataType);
    final double baseWidth = edge.kind == ScriptPinKind.exec
        ? execWidth
        : dataWidth;
    final Color color;
    final double width;
    if (edge.selected) {
      color = UCColors.accent;
      width = selectedWidth;
    } else if (edge.hovered) {
      color = base;
      width = baseWidth + hoverWidthDelta;
    } else {
      final double alpha = edge.kind == ScriptPinKind.exec
          ? normalExecAlpha
          : normalDataAlpha;
      color = base.withValues(alpha: alpha);
      width = baseWidth;
    }
    canvas.drawPath(edgePath(edge.from, edge.to), _strokePaint(color, width));
    if (edge.selected) {
      final Paint dot = Paint()..color = UCColors.accent;
      canvas.drawCircle(edge.from, endpointDotRadius, dot);
      canvas.drawCircle(edge.to, endpointDotRadius, dot);
    }
  }

  void _paintPreview(Canvas canvas, EdgePreviewVisual preview) {
    final (Color color, double width) = switch (preview.state) {
      EdgePreviewState.normal => (
        preview.color.withValues(alpha: previewAlpha),
        dataWidth,
      ),
      EdgePreviewState.compatible => (preview.color, previewCompatibleWidth),
      EdgePreviewState.incompatible => (
        UCColors.flavor.red.withValues(alpha: previewIncompatibleAlpha),
        previewIncompatibleWidth,
      ),
    };
    canvas.drawPath(
      edgePath(preview.from, preview.to),
      _strokePaint(color, width),
    );
    canvas.drawCircle(
      preview.to,
      previewPointerRadius,
      _strokePaint(color, previewPointerStrokeWidth),
    );
  }

  Paint _strokePaint(Color color, double width) {
    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
  }

  @override
  bool shouldRepaint(EdgePainter oldDelegate) {
    return !listEquals(oldDelegate.edges, edges) ||
        oldDelegate.preview != preview;
  }
}
