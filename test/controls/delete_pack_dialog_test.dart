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

  testWidgets('点击删除返回确认结果并关闭对话框', (tester) async {
    DeletePackResult? result;
    await _pumpDialog(
      tester,
      onResult: (DeletePackResult value) => result = value,
    );

    await tester.tap(find.byKey(const Key('deletePackConfirmButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result!.confirmed, isTrue);
    expect(result!.deleteCache, isFalse);
    expect(find.byKey(const Key('deletePackDialog')), findsNothing);
  });

  testWidgets('点击取消返回未确认并关闭对话框', (tester) async {
    DeletePackResult? result;
    await _pumpDialog(
      tester,
      onResult: (DeletePackResult value) => result = value,
    );

    await tester.tap(find.byKey(const Key('deletePackCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result!.confirmed, isFalse);
    expect(result!.deleteCache, isFalse);
    expect(find.byKey(const Key('deletePackDialog')), findsNothing);
  });

  testWidgets('无构建缓存时复选禁用且提示未发现缓存', (tester) async {
    await _pumpDialog(tester);

    expect(find.text('同时删除构建缓存'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('deletePackCacheCheckbox')))
          .onChanged,
      isNull,
    );
    expect(find.text('未发现该包的构建缓存。'), findsOneWidget);
  });

  testWidgets('有构建缓存时提示清洗后的缓存路径', (tester) async {
    await _pumpDialog(tester, hasBuildCache: true);

    expect(find.textContaining('cache/build/$_packName'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('勾选后确认返回删除缓存标记', (tester) async {
    DeletePackResult? result;
    await _pumpDialog(
      tester,
      hasBuildCache: true,
      onResult: (DeletePackResult value) => result = value,
    );

    await tester.tap(find.byKey(const Key('deletePackCacheCheckbox')));
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('deletePackCacheCheckbox')))
          .checked,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('deletePackConfirmButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result!.confirmed, isTrue);
    expect(result!.deleteCache, isTrue);
  });

  testWidgets('点击整行可切换复选状态', (tester) async {
    await _pumpDialog(tester, hasBuildCache: true);

    await tester.tap(find.text('同时删除构建缓存'));
    await tester.pump();

    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('deletePackCacheCheckbox')))
          .checked,
      isTrue,
    );
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  ValueChanged<DeletePackResult>? onResult,
  List<PackDependent> dependents = const <PackDependent>[],
  bool hasBuildCache = false,
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
              final DeletePackResult result = await showDeletePackDialog(
                context,
                packName: _packName,
                dependents: dependents,
                hasBuildCache: hasBuildCache,
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
