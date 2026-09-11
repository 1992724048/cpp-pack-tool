import 'dart:math' as math;

import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart'
    show
        DragStartBehavior,
        PanGestureRecognizer,
        PointerEnterEvent,
        PointerExitEvent,
        TapGestureRecognizer,
        kPrimaryButton;

/// 节点卡固定几何（场景 px，视觉规范 §5.2）。
const double nodeCardWidth = 208;
const double nodeCardHeaderHeight = 34;
const double nodePinRowHeight = 22;

/// 卡片四周为引脚与错误红点预留的溢出区（场景 px）。
const double nodeCardOverflow = 10;

const double _pinAreaTopPadding = 4;
const double _pinAreaBottomPadding = 6;
const double _pinLabelMaxWidth = 90;
const double _dataPinDiameter = 10;
const double _execPinWidth = 14;
const double _execPinHeight = 8;
const double _pinStrokeWidth = 1.5;
const double _errorDotDiameter = 8;

/// 节点卡高度 = 头部 34 + 引脚区上下内边距 10 + 行高 22 × 行数（§5.2）。
double nodeCardHeight(ScriptNodeTypeDescriptor? descriptor) {
  if (descriptor == null) {
    return nodeCardHeaderHeight + _pinAreaTopPadding + _pinAreaBottomPadding;
  }
  int inputCount = 0;
  int outputCount = 0;
  for (final ScriptPinDescriptor pin in descriptor.pins) {
    if (pin.isInput) {
      inputCount++;
    } else {
      outputCount++;
    }
  }
  final int rows = math.max(inputCount, outputCount);
  return nodeCardHeaderHeight +
      _pinAreaTopPadding +
      _pinAreaBottomPadding +
      nodePinRowHeight * rows;
}

/// 第 [rowIndex] 行（0 起）引脚的竖直中心（卡片本地坐标）。
double nodePinRowCenterY(int rowIndex) {
  return nodeCardHeaderHeight +
      _pinAreaTopPadding +
      nodePinRowHeight / 2 +
      nodePinRowHeight * rowIndex;
}

/// 节点分类色（图标与头部底色，视觉规范 §2.2/§9）。
Color nodeCategoryColor(ScriptNodeCategory category) {
  return switch (category) {
    ScriptNodeCategory.flow => UCColors.flavor.mauve,
    ScriptNodeCategory.file => UCColors.flavor.blue,
    ScriptNodeCategory.process => UCColors.flavor.peach,
    ScriptNodeCategory.context => UCColors.flavor.teal,
    ScriptNodeCategory.value => UCColors.flavor.yellow,
    ScriptNodeCategory.string => UCColors.flavor.green,
    ScriptNodeCategory.log => UCColors.flavor.sky,
    ScriptNodeCategory.logic => UCColors.flavor.maroon,
  };
}

/// 节点图标（视觉规范 §9）供节点卡与节点库共用；未知类型回退方块图标。
IconData nodeTypeIcon(String typeKey) {
  return switch (typeKey) {
    'flow.entry' => FluentIcons.play,
    'flow.branch' => FluentIcons.branch_fork,
    'flow.foreach' => FluentIcons.repeat_all,
    'flow.while' => FluentIcons.sync,
    'file.copy' => FluentIcons.copy,
    'file.move' => FluentIcons.move,
    'file.delete' => FluentIcons.delete,
    'file.makeDirectory' => FluentIcons.folder,
    'file.list' => FluentIcons.list,
    'file.exists' => FluentIcons.search,
    'process.run' => FluentIcons.process,
    'context.macro' => FluentIcons.variable,
    'context.environment' => FluentIcons.globe,
    'context.packageFile' => FluentIcons.file_symlink,
    'value.text' => FluentIcons.font,
    'value.boolean' => FluentIcons.checkbox,
    'string.concat' => FluentIcons.link,
    'string.replace' => FluentIcons.edit,
    'string.lowerCase' => FluentIcons.font_decrease,
    'string.fileName' => FluentIcons.document,
    'string.directoryName' => FluentIcons.folder_open,
    'path.join' => FluentIcons.merge,
    'log.message' => FluentIcons.message,
    'logic.compareString' => FluentIcons.calculator,
    'logic.not' => FluentIcons.cancel,
    _ => FluentIcons.cube_shape,
  };
}

bool _primaryButtonOnly(int buttons) => buttons == kPrimaryButton;

/// 节点卡：头部（分类色 + 图标 + 标题）与引脚行列静态形态（视觉规范 §5.2/§5.3）。
///
/// 拖动/单击回调由画布注入（拖动坐标换算属画布职责）；引脚交互与错误标记
/// 接线留待 T6，[errorPins]/[hasError] 已是最终渲染接口。
class NodeCard extends StatefulWidget {
  const NodeCard({
    super.key,
    required this.nodeId,
    required this.typeKey,
    required this.descriptor,
    required this.selected,
    required this.dragging,
    required this.hasError,
    required this.connectedPins,
    this.errorPins = const <String>{},
    this.showPinLabels = true,
    this.onTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  final String nodeId;
  final String typeKey;

  /// 注册表描述符；null 表示未知类型（手改 YAML），回退中性外观。
  final ScriptNodeTypeDescriptor? descriptor;
  final bool selected;
  final bool dragging;
  final bool hasError;
  final Set<String> connectedPins;
  final Set<String> errorPins;
  final bool showPinLabels;

  final VoidCallback? onTap;
  final void Function(DragStartDetails details)? onDragStart;
  final void Function(DragUpdateDetails details)? onDragUpdate;
  final void Function(DragEndDetails details)? onDragEnd;
  final VoidCallback? onDragCancel;

  @override
  State<NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<NodeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ScriptNodeTypeDescriptor? descriptor = widget.descriptor;
    final double height = nodeCardHeight(descriptor);
    final Color categoryColor = descriptor == null
        ? UCColors.flavor.overlay1
        : nodeCategoryColor(descriptor.category);
    final IconData icon = nodeTypeIcon(descriptor?.typeKey ?? widget.typeKey);
    final String title = descriptor?.displayName ?? widget.typeKey;

    return SizedBox(
      width: nodeCardWidth + nodeCardOverflow * 2,
      height: height + nodeCardOverflow * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: nodeCardOverflow,
            top: nodeCardOverflow,
            child: _buildBody(
              height: height,
              title: title,
              icon: icon,
              categoryColor: categoryColor,
              descriptor: descriptor,
            ),
          ),
          if (widget.hasError) _buildErrorDot(),
          ..._buildPins(descriptor),
        ],
      ),
    );
  }

  Widget _buildBody({
    required double height,
    required String title,
    required IconData icon,
    required Color categoryColor,
    required ScriptNodeTypeDescriptor? descriptor,
  }) {
    final bool active = widget.selected || widget.dragging;
    final Color background = (_hovered || widget.dragging)
        ? UCColors.flavor.surface1
        : UCColors.flavor.surface0;
    final Color borderColor = active
        ? UCColors.accent
        : (_hovered ? UCColors.flavor.overlay1 : UCColors.flavor.overlay0);

    return MouseRegion(
      cursor: widget.dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.move,
      onEnter: (PointerEnterEvent event) => setState(() => _hovered = true),
      onExit: (PointerExitEvent event) => setState(() => _hovered = false),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: _gestures(),
        child: Container(
          key: Key('nodeCard_${widget.nodeId}'),
          width: nodeCardWidth,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
          ),
          // 边框画在前景：不挤压固定几何（头部 34 / 行高 22 / 引脚锚点对齐）。
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: active ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(title: title, icon: icon, color: categoryColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: _pinAreaTopPadding,
                    bottom: _pinAreaBottomPadding,
                  ),
                  child: Column(children: _buildPinRows(descriptor)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<Type, GestureRecognizerFactory> _gestures() {
    return <Type, GestureRecognizerFactory>{
      PanGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
            () =>
                PanGestureRecognizer(allowedButtonsFilter: _primaryButtonOnly),
            (PanGestureRecognizer instance) {
              instance
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = widget.onDragStart
                ..onUpdate = widget.onDragUpdate
                ..onEnd = widget.onDragEnd
                ..onCancel = widget.onDragCancel;
            },
          ),
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () =>
                TapGestureRecognizer(allowedButtonsFilter: _primaryButtonOnly),
            (TapGestureRecognizer instance) {
              instance.onTap = widget.onTap;
            },
          ),
    };
  }

  Widget _buildHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: nodeCardHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border(bottom: BorderSide(color: UCColors.flavor.surface2)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: UCColors.flavor.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  List<Widget> _buildPinRows(ScriptNodeTypeDescriptor? descriptor) {
    if (descriptor == null) {
      return const <Widget>[];
    }
    final List<ScriptPinDescriptor> inputs = descriptor.pins
        .where((ScriptPinDescriptor pin) => pin.isInput)
        .toList();
    final List<ScriptPinDescriptor> outputs = descriptor.pins
        .where((ScriptPinDescriptor pin) => !pin.isInput)
        .toList();
    final int rows = math.max(inputs.length, outputs.length);
    return <Widget>[
      for (int index = 0; index < rows; index++)
        SizedBox(
          height: nodePinRowHeight,
          child: Row(
            children: <Widget>[
              if (index < inputs.length && widget.showPinLabels)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: _buildPinLabel(inputs[index].label),
                ),
              const Spacer(),
              if (index < outputs.length && widget.showPinLabels)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _buildPinLabel(outputs[index].label),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _buildPinLabel(String label) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _pinLabelMaxWidth),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: UCColors.flavor.subtext1),
      ),
    );
  }

  List<Widget> _buildPins(ScriptNodeTypeDescriptor? descriptor) {
    if (descriptor == null) {
      return const <Widget>[];
    }
    final List<Widget> pins = <Widget>[];
    int inputIndex = 0;
    int outputIndex = 0;
    for (final ScriptPinDescriptor pin in descriptor.pins) {
      if (pin.isInput) {
        pins.addAll(_buildPin(pin, inputIndex, isInput: true));
        inputIndex++;
      } else {
        pins.addAll(_buildPin(pin, outputIndex, isInput: false));
        outputIndex++;
      }
    }
    return pins;
  }

  List<Widget> _buildPin(
    ScriptPinDescriptor pin,
    int rowIndex, {
    required bool isInput,
  }) {
    final bool exec = pin.kind == ScriptPinKind.exec;
    final double pinWidth = exec ? _execPinWidth : _dataPinDiameter;
    final double pinHeight = exec ? _execPinHeight : _dataPinDiameter;
    final double anchorX = isInput
        ? nodeCardOverflow.toDouble()
        : nodeCardOverflow + nodeCardWidth;
    final double anchorY = nodeCardOverflow + nodePinRowCenterY(rowIndex);
    final Color color = _pinColor(pin);
    final bool connected = widget.connectedPins.contains(pin.id);

    final List<Widget> widgets = <Widget>[];
    if (widget.errorPins.contains(pin.id)) {
      final double ringWidth = exec ? _execPinWidth + 6 : _dataPinDiameter + 6;
      final double ringHeight = exec
          ? _execPinHeight + 6
          : _dataPinDiameter + 6;
      widgets.add(
        Positioned(
          left: anchorX - ringWidth / 2,
          top: anchorY - ringHeight / 2,
          child: IgnorePointer(
            child: Container(
              key: Key('pinRing_${widget.nodeId}_${pin.id}'),
              width: ringWidth,
              height: ringHeight,
              decoration: BoxDecoration(
                shape: exec ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: exec ? BorderRadius.circular(7) : null,
                border: Border.all(color: UCColors.flavor.red, width: 2),
              ),
            ),
          ),
        ),
      );
    }
    widgets.add(
      Positioned(
        left: anchorX - pinWidth / 2,
        top: anchorY - pinHeight / 2,
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: Container(
            key: Key('pin_${widget.nodeId}_${pin.id}'),
            width: pinWidth,
            height: pinHeight,
            decoration: BoxDecoration(
              color: connected
                  ? color
                  : color.withValues(alpha: exec ? 0.30 : 0.35),
              border: Border.all(color: color, width: _pinStrokeWidth),
              shape: exec ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: exec ? BorderRadius.circular(4) : null,
            ),
          ),
        ),
      ),
    );
    return widgets;
  }

  Color _pinColor(ScriptPinDescriptor pin) {
    if (pin.kind == ScriptPinKind.exec) {
      return UCColors.flavor.text;
    }
    return switch (pin.dataType) {
      ScriptDataType.string => UCColors.flavor.blue,
      ScriptDataType.boolean => UCColors.flavor.peach,
      ScriptDataType.listString => UCColors.flavor.mauve,
      null => UCColors.flavor.overlay1,
    };
  }

  Widget _buildErrorDot() {
    return Positioned(
      left: nodeCardOverflow + nodeCardWidth - _errorDotDiameter / 2,
      top: nodeCardOverflow - _errorDotDiameter / 2,
      child: IgnorePointer(
        child: Container(
          key: Key('nodeErrorDot_${widget.nodeId}'),
          width: _errorDotDiameter,
          height: _errorDotDiameter,
          decoration: BoxDecoration(
            color: UCColors.flavor.red,
            shape: BoxShape.circle,
            border: Border.all(color: UCColors.flavor.surface0),
          ),
        ),
      ),
    );
  }
}
