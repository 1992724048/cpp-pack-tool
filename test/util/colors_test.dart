import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildTheme', () {
    test('仅按 brightness 构建，字体族保留 HarmonyOS_Sans_SC', () {
      final FluentThemeData light = buildTheme(Brightness.light);
      final FluentThemeData dark = buildTheme(Brightness.dark);

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.typography.body?.fontFamily, 'HarmonyOS_Sans_SC');
      expect(dark.typography.body?.fontFamily, 'HarmonyOS_Sans_SC');
      expect(light.typography.caption?.fontFamily, 'HarmonyOS_Sans_SC');
    });

    test('明暗两族主题的资源随框架默认（非全局共享）', () {
      final FluentThemeData light = buildTheme(Brightness.light);
      final FluentThemeData dark = buildTheme(Brightness.dark);

      expect(
        light.resources.textFillColorPrimary,
        isNot(dark.resources.textFillColorPrimary),
      );
      expect(
        light.resources.cardBackgroundFillColorDefault,
        isNot(dark.resources.cardBackgroundFillColorDefault),
      );
    });
  });

  group('AppColors', () {
    test('四个系统语义色含明暗变体', () {
      for (final Color Function(Brightness) variant in <Color Function(Brightness)>[
        AppColors.success,
        AppColors.caution,
        AppColors.critical,
        AppColors.info,
      ]) {
        expect(variant(Brightness.light), isNot(variant(Brightness.dark)));
      }
    });

    test('语义色取 Fluent 主题 token', () {
      final FluentThemeData theme = buildTheme(Brightness.light);
      expect(AppColors.textPrimary(theme), theme.resources.textFillColorPrimary);
      expect(AppColors.textSecondary(theme), theme.resources.textFillColorSecondary);
      expect(AppColors.accent(theme), theme.accentColor);
      expect(AppColors.card(theme), theme.resources.cardBackgroundFillColorDefault);
    });

    test('浅色状态色在浅色底上对比度 ≥ 4.5:1', () {
      final FluentThemeData theme = buildTheme(Brightness.light);
      final Color surface = _flatten(
        theme.resources.solidBackgroundFillColorBase,
        const Color(0xFFFFFFFF),
      );
      for (final Color color in <Color>[
        AppColors.success(Brightness.light),
        AppColors.caution(Brightness.light),
        AppColors.critical(Brightness.light),
        AppColors.info(Brightness.light),
      ]) {
        expect(
          _contrastRatio(_flatten(color, surface), surface),
          greaterThanOrEqualTo(4.5),
          reason: '状态色 $color 在浅色底对比度不足',
        );
      }
    });

    test('深色状态色在深色底上对比度 ≥ 4.5:1', () {
      final FluentThemeData theme = buildTheme(Brightness.dark);
      final Color surface = _flatten(
        theme.resources.solidBackgroundFillColorBase,
        const Color(0xFF202020),
      );
      for (final Color color in <Color>[
        AppColors.success(Brightness.dark),
        AppColors.caution(Brightness.dark),
        AppColors.critical(Brightness.dark),
        AppColors.info(Brightness.dark),
      ]) {
        expect(
          _contrastRatio(_flatten(color, surface), surface),
          greaterThanOrEqualTo(4.5),
          reason: '状态色 $color 在深色底对比度不足',
        );
      }
    });

    test('浅色正文色在白底上对比度 ≥ 4.5:1', () {
      final FluentThemeData theme = buildTheme(Brightness.light);
      final Color surface = _flatten(
        theme.resources.cardBackgroundFillColorDefault,
        const Color(0xFFF3F3F3),
      );
      final Color text = _flatten(
        theme.resources.textFillColorPrimary,
        surface,
      );
      expect(_contrastRatio(text, surface), greaterThanOrEqualTo(4.5));
    });
  });

  group('MarkerColors', () {
    test('固定标记色板为 13 色且不随主题变化', () {
      expect(MarkerColors.blue, const Color(0xFF0F6CBD));
      expect(MarkerColors.teal, const Color(0xFF038387));
      expect(MarkerColors.green, const Color(0xFF107C10));
      expect(MarkerColors.orange, const Color(0xFFCA5010));
      expect(MarkerColors.red, const Color(0xFFC50F1F));
      expect(MarkerColors.purple, const Color(0xFF8764B8));
      expect(MarkerColors.magenta, const Color(0xFFE3008C));
      expect(MarkerColors.gold, const Color(0xFFC19C00));
      expect(MarkerColors.cyan, const Color(0xFF0099BC));
      expect(MarkerColors.plum, const Color(0xFF881798));
      expect(MarkerColors.indigo, const Color(0xFF5B5FC7));
      expect(MarkerColors.coral, const Color(0xFFEF6950));
      expect(MarkerColors.lavender, const Color(0xFF8E8CD8));
    });
  });
}

/// 把 [color]（含透明度）合成到不透明底色 [background] 上，返回不透明色。
Color _flatten(Color color, Color background) {
  final double alpha = color.a;
  if (alpha >= 1.0) {
    return color;
  }
  final double red = color.r * alpha + background.r * (1 - alpha);
  final double green = color.g * alpha + background.g * (1 - alpha);
  final double blue = color.b * alpha + background.b * (1 - alpha);
  return Color.from(alpha: 1.0, red: red, green: green, blue: blue);
}

/// WCAG 2.x 相对亮度对比度（不透明色）。
double _contrastRatio(Color first, Color second) {
  final double lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final double darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}
