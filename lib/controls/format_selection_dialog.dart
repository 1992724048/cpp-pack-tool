import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _listHeight = 240;
const double _actionColumnWidth = 88;
const double _selectionColumnWidth = 240;

/// 「选择打包格式」对话框：左右双列表（未启用 / 已启用）多选调整。
///
/// 返回启用 id 列表（注册表序）；返回 `null` = 取消 / 关闭（调用方不应用
/// 任何变更，暂存语义）。初始化集合 = [enabledIds] ∩ [builders] 的 id。
Future<List<String>?> showFormatSelectionDialog(
  BuildContext context, {
  required List<PackageBuilder> builders,
  required List<String> enabledIds,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _FormatSelectionDialog(builders: builders, enabledIds: enabledIds),
  );
}

class _FormatSelectionDialog extends StatefulWidget {
  const _FormatSelectionDialog({
    required this.builders,
    required this.enabledIds,
  });

  final List<PackageBuilder> builders;
  final List<String> enabledIds;

  @override
  State<_FormatSelectionDialog> createState() => _FormatSelectionDialogState();
}

class _FormatSelectionDialogState extends State<_FormatSelectionDialog> {
  late final Set<String> _enabled;
  String? _disabledSelection;
  String? _enabledSelection;

  @override
  void initState() {
    super.initState();
    final Set<String> knownIds = <String>{
      for (final PackageBuilder builder in widget.builders) builder.id,
    };
    _enabled = <String>{
      for (final String id in widget.enabledIds)
        if (knownIds.contains(id)) id,
    };
  }

  List<PackageBuilder> get _disabledBuilders => <PackageBuilder>[
    for (final PackageBuilder builder in widget.builders)
      if (!_enabled.contains(builder.id)) builder,
  ];

  List<PackageBuilder> get _enabledBuilders => <PackageBuilder>[
    for (final PackageBuilder builder in widget.builders)
      if (_enabled.contains(builder.id)) builder,
  ];

  void _selectDisabled(String id) {
    setState(() {
      _disabledSelection = id;
      _enabledSelection = null;
    });
  }

  void _selectEnabled(String id) {
    setState(() {
      _enabledSelection = id;
      _disabledSelection = null;
    });
  }

  void _enableSelected() {
    final String? id = _disabledSelection;
    if (id == null) {
      return;
    }
    setState(() {
      _enabled.add(id);
      _enabledSelection = id;
      _disabledSelection = null;
    });
  }

  void _disableSelected() {
    final String? id = _enabledSelection;
    if (id == null) {
      return;
    }
    setState(() {
      _enabled.remove(id);
      _disabledSelection = id;
      _enabledSelection = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final TextStyle hintStyle = TextStyle(
      fontSize: 12,
      color: theme.resources.textFillColorSecondary,
    );
    return ContentDialog(
      key: const Key('formatSelectionDialog'),
      title: const Text('选择打包格式'),
      constraints: const BoxConstraints(maxWidth: 600),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('选择该包可用的打包格式；未启用的格式不会出现在「打包设置」中。', style: hintStyle),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _buildListColumn(
                  context,
                  title: '未启用',
                  listKey: const Key('formatDisabledList'),
                  builders: _disabledBuilders,
                  emptyText: '已启用全部格式',
                  itemKeySuffix: 'disabled',
                  isSelected: (String id) => _disabledSelection == id,
                  onSelected: _selectDisabled,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _actionColumnWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Button(
                        key: const Key('formatEnableButton'),
                        onPressed: _disabledSelection == null
                            ? null
                            : _enableSelected,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text('启用'),
                            SizedBox(width: 4),
                            Icon(FluentIcons.chevron_right, size: 12),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Button(
                        key: const Key('formatDisableButton'),
                        onPressed: _enabledSelection == null
                            ? null
                            : _disableSelected,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(FluentIcons.chevron_left, size: 12),
                            SizedBox(width: 4),
                            Text('移除'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildListColumn(
                  context,
                  title: '已启用',
                  listKey: const Key('formatEnabledList'),
                  builders: _enabledBuilders,
                  emptyText: '尚未启用任何格式',
                  itemKeySuffix: 'enabled',
                  isSelected: (String id) => _enabledSelection == id,
                  onSelected: _selectEnabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('至少需要启用一种格式。', style: hintStyle),
        ],
      ),
      actions: <Widget>[
        Button(
          key: const Key('formatSelectionCancelButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('formatSelectionConfirmButton'),
          onPressed: _enabledBuilders.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedIds()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<String> _selectedIds() => <String>[
    for (final PackageBuilder builder in widget.builders)
      if (_enabled.contains(builder.id)) builder.id,
  ];

  Widget _buildListColumn(
    BuildContext context, {
    required String title,
    required Key listKey,
    required List<PackageBuilder> builders,
    required String emptyText,
    required String itemKeySuffix,
    required bool Function(String id) isSelected,
    required ValueChanged<String> onSelected,
  }) {
    final FluentThemeData theme = FluentTheme.of(context);
    final TextStyle hintStyle = TextStyle(
      fontSize: 12,
      color: theme.resources.textFillColorSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: hintStyle),
        const SizedBox(height: 4),
        Container(
          key: listKey,
          height: _listHeight,
          width: _selectionColumnWidth,
          decoration: BoxDecoration(
            border: Border.all(color: theme.resources.cardStrokeColorDefault),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: builders.isEmpty
              ? Center(child: Text(emptyText, style: hintStyle))
              : ListView(
                  children: <Widget>[
                    for (final PackageBuilder builder in builders)
                      ListTile.selectable(
                        key: Key('formatItem_${builder.id}_$itemKeySuffix'),
                        title: Text(builder.displayName),
                        selected: isSelected(builder.id),
                        selectionMode: ListTileSelectionMode.single,
                        onSelectionChange: (bool value) {
                          if (value) {
                            onSelected(builder.id);
                          }
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
