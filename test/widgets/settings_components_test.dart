import 'package:cpp_nuget_pack/widgets/settings/settings_card.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_expander.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_group.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// 紧凑设置组件的几何/语义契约测试。
///
/// 几何期望值一律写独立字面量（PowerToys 契约数值），不用生产 token 常量求值——
/// 否则 token 与实现同改时断言会一并漂移，回归无法被发现；高度类契约改用
/// [tester.getSize] 的实测排版结果表达（自适应高度），不做 `>= token` 的空断言。
/// 颜色类断言引用 Fluent 主题资源，目的仅是锁定 AppColors 的语义映射。
void main() {
  group('SettingsCard', () {
    testWidgets('高度随内容自适应、内边距 16、四边 1px 描边 + 圆角 4', (tester) async {
      await _pump(
        tester,
        const Column(
          children: <Widget>[
            SettingsCard(key: Key('shortCard'), header: Text('短卡')),
            SizedBox(height: 8),
            SettingsCard(
              key: Key('tallCard'),
              header: Text('高卡'),
              content: SizedBox(height: 64),
            ),
          ],
        ),
      );

      final double shortHeight = tester
          .getSize(find.byKey(const Key('shortCard')))
          .height;
      final double tallHeight = tester
          .getSize(find.byKey(const Key('tallCard')))
          .height;
      final double lineHeight = tester.getSize(find.text('短卡')).height;
      // 34 = 上下内边距 16 + 上下描边 1；卡高只随内容增长，无固定最小高。
      expect(shortHeight, closeTo(34 + lineHeight, 0.5));
      expect(tallHeight, closeTo(34 + 64, 0.5));

      final AnimatedContainer container = _cardContainer(
        tester,
        const Key('shortCard'),
      );
      expect(container.padding, const EdgeInsets.all(16));
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(4));
      expect(
        decoration.border,
        Border.all(color: _theme(tester).resources.cardStrokeColorDefault),
      );
    });

    testWidgets('普通卡悬停无背景变化，可点击卡悬停/按下切换状态色', (tester) async {
      await _pump(
        tester,
        const SettingsCard(key: Key('plain'), header: Text('普通')),
      );
      // 期望色取自 Fluent 主题资源：普通卡静止色 = cardBackgroundFillColorDefault，
      // 悬停 = controlFillColorSecondary、按压 = controlFillColorTertiary，
      // 用于锁定 AppColors 的语义映射（而非把主题常量复制一份）。
      final Color normalColor =
          (_cardContainer(tester, const Key('plain')).decoration!
                  as BoxDecoration)
              .color!;
      expect(
        normalColor,
        _theme(tester).resources.cardBackgroundFillColorDefault,
      );

      final TestGesture hover = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await hover.addPointer(
        location: tester.getCenter(find.byKey(const Key('plain'))),
      );
      await hover.moveTo(tester.getCenter(find.byKey(const Key('plain'))));
      await tester.pump();
      expect(
        (_cardContainer(tester, const Key('plain')).decoration!
                as BoxDecoration)
            .color,
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
        (_cardContainer(tester, const Key('clickable')).decoration!
                as BoxDecoration)
            .color,
        _theme(tester).resources.controlFillColorSecondary,
      );

      await hover2.down(tester.getCenter(find.byKey(const Key('clickable'))));
      await tester.pump();
      expect(
        (_cardContainer(tester, const Key('clickable')).decoration!
                as BoxDecoration)
            .color,
        _theme(tester).resources.controlFillColorTertiary,
      );

      await hover2.up();
      await hover2.removePointer();
      // HoverButton 在 tapUp 后 100ms 重置悬停态；泵完避免残留 Timer。
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        (_cardContainer(tester, const Key('clickable')).decoration!
                as BoxDecoration)
            .color,
        normalColor,
      );
    });

    testWidgets('可点击卡显示 13px 尾部箭头，普通卡不显示', (tester) async {
      await _pump(
        tester,
        const SettingsCard(key: Key('plainCard'), header: Text('普通')),
      );
      expect(find.byIcon(FluentIcons.chevron_right), findsNothing);

      await _pump(
        tester,
        SettingsCard(
          key: const Key('clickCard'),
          header: const Text('可点击'),
          onPressed: () {},
        ),
      );
      final Icon chevron = tester.widget<Icon>(
        find.byIcon(FluentIcons.chevron_right),
      );
      expect(chevron.size, 13);
      // 箭头贴卡片右缘：内边距 16 + 描边 1。
      expect(
        tester.getBottomRight(find.byKey(const Key('clickCard'))).dx -
            tester.getBottomRight(find.byIcon(FluentIcons.chevron_right)).dx,
        closeTo(17, 0.5),
      );
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
        (_cardContainer(tester, const Key('disabled')).decoration!
                as BoxDecoration)
            .color,
        _theme(tester).resources.controlFillColorDisabled,
      );
      await tester.tap(find.byKey(const Key('disabled')), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);
    });

    testWidgets('紧凑 ToggleSwitch 高 36、宽度不被拉伸、贴右缘 17', (tester) async {
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
      // 开关保持自然宽度：远窄于整卡（不被 Expanded/SizedBox 撑满）。
      expect(
        tester.getSize(find.byType(ToggleSwitch)).width,
        lessThan(tester.getSize(find.byKey(const Key('toggleCard'))).width / 2),
      );
      final double cardRight = tester
          .getBottomRight(find.byKey(const Key('toggleCard')))
          .dx;
      final double switchRight = tester
          .getBottomRight(find.byType(ToggleSwitch))
          .dx;
      // 1px 描边绘制在内侧，容器的内边距含描边尺寸：16 + 1 = 17。
      expect(cardRight - switchRight, closeTo(17, 0.5));

      await tester.tap(find.byType(ToggleSwitch));
      await tester.pump();
      expect(value, isTrue);
      // HoverButton 在 tapUp 后 100ms 重置悬停态；泵完避免残留 Timer。
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('可用宽 476 不换行、475 换行到头部下方；可用宽 286 显示、285 隐藏头部图标', (
      tester,
    ) async {
      // 换行/隐藏阈值按卡内可用宽判定：外宽 = 阈值 + 左右内边距 16 与描边 1（共 34）。
      await _pump(tester, _wrapHost(510, contentKey: const Key('sideContent')));
      expect(
        tester.getTopLeft(find.byKey(const Key('sideContent'))).dx,
        greaterThan(tester.getTopRight(find.text('头部')).dx),
      );

      await _pump(tester, _wrapHost(509, contentKey: const Key('wrapContent')));
      expect(
        tester.getTopLeft(find.byKey(const Key('wrapContent'))).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('头部')).dy),
      );

      await _pump(tester, _wrapHost(320, withIcon: true));
      expect(find.byKey(const Key('cardIcon')), findsOneWidget);

      await _pump(tester, _wrapHost(319, withIcon: true));
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
    testWidgets('标题 14 Semibold、组上边距 8、标题到卡 8、卡间距 2', (tester) async {
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
      expect(firstTitleTop - firstTop, 8);

      final double secondTop = tester
          .getTopLeft(find.byKey(const Key('secondGroup')))
          .dy;
      final double secondTitleTop = tester.getTopLeft(find.text('外观')).dy;
      expect(secondTitleTop - secondTop, 8);

      final double titleBottom = tester.getBottomLeft(find.text('打包')).dy;
      final double card1Top = tester
          .getTopLeft(find.byKey(const Key('card1')))
          .dy;
      expect(card1Top - titleBottom, 8);

      final double card1Bottom = tester
          .getBottomLeft(find.byKey(const Key('card1')))
          .dy;
      final double card2Top = tester
          .getTopLeft(find.byKey(const Key('card2')))
          .dy;
      expect(card2Top - card1Bottom, 2);
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
      expect(_animatedSize(tester).duration, const Duration(milliseconds: 167));

      await tester.tap(find.byType(SettingsCard).first);
      await tester.pump();
      expect(find.text('子项'), findsOneWidget);
      expect(_animatedSize(tester).duration, const Duration(milliseconds: 333));
      await tester.pump(const Duration(milliseconds: 333));
      await tester.pump();

      await tester.tap(find.byType(SettingsCard).first);
      await tester.pump();
      expect(_animatedSize(tester).duration, const Duration(milliseconds: 167));
      await tester.pump(const Duration(milliseconds: 167));
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
      // 头部卡不叠加尾部箭头（只保留折叠按钮自身的 chevron_down）。
      expect(find.byIcon(FluentIcons.chevron_right), findsNothing);
      await tester.tap(find.byType(SettingsCard).first);
      await tester.pump();
      expect(find.byTooltip('收起设置'), findsOneWidget);
      expect(find.text('子项'), findsOneWidget);
    });

    testWidgets('子项为无圆角、左缩进 48、顶部 1px 分隔线且高度随内容自适应', (tester) async {
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
      expect(container.padding, const EdgeInsets.fromLTRB(48, 8, 44, 8));
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.zero);
      final Border border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.left.width, 0);
      // 左缩进 48：子项文字相对卡左缘内缩 48（左边框 0 不额外占位）。
      expect(
        tester.getTopLeft(find.text('子项')).dx -
            tester.getTopLeft(find.byKey(const Key('item'))).dx,
        closeTo(48, 0.5),
      );
      // 高度自适应：17 = 顶部 1px 分隔线 + 上下内边距 8，无固定最小高。
      expect(
        tester.getSize(find.byKey(const Key('item'))).height,
        closeTo(17 + tester.getSize(find.text('子项')).height, 0.5),
      );

      await _pump(
        tester,
        SettingsExpander(
          header: const Text('头部'),
          initiallyExpanded: true,
          items: const <Widget>[
            SettingsExpanderItem(
              key: Key('tallItem'),
              header: Text('子项'),
              content: SizedBox(height: 40),
            ),
          ],
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('tallItem'))).height,
        closeTo(17 + 40, 0.5),
      );
    });
  });

  group('SettingsPage', () {
    testWidgets('标题 24 Semibold、水平内边距 8、内容最大宽 1000、底部留白 32', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Widget buildPage() => SettingsPage(
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
      );

      await _pump(tester, buildPage());

      final Text title = tester.widget<Text>(find.text('设置'));
      expect(title.style?.fontSize, 24);
      expect(title.style?.fontWeight, FontWeight.w600);

      // 页面铺满视口；宽视口下内容右边界 = 水平内边距 8 + 内容最大宽 1000。
      expect(tester.getSize(find.byKey(const Key('page'))).width, 1600);
      expect(
        tester.getBottomRight(find.byType(SettingsCard).first).dx,
        8 + 1000,
      );
      // 底部留白 32 由滚动视口的 EdgeInsets 承载（不随内容高度变化）。
      final SingleChildScrollView viewport = tester
          .widget<SingleChildScrollView>(
            find.descendant(
              of: find.byKey(const Key('page')),
              matching: find.byType(SingleChildScrollView),
            ),
          );
      expect(viewport.padding, const EdgeInsets.fromLTRB(8, 0, 8, 32));

      // 最大宽是上界：视口收窄到 600 时内容随之收缩，右边界 = 600 - 8。
      tester.view.physicalSize = const Size(600, 900);
      await _pump(tester, buildPage());
      expect(
        tester.getBottomRight(find.byType(SettingsCard).first).dx,
        600 - 8,
      );
    });
  });
}

FluentThemeData _theme(WidgetTester tester) =>
    FluentTheme.of(tester.element(find.byType(SettingsCard).first));

/// 固定外宽的卡片宿主：卡内可用宽 = [width] - 34（左右内边距 16 + 描边 1）。
Widget _wrapHost(double width, {Key? contentKey, bool withIcon = false}) {
  return Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: SettingsCard(
        key: const Key('wrapCard'),
        header: const Text('头部'),
        headerIcon: withIcon
            ? const Icon(FluentIcons.settings, key: Key('cardIcon'))
            : null,
        content: contentKey == null
            ? null
            : SizedBox(key: contentKey, width: 24, height: 24),
      ),
    ),
  );
}

AnimatedContainer _cardContainer(WidgetTester tester, Key key) {
  return tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byType(AnimatedContainer),
    ),
  );
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
