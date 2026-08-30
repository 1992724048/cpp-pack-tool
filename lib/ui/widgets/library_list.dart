/// 左侧库项目列表：选中高亮、悬停、空态、新增/重命名/删除。
///
/// 顶部行为 `[设置] [＋ 添加]`：设置按钮（[onSettings]）在最左、添加按钮在右。
/// 对照 `docs/ui-spec.md` §3.2 与 §4.3 空态。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../tokens.dart';

/// 左侧库项目列表。
class LibraryList extends StatelessWidget {
  const LibraryList({
    super.key,
    required this.projects,
    required this.selectedIndex,
    required this.iconPaths,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onSettings,
    required this.onRefresh,
    required this.refreshing,
  });

  final List<PackProject> projects;
  final int? selectedIndex;

  /// 按 packageId 索引的库图标路径；缺失或 null 时显示默认 [Icons.package]。
  final Map<String, String?> iconPaths;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final void Function(int index) onRename;
  final void Function(int index) onDelete;

  /// 点击顶部设置按钮的回调（由 MainShell 打开设置对话框）。
  final VoidCallback onSettings;

  /// 点击某库项目行「刷新映射」按钮的回调（由 MainShell 重新扫描源目录并生成映射）。
  final void Function(int index) onRefresh;

  /// 是否有库项目正在刷新映射（用于在对应行展示处理中状态）。
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDims.libraryWidth,
      color: AppColors.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(child: projects.isEmpty ? _emptyState() : _list()),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      height: AppDims.logHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
      child: Row(
        children: [
          IconButton(
            onPressed: onSettings,
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined, size: 18),
            color: AppColors.textSemantic,
            iconSize: 18,
          ),
          const Spacer(),
          IconButton(
            onPressed: onAdd,
            tooltip: '添加库项目',
            icon: const Icon(Icons.add, size: 18),
            color: AppColors.textSemantic,
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.library_add_outlined,
            size: 36,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSpacing.s2),
          const Text(
            '尚未添加库项目',
            style: TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.body,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          TextButton(onPressed: onAdd, child: const Text('添加')),
        ],
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      itemCount: projects.length,
      itemBuilder: (context, index) {
        return _ProjectRow(
          project: projects[index],
          selected: index == selectedIndex,
          iconPath: iconPaths[projects[index].packageId],
          onTap: () => onSelect(index),
          onRename: () => onRename(index),
          onDelete: () => onDelete(index),
          onRefresh: () => onRefresh(index),
          refreshing: refreshing && index == selectedIndex,
        );
      },
    );
  }
}

class _ProjectRow extends StatefulWidget {
  const _ProjectRow({
    required this.project,
    required this.selected,
    required this.iconPath,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onRefresh,
    required this.refreshing,
  });

  final PackProject project;
  final bool selected;

  /// 库图标完整路径；null 或空表示未找到，显示默认 [Icons.package]。
  final String? iconPath;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// 点击「刷新映射」按钮的回调（仅选中项目时可用）。
  final VoidCallback onRefresh;

  /// 该行是否处于刷新映射处理中（显示加载指示）。
  final bool refreshing;

  @override
  State<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<_ProjectRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppColors.bgSel
        : (_hovered ? AppColors.bgHover : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 40,
          color: bg,
          child: Row(
            children: [
              Container(
                width: 2,
                color: widget.selected ? AppColors.accent : Colors.transparent,
              ),
              const SizedBox(width: AppSpacing.s2),
              _icon(),
              const SizedBox(width: AppSpacing.s1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.project.packageId.isEmpty
                          ? '（未命名）'
                          : widget.project.packageId,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.selected
                            ? AppColors.textOnDark
                            : AppColors.textPrimary,
                        fontSize: AppFontSizes.body,
                      ),
                    ),
                    Text(
                      widget.project.version,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.selected
                            ? AppColors.textOnDark
                            : AppColors.textSemantic,
                        fontSize: AppFontSizes.caption,
                      ),
                    ),
                  ],
                ),
              ),
              _refreshButton(),
              _menuButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// 「刷新映射」按钮：仅选中项目可用；刷新期间该行显示加载指示。
  Widget _refreshButton() {
    if (widget.refreshing) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      onPressed: widget.selected ? widget.onRefresh : null,
      tooltip: '刷新映射',
      icon: const Icon(Icons.refresh, size: 16),
      iconSize: 16,
      color: widget.selected ? AppColors.textSemantic : AppColors.textDisabled,
    );
  }

  /// 库项目图标：找到 icon.* 时用 [Image.file] 加载（含 ico，解码失败走兜底），
  /// 否则显示默认 [Icons.inventory_2]。
  Widget _icon() {
    final path = widget.iconPath;
    final fallback = const Icon(
      Icons.inventory_2,
      size: 24,
      color: AppColors.textSemantic,
    );
    if (path == null || path.trim().isEmpty) return fallback;
    return Image.file(
      File(path),
      width: 24,
      height: 24,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  Widget _menuButton() {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: Icon(
        Icons.more_vert,
        size: 16,
        color: widget.selected ? AppColors.textOnDark : AppColors.textSemantic,
      ),
      onSelected: (value) {
        if (value == 'rename') {
          widget.onRename();
        } else if (value == 'delete') {
          widget.onDelete();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuItem(value: 'delete', child: Text('删除库项目')),
      ],
    );
  }
}
