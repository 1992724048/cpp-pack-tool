import 'package:cpp_nuget_pack/packaging/script_packaging.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _labelColumnWidth = 120;

/// 导出前脚本校验警告。返回 true 表示继续导出，false 表示取消。
Future<bool> showPackagingIssuesDialog(
  BuildContext context, {
  required List<PackagingIssue> issues,
}) async {
  if (issues.isEmpty) {
    return true;
  }
  final bool? proceed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => ContentDialog(
      key: const Key('packagingIssuesDialog'),
      title: const Text('脚本校验'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('以下脚本或包内路径存在问题：'),
          const SizedBox(height: 12),
          _buildIssuesTable(dialogContext, issues),
          const SizedBox(height: 8),
          const Text('可继续导出，或取消返回修改。'),
        ],
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Button(
              key: const Key('packagingIssuesCancelButton'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('packagingIssuesContinueButton'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('继续导出'),
            ),
          ],
        ),
      ],
    ),
  );
  return proceed ?? false;
}

Widget _buildIssuesTable(BuildContext context, List<PackagingIssue> issues) {
  final FluentThemeData theme = FluentTheme.of(context);
  final DividerThemeData dividerTheme = theme.dividerTheme;
  final TextStyle style = TextStyle(
    fontSize: 12,
    color: theme.resources.textFillColorSecondary,
  );
  final Color valueColor = theme.resources.textFillColorSecondary;
  return FluentTheme(
    data: theme.copyWith(
      // 全局分割线自带 8px 水平边距，覆盖为 0 使线与表格内容同宽
      dividerTheme: DividerThemeData(
        decoration: dividerTheme.decoration,
        verticalMargin: dividerTheme.verticalMargin,
        horizontalMargin: EdgeInsets.zero,
      ),
    ),
    child: Column(
      key: const Key('packagingIssuesTable'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: _labelColumnWidth,
                child: Text('名称', style: style),
              ),
              Expanded(child: Text('问题', style: style)),
            ],
          ),
        ),
        const Divider(),
        for (int index = 0; index < issues.length; index++) ...[
          if (index > 0) const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _labelColumnWidth,
                  child: Text(
                    issues[index].label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    issues[index].message,
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
  );
}
