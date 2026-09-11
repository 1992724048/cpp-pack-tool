import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/pages/pack_packaging.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('渲染打包格式下拉、预览按钮与说明文字', (tester) async {
    await _pumpPage(tester, PackPackaging(pack: _pack()));

    expect(find.text('打包格式'), findsOneWidget);
    expect(find.byKey(const Key('packagingBuilderField')), findsOneWidget);
    expect(find.text('NuGet 包'), findsOneWidget);
    expect(find.byKey(const Key('packPreviewButton')), findsOneWidget);
    expect(find.text('预览打包内容'), findsOneWidget);
    expect(find.textContaining('build/native/include/'), findsOneWidget);
    expect(find.textContaining('预览打包内容」可查看'), findsOneWidget);
  });

  testWidgets('点击预览生成计划并打开对话框', (tester) async {
    final PackModel pack = _pack(sourcePath: r'D:\libs\demo');
    final _FakePackageBuilder builder = _FakePackageBuilder(
      plan: _plan(<PackageEntry>[
        _generated('build/native/demo.nuspec', '<package/>'),
      ]),
    );

    await _pumpPage(
      tester,
      PackPackaging(pack: pack, builders: <PackageBuilder>[builder]),
    );
    await tester.tap(find.byKey(const Key('packPreviewButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(builder.calls, 1);
    expect(builder.receivedPack, same(pack));
    expect(find.byKey(const Key('packPreviewDialog')), findsOneWidget);
  });

  testWidgets('下拉可切换打包格式', (tester) async {
    final _FakePackageBuilder first = _FakePackageBuilder(
      id: 'fake-one',
      displayName: '格式一',
      plan: _plan(<PackageEntry>[]),
    );
    final _FakePackageBuilder second = _FakePackageBuilder(
      id: 'fake-two',
      displayName: '格式二',
      plan: _plan(<PackageEntry>[]),
    );

    await _pumpPage(
      tester,
      PackPackaging(pack: _pack(), builders: <PackageBuilder>[first, second]),
    );

    await tester.tap(find.byKey(const Key('packagingBuilderField')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('格式二').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final ComboBox<String> field = tester.widget<ComboBox<String>>(
      find.byKey(const Key('packagingBuilderField')),
    );
    expect(field.value, 'fake-two');
  });

  testWidgets('缺少源目录时提示且不生成计划', (tester) async {
    final _FakePackageBuilder builder = _FakePackageBuilder(
      plan: _plan(<PackageEntry>[]),
    );

    await _pumpPage(
      tester,
      PackPackaging(pack: _pack(), builders: <PackageBuilder>[builder]),
    );
    await tester.tap(find.byKey(const Key('packPreviewButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(builder.calls, 0);
    expect(find.text('该包缺少源目录信息，无法预览打包内容'), findsOneWidget);
    expect(find.byKey(const Key('packPreviewDialog')), findsNothing);
  });

  testWidgets('生成计划异常时提示预览失败且不打开对话框', (tester) async {
    final _FakePackageBuilder builder = _FakePackageBuilder(
      error: ArgumentError('无法生成计划'),
    );

    await _pumpPage(
      tester,
      PackPackaging(
        pack: _pack(sourcePath: r'D:\libs\demo'),
        builders: <PackageBuilder>[builder],
      ),
    );
    await tester.tap(find.byKey(const Key('packPreviewButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('预览失败：无法生成计划'), findsOneWidget);
    expect(find.byKey(const Key('packPreviewDialog')), findsNothing);
  });

  testWidgets('无可用打包格式时预览按钮禁用', (tester) async {
    await _pumpPage(
      tester,
      PackPackaging(pack: _pack(), builders: const <PackageBuilder>[]),
    );

    final FilledButton button = tester.widget<FilledButton>(
      find.byKey(const Key('packPreviewButton')),
    );
    expect(button.onPressed, isNull);
  });
}

class _FakePackageBuilder implements PackageBuilder {
  _FakePackageBuilder({
    this.id = 'fake',
    this.displayName = '测试包',
    this.plan,
    this.error,
  });

  @override
  final String id;

  @override
  final String displayName;

  final PackagePlan? plan;
  final Object? error;
  int calls = 0;
  PackModel? receivedPack;

  @override
  Future<PackagePlan> buildPlan(PackModel pack) async {
    calls++;
    receivedPack = pack;
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    return plan!;
  }
}

PackModel _pack({String? sourcePath}) => PackModel(
  name: 'demo',
  version: '1.0.0',
  author: 'tester',
  sourcePath: sourcePath,
);

PackagePlan _plan(List<PackageEntry> entries) => PackagePlan(entries: entries);

PackageEntry _generated(String packagePath, String content) {
  return PackageEntry(
    packagePath: packagePath,
    source: PackageGeneratedSource(content: content),
  );
}

Future<void> _pumpPage(WidgetTester tester, PackPackaging page) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(home: page));
  await tester.pump();
}
