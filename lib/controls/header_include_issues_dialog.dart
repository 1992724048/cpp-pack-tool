import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _labelColumnWidth = 220;

/// 构建后 `#include` 引用的高置信待处理问题列表；仅关闭，不阻断流程。
Future<void> showHeaderIncludeIssuesDialog(
  BuildContext context, {
  required HeaderIncludeFixReport report,
}) async {
  if (!report.hasIssues) {
    return;
  }
  final List<HeaderIncludeIssue> issues = report.issues;
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => ContentDialog(
      key: const Key('headerIncludeIssuesDialog'),
      title: const Text('头文件引用检查'),
      constraints: const BoxConstraints(maxWidth: 560),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('以下源码引用未自动修复，打包后可能失效：'),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: _buildIssuesTable(dialogContext, issues),
            ),
          ),
          const SizedBox(height: 8),
          const Text('条件外部依赖（如第三方库头文件）不在检查范围；可手动调整源码后重新构建。'),
        ],
      ),
      actions: [
        Button(
          key: const Key('headerIncludeIssuesCloseButton'),
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Widget _buildIssuesTable(
  BuildContext context,
  List<HeaderIncludeIssue> issues,
) {
  final FluentThemeData theme = FluentTheme.of(context);
  final DividerThemeData dividerTheme = theme.dividerTheme;
  final TextStyle style = TextStyle(
    fontSize: 12,
    color: theme.resources.textFillColorSecondary,
  );
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
      key: const Key('headerIncludeIssuesTable'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: _labelColumnWidth,
                child: Text('位置', style: style),
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
                    '${issues[index].filePath}:${issues[index].line}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    '"${issues[index].include}"：${issues[index].description}',
                    overflow: TextOverflow.ellipsis,
                    style: style,
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
