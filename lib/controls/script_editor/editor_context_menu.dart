import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 画布右键菜单（视觉规范 §5.6）：添加节点（8 分类子菜单）、重置视图、删除所选。
///
/// 「删除所选」无选中时禁用（`onPressed` 为 null）；分隔线仅在有选中时显示。
/// [onAddNode] 以弹出点的场景坐标落点，实际添加由画布注入控制器操作。
Widget buildEditorContextMenu({
  required Offset scenePoint,
  required bool hasSelection,
  required VoidCallback onResetView,
  required VoidCallback onDeleteSelection,
  required void Function(String typeKey, Offset scenePoint) onAddNode,
}) {
  return MenuFlyout(
    items: <MenuFlyoutItemBase>[
      MenuFlyoutSubItem(
        key: const Key('canvasMenuAddNode'),
        text: const Text('添加节点'),
        items: _buildAddNodeItems(scenePoint, onAddNode),
      ),
      const MenuFlyoutSeparator(),
      MenuFlyoutItem(
        key: const Key('canvasMenuResetView'),
        text: const Text('重置视图'),
        leading: const Icon(FluentIcons.refresh, size: 14),
        onPressed: onResetView,
      ),
      if (hasSelection) const MenuFlyoutSeparator(),
      MenuFlyoutItem(
        key: const Key('canvasMenuDeleteSelection'),
        text: const Text('删除所选'),
        leading: const Icon(FluentIcons.delete, size: 14),
        onPressed: hasSelection ? onDeleteSelection : null,
      ),
    ],
  );
}

/// 添加节点子菜单（§5.6）：分类子菜单（ScriptNodeCategory.values 声明序），
/// 项 = 该类节点，落点 = 弹出点场景坐标。
MenuItemsBuilder _buildAddNodeItems(
  Offset scenePoint,
  void Function(String typeKey, Offset scenePoint) onAddNode,
) {
  return (BuildContext context) => <MenuFlyoutItemBase>[
    for (final ScriptNodeCategory category in ScriptNodeCategory.values)
      MenuFlyoutSubItem(
        key: Key('canvasMenuCategory_${category.name}'),
        text: Text(category.label),
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: nodeCategoryColor(category),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        items: (BuildContext context) => <MenuFlyoutItemBase>[
          for (final ScriptNodeTypeDescriptor descriptor
              in NodeRegistry.byCategory(category))
            MenuFlyoutItem(
              key: Key('canvasMenuNode_${descriptor.typeKey}'),
              text: Text(descriptor.displayName),
              leading: Icon(
                nodeTypeIcon(descriptor.typeKey),
                size: 14,
                color: nodeCategoryColor(descriptor.category),
              ),
              onPressed: () => onAddNode(descriptor.typeKey, scenePoint),
            ),
        ],
      ),
  ];
}
