import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 被依赖方：依赖当前包的包名，以及其依赖所要求的版本范围。
typedef PackDependent = ({String name, String version});

const double _versionColumnWidth = 120;

Future<bool> showDeletePackDialog(
  BuildContext context, {
  required String packName,
  List<PackDependent> dependents = const <PackDependent>[],
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => ContentDialog(
      key: const Key('deletePackDialog'),
      title: const Text('删除包'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要删除包「$packName」吗？'),
          const SizedBox(height: 8),
          const Text('将移除其配置文件，此操作不可恢复；源目录中的文件不会被删除。'),
          if (dependents.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDependentsSection(dialogContext, dependents),
          ],
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
            Button(
              key: const Key('deletePackCancelButton'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
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
