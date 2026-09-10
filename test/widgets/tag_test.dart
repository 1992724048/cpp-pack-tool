import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('深色背景使用白色文字', (tester) async {
    await _pumpTag(tester, const Tag(text: 'Release', color: _latteGreen));

    expect(_textColor(tester), Colors.white);
  });

  testWidgets('浅色背景使用深色文字', (tester) async {
    await _pumpTag(tester, const Tag(text: 'Release', color: _mochaGreen));

    expect(_textColor(tester), _darkText);
  });

  testWidgets('未指定背景色时使用强调色且正常渲染', (tester) async {
    await _pumpTag(tester, const Tag(text: 'v1.0.0'));

    expect(find.text('v1.0.0'), findsOneWidget);
    final Container container = tester.widget<Container>(
      find.descendant(of: find.byType(Tag), matching: find.byType(Container)),
    );
    expect((container.decoration as BoxDecoration?)?.color, UCColors.accent);
    expect(_textColor(tester), isNotNull);
  });
}

const Color _latteGreen = Color(0xFF40A02B);

const Color _mochaGreen = Color(0xFFA6E3A1);

const Color _darkText = Color(0xFF1E1E2E);

Future<void> _pumpTag(WidgetTester tester, Tag tag) async {
  await tester.pumpWidget(FluentApp(home: Center(child: tag)));
  await tester.pump();
}

Color? _textColor(WidgetTester tester) {
  final Text label = tester.widget<Text>(
    find.descendant(of: find.byType(Tag), matching: find.byType(Text)),
  );
  return label.style?.color;
}
