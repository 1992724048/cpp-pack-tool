import 'package:cpp_nuget_pack/controls/packaging_issues_dialog.dart';
import 'package:cpp_nuget_pack/packaging/script_packaging.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const List<PackagingIssue> _issues = <PackagingIssue>[
  PackagingIssue(label: '坏脚本', message: '脚本编译失败（共 2 个错误）：缺少入口节点'),
  PackagingIssue(label: '包内路径', message: '包内路径重复：build/native/files/foo.h'),
];

void main() {
  testWidgets('显示脚本校验表格与操作提示', (tester) async {
    await _pumpDialog(tester);

    expect(find.byKey(const Key('packagingIssuesDialog')), findsOneWidget);
    expect(find.text('脚本校验'), findsOneWidget);
    expect(find.text('以下脚本或包内路径存在问题：'), findsOneWidget);
    expect(find.byKey(const Key('packagingIssuesTable')), findsOneWidget);
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('问题'), findsOneWidget);
    expect(find.text('坏脚本'), findsOneWidget);
    expect(find.text('脚本编译失败（共 2 个错误）：缺少入口节点'), findsOneWidget);
    expect(find.text('包内路径'), findsOneWidget);
    expect(find.text('包内路径重复：build/native/files/foo.h'), findsOneWidget);
    expect(find.text('可继续导出，或取消返回修改。'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('表格的名称与问题列对齐', (tester) async {
    await _pumpDialog(tester);

    final Rect firstName = tester.getRect(find.text('坏脚本'));
    final Rect secondName = tester.getRect(find.text('包内路径'));
    final Rect firstMessage = tester.getRect(
      find.text('脚本编译失败（共 2 个错误）：缺少入口节点'),
    );
    final Rect secondMessage = tester.getRect(
      find.text('包内路径重复：build/native/files/foo.h'),
    );
    final Rect nameHeader = tester.getRect(find.text('名称'));
    final Rect messageHeader = tester.getRect(find.text('问题'));

    expect(firstName.left, secondName.left);
    expect(firstMessage.left, secondMessage.left);
    expect(firstName.left, nameHeader.left);
    expect(firstMessage.left, messageHeader.left);
  });

  testWidgets('取消按钮位于左端，继续导出按钮位于右端', (tester) async {
    await _pumpDialog(tester);

    final Finder cancel = find.byKey(
      const Key('packagingIssuesCancelButton'),
    );
    final Finder proceed = find.byKey(
      const Key('packagingIssuesContinueButton'),
    );
    final double dialogCenterX = tester
        .getRect(find.byKey(const Key('packagingIssuesDialog')))
        .center
        .dx;

    expect(tester.getCenter(cancel).dx, lessThan(dialogCenterX));
    expect(tester.getCenter(proceed).dx, greaterThan(dialogCenterX));
    expect(tester.widget(proceed), isA<FilledButton>());
    expect(tester.widget(cancel), isNot(isA<FilledButton>()));
  });

  testWidgets('点击继续导出返回 true 并关闭对话框', (tester) async {
    bool? result;
    await _pumpDialog(tester, onResult: (bool value) => result = value);

    await tester.tap(find.byKey(const Key('packagingIssuesContinueButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isTrue);
    expect(find.byKey(const Key('packagingIssuesDialog')), findsNothing);
  });

  testWidgets('点击取消返回 false 并关闭对话框', (tester) async {
    bool? result;
    await _pumpDialog(tester, onResult: (bool value) => result = value);

    await tester.tap(find.byKey(const Key('packagingIssuesCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isFalse);
    expect(find.byKey(const Key('packagingIssuesDialog')), findsNothing);
  });

  testWidgets('问题列表为空时直接返回 true 且不弹对话框', (tester) async {
    bool? result;
    await _pumpDialog(
      tester,
      issues: const <PackagingIssue>[],
      onResult: (bool value) => result = value,
    );

    expect(result, isTrue);
    expect(find.byKey(const Key('packagingIssuesDialog')), findsNothing);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  ValueChanged<bool>? onResult,
  List<PackagingIssue> issues = _issues,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () async {
              final bool result = await showPackagingIssuesDialog(
                context,
                issues: issues,
              );
              onResult?.call(result);
            },
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
