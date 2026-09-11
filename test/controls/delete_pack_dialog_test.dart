import 'package:cpp_nuget_pack/controls/delete_pack_dialog.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const String _packName = 'demo';

void main() {
  testWidgets('显示包名与说明文案', (tester) async {
    await _pumpDialog(tester);

    expect(find.byKey(const Key('deletePackDialog')), findsOneWidget);
    expect(find.text('删除包'), findsOneWidget);
    expect(find.text('确定要删除包「$_packName」吗？'), findsOneWidget);
    expect(find.text('将移除其配置文件，此操作不可恢复；源目录中的文件不会被删除。'), findsOneWidget);
  });

  testWidgets('存在被依赖项时以表格显示依赖方与版本范围', (tester) async {
    await _pumpDialog(
      tester,
      dependents: const <PackDependent>[
        (name: 'alpha', version: '1.0'),
        (name: 'gamma', version: '[2.0,3.0)'),
      ],
    );

    expect(find.byKey(const Key('deletePackDependents')), findsOneWidget);
    expect(find.text('以下包依赖它：'), findsOneWidget);
    expect(find.text('包名'), findsOneWidget);
    expect(find.text('版本范围'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('gamma'), findsOneWidget);
    expect(find.text('[2.0,3.0)'), findsOneWidget);
    expect(find.text('删除后这些依赖将显示为「缺失」。'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('被依赖表格的包名与版本范围列对齐', (tester) async {
    await _pumpDialog(
      tester,
      dependents: const <PackDependent>[
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

  testWidgets('无被依赖项时不显示依赖提示', (tester) async {
    await _pumpDialog(tester);

    expect(find.byKey(const Key('deletePackDependents')), findsNothing);
    expect(find.text('以下包依赖它：'), findsNothing);
    expect(find.text('删除后这些依赖将显示为「缺失」。'), findsNothing);
  });

  testWidgets('删除键位于左端且为红底白字，取消键位于右端', (tester) async {
    await _pumpDialog(tester);

    final Finder confirm = find.byKey(const Key('deletePackConfirmButton'));
    final Finder cancel = find.byKey(const Key('deletePackCancelButton'));
    final double dialogCenterX = tester
        .getRect(find.byKey(const Key('deletePackDialog')))
        .center
        .dx;

    expect(
      tester.getTopLeft(confirm).dx,
      lessThan(tester.getTopLeft(cancel).dx),
    );
    expect(tester.getCenter(confirm).dx, lessThan(dialogCenterX));
    expect(tester.getCenter(cancel).dx, greaterThan(dialogCenterX));

    final ButtonStyle style = tester.widget<FilledButton>(confirm).style!;
    expect(
      style.backgroundColor?.resolve(<WidgetState>{}),
      UCColors.flavor.red,
    );
    expect(style.foregroundColor?.resolve(<WidgetState>{}), Colors.white);
  });

  testWidgets('点击删除返回 true 并关闭对话框', (tester) async {
    bool? result;
    await _pumpDialog(tester, onResult: (bool value) => result = value);

    await tester.tap(find.byKey(const Key('deletePackConfirmButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isTrue);
    expect(find.byKey(const Key('deletePackDialog')), findsNothing);
  });

  testWidgets('点击取消返回 false 并关闭对话框', (tester) async {
    bool? result;
    await _pumpDialog(tester, onResult: (bool value) => result = value);

    await tester.tap(find.byKey(const Key('deletePackCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isFalse);
    expect(find.byKey(const Key('deletePackDialog')), findsNothing);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  ValueChanged<bool>? onResult,
  List<PackDependent> dependents = const <PackDependent>[],
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
              final bool result = await showDeletePackDialog(
                context,
                packName: _packName,
                dependents: dependents,
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
