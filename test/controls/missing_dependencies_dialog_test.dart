import 'package:cpp_nuget_pack/controls/delete_pack_dialog.dart';
import 'package:cpp_nuget_pack/controls/missing_dependencies_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('显示引导文案、缺失表格与提示', (tester) async {
    await _pumpDialog(
      tester,
      missing: const <PackDependent>[
        (name: 'alpha', version: '1.0'),
        (name: 'gamma', version: '[2.0,3.0)'),
      ],
    );

    expect(find.byKey(const Key('missingDependenciesDialog')), findsOneWidget);
    expect(find.text('缺失依赖'), findsOneWidget);
    expect(find.text('以下依赖在当前包列表中不存在：'), findsOneWidget);
    expect(find.byKey(const Key('missingDependenciesTable')), findsOneWidget);
    expect(find.text('包名'), findsOneWidget);
    expect(find.text('版本范围'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('gamma'), findsOneWidget);
    expect(find.text('[2.0,3.0)'), findsOneWidget);
    expect(find.text('可继续打包，缺失依赖将原样写入包配置。'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('缺失表格的包名与版本范围列对齐', (tester) async {
    await _pumpDialog(
      tester,
      missing: const <PackDependent>[
        (name: 'alpha', version: '1.0'),
        (name: 'gamma', version: '[2.0,3.0)'),
      ],
    );

    final Rect firstName = tester.getRect(find.text('alpha'));
    final Rect secondName = tester.getRect(find.text('gamma'));
    final Rect firstVersion = tester.getRect(find.text('1.0'));
    final Rect secondVersion = tester.getRect(find.text('[2.0,3.0)'));
    final Rect versionHeader = tester.getRect(find.text('版本范围'));

    expect(firstName.left, secondName.left);
    expect(firstVersion.left, secondVersion.left);
    expect(firstVersion.left, versionHeader.left);
  });

  testWidgets('取消按钮位于左端，继续打包按钮位于右端', (tester) async {
    await _pumpDialog(
      tester,
      missing: const <PackDependent>[(name: 'alpha', version: '1.0')],
    );

    final Finder cancel = find.byKey(
      const Key('missingDependenciesCancelButton'),
    );
    final Finder proceed = find.byKey(
      const Key('missingDependenciesContinueButton'),
    );
    final double dialogCenterX = tester
        .getRect(find.byKey(const Key('missingDependenciesDialog')))
        .center
        .dx;

    expect(tester.getCenter(cancel).dx, lessThan(dialogCenterX));
    expect(tester.getCenter(proceed).dx, greaterThan(dialogCenterX));
    expect(tester.widget(proceed), isA<FilledButton>());
    expect(tester.widget(cancel), isNot(isA<FilledButton>()));
  });

  testWidgets('点击继续打包返回 true 并关闭对话框', (tester) async {
    bool? result;
    await _pumpDialog(
      tester,
      missing: const <PackDependent>[(name: 'alpha', version: '1.0')],
      onResult: (bool value) => result = value,
    );

    await tester.tap(
      find.byKey(const Key('missingDependenciesContinueButton')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isTrue);
    expect(find.byKey(const Key('missingDependenciesDialog')), findsNothing);
  });

  testWidgets('点击取消返回 false 并关闭对话框', (tester) async {
    bool? result;
    await _pumpDialog(
      tester,
      missing: const <PackDependent>[(name: 'alpha', version: '1.0')],
      onResult: (bool value) => result = value,
    );

    await tester.tap(find.byKey(const Key('missingDependenciesCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isFalse);
    expect(find.byKey(const Key('missingDependenciesDialog')), findsNothing);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  ValueChanged<bool>? onResult,
  List<PackDependent> missing = const <PackDependent>[],
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
              final bool result = await showMissingDependenciesDialog(
                context,
                missing: missing,
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
