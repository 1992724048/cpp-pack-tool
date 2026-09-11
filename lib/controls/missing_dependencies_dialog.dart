import 'package:cpp_nuget_pack/controls/delete_pack_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _versionColumnWidth = 120;

/// 打包前缺失依赖警告。返回 true 表示继续打包，false 表示取消。
Future<bool> showMissingDependenciesDialog(
  BuildContext context, {
  required List<PackDependent> missing,
}) async {
  final bool? proceed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => ContentDialog(
      key: const Key('missingDependenciesDialog'),
      title: const Text('缺失依赖'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('以下依赖在当前包列表中不存在：'),
          const SizedBox(height: 12),
          _buildMissingTable(dialogContext, missing),
          const SizedBox(height: 8),
          const Text('可继续打包，缺失依赖将原样写入包配置。'),
        ],
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Button(
              key: const Key('missingDependenciesCancelButton'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('missingDependenciesContinueButton'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('继续打包'),
            ),
          ],
        ),
      ],
    ),
  );
  return proceed ?? false;
}

Widget _buildMissingTable(BuildContext context, List<PackDependent> missing) {
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
      key: const Key('missingDependenciesTable'),
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
        for (int index = 0; index < missing.length; index++) ...[
          if (index > 0) const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    missing[index].name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: _versionColumnWidth,
                  child: Text(
                    missing[index].version,
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
