import 'package:catppuccin_flutter/catppuccin_flutter.dart';
import 'package:cpp_nuget_pack/controls/script_editor/edge_painter.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pinStrokeColor 数据类型色（§2.2）', () {
    late Flavor previousFlavor;

    setUp(() {
      previousFlavor = UCColors.flavor;
    });

    tearDown(() {
      UCColors.flavor = previousFlavor;
    });

    test('number 为 flavor.green：latte #40A02B、mocha #A6E3A1', () {
      UCColors.flavor = catppuccin.latte;
      final Color latteNumber = pinStrokeColor(
        ScriptPinKind.data,
        ScriptDataType.number,
      );
      expect(latteNumber, UCColors.flavor.green);
      expect(latteNumber, const Color(0xFF40A02B));

      UCColors.flavor = catppuccin.mocha;
      final Color mochaNumber = pinStrokeColor(
        ScriptPinKind.data,
        ScriptDataType.number,
      );
      expect(mochaNumber, UCColors.flavor.green);
      expect(mochaNumber, const Color(0xFFA6E3A1));
    });
  });
}
