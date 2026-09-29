import 'package:fluent_ui/fluent_ui.dart';

FluentThemeData buildTheme(Brightness brightness) {
  return FluentThemeData(brightness: brightness, fontFamily: 'HarmonyOS_Sans_SC');
}

class AppColors {
  static Color success(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F);

  static Color caution(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFFFCE100) : const Color(0xFF9D5D00);

  static Color critical(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFFFF99A4) : const Color(0xFFC42B1C);

  static Color info(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF60CDFF) : const Color(0xFF005FB8);

  static Color textPrimary(FluentThemeData theme) => theme.resources.textFillColorPrimary;

  static Color textSecondary(FluentThemeData theme) => theme.resources.textFillColorSecondary;

  static Color textDisabled(FluentThemeData theme) => theme.resources.textFillColorDisabled;

  static Color card(FluentThemeData theme) => theme.resources.cardBackgroundFillColorDefault;

  static Color stroke(FluentThemeData theme) => theme.resources.cardStrokeColorDefault;

  static Color controlStroke(FluentThemeData theme) => theme.resources.controlStrokeColorDefault;

  static Color hoverFill(FluentThemeData theme) => theme.resources.controlFillColorSecondary;

  static Color pressedFill(FluentThemeData theme) => theme.resources.controlFillColorTertiary;
}

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
