import 'package:cpp_nuget_pack/pack/ui/pack_manage.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('切换页签再返回后保留包信息未保存编辑态', (tester) async {
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.2.3',
      author: '张三',
      description: '示例描述',
      license: 'MIT',
    );

    await _pumpPackManage(tester, pack);

    await tester.tap(find.byKey(const Key('packInfoEditButton')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '9.9.9',
    );
    await tester.pump();
    expect(find.byKey(const Key('packInfoCancelButton')), findsOneWidget);

    await _selectTab(tester, '文件管理');
    expect(find.text('该包暂无文件'), findsOneWidget);

    await _selectTab(tester, '包信息');
    final TextBox versionField = tester.widget<TextBox>(
      find.byKey(const Key('packInfoVersionField')),
    );
    expect(versionField.controller!.text, '9.9.9');
    expect(versionField.readOnly, isFalse);
    expect(find.byKey(const Key('packInfoCancelButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoEditButton')), findsNothing);
  });
}

Future<void> _pumpPackManage(WidgetTester tester, PackModel pack) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: PackManage(
        pack: pack,
        allPacks: <PackModel>[pack],
        onSave: (_) async => false,
        pickDirectory: () async => null,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
