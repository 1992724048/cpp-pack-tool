import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:cpp_nuget_pack/controls/header_include_issues_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const HeaderIncludeFixReport _report = HeaderIncludeFixReport(
  fixed: <HeaderIncludeFix>[
    HeaderIncludeFix(
      filePath: 'src/gtest/gtest-all.cc',
      line: 2,
      from: 'src/gtest.cc',
      to: 'gtest.cc',
    ),
  ],
  issues: <HeaderIncludeIssue>[
    HeaderIncludeIssue(
      filePath: 'src/gtest/gtest.cc',
      line: 133,
      include: 'src/gtest-internal-inl.h',
      kind: HeaderIncludeIssueKind.crossTree,
      candidates: <String>['src/gtest/gtest-internal-inl.h'],
    ),
    HeaderIncludeIssue(
      filePath: 'include/mimalloc/track.h',
      line: 85,
      include: '../src/prim/windows/etw.h',
      kind: HeaderIncludeIssueKind.noCandidate,
    ),
    HeaderIncludeIssue(
      filePath: 'src/a/one.cc',
      line: 3,
      include: 'q/helper.h',
      kind: HeaderIncludeIssueKind.multipleCandidates,
      candidates: <String>['x/helper.h', 'y/helper.h'],
    ),
    HeaderIncludeIssue(
      filePath: 'src/a.cc',
      line: 2,
      include: 'gtest/missing.h',
      kind: HeaderIncludeIssueKind.missingAngle,
    ),
  ],
);

void main() {
  testWidgets('展示待处理引用表格（位置/引用/说明）', (tester) async {
    await _pumpDialog(tester);

    expect(find.byKey(const Key('headerIncludeIssuesDialog')), findsOneWidget);
    expect(find.text('头文件引用检查'), findsOneWidget);
    expect(find.text('以下源码引用未自动修复，打包后可能失效：'), findsOneWidget);
    expect(find.byKey(const Key('headerIncludeIssuesTable')), findsOneWidget);
    expect(find.text('位置'), findsOneWidget);
    expect(find.text('问题'), findsOneWidget);

    expect(find.text('src/gtest/gtest.cc:133'), findsOneWidget);
    expect(
      find.text('"src/gtest-internal-inl.h"：唯一候选打包后与引用文件不同目录：src/gtest/gtest-internal-inl.h'),
      findsOneWidget,
    );
    expect(find.text('include/mimalloc/track.h:85'), findsOneWidget);
    expect(find.text('"../src/prim/windows/etw.h"：包内未找到同名文件'), findsOneWidget);
    expect(find.text('src/a/one.cc:3'), findsOneWidget);
    expect(
      find.text('"q/helper.h"：存在多个同名候选：x/helper.h、y/helper.h'),
      findsOneWidget,
    );
    expect(find.text('src/a.cc:2'), findsOneWidget);
    expect(find.text('"gtest/missing.h"：尖括号自引用缺失（不自动修改）'), findsOneWidget);
  });

  testWidgets('点击关闭关闭对话框', (tester) async {
    await _pumpDialog(tester);

    await tester.tap(find.byKey(const Key('headerIncludeIssuesCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('headerIncludeIssuesDialog')), findsNothing);
  });

  testWidgets('无问题时直接返回且不弹对话框', (tester) async {
    await _pumpDialog(tester, report: const HeaderIncludeFixReport());

    expect(find.byKey(const Key('headerIncludeIssuesDialog')), findsNothing);
  });

  testWidgets('问题较多（30 条）时内容可滚动且无溢出', (tester) async {
    final HeaderIncludeFixReport manyIssues = HeaderIncludeFixReport(
      issues: <HeaderIncludeIssue>[
        for (int index = 0; index < 30; index++)
          HeaderIncludeIssue(
            filePath: 'src/file$index.cc',
            line: index + 1,
            include: 'src/target$index.h',
            kind: HeaderIncludeIssueKind.noCandidate,
          ),
      ],
    );
    await _pumpDialog(tester, report: manyIssues);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('headerIncludeIssuesTable')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('headerIncludeIssuesDialog')),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  HeaderIncludeFixReport report = _report,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () => showHeaderIncludeIssuesDialog(
              context,
              report: report,
            ),
            child: const Text('打开对话框'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开对话框'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
