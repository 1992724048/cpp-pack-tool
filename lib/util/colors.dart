import 'package:catppuccin_flutter/catppuccin_flutter.dart';
import 'package:fluent_ui/fluent_ui.dart';

class UCColors {
  static Flavor flavor = catppuccin.latte;
  static Color accent = flavor.teal;
}

const List<String> darkFlavorNames = ['frappe', 'macchiato', 'mocha'];

const List<String> accentColorNames = [
  'rosewater',
  'flamingo',
  'pink',
  'mauve',
  'red',
  'maroon',
  'peach',
  'yellow',
  'green',
  'teal',
  'sky',
  'sapphire',
  'blue',
  'lavender',
];

Flavor flavorByName(String name) {
  return switch (name) {
    'latte' => catppuccin.latte,
    'frappe' => catppuccin.frappe,
    'macchiato' => catppuccin.macchiato,
    'mocha' => catppuccin.mocha,
    _ => catppuccin.mocha,
  };
}

Color accentColorFor(Flavor flavor, String name) {
  return switch (name) {
    'rosewater' => flavor.rosewater,
    'flamingo' => flavor.flamingo,
    'pink' => flavor.pink,
    'mauve' => flavor.mauve,
    'red' => flavor.red,
    'maroon' => flavor.maroon,
    'peach' => flavor.peach,
    'yellow' => flavor.yellow,
    'green' => flavor.green,
    'teal' => flavor.teal,
    'sky' => flavor.sky,
    'sapphire' => flavor.sapphire,
    'blue' => flavor.blue,
    'lavender' => flavor.lavender,
    _ => flavor.teal,
  };
}

FluentThemeData buildTheme(
  Brightness brightness,
  Flavor flavor,
  String accentName,
) {
  final bool isLight = brightness == Brightness.light;

  UCColors.flavor = flavor;
  UCColors.accent = accentColorFor(flavor, accentName);

  final accent = UCColors.accent;

  final Color text = flavor.text;
  final Color subtext = flavor.subtext1;

  return FluentThemeData(
    // 基础
    brightness: brightness,
    fontFamily: 'HarmonyOS_Sans_SC',
    typography: Typography.fromBrightness(brightness: brightness, color: text),
    resources: _catppuccinResources(flavor, brightness),

    // 强调色
    accentColor: AccentColor('normal', {
      'normal': accent,
      'dark': _shade(accent, -0.08),
      'darker': _shade(accent, -0.16),
      'light': _shade(accent, 0.08),
      'lighter': _shade(accent, 0.16),
    }),
    activeColor: flavor.crust,
    // 强调色之上的前景（勾号、文字）
    inactiveColor: subtext,
    inactiveBackgroundColor: flavor.surface1,

    // 背景层次
    scaffoldBackgroundColor: flavor.mantle,
    micaBackgroundColor: flavor.mantle,
    acrylicBackgroundColor: flavor.base,
    cardColor: flavor.surface0,
    menuColor: flavor.surface0,

    // 阴影与选中
    shadowColor: isLight ? const Color(0x40000000) : flavor.crust,
    selectionColor: accent.withValues(alpha: 0.35),

    // 图标
    iconTheme: IconThemeData(color: text, size: 18),

    // 按钮
    buttonTheme: ButtonThemeData(
      defaultButtonStyle: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? flavor.subtext0 : text,
        ),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return flavor.surface0;
          if (s.contains(WidgetState.pressed)) return flavor.surface2;
          if (s.contains(WidgetState.hovered)) return flavor.surface1;
          return flavor.surface0;
        }),
      ),
      filledButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return flavor.surface0;
          if (s.contains(WidgetState.pressed)) return _shade(accent, -0.16);
          if (s.contains(WidgetState.hovered)) return _shade(accent, -0.08);
          return accent;
        }),
        foregroundColor: WidgetStateProperty.all(flavor.crust),
      ),
    ),

    // 分割线
    dividerTheme: DividerThemeData(
      decoration: BoxDecoration(color: flavor.surface2),
      verticalMargin: const EdgeInsets.symmetric(vertical: 8),
      horizontalMargin: const EdgeInsets.symmetric(horizontal: 8),
    ),

    // 焦点框
    focusTheme: FocusThemeData(
      primaryBorder: BorderSide(color: accent, width: 1.5),
      secondaryBorder: BorderSide(
        color: accent.withValues(alpha: 0.5),
        width: 1,
      ),
      glowColor: accent.withValues(alpha: 0.2),
      glowFactor: 2.0,
    ),

    // 复选框
    checkboxTheme: CheckboxThemeData(
      checkedDecoration: WidgetStateProperty.all(
        BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
      ),
      uncheckedDecoration: WidgetStateProperty.all(
        BoxDecoration(
          color: flavor.surface0,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: flavor.overlay1),
        ),
      ),
      thirdstateDecoration: WidgetStateProperty.all(
        BoxDecoration(
          color: flavor.surface2,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: flavor.overlay1),
        ),
      ),
      checkedIconColor: WidgetStateProperty.all(flavor.crust),
      uncheckedIconColor: WidgetStateProperty.all(text),
      thirdstateIconColor: WidgetStateProperty.all(subtext),
    ),

    // 单选框
    radioButtonTheme: RadioButtonThemeData(
      checkedDecoration: WidgetStateProperty.all(
        BoxDecoration(color: accent, shape: BoxShape.circle),
      ),
      uncheckedDecoration: WidgetStateProperty.all(
        BoxDecoration(
          color: flavor.surface0,
          shape: BoxShape.circle,
          border: Border.all(color: flavor.overlay1),
        ),
      ),
      foregroundColor: WidgetStateProperty.all(text),
    ),

    // 切换开关
    toggleSwitchTheme: ToggleSwitchThemeData(
      checkedDecoration: WidgetStateProperty.all(
        BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20)),
      ),
      uncheckedDecoration: WidgetStateProperty.all(
        BoxDecoration(
          color: flavor.surface2,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      checkedKnobDecoration: WidgetStateProperty.all(
        BoxDecoration(color: flavor.crust, shape: BoxShape.circle),
      ),
      uncheckedKnobDecoration: WidgetStateProperty.all(
        BoxDecoration(color: text, shape: BoxShape.circle),
      ),
    ),

    // 切换按钮
    toggleButtonTheme: ToggleButtonThemeData(
      checkedButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(accent),
        foregroundColor: WidgetStateProperty.all(flavor.crust),
      ),
      uncheckedButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(flavor.surface0),
        foregroundColor: WidgetStateProperty.all(text),
      ),
    ),

    // 滑块
    sliderTheme: SliderThemeData(
      thumbColor: WidgetStateProperty.all(text),
      activeColor: WidgetStateProperty.all(accent),
      inactiveColor: WidgetStateProperty.all(flavor.surface2),
      labelBackgroundColor: accent,
      labelForegroundColor: flavor.crust,
    ),

    // 滚动条
    scrollbarTheme: ScrollbarThemeData(
      backgroundColor: Colors.transparent,
      scrollbarColor: flavor.overlay0,
      scrollbarPressingColor: flavor.overlay2,
      trackBorderColor: Colors.transparent,
      hoveringTrackBorderColor: flavor.overlay0,
      radius: const Radius.circular(4),
      hoveringRadius: const Radius.circular(4),
    ),

    // 导航面板
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor: flavor.crust,
      overlayBackgroundColor: flavor.mantle,
      highlightColor: accent,
      tileColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) return flavor.surface2;
        if (s.contains(WidgetState.hovered)) return flavor.surface0;
        return Colors.transparent;
      }),
      selectedTextStyle: WidgetStateProperty.all(
        TextStyle(color: text, fontFamily: "HarmonyOS_Sans_SC"),
      ),
      unselectedTextStyle: WidgetStateProperty.all(
        TextStyle(color: subtext, fontFamily: "HarmonyOS_Sans_SC"),
      ),
      selectedIconColor: WidgetStateProperty.all(text),
      unselectedIconColor: WidgetStateProperty.all(subtext),
    ),

    // 内容对话框
    dialogTheme: ContentDialogThemeData(
      decoration: BoxDecoration(
        color: flavor.surface1,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: isLight ? const Color(0x40000000) : flavor.crust,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      barrierColor: flavor.crust.withValues(alpha: 0.5),
      titleStyle: TextStyle(
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      bodyStyle: TextStyle(color: subtext, fontFamily: "HarmonyOS_Sans_SC"),
    ),

    // 工具提示
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: flavor.overlay2,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: flavor.base, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}

Color _shade(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

/// Catppuccin 版 ResourceDictionary：
/// 同时覆盖 TabView 标签条、输入框、Flyout、InfoBar 等所有 WinUI 控件的基础色
ResourceDictionary _catppuccinResources(Flavor f, Brightness brightness) {
  return (brightness == Brightness.light
      ? ResourceDictionary.light
      : ResourceDictionary.dark)(
    // ── 文字（TabView 标签文字走这里）
    textFillColorPrimary: f.text,
    // 选中标签
    textFillColorSecondary: f.subtext1,
    // 未选中标签
    textFillColorTertiary: f.subtext0,
    // 按下
    textFillColorDisabled: f.overlay1,
    textFillColorInverse: f.crust,
    accentTextFillColorDisabled: f.overlay1,
    textOnAccentFillColorSelectedText: f.crust,
    textOnAccentFillColorPrimary: f.crust,
    textOnAccentFillColorSecondary: f.subtext0,
    textOnAccentFillColorDisabled: f.overlay1,

    // ── 控件填充（输入框、下拉、按钮底）
    controlFillColorDefault: f.surface0,
    controlFillColorSecondary: f.surface1,
    controlFillColorTertiary: f.surface2,
    controlFillColorQuarternary: f.surface2,
    controlFillColorDisabled: f.surface0,
    controlFillColorInputActive: f.mantle,
    controlStrongFillColorDefault: f.overlay1,
    controlStrongFillColorDisabled: f.overlay0,
    controlSolidFillColorDefault: f.surface1,
    controlAltFillColorSecondary: f.surface1,
    controlAltFillColorTertiary: f.surface2,
    controlAltFillColorQuarternary: f.overlay0,
    controlAltFillColorDisabled: f.surface0,
    controlOnImageFillColorDefault: f.surface1,
    controlOnImageFillColorSecondary: f.surface2,
    controlOnImageFillColorTertiary: f.surface2,
    controlOnImageFillColorDisabled: f.surface0,

    // ── 悬停/按下水纹（未选中标签悬停走 subtleFill）
    subtleFillColorTransparent: Colors.transparent,
    subtleFillColorSecondary: f.overlay0.withValues(alpha: 0.6),
    subtleFillColorTertiary: f.overlay0.withValues(alpha: 0.8),
    subtleFillColorDisabled: Colors.transparent,

    // ── 描边
    /*    controlStrokeColorDefault: f.overlay0,
    controlStrokeColorSecondary: f.overlay1,
    controlStrokeColorOnAccentDefault: f.crust.withOpacity(0.3),
    controlStrokeColorOnAccentSecondary: f.crust,
    controlStrokeColorOnAccentTertiary: f.crust,
    controlStrokeColorOnAccentDisabled: f.overlay1,
    cardStrokeColorDefault: f.overlay0,
    cardStrokeColorDefaultSolid: f.surface2,
    controlStrongStrokeColorDefault: f.overlay1,
    controlStrongStrokeColorDisabled: f.overlay0,
    dividerStrokeColorDefault: f.surface2,*/

    // 标签间分割线
    focusStrokeColorOuter: f.text,
    focusStrokeColorInner: f.crust,

    // ── 卡片与背景层次
    cardBackgroundFillColorDefault: f.surface0,
    cardBackgroundFillColorSecondary: f.surface1,
    cardBackgroundFillColorTertiary: f.surface2,
    solidBackgroundFillColorBase: f.mantle,
    solidBackgroundFillColorSecondary: f.mantle,
    solidBackgroundFillColorTertiary: f.surface0,

    // ← 选中标签背景
    solidBackgroundFillColorQuarternary: f.surface1,
    solidBackgroundFillColorQuinary: f.surface1,
    solidBackgroundFillColorSenary: f.surface2,
    solidBackgroundFillColorBaseAlt: f.crust,
    layerFillColorDefault: f.surface1,
    layerFillColorAlt: f.surface0,
    layerOnAcrylicFillColorDefault: f.base,
    layerOnMicaBaseAltFillColorDefault: f.surface1,
    layerOnMicaBaseAltFillColorSecondary: f.surface2,
    layerOnMicaBaseAltFillColorTertiary: f.surface0,
    smokeFillColorDefault: f.crust.withValues(alpha: 0.5),

    // ── 系统语义色（InfoBar 成功/警告/错误等）
    systemFillColorSuccess: f.green,
    systemFillColorCaution: f.yellow,
    systemFillColorCritical: f.red,
    systemFillColorNeutral: f.subtext0,
    systemFillColorSolidNeutral: f.overlay2,
    systemFillColorSuccessBackground: f.green.withValues(alpha: 0.15),
    systemFillColorCautionBackground: f.yellow.withValues(alpha: 0.15),
    systemFillColorCriticalBackground: f.red.withValues(alpha: 0.15),
    systemFillColorNeutralBackground: f.surface1,
    systemFillColorAttentionBackground: f.surface1,
    systemFillColorSolidAttentionBackground: f.surface1,
    systemFillColorSolidNeutralBackground: f.surface1,
  );
}
