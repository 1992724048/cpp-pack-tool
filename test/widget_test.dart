import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/main.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PackTool());
  }

  testWidgets('应用启动并渲染顶部工具栏与四个 Tab', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('C++ NuGet 打包工具'), findsOneWidget);
    expect(find.text('包信息'), findsOneWidget);
    expect(find.text('文件映射'), findsOneWidget);
    expect(find.text('编译配置'), findsOneWidget);
    expect(find.text('打包'), findsOneWidget);
  });

  testWidgets('未添加库项目时显示左栏空态', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('尚未添加库项目'), findsOneWidget);
    // 未选中库项目时，当前「包信息」页显示占位。
    expect(find.text('从左侧选择一个库项目开始编辑'), findsOneWidget);
  });

  testWidgets('点击左栏 + 弹出添加源目录对话框', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('添加源目录'));
    await tester.pumpAndSettle();

    expect(find.text('添加源目录'), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);

    // 取消关闭对话框。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('添加源目录'), findsNothing);
  });

  testWidgets('Tab 切换到不同页显示对应占位', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('打包'));
    await tester.pumpAndSettle();
    expect(find.text('从左侧选择一个库项目开始打包'), findsOneWidget);

    await tester.tap(find.text('编译配置'));
    await tester.pumpAndSettle();
    expect(find.text('从左侧选择一个库项目开始编辑'), findsOneWidget);
  });

  testWidgets('底部日志面板可折叠/展开', (WidgetTester tester) async {
    await pumpApp(tester);

    // 初始为展开态（折叠箭头是「折叠日志」），且已有一条启动日志。
    expect(find.byTooltip('折叠日志'), findsOneWidget);
    expect(find.textContaining('应用已启动'), findsOneWidget);

    await tester.tap(find.byTooltip('折叠日志'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开日志'), findsOneWidget);
  });
}
