import 'package:cpp_nuget_pack/widgets/settings/settings_card.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_expander.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_group.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsCard', () {
    testWidgets('默认最小高 68、内边距 16、1px 描边 + 圆角 4', (tester) async {
      await _pump(
        tester,
        const SettingsCard(
          key: Key('card'),
          header: Text('标题'),
          description: Text('描述'),
        ),
      );

      final Size size = tester.getSize(find.byKey(const Key('card')));
      expect(size.height, greaterThanOrEqualTo(SettingsCardTokens.minHeight));

      final AnimatedContainer container = _cardContainer(tester);
      expect(container.padding, SettingsCardTokens.padding);
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(4));
      final Border border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, _theme(tester).resources.cardStrokeColorDefault);
    });

    testWidgets('普通卡悬停无背景变化，可点击卡悬停/按下切换状态色', (tester) async {
      await _pump(
        tester,
        const SettingsCard(key: Key('plain'), header: Text('普通')),
      );
      final Color normalColor =
          (_cardContainer(tester).decoration! as BoxDecoration).color!;

      final TestGesture hover = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await hover.addPointer(
        location: tester.getCenter(find.byKey(const Key('plain'))),
      );
      await hover.moveTo(tester.getCenter(find.byKey(const Key('plain'))));
      await tester.pump();
      expect(
        (_cardContainer(tester).decoration! as BoxDecoration).color,
        normalColor,
      );
      await hover.removePointer();
      await tester.pump();

      await _pump(
        tester,
        SettingsCard(
          key: const Key('clickable'),
          header: const Text('可点击'),
          onPressed: () {},
        ),
      );
      final TestGesture hover2 = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await hover2.addPointer(
        location: tester.getCenter(find.byKey(const Key('clickable'))),
      );
      await hover2.moveTo(tester.getCenter(find.byKey(const Key('clickable'))));
      await tester.pump();
      expect(
        (_cardContainer(tester).decoration! as BoxDecoration).color,
        _theme(tester).resources.controlFillColorSecondary,
      );

      await hover2.down(tester.getCenter(find.byKey(const Key('clickable'))));
      await tester.pump();
      expect(
        (_cardContainer(tester).decoration! as BoxDecoration).color,
        _theme(tester).resources.controlFillColorTertiary,
      );

      await hover2.up();
      await hover2.removePointer();
      await tester.pump();
    });

    testWidgets('禁用卡背景为禁用填充色且点击不触发', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        SettingsCard(
          key: const Key('disabled'),
          header: const Text('禁用'),
          enabled: false,
          onPressed: () => pressed++,
        ),
      );

      expect(
        (_cardContainer(tester).decoration! as BoxDecoration).color,
        _theme(tester).resources.controlFillColorDisabled,
      );
      await tester.tap(find.byKey(const Key('disabled')), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);
    });

    testWidgets('紧凑 ToggleSwitch 高 36、宽度不撑到内容最小宽、右对齐', (tester) async {
      bool? value;
      await _pump(
        tester,
        SettingsCard(
          key: const Key('toggleCard'),
          header: const Text('开关'),
          content: SettingsCardToggle(
            checked: false,
            onChanged: (bool next) => value = next,
          ),
        ),
      );

      expect(tester.getSize(find.byType(SettingsCardToggle)).height, 36);
      expect(
        tester.getSize(find.byType(ToggleSwitch)).width,
        lessThan(SettingsCardTokens.minWidth),
      );
      final double cardRight = tester
          .getBottomRight(find.byKey(const Key('toggleCard')))
          .dx;
      final double switchRight = tester
          .getBottomRight(find.byType(ToggleSwitch))
          .dx;
      // 1px 描边绘制在内侧，容器的内边距含描边尺寸。
      expect(
        cardRight - switchRight,
        closeTo(SettingsCardTokens.padding.right + 1, 0.5),
      );

      await tester.tap(find.byType(ToggleSwitch));
      await tester.pump();
      expect(value, isTrue);
      // HoverButton 在 tapUp 后 100ms 重置悬停态；泵完避免残留 Timer。
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('窄窗（<476）内容换行到头部下方，更窄（<286）隐藏头部图标', (tester) async {
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: SettingsCard(
              key: const Key('wrapCard'),
              header: const Text('头部'),
              content: const SizedBox(key: Key('wrapContent'), width: 24),
            ),
          ),
        ),
      );

      final double headerBottom = tester.getBottomLeft(find.text('头部')).dy;
      final double contentTop = tester
          .getTopLeft(find.byKey(const Key('wrapContent')))
          .dy;
      expect(contentTop, greaterThanOrEqualTo(headerBottom));

      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            child: SettingsCard(
              key: const Key('narrowCard'),
              header: const Text('头部'),
              headerIcon: const Icon(
                FluentIcons.settings,
                key: Key('cardIcon'),
              ),
              content: const SizedBox(width: 24),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('cardIcon')), findsNothing);
    });

    testWidgets('可点击卡 ActivateIntent（Enter/Space）触发回调', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        SettingsCard(
          key: const Key('keyboardCard'),
          header: const Text('键盘'),
          onPressed: () => pressed++,
        ),
      );

      Actions.invoke(
        tester.element(find.byType(AnimatedContainer).first),
        const ActivateIntent(),
      );
      await tester.pump();
      expect(pressed, 1);
    });
  });

  group('SettingsGroup', () {
    testWidgets('标题 14 Semibold、首个上边距 8、其余 32、卡间距 2', (tester) async {
      await _pump(
        tester,
        Column(
          children: <Widget>[
            SettingsGroup(
              key: const Key('firstGroup'),
              header: '打包',
              first: true,
              children: const <Widget>[
                SettingsCard(key: Key('card1'), header: Text('一')),
                SettingsCard(key: Key('card2'), header: Text('二')),
              ],
            ),
            SettingsGroup(
              key: const Key('secondGroup'),
              header: '外观',
              children: const <Widget>[
                SettingsCard(key: Key('card3'), header: Text('三')),
              ],
            ),
          ],
        ),
      );

      final Text title = tester.widget<Text>(find.text('打包'));
      expect(title.style?.fontSize, 14);
      expect(title.style?.fontWeight, FontWeight.w600);

      final double firstTop = tester
          .getTopLeft(find.byKey(const Key('firstGroup')))
          .dy;
      final double firstTitleTop = tester.getTopLeft(find.text('打包')).dy;
      expect(firstTitleTop - firstTop, SettingsGroupTokens.firstHeaderSpacing);

      final double secondTop = tester
          .getTopLeft(find.byKey(const Key('secondGroup')))
          .dy;
      final double secondTitleTop = tester.getTopLeft(find.text('外观')).dy;
      expect(secondTitleTop - secondTop, SettingsGroupTokens.headerSpacing);

      final double card1Bottom = tester
          .getBottomLeft(find.byKey(const Key('card1')))
          .dy;
      final double card2Top = tester.getTopLeft(find.byKey(const Key('card2'))).dy;
      expect(card2Top - card1Bottom, SettingsGroupTokens.cardSpacing);
    });
  });

  group('SettingsExpander', () {
    testWidgets('默认收起；点击头部展开（333ms）再收起（167ms）', (tester) async {
      await _pump(
        tester,
        SettingsExpander(
          key: const Key('expander'),
          header: const Text('代理'),
          toggleKey: const Key('expanderToggle'),
          items: const <Widget>[SettingsExpanderItem(header: Text('子项'))],
        ),
      );

      expect(find.text('子项'), findsNothing);
      expect(
        _animatedSize(tester).duration,
        SettingsExpanderTokens.collapseDuration,
      );

      await tester.tap(find.byType(SettingsCard).first);
      await tester.pump();
      expect(find.text('子项'), findsOneWidget);
      expect(
        _animatedSize(tester).duration,
        SettingsExpanderTokens.expandDuration,
      );
      await tester.pump(SettingsExpanderTokens.expandDuration);
      await tester.pump();

      await tester.tap(find.byType(SettingsCard).first);
      await tester.pump();
      expect(
        _animatedSize(tester).duration,
        SettingsExpanderTokens.collapseDuration,
      );
      await tester.pump(SettingsExpanderTokens.collapseDuration);
      await tester.pump();
      expect(find.text('子项'), findsNothing);
    });

    testWidgets('chevron 可点击切换且 Tooltip 文案随状态切换', (tester) async {
      await _pump(
        tester,
        SettingsExpander(
          header: const Text('头部'),
          toggleKey: const Key('expanderToggle'),
          items: const <Widget>[SettingsExpanderItem(header: Text('子项'))],
        ),
      );

      expect(find.byTooltip('展开设置'), findsOneWidget);
      expect(find.byKey(const Key('expanderToggle')), findsOneWidget);
      expect(find.text('子项'), findsNothing);
      await tester.tap(find.byType(SettingsCard).first);
      await tester.pump();
      expect(find.byTooltip('收起设置'), findsOneWidget);
      expect(find.text('子项'), findsOneWidget);
    });

    testWidgets('子项为无圆角、左缩进 58、最小高 52、顶部 1px 的卡', (tester) async {
      await _pump(
        tester,
        SettingsExpander(
          header: const Text('头部'),
          initiallyExpanded: true,
          items: const <Widget>[
            SettingsExpanderItem(key: Key('item'), header: Text('子项')),
          ],
        ),
      );

      final SettingsCard card = tester.widget<SettingsCard>(
        find.descendant(
          of: find.byKey(const Key('item')),
          matching: find.byType(SettingsCard),
        ),
      );
      expect(card.subItem, isTrue);

      final AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const Key('item')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(container.padding, SettingsCardTokens.subItemPadding);
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.zero);
      final Border border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.left.width, 0);
      expect(
        tester.getSize(find.byKey(const Key('item'))).height,
        greaterThanOrEqualTo(SettingsCardTokens.subItemMinHeight),
      );
    });
  });

  group('SettingsPage', () {
    testWidgets('标题 28 Semibold、内容最大宽 1000、底部留白 48', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(
        tester,
        SettingsPage(
          key: const Key('page'),
          title: '设置',
          description: const Text('页面描述'),
          children: <Widget>[
            SettingsGroup(
              header: '打包',
              first: true,
              children: const <Widget>[SettingsCard(header: Text('卡'))],
            ),
          ],
        ),
      );

      final Text title = tester.widget<Text>(find.text('设置'));
      expect(title.style?.fontSize, 28);
      expect(title.style?.fontWeight, FontWeight.w600);

      expect(tester.getSize(find.byKey(const Key('page'))).width, 1600);
      final double cardRight = tester
          .getBottomRight(find.byType(SettingsCard).first)
          .dx;
      expect(
        cardRight,
        SettingsPageTokens.horizontalPadding +
            SettingsPageTokens.contentMaxWidth,
      );
      final Size page = tester.getSize(find.byKey(const Key('page')));
      expect(
        page.height - tester.getBottomLeft(find.byType(SettingsCard)).dy,
        greaterThanOrEqualTo(SettingsPageTokens.bottomPadding),
      );
    });
  });
}

FluentThemeData _theme(WidgetTester tester) =>
    FluentTheme.of(tester.element(find.byType(SettingsCard).first));

AnimatedContainer _cardContainer(WidgetTester tester) {
  return tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .first;
}

AnimatedSize _animatedSize(WidgetTester tester) {
  return tester.widget<AnimatedSize>(
    find.byKey(SettingsExpanderTokens.bodyKey),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(FluentApp(home: child));
  await tester.pump();
}
