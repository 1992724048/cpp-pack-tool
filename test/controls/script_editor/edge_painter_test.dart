import 'package:cpp_nuget_pack/controls/script_editor/edge_painter.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pinStrokeColor 数据类型色（§2.2）', () {
    test('data 类型为 MarkerColors 固定色板（不随明暗主题变化）', () {
      final FluentThemeData light = buildTheme(Brightness.light);
      final FluentThemeData dark = buildTheme(Brightness.dark);

      for (final ScriptDataType dataType in ScriptDataType.values) {
        expect(
          pinStrokeColor(ScriptPinKind.data, dataType, light),
          pinStrokeColor(ScriptPinKind.data, dataType, dark),
        );
      }
      expect(
        pinStrokeColor(ScriptPinKind.data, ScriptDataType.number, light),
        MarkerColors.green,
      );
      expect(
        pinStrokeColor(ScriptPinKind.data, ScriptDataType.string, light),
        MarkerColors.blue,
      );
      expect(
        pinStrokeColor(ScriptPinKind.data, ScriptDataType.boolean, light),
        MarkerColors.orange,
      );
      expect(
        pinStrokeColor(ScriptPinKind.data, ScriptDataType.listString, light),
        MarkerColors.purple,
      );
    });

    test('exec 与未知类型取主题 token 且明暗可区分', () {
      final FluentThemeData light = buildTheme(Brightness.light);
      final FluentThemeData dark = buildTheme(Brightness.dark);

      expect(
        pinStrokeColor(ScriptPinKind.exec, null, light),
        light.resources.textFillColorPrimary,
      );
      expect(
        pinStrokeColor(ScriptPinKind.exec, null, dark),
        dark.resources.textFillColorPrimary,
      );
      expect(
        pinStrokeColor(ScriptPinKind.data, null, light),
        light.resources.textFillColorDisabled,
      );
      expect(
        pinStrokeColor(ScriptPinKind.exec, null, light),
        isNot(pinStrokeColor(ScriptPinKind.exec, null, dark)),
      );
    });

    test('明暗主题切换触发连线重绘，同主题不重绘', () {
      final EdgePainter light = EdgePainter(
        theme: buildTheme(Brightness.light),
      );
      final EdgePainter dark = EdgePainter(theme: buildTheme(Brightness.dark));

      expect(dark.shouldRepaint(light), isTrue);
      expect(light.shouldRepaint(light), isFalse);
    });
  });
}
