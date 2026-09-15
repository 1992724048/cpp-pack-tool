import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// PowerToys SettingsPageControl token：标题 28 Semibold、模块描述 14 Secondary、
/// 内容最大宽 1000、水平内边距 16、底部滚动留白 48。
abstract final class SettingsPageTokens {
  static const double titleFontSize = 28;
  static const double descriptionFontSize = 14;
  static const double contentMaxWidth = 1000;
  static const double horizontalPadding = 16;
  static const double bottomPadding = 48;
  static const double descriptionSpacing = 8;
  static const double contentSpacing = 24;
}

/// 设置页模板：标题 → 模块描述 → 内容（左对齐、最大宽 1000、可滚动）。
///
/// 页面背景沿用 `cardColor`，与 Tab 页保持一致；底部留白 48。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    this.description,
    this.children = const <Widget>[],
    this.contentMaxWidth = SettingsPageTokens.contentMaxWidth,
  });

  final String title;
  final Widget? description;
  final List<Widget> children;
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(color: theme.cardColor),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            SettingsPageTokens.horizontalPadding,
            0,
            SettingsPageTokens.horizontalPadding,
            SettingsPageTokens.bottomPadding,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: SettingsPageTokens.horizontalPadding,
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: SettingsPageTokens.titleFontSize,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(theme),
                      ),
                    ),
                  ),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: SettingsPageTokens.descriptionSpacing,
                      ),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: SettingsPageTokens.descriptionFontSize,
                          color: AppColors.textSecondary(theme),
                        ),
                        child: description!,
                      ),
                    ),
                  const SizedBox(height: SettingsPageTokens.contentSpacing),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
