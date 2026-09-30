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

  testWidgets('渲染消费方契约：两条用户约束编号可见，工具自身布局约定不上 UI', (tester) async {
    await _pumpPage(tester, PackPackaging(pack: _pack()));

    // 违反后 NuGet / MSBuild 一律不报错，只静默失效；删掉任一条用户就再也无从得知。
    expect(find.textContaining('两条硬性约束'), findsOneWidget);
    expect(find.textContaining('违反后不会有任何报错'), findsOneWidget);
    expect(find.textContaining('1. 产物不要放进点开头的目录'), findsOneWidget);
    expect(find.textContaining('把目录命名为 build 或 out（任意层级都算）'), findsOneWidget);
    expect(find.textContaining('2. 本包生成的 .targets 只会被'), findsOneWidget);
    expect(find.textContaining('只会被 .vcxproj（含 C++/CLI）工程导入'), findsOneWidget);
    // .props 与 .targets 的导入范围差异曾被写成「其它项目类型不导入」，与事实相反；
    // 即使该句已移出配包页，也要防止它改回来。
    expect(find.textContaining('其它项目类型不导入'), findsNothing);
    // 工具自身的包内布局（native 段名、文件名）不是用户能行动的事，只属 README。
    // 混进配包页等于让读者去遵守一件自己控制不了的约定，故以 findsNothing 钉住。
    expect(find.textContaining('native@0.0'), findsNothing);
    expect(find.textContaining('native 段名必须字面一致'), findsNothing);
    expect(find.textContaining('「包 ID.targets」与「包 ID.props」'), findsNothing);
    // .lib / .a 的配置隔离沿用 _description 的既有提示，不在契约段重复写。
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
