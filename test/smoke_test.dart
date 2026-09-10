import 'package:cpp_nuget_pack/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('应用启动后渲染主界面关键元素', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PackTool());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationView), findsOneWidget);
    expect(find.text('C++ NuGet 打包工具'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  });
}
