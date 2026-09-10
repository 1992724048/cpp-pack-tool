import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/pages/pack_files.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('展示包内文件表格', (tester) async {
    final PackModel pack =
        PackModel(name: 'demo', version: '1.0.0', author: 'tester')
          ..files = <FileModel>[
            FileModel(name: 'foo.h', path: 'include/foo.h', size: 2048),
            FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 512),
          ];

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('路径'), findsOneWidget);
    expect(find.text('大小'), findsOneWidget);
    expect(find.text('foo.h'), findsOneWidget);
    expect(find.text('include/foo.h'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('main.cpp'), findsOneWidget);
    expect(find.text('src/main.cpp'), findsOneWidget);
    expect(find.text('512 B'), findsOneWidget);
  });

  testWidgets('空文件列表显示提示', (tester) async {
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
    );

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(find.text('该包暂无文件'), findsOneWidget);
    expect(find.byType(Table), findsNothing);
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(home: page));
  await tester.pump();
}
