import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/models/pack_project.dart';
import 'package:cpp_nuget_pack/services/package_registry.dart';
import 'package:cpp_nuget_pack/services/path_utils.dart';
import 'package:cpp_nuget_pack/services/settings.dart';
import 'package:cpp_nuget_pack/ui/main_shell.dart';
import 'package:cpp_nuget_pack/ui/theme.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    AppSettings? settings,
    List<PackProject>? initialPackages,
    String? registryOutputDir,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        theme: buildDarkTheme(),
        darkTheme: buildDarkTheme(),
        home: MainShell(
          settings: settings ?? AppSettings(),
          initialPackages: initialPackages,
          registryOutputDir: registryOutputDir,
        ),
      ),
    );
  }

  testWidgets('应用启动并渲染五个 Tab 与左栏设置按钮', (WidgetTester tester) async {
    await pumpApp(tester);

    // 顶部工具栏已移除：不再有旧的标题文本。
    expect(find.text('C++ NuGet 打包工具'), findsNothing);
    // 五个 Tab 均渲染。
    expect(find.text('包信息'), findsOneWidget);
    expect(find.text('文件映射'), findsOneWidget);
    expect(find.text('依赖管理'), findsOneWidget);
    expect(find.text('编译配置'), findsOneWidget);
    expect(find.text('打包'), findsOneWidget);
    // 左栏顶部有设置按钮。
    expect(find.byTooltip('设置'), findsOneWidget);
  });

  testWidgets('未添加库项目时显示左栏空态', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('尚未添加库项目'), findsOneWidget);
    // 未选中库项目时，当前「包信息」页显示占位。
    expect(find.text('从左侧选择一个库项目开始编辑'), findsOneWidget);
  });

  testWidgets('点击左栏 + 弹出添加源目录对话框（新建库项目流程入口）', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('添加库项目'));
    await tester.pumpAndSettle();

    expect(find.text('添加源目录'), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);

    // 取消关闭对话框。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('添加源目录'), findsNothing);
  });

  testWidgets('已有选中项目时点击左栏 + 仍打开新建库项目对话框', (WidgetTester tester) async {
    await pumpApp(
      tester,
      initialPackages: [PackProject(packageId: 'V8.Native', version: '1.0.0')],
    );

    // 首个项目被自动选中，此时 + 仍应触发「新建库项目」流程而非「加源目录到当前项目」。
    await tester.tap(find.byTooltip('添加库项目'));
    await tester.pumpAndSettle();

    expect(find.text('添加源目录'), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('添加源目录'), findsNothing);
  });

  testWidgets('注入两个库项目时左栏渲染两条', (WidgetTester tester) async {
    await pumpApp(
      tester,
      initialPackages: [
        PackProject(packageId: 'V8.Native', version: '1.0.0'),
        PackProject(packageId: 'Zlib', version: '2.0.0'),
      ],
    );

    // 两个库项目均出现在左栏（不再只显示一个）。
    expect(find.text('V8.Native'), findsWidgets);
    expect(find.text('Zlib'), findsWidgets);
    expect(find.text('尚未添加库项目'), findsNothing);
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

  testWidgets('输出目录注册表有包时左栏恢复并显示包名与版本', (WidgetTester tester) async {
    final tempRoot = Directory.systemTemp.createTempSync('widget_registry_');
    addTearDown(() {
      try {
        tempRoot.deleteSync(recursive: true);
      } catch (_) {
        // 清理失败不阻塞测试。
      }
    });
    final out = joinPath([tempRoot.path, 'out']);
    saveRegistry(out, [
      RegisteredPackage(
        project: PackProject(packageId: 'V8.Native', version: '15.2.124.1'),
        lastPackedAt: DateTime.now(),
      ),
    ]);

    await pumpApp(
      tester,
      settings: AppSettings(defaultOutputDir: out),
      registryOutputDir: out,
    );

    // 注册表恢复的包出现在左栏（行内 Text + 已选中项目的表单字段，故至少一处）。
    expect(find.text('V8.Native'), findsWidgets);
    expect(find.text('15.2.124.1'), findsWidgets);
    // 不再显示空态文案。
    expect(find.text('尚未添加库项目'), findsNothing);
  });
}
