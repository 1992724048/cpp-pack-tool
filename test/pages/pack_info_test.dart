import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/pages/pack_info.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('只读展示包的字段', (tester) async {
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.2.3',
      author: '张三',
      description: '示例描述',
      license: 'MIT',
    );

    await _pumpPage(tester, PackInfo(pack: pack));

    expect(find.text('demo'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('MIT'), findsOneWidget);
    expect(find.text('示例描述'), findsOneWidget);

    final Iterable<TextBox> boxes = tester.widgetList<TextBox>(
      find.byType(TextBox),
    );
    expect(boxes, isNotEmpty);
    expect(boxes.every((TextBox box) => box.readOnly), isTrue);
  });

  testWidgets('许可证与描述为空时显示占位', (tester) async {
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
    );

    await _pumpPage(tester, PackInfo(pack: pack));

    expect(find.text('无'), findsNWidgets(2));
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(home: page));
  await tester.pump();
}
