import 'package:cpp_nuget_pack/app_info.dart';
import 'package:cpp_nuget_pack/pages/about.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('渲染应用名、版本、描述与项目主页按钮', (tester) async {
    await _pumpAbout(tester, openUrl: (_) async => true);

    expect(find.text(appName), findsOneWidget);
    expect(find.text('v$appVersion'), findsOneWidget);
    expect(find.text(appDescription), findsOneWidget);
    expect(find.byKey(const Key('aboutRepoButton')), findsOneWidget);
    expect(find.text('项目主页'), findsOneWidget);
    expect(find.text('第三方组件许可见仓库 THIRD_PARTY_NOTICES.md'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击项目主页用仓库地址调用打开函数', (tester) async {
    String? openedUrl;
    await _pumpAbout(
      tester,
      openUrl: (String url) async {
        openedUrl = url;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('aboutRepoButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(openedUrl, appRepositoryUrl);
    expect(find.byKey(const Key('floatingToast')), findsNothing);
  });

  testWidgets('打开链接失败时显示错误提示', (tester) async {
    await _pumpAbout(tester, openUrl: (_) async => false);

    await tester.tap(find.byKey(const Key('aboutRepoButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('无法打开链接'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
  });

  testWidgets('宽松约束下铺满可用区域且带页面背景表面', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      FluentApp(
        home: Center(
          key: const Key('aboutLooseBox'),
          child: About(openUrl: (_) async => true),
        ),
      ),
    );
    await tester.pump();

    final Size available = tester.getSize(
      find.byKey(const Key('aboutLooseBox')),
    );
    expect(tester.getSize(find.byType(About)), available);

    final Finder surface = _pageSurface(tester);
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface), available);
  });
}

Future<void> _pumpAbout(
  WidgetTester tester, {
  required Future<bool> Function(String url) openUrl,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(home: About(openUrl: openUrl)));
  await tester.pump();
}

Finder _pageSurface(WidgetTester tester) {
  final Color cardColor = FluentTheme.of(tester.element(find.byType(About)))
      .cardColor;
  return find.descendant(
    of: find.byType(About),
    matching: find.byWidgetPredicate((Widget widget) {
      if (widget is! Container) {
        return false;
      }
      final Decoration? decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == cardColor;
    }),
  );
}
