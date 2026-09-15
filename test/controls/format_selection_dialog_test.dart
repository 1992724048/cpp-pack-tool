import 'package:cpp_nuget_pack/controls/format_selection_dialog.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBuilder implements PackageBuilder {
  _FakeBuilder(this.id, this.displayName);

  @override
  final String id;

  @override
  final String displayName;

  @override
  Future<PackagePlan> buildPlan(PackModel pack) async =>
      PackagePlan(entries: const <PackageEntry>[]);
}

final List<PackageBuilder> _builders = <PackageBuilder>[
  _FakeBuilder('nuget', 'NuGet 包'),
  _FakeBuilder('cmake', 'CMake'),
];

void main() {
  testWidgets('渲染双列表与操作按钮，未启用项在左、已启用项在右', (tester) async {
    await _pumpDialog(tester, enabledIds: const <String>['nuget']);

    expect(find.byKey(const Key('formatSelectionDialog')), findsOneWidget);
    expect(find.text('选择打包格式'), findsOneWidget);
    expect(find.text('未启用'), findsOneWidget);
    expect(find.text('已启用'), findsOneWidget);
    expect(find.byKey(const Key('formatItem_cmake_disabled')), findsOneWidget);
    expect(find.byKey(const Key('formatItem_nuget_disabled')), findsNothing);
    expect(find.byKey(const Key('formatItem_nuget_enabled')), findsOneWidget);
    expect(find.byKey(const Key('formatItem_cmake_enabled')), findsNothing);
    expect(find.text('至少需要启用一种格式。'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNotNull);
    expect(_enableButton(tester).onPressed, isNull);
    expect(_disableButton(tester).onPressed, isNull);
  });

  testWidgets('启用集合为空时右侧为空且确定禁用', (tester) async {
    await _pumpDialog(tester, enabledIds: const <String>[]);

    expect(find.byKey(const Key('formatItem_nuget_disabled')), findsOneWidget);
    expect(find.byKey(const Key('formatItem_cmake_disabled')), findsOneWidget);
    expect(find.text('尚未启用任何格式'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('选中左侧项后启用按钮可用，启用后移入右列表并成为选中项', (tester) async {
    await _pumpDialog(tester, enabledIds: const <String>['nuget']);

    await _tapItem(tester, const Key('formatItem_cmake_disabled'));
    expect(_enableButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('formatEnableButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('formatItem_cmake_enabled')), findsOneWidget);
    expect(find.byKey(const Key('formatItem_cmake_disabled')), findsNothing);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('formatItem_cmake_enabled')))
          .selected,
      isTrue,
    );
    expect(_disableButton(tester).onPressed, isNotNull);
    expect(_enableButton(tester).onPressed, isNull);
  });

  testWidgets('移除后回到左列表，两侧选择互斥', (tester) async {
    await _pumpDialog(tester, enabledIds: const <String>['nuget', 'cmake']);

    await _tapItem(tester, const Key('formatItem_cmake_enabled'));
    expect(_disableButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('formatDisableButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('formatItem_cmake_disabled')), findsOneWidget);
    expect(find.byKey(const Key('formatItem_cmake_enabled')), findsNothing);
    expect(_enableButton(tester).onPressed, isNotNull);
    expect(_disableButton(tester).onPressed, isNull);

    await _tapItem(tester, const Key('formatItem_nuget_enabled'));

    expect(_disableButton(tester).onPressed, isNotNull);
    expect(_enableButton(tester).onPressed, isNull);
  });

  testWidgets('全部移除后确定禁用（至少需要一种格式）', (tester) async {
    await _pumpDialog(tester, enabledIds: const <String>['nuget']);

    await _tapItem(tester, const Key('formatItem_nuget_enabled'));
    await tester.tap(find.byKey(const Key('formatDisableButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('尚未启用任何格式'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('确定返回注册表顺序的启用 id 列表', (tester) async {
    List<String>? result;
    await _pumpDialog(
      tester,
      enabledIds: const <String>['cmake'],
      onResult: (List<String>? value) => result = value,
    );

    await _tapItem(tester, const Key('formatItem_nuget_disabled'));
    await tester.tap(find.byKey(const Key('formatEnableButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('formatSelectionConfirmButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, <String>['nuget', 'cmake']);
    expect(find.byKey(const Key('formatSelectionDialog')), findsNothing);
  });

  testWidgets('取消返回 null 且不应用变更', (tester) async {
    List<String>? result = const <String>['placeholder'];
    await _pumpDialog(
      tester,
      enabledIds: const <String>['nuget'],
      onResult: (List<String>? value) => result = value,
    );

    await tester.tap(find.byKey(const Key('formatSelectionCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isNull);
    expect(find.byKey(const Key('formatSelectionDialog')), findsNothing);
  });
}

FilledButton _confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('formatSelectionConfirmButton')),
);

Button _enableButton(WidgetTester tester) =>
    tester.widget<Button>(find.byKey(const Key('formatEnableButton')));

Button _disableButton(WidgetTester tester) =>
    tester.widget<Button>(find.byKey(const Key('formatDisableButton')));

/// 点击列表项并等待 HoverButton 的悬停定时器结束（防 pending timer）。
Future<void> _tapItem(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<String> enabledIds,
  ValueChanged<List<String>?>? onResult,
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
              final List<String>? result = await showFormatSelectionDialog(
                context,
                builders: _builders,
                enabledIds: enabledIds,
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
