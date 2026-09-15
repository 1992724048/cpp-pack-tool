import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 被依赖方：依赖当前包的包名，以及其依赖所要求的版本范围。
typedef PackDependent = ({String name, String version});

/// 删除对话框结果：是否确认删除、是否同时删除构建缓存。
typedef DeletePackResult = ({bool confirmed, bool deleteCache});

const double _versionColumnWidth = 120;

Future<DeletePackResult> showDeletePackDialog(
  BuildContext context, {
  required String packName,
  List<PackDependent> dependents = const <PackDependent>[],
  bool hasBuildCache = false,
}) async {
  final DeletePackResult? result = await showDialog<DeletePackResult>(
    context: context,
    builder: (BuildContext dialogContext) => _DeletePackDialog(
      packName: packName,
      dependents: dependents,
      hasBuildCache: hasBuildCache,
    ),
  );
  return result ?? (confirmed: false, deleteCache: false);
}

class _DeletePackDialog extends StatefulWidget {
  const _DeletePackDialog({
    required this.packName,
    required this.dependents,
    required this.hasBuildCache,
  });

  final String packName;
  final List<PackDependent> dependents;
  final bool hasBuildCache;

  @override
  State<_DeletePackDialog> createState() => _DeletePackDialogState();
}

class _DeletePackDialogState extends State<_DeletePackDialog> {
  bool _deleteCache = false;
  bool _cacheRowHovered = false;

  void _toggleDeleteCache() {
    if (!widget.hasBuildCache) {
      return;
    }
    setState(() => _deleteCache = !_deleteCache);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return ContentDialog(
      key: const Key('deletePackDialog'),
      title: const Text('删除包'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要删除包「${widget.packName}」吗？'),
          const SizedBox(height: 8),
          const Text('将移除其配置文件，此操作不可恢复；源目录中的文件不会被删除。'),
          if (widget.dependents.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDependentsSection(context, widget.dependents),
          ],
          const SizedBox(height: 12),
          _buildCacheSection(theme),
        ],
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FilledButton(
              key: const Key('deletePackConfirmButton'),
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(UCColors.flavor.red),
                foregroundColor: WidgetStatePropertyAll(Colors.white),
              ),
              onPressed: () => Navigator.pop(context, (
                confirmed: true,
                deleteCache: _deleteCache,
              )),
              child: const Text('删除'),
            ),
            Button(
              key: const Key('deletePackCancelButton'),
              onPressed: () => Navigator.pop(context, (
                confirmed: false,
                deleteCache: false,
              )),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCacheSection(FluentThemeData theme) {
    final String hint = widget.hasBuildCache
        ? '将删除 cache/build/${PackStore.sanitizeFileName(widget.packName)}'
              '（下次构建需重新拉取源码）。'
        : '未发现该包的构建缓存。';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: widget.hasBuildCache
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onEnter: (_) => setState(() => _cacheRowHovered = true),
          onExit: (_) => setState(() => _cacheRowHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleDeleteCache,
            child: Container(
              constraints: const BoxConstraints(minHeight: 32),
              decoration: BoxDecoration(
                color: _cacheRowHovered
                    ? UCColors.flavor.surface0
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: <Widget>[
                  Checkbox(
                    key: const Key('deletePackCacheCheckbox'),
                    checked: _deleteCache,
                    onChanged: widget.hasBuildCache
                        ? (bool? _) => _toggleDeleteCache()
                        : null,
                  ),
                  const SizedBox(width: 8),
                  const Text('同时删除构建缓存'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          key: const Key('deletePackCacheHint'),
          style: TextStyle(
            fontSize: 12,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
      ],
    );
  }
}

Widget _buildDependentsSection(
  BuildContext context,
  List<PackDependent> dependents,
) {
  final FluentThemeData theme = FluentTheme.of(context);
  final DividerThemeData dividerTheme = theme.dividerTheme;
  final TextStyle style = TextStyle(
    fontSize: 12,
    color: theme.resources.textFillColorSecondary,
  );
  final Color valueColor = theme.resources.textFillColorSecondary;
  return Column(
    key: const Key('deletePackDependents'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('以下包依赖它：', style: TextStyle(color: UCColors.flavor.red)),
      const SizedBox(height: 6),
      FluentTheme(
        data: theme.copyWith(
          // 全局分割线自带 8px 水平边距，覆盖为 0 使线与表格内容同宽
          dividerTheme: DividerThemeData(
            decoration: dividerTheme.decoration,
            verticalMargin: dividerTheme.verticalMargin,
            horizontalMargin: EdgeInsets.zero,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text('包名', style: style)),
                  SizedBox(
                    width: _versionColumnWidth,
                    child: Text('版本范围', style: style),
                  ),
                ],
              ),
            ),
            const Divider(),
            for (int index = 0; index < dependents.length; index++) ...[
              if (index > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dependents[index].name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: _versionColumnWidth,
                      child: Text(
                        dependents[index].version,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: valueColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Text('删除后这些依赖将显示为「缺失」。'),
    ],
  );
}
