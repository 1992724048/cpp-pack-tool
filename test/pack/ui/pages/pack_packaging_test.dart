import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/pack/ui/pages/pack_packaging.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('渲染预览按钮与 NuGet 说明文字', (tester) async {
    await _pumpPage(tester, PackPackaging(pack: _pack()));

    expect(find.byKey(const Key('packPreviewButton')), findsOneWidget);
    expect(find.text('预览打包内容'), findsOneWidget);
    expect(find.textContaining('build/native/include/'), findsOneWidget);
    expect(find.textContaining('build/native/files/'), findsOneWidget);
    expect(find.textContaining('.nuspec'), findsOneWidget);
    expect(find.textContaining('预览打包内容」可查看'), findsOneWidget);
    // 子目录清单直接由 filesSubdirectories 拼出：共享常量改名而文案未跟随时本用例转红，
    // 不必等到用户在预览对话框里发现文案与实际落点不符。
    expect(find.textContaining(filesSubdirectories.join(' / ')), findsOneWidget);
    expect(find.textContaining('根级许可证直接放在 files/ 下'), findsOneWidget);
  });

  testWidgets('渲染消费方契约：五条失效边界逐条可见', (tester) async {
    await _pumpPage(tester, PackPackaging(pack: _pack()));

    // 违反后 NuGet / MSBuild 一律不报错，只静默失效；删掉任一句用户就再也无从得知。
    expect(find.textContaining('违反后均无任何报错'), findsOneWidget);
    expect(find.textContaining('native 段名必须字面一致'), findsOneWidget);
    expect(find.textContaining('native@0.0'), findsOneWidget);
    expect(find.textContaining('「包 ID.targets」与「包 ID.props」'), findsOneWidget);
    expect(find.textContaining('只有 .vcxproj（含 C++/CLI）项目会导入'), findsOneWidget);
    expect(find.textContaining('名为 build / out 的目录'), findsOneWidget);
    // 第 5 条（.lib / .a 的配置隔离）沿用既有提示，不重复写。
    expect(find.textContaining('release / debug 目录名'), findsOneWidget);
  });

  testWidgets('点击预览生成 NuGet 计划并打开对话框', (tester) async {
    await _pumpPage(
      tester,
      PackPackaging(pack: _pack(sourcePath: r'D:\libs\demo')),
    );
    await tester.tap(find.byKey(const Key('packPreviewButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('packPreviewDialog')), findsOneWidget);
  });

  testWidgets('缺少源目录时提示且不打开预览对话框', (tester) async {
    await _pumpPage(tester, PackPackaging(pack: _pack()));
    await tester.tap(find.byKey(const Key('packPreviewButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('该包缺少源目录信息，无法预览打包内容'), findsOneWidget);
    expect(find.byKey(const Key('packPreviewDialog')), findsNothing);
  });
}

PackModel _pack({String? sourcePath}) => PackModel(
  name: 'demo',
  version: '1.0.0',
  author: 'tester',
  sourcePath: sourcePath,
)
  ..files = <FileModel>[
    FileModel(name: 'foo.h', path: 'include/foo.h', size: 512),
  ];

Future<void> _pumpPage(WidgetTester tester, PackPackaging page) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(home: page));
  await tester.pump();
}
