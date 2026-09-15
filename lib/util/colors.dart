import 'package:fluent_ui/fluent_ui.dart';

/// 应用主题入口：Fluent 默认配色（浅/深两族；系统跟随由 `FluentApp.themeMode` 提供）。
///
/// 资源字典、强调色与各控件主题全部走框架默认；不再保留任何全局可变配色，
/// 组件着色一律经 `FluentTheme.of(context)` 或 [AppColors] / [MarkerColors]。
FluentThemeData buildTheme(Brightness brightness) {
  return FluentThemeData(
    brightness: brightness,
    fontFamily: 'HarmonyOS_Sans_SC',
  );
}

/// 随明暗主题切换的语义色（WinUI `SystemFillColor{Success,Caution,Critical,Attention}` 口径）。
class AppColors {
  static Color success(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF6CCB5F)
      : const Color(0xFF0F7B0F);

  static Color caution(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFFCE100)
      : const Color(0xFF9D5D00);

  static Color critical(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFFF99A4)
      : const Color(0xFFC42B1C);

  static Color info(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFF60CDFF)
      : const Color(0xFF005FB8);

  static Color textPrimary(FluentThemeData theme) =>
      theme.resources.textFillColorPrimary;

  static Color textSecondary(FluentThemeData theme) =>
      theme.resources.textFillColorSecondary;

  static Color textTertiary(FluentThemeData theme) =>
      theme.resources.textFillColorTertiary;

  static Color textDisabled(FluentThemeData theme) =>
      theme.resources.textFillColorDisabled;

  static Color onAccent(FluentThemeData theme) =>
      theme.resources.textOnAccentFillColorPrimary;

  static Color card(FluentThemeData theme) =>
      theme.resources.cardBackgroundFillColorDefault;

  static Color cardSecondary(FluentThemeData theme) =>
      theme.resources.cardBackgroundFillColorSecondary;

  static Color layer(FluentThemeData theme) =>
      theme.resources.layerFillColorDefault;

  static Color stroke(FluentThemeData theme) =>
      theme.resources.cardStrokeColorDefault;

  static Color controlStroke(FluentThemeData theme) =>
      theme.resources.controlStrokeColorDefault;

  static Color hoverFill(FluentThemeData theme) =>
      theme.resources.controlFillColorSecondary;

  static Color pressedFill(FluentThemeData theme) =>
      theme.resources.controlFillColorTertiary;

  static Color neutralFill(FluentThemeData theme) =>
      theme.resources.controlStrongFillColorDefault;

  static Color accent(FluentThemeData theme) => theme.accentColor;
}

/// 固定标记色板：内容标识色（标签 / 类别 / 时间线类型），
/// 不随深浅主题切换、不参与主题定制；来源微软/Fluent 调色板。
class MarkerColors {
  static const Color blue = Color(0xFF0F6CBD);
  static const Color teal = Color(0xFF038387);
  static const Color green = Color(0xFF107C10);
  static const Color orange = Color(0xFFCA5010);
  static const Color red = Color(0xFFC50F1F);
  static const Color purple = Color(0xFF8764B8);
  static const Color magenta = Color(0xFFE3008C);
  static const Color gold = Color(0xFFC19C00);
  static const Color cyan = Color(0xFF0099BC);
  static const Color plum = Color(0xFF881798);
  static const Color indigo = Color(0xFF5B5FC7);
  static const Color coral = Color(0xFFEF6950);
  static const Color lavender = Color(0xFF8E8CD8);
}
