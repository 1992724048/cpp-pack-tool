import 'package:cpp_nuget_pack/controls/license_field.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _comboKey = Key('testLicenseField');
const Key _customKey = Key('testLicenseCustomField');
const Key _errorKey = Key('testLicenseCustomError');

void main() {
  testWidgets('无值时显示「无」且不显示自定义文本框', (tester) async {
    await _pumpField(tester, value: null);

    expect(_comboValue(tester), isNull);
    expect(find.byKey(_customKey), findsNothing);
  });

  testWidgets('预设 SPDX 值直接显示，切换后发射新值与可提交标记', (tester) async {
    final List<(String?, bool)> emissions = <(String?, bool)>[];
    await _pumpField(
      tester,
      value: 'MIT',
      onChanged: (String? license, bool isValid) =>
          emissions.add((license, isValid)),
    );

    expect(_comboValue(tester), 'MIT');

    await _selectCombo(tester, 'Apache-2.0');

    expect(emissions, <(String?, bool)>[('Apache-2.0', true)]);
  });

  testWidgets('选择「自定义…」显示文本框，输入后发射自定义值', (tester) async {
    final List<(String?, bool)> emissions = <(String?, bool)>[];
    await _pumpField(
      tester,
      value: null,
      onChanged: (String? license, bool isValid) =>
          emissions.add((license, isValid)),
    );

    await _selectCombo(tester, customLicenseEntry);

    expect(_comboValue(tester), customLicenseEntry);
    expect(find.byKey(_customKey), findsOneWidget);
    expect(emissions, <(String?, bool)>[(null, false)]);

    await tester.enterText(find.byKey(_customKey), 'MyLicense');
    await tester.pump();

    expect(emissions.last, ('MyLicense', true));
    expect(find.textContaining('建议使用 SPDX 标识符'), findsOneWidget);
    expect(find.text('请输入自定义许可证'), findsNothing);
  });

  testWidgets('自定义文本为空时显示红色错误且不可提交', (tester) async {
    final List<(String?, bool)> emissions = <(String?, bool)>[];
    await _pumpField(
      tester,
      value: null,
      onChanged: (String? license, bool isValid) =>
          emissions.add((license, isValid)),
    );

    await _selectCombo(tester, customLicenseEntry);
    await tester.enterText(find.byKey(_customKey), '   ');
    await tester.pump();

    final Text error = tester.widget<Text>(find.byKey(_errorKey));
    expect(error.data, '请输入自定义许可证');
    expect(error.style?.color, isNotNull);
    expect(emissions.last, (null, false));
  });

  testWidgets('切回预设保留已输入文本，再选自定义时恢复', (tester) async {
    await _pumpField(tester, value: null);

    await _selectCombo(tester, customLicenseEntry);
    await tester.enterText(find.byKey(_customKey), 'MyLicense');
    await tester.pump();

    await _selectCombo(tester, 'MIT');
    expect(find.byKey(_customKey), findsNothing);

    await _selectCombo(tester, customLicenseEntry);
    expect(
      tester.widget<TextBox>(find.byKey(_customKey)).controller?.text,
      'MyLicense',
    );
  });

  testWidgets('外部回显为自定义值时进入自定义模式并预填文本', (tester) async {
    await _pumpField(tester, value: 'MIT');

    await _pumpField(tester, value: 'Custom-1.0');

    expect(_comboValue(tester), customLicenseEntry);
    expect(
      tester.widget<TextBox>(find.byKey(_customKey)).controller?.text,
      'Custom-1.0',
    );
  });

  testWidgets('外部回显为 SPDX 值时退出自定义模式', (tester) async {
    await _pumpField(tester, value: 'Custom-1.0');
    expect(find.byKey(_customKey), findsOneWidget);

    await _pumpField(tester, value: 'GPL-3.0');

    expect(_comboValue(tester), 'GPL-3.0');
    expect(find.byKey(_customKey), findsNothing);
  });
}

String? _comboValue(WidgetTester tester) =>
    tester.widget<ComboBox<String?>>(find.byKey(_comboKey)).value;

Future<void> _selectCombo(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(_comboKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpField(
  WidgetTester tester, {
  required String? value,
  void Function(String? license, bool isValid)? onChanged,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Center(
        child: SizedBox(
          width: 320,
          child: LicenseField(
            value: value,
            comboBoxKey: _comboKey,
            customFieldKey: _customKey,
            errorKey: _errorKey,
            onChanged: onChanged ?? (String? license, bool isValid) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
