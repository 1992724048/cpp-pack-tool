import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// PowerToys SettingsGroup token：组标题 14 Semibold、上边距 32（首个 8）、
/// 卡容器上距 8、卡间距 2。
abstract final class SettingsGroupTokens {
  static const double headerSpacing = 32;
  static const double firstHeaderSpacing = 8;
  static const double containerSpacing = 8;
  static const double cardSpacing = 2;
  static const double headerFontSize = 14;
  static const double descriptionFontSize = 12;
}

/// 设置组：标题 + 可选描述 + 卡片列表（纵向、间距 2、Stretch）。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.header,
    this.description,
    this.first = false,
    this.children = const <Widget>[],
  });

  final String header;
  final Widget? description;

  /// 页面首个分组：上边距 8（其余 32）。
  final bool first;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final List<Widget> cards = <Widget>[
      for (var index = 0; index < children.length; index++)
        Padding(
          padding: EdgeInsets.only(
            top: index == 0 ? 0 : SettingsGroupTokens.cardSpacing,
          ),
          child: children[index],
        ),
    ];
    return Padding(
      padding: EdgeInsets.only(
        top: first
            ? SettingsGroupTokens.firstHeaderSpacing
            : SettingsGroupTokens.headerSpacing,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Text(
              header,
              style: TextStyle(
                fontSize: SettingsGroupTokens.headerFontSize,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(theme),
              ),
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: SettingsGroupTokens.descriptionFontSize,
                  color: AppColors.textSecondary(theme),
                ),
                child: description!,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(
              top: SettingsGroupTokens.containerSpacing,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cards,
            ),
          ),
        ],
      ),
    );
  }
}
