import 'package:cpp_nuget_pack/controls/dependency_dialog.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('添加模式显示候选下拉与提示且未选包时确定禁用', (tester) async {
    await _pumpDialog(tester, candidates: _candidates());

    expect(find.text('添加依赖'), findsOneWidget);
    expect(find.text('包名'), findsOneWidget);
    expect(find.text('版本范围'), findsOneWidget);
    expect(find.text('支持 NuGet 区间写法，如 [1.0,2.0)、[1.0]、1.0'), findsOneWidget);
    expect(find.byType(ComboBox<String>), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '1.0',
    );
    await tester.pump();

    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('包名下拉框与版本输入框等高', (tester) async {
    await _pumpDialog(tester, candidates: _candidates());

    final Size package = tester.getSize(
      find.byKey(const Key('dependencyPackageField')),
    );
    final Size version = tester.getSize(
      find.byKey(const Key('dependencyVersionField')),
    );

    expect(package.height, version.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有候选包时显示提示且确定禁用', (tester) async {
    await _pumpDialog(tester);

    expect(find.text('没有可添加的包'), findsOneWidget);
    expect(find.byType(ComboBox<String>), findsNothing);

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '1.0',
    );
    await tester.pump();

    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('非法版本范围实时提示并禁用确定', (tester) async {
    await _pumpDialog(tester, candidates: _candidates());
    await _selectPackage(tester, 'libfoo');

    expect(_confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '(1.0)',
    );
    await tester.pump();
    expect(find.text('单值范围必须写成 [版本] 形式'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '1.*',
    );
    await tester.pump();
    expect(find.text('单值范围必须写成 [版本] 形式'), findsNothing);
    expect(find.textContaining('不支持浮版本'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '[1.0,2.0)',
    );
    await tester.pump();
    expect(find.byKey(const Key('dependencyVersionError')), findsNothing);
    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('点击确定返回 trim 后的依赖', (tester) async {
    DependencyModel? result;
    await _pumpDialog(
      tester,
      candidates: _candidates(),
      onResult: (DependencyModel? value) => result = value,
    );

    await _selectPackage(tester, 'libfoo');
    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '  [1.0]  ',
    );
    await tester.pump();
    await _tapConfirm(tester);

    expect(result, isNotNull);
    expect(result!.name, 'libfoo');
    expect(result!.version, '[1.0]');
    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('编辑模式固定包名且版本预填', (tester) async {
    DependencyModel? result;
    await _pumpDialog(
      tester,
      editing: const DependencyModel(name: 'libfoo', version: '1.0'),
      onResult: (DependencyModel? value) => result = value,
    );

    expect(find.text('编辑依赖'), findsOneWidget);
    expect(find.text('libfoo'), findsOneWidget);
    expect(find.byType(ComboBox<String>), findsNothing);
    expect(_versionBox(tester).controller!.text, '1.0');
    expect(_confirmButton(tester).onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '(1.0)',
    );
    await tester.pump();
    expect(find.text('单值范围必须写成 [版本] 形式'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '2.0',
    );
    await tester.pump();
    await _tapConfirm(tester);

    expect(result, isNotNull);
    expect(result!.name, 'libfoo');
    expect(result!.version, '2.0');
  });

  testWidgets('点击取消返回 null', (tester) async {
    bool completed = false;
    DependencyModel? result;
    await _pumpDialog(
      tester,
      candidates: _candidates(),
      onResult: (DependencyModel? value) {
        completed = true;
        result = value;
      },
    );

    await tester.tap(find.byKey(const Key('dependencyCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(completed, isTrue);
    expect(result, isNull);
    expect(find.byType(ContentDialog), findsNothing);
  });
}

List<PackModel> _candidates() => <PackModel>[
  PackModel(name: 'libfoo', version: '1.0.0', author: 'tester'),
  PackModel(name: 'libbar', version: '2.0.0', author: 'tester'),
];

Future<void> _pumpDialog(
  WidgetTester tester, {
  List<PackModel> candidates = const <PackModel>[],
  DependencyModel? editing,
  ValueChanged<DependencyModel?>? onResult,
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
              final DependencyModel? result = await showDialog<DependencyModel>(
                context: context,
                builder: (_) =>
                    DependencyDialog(candidates: candidates, editing: editing),
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

Future<void> _selectPackage(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('dependencyPackageField')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(name).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dependencyConfirmButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

TextBox _versionBox(WidgetTester tester) =>
    tester.widget<TextBox>(find.byKey(const Key('dependencyVersionField')));

FilledButton _confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('dependencyConfirmButton')),
);
