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

  testWidgets('未指定 maxWidth 与 tooltip 时保持默认渲染', (tester) async {
    await _pumpTag(tester, const Tag(text: 'v1.0.0'));

    expect(find.byType(Tooltip), findsNothing);
    final Text label = tester.widget<Text>(
      find.descendant(of: find.byType(Tag), matching: find.byType(Text)),
    );
    expect(label.maxLines, isNull);
    expect(label.overflow, isNull);
  });

  testWidgets('maxWidth 超长文本单行省略截断', (tester) async {
    await _pumpTag(
      tester,
      const Tag(text: 'v2.0.0-beta.1+build.123456789', fontSize: 10, maxWidth: 96),
    );

    final Text label = tester.widget<Text>(
      find.descendant(of: find.byType(Tag), matching: find.byType(Text)),
    );
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text('v2.0.0-beta.1+build.123456789')).width, 96);
  });

  testWidgets('maxWidth 不放大短文本', (tester) async {
    await _pumpTag(
      tester,
      const Tag(text: 'v1.0.0', fontSize: 10, maxWidth: 96),
    );

    expect(
      tester.getSize(find.text('v1.0.0')).width,
      lessThan(96),
      reason: '短文本按内容宽度渲染',
    );
  });

  testWidgets('tooltip 非空时包裹悬停提示', (tester) async {
    await _pumpTag(
      tester,
      const Tag(
        text: 'v2.0.0-beta.1+build.123',
        fontSize: 10,
        maxWidth: 96,
        tooltip: 'v2.0.0-beta.1+build.123',
      ),
    );

    final Tooltip tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'v2.0.0-beta.1+build.123');
    expect(find.text('v2.0.0-beta.1+build.123'), findsOneWidget);
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
