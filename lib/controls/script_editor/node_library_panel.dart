import 'dart:math' as math;

import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart'
    show PointerEnterEvent, PointerExitEvent, PointerUpEvent;

/// 节点库点击添加落点（视觉规范 §4.2）：视口中心场景坐标 − (104, 卡片高/2)，
/// 再叠加级联偏移 `24 × (现有节点数 % 8)`；坐标 clamp 到 ≥ 0（负坐标裁决）。
Offset nodeLibraryAddPosition({
  required Offset viewportCenterScene,
  required ScriptNodeTypeDescriptor descriptor,
  required int existingNodeCount,
}) {
  final double cascade = 24.0 * (existingNodeCount % 8);
  return Offset(
    math.max(0, viewportCenterScene.dx - nodeCardWidth / 2 + cascade),
    math.max(
      0,
      viewportCenterScene.dy - nodeCardHeight(descriptor) / 2 + cascade,
    ),
  );
}

/// 左侧节点库面板（视觉规范 §4 全节）。
class NodeLibraryPanel extends StatefulWidget {
  const NodeLibraryPanel({super.key, required this.onAddNode});

  /// 条目点击回调；null 表示无可用项目（条目不可交互）。
  final ValueChanged<ScriptNodeTypeDescriptor>? onAddNode;

  @override
  State<NodeLibraryPanel> createState() => _NodeLibraryPanelState();
}

class _NodeLibraryPanelState extends State<NodeLibraryPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<ScriptNodeCategory> _collapsedCategories = <ScriptNodeCategory>{};
  String _query = '';

  bool get _enabled => widget.onAddNode != null;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SizedBox(
            height: 32,
            child: TextBox(
              key: const Key('nodeLibrarySearch'),
              controller: _searchController,
              placeholder: '搜索节点',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8, right: 6),
                child: Icon(FluentIcons.search, size: 14),
              ),
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  /// 分组顺序 = [ScriptNodeCategory.values] 声明序；搜索时仅显示命中分组并自动展开（§4.1）。
  Widget _buildList() {
    final String query = _query.trim().toLowerCase();
    final bool searching = query.isNotEmpty;
    final List<Widget> rows = <Widget>[];
    for (final ScriptNodeCategory category in ScriptNodeCategory.values) {
      final List<ScriptNodeTypeDescriptor> matches =
          NodeRegistry.byCategory(category)
              .where(
                (ScriptNodeTypeDescriptor descriptor) =>
                    _matches(descriptor, query),
              )
              .toList();
      if (searching && matches.isEmpty) {
        continue;
      }
      final bool expanded =
          searching || !_collapsedCategories.contains(category);
      rows.add(_buildGroupHeader(category, expanded, searching));
      if (!expanded) {
        continue;
      }
      for (final ScriptNodeTypeDescriptor descriptor in matches) {
        rows.add(
          _NodeLibraryItem(
            descriptor: descriptor,
            enabled: _enabled,
            onTap: () => widget.onAddNode?.call(descriptor),
          ),
        );
      }
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(
            '未找到匹配的节点',
            style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
          ),
        ),
      );
    }
    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        children: rows,
      ),
    );
  }

  bool _matches(ScriptNodeTypeDescriptor descriptor, String query) {
    if (query.isEmpty) {
      return true;
    }
    return descriptor.displayName.toLowerCase().contains(query) ||
        descriptor.typeKey.toLowerCase().contains(query) ||
        descriptor.category.label.toLowerCase().contains(query);
  }

  Widget _buildGroupHeader(
    ScriptNodeCategory category,
    bool expanded,
    bool searching,
  ) {
    return GestureDetector(
      key: Key('nodeLibraryGroup_${category.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: searching ? null : () => _toggleCategory(category),
      child: MouseRegion(
        cursor: searching ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                Icon(
                  expanded
                      ? FluentIcons.chevron_down
                      : FluentIcons.chevron_right,
                  size: 10,
                  color: UCColors.flavor.subtext1,
                ),
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: nodeCategoryColor(category),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: UCColors.flavor.subtext1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleCategory(ScriptNodeCategory category) {
    setState(() {
      if (!_collapsedCategories.remove(category)) {
        _collapsedCategories.add(category);
      }
    });
  }
}

/// 节点库条目（视觉规范 §4.2）：28 高、左 20 右 12 内边距、行外边距 4、圆角 4。
///
/// 单击经 [onTap] 添加；拖拽经 `Draggable` 携带类型描述符交由画布 `DragTarget`
/// 处理；[enabled] 为 false 时不响应点击且不构建拖拽源。
class _NodeLibraryItem extends StatefulWidget {
  const _NodeLibraryItem({
    required this.descriptor,
    required this.enabled,
    required this.onTap,
  });

  final ScriptNodeTypeDescriptor descriptor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_NodeLibraryItem> createState() => _NodeLibraryItemState();
}

class _NodeLibraryItemState extends State<_NodeLibraryItem> {
  bool _hovered = false;
  bool _pressed = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final ScriptNodeTypeDescriptor descriptor = widget.descriptor;
    final Widget row = Container(
      key: Key('nodeLibraryItem_${descriptor.typeKey}'),
      height: 28,
      padding: const EdgeInsets.only(left: 20, right: 12),
      decoration: BoxDecoration(
        color: _rowColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            nodeTypeIcon(descriptor.typeKey),
            size: 14,
            color: nodeCategoryColor(descriptor.category),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              descriptor.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: UCColors.flavor.text),
            ),
          ),
        ],
      ),
    );

    final Widget interactive = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.enabled
          ? (_) => setState(() => _pressed = true)
          : null,
      onPointerUp: widget.enabled
          ? (PointerUpEvent event) => setState(() => _pressed = false)
          : null,
      onPointerCancel: widget.enabled
          ? (_) => setState(() => _pressed = false)
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: row,
      ),
    );

    return Tooltip(
      message: descriptor.typeKey,
      style: TooltipThemeData(
        textStyle: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 11,
          color: UCColors.flavor.base,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: MouseRegion(
          cursor: _cursor,
          onEnter: widget.enabled
              ? (PointerEnterEvent event) => setState(() => _hovered = true)
              : null,
          onExit: widget.enabled
              ? (PointerExitEvent event) => setState(() => _hovered = false)
              : null,
          child: widget.enabled
              ? Draggable<ScriptNodeTypeDescriptor>(
                  data: descriptor,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: _buildDragFeedback(descriptor),
                  childWhenDragging: Opacity(opacity: 0.4, child: row),
                  onDragStarted: () => setState(() => _dragging = true),
                  onDragEnd: (DraggableDetails details) =>
                      setState(() => _dragging = false),
                  child: interactive,
                )
              : interactive,
        ),
      ),
    );
  }

  MouseCursor get _cursor {
    if (_dragging) {
      return SystemMouseCursors.grabbing;
    }
    return widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic;
  }

  Color get _rowColor {
    if (_dragging) {
      return Colors.transparent;
    }
    if (_pressed) {
      return UCColors.flavor.surface1;
    }
    if (_hovered) {
      return UCColors.flavor.surface0;
    }
    return Colors.transparent;
  }

  /// 拖拽反馈迷你卡 160×34（§4.2）。
  Widget _buildDragFeedback(ScriptNodeTypeDescriptor descriptor) {
    return MouseRegion(
      cursor: SystemMouseCursors.grabbing,
      child: Container(
        key: const Key('nodeLibraryDragFeedback'),
        width: 160,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: UCColors.flavor.surface0.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: UCColors.accent),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              nodeTypeIcon(descriptor.typeKey),
              size: 12,
              color: nodeCategoryColor(descriptor.category),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                descriptor.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: UCColors.flavor.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
