import 'package:cpp_nuget_pack/controls/pack_preview_dialog.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('默认全部展开并渲染目录与文件', (tester) async {
    final PackagePlan plan = _plan(<PackageEntry>[
      _generated('build/native/demo.nuspec', '<package>nuspec</package>'),
      _generated('build/native/demo.targets', '<Project>targets</Project>'),
      _file('build/native/include/foo.h', 'include/foo.h'),
      _file('build/native/include/detail/bar.h', 'include/detail/bar.h'),
    ]);

    await _pumpDialog(tester, plan: plan);

    expect(find.byKey(const Key('packPreviewDialog')), findsOneWidget);
    expect(find.text('打包预览'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    expect(find.text('native'), findsOneWidget);
    expect(find.text('include'), findsOneWidget);
    expect(find.text('detail'), findsOneWidget);
    expect(find.text('demo.nuspec'), findsOneWidget);
    expect(find.text('demo.targets'), findsOneWidget);
    expect(find.text('foo.h'), findsOneWidget);
    expect(find.text('bar.h'), findsOneWidget);
    expect(find.text('选择左侧文件预览内容'), findsOneWidget);
  });

  testWidgets('点击目录行与箭头均可折叠展开', (tester) async {
    final PackagePlan plan = _plan(<PackageEntry>[
      _file('build/native/include/foo.h', 'include/foo.h'),
      _file('build/native/include/detail/bar.h', 'include/detail/bar.h'),
    ]);

    await _pumpDialog(tester, plan: plan);
    expect(find.text('foo.h'), findsOneWidget);
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.text('include'));
    await tester.pump();
    expect(find.text('foo.h'), findsNothing);
    expect(find.text('detail'), findsNothing);

    await tester.tap(find.text('include'));
    await tester.pump();
    expect(find.text('foo.h'), findsOneWidget);
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.chevron_down).first);
    await tester.pump();
    expect(find.text('include'), findsNothing);
    expect(find.text('foo.h'), findsNothing);
  });

  testWidgets('点击生成文件显示内容与信息头', (tester) async {
    final PackagePlan plan = _plan(<PackageEntry>[
      _generated('build/native/demo.nuspec', '<package>生成内容</package>'),
    ]);

    await _pumpDialog(tester, plan: plan);
    await tester.tap(find.text('demo.nuspec'));
    await tester.pump();

    expect(find.text('build/native/demo.nuspec'), findsOneWidget);
    expect(find.text('生成文件'), findsOneWidget);
    expect(find.textContaining('生成内容'), findsOneWidget);
  });

  testWidgets('点击源文件经注入读取器显示内容', (tester) async {
    final PackagePlan plan = _plan(<PackageEntry>[
      _file('build/native/include/foo.h', 'include/foo.h', size: 12),
    ]);
    String? requested;

    await _pumpDialog(
      tester,
      plan: plan,
      readFile: (String path) async {
        requested = path;
        return '#pragma once\nint foo();';
      },
    );
    await tester.tap(find.text('foo.h'));
    await tester.pump();
    await tester.pump();

    expect(requested, r'D:\libs\demo/include/foo.h');
    expect(find.text('源文件'), findsOneWidget);
    expect(find.textContaining('#pragma once'), findsOneWidget);
  });

  testWidgets('源文件读取失败显示错误提示', (tester) async {
    final PackagePlan plan = _plan(<PackageEntry>[
      _file('build/native/include/foo.h', 'include/foo.h'),
    ]);

    await _pumpDialog(
      tester,
      plan: plan,
      readFile: (String path) async => throw ArgumentError('无法读取文件'),
    );
    await tester.tap(find.text('foo.h'));
    await tester.pump();
    await tester.pump();

    expect(find.text('读取失败：无法读取文件'), findsOneWidget);
  });

  testWidgets('点击二进制文件显示无法预览提示', (tester) async {
    final PackagePlan plan = _plan(<PackageEntry>[
      _file(
        'build/native/lib/x64/Release/foo.lib',
        'lib/x64/Release/foo.lib',
        isBinary: true,
        size: 2048,
      ),
    ]);

    await _pumpDialog(tester, plan: plan);
    await tester.tap(find.text('foo.lib'));
    await tester.pump();

    expect(find.text('二进制文件（2.0 KB），无法预览'), findsOneWidget);
    expect(find.text('二进制文件'), findsOneWidget);
  });

  testWidgets('点击关闭按钮关闭对话框', (tester) async {
    await _pumpDialog(
      tester,
      plan: _plan(<PackageEntry>[
        _generated('build/native/demo.nuspec', '<package/>'),
      ]),
    );

    await tester.tap(find.byKey(const Key('packPreviewCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('packPreviewDialog')), findsNothing);
  });
}

PackagePlan _plan(List<PackageEntry> entries) => PackagePlan(entries: entries);

PackageEntry _file(
  String packagePath,
  String sourcePath, {
  bool isBinary = false,
  int size = 10,
}) {
  return PackageEntry(
    packagePath: packagePath,
    source: PackageFileSource(path: sourcePath, isBinary: isBinary, size: size),
  );
}

PackageEntry _generated(String packagePath, String content) {
  return PackageEntry(
    packagePath: packagePath,
    source: PackageGeneratedSource(content: content),
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required PackagePlan plan,
  Future<String> Function(String path)? readFile,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final PackModel pack = PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
    sourcePath: r'D:\libs\demo',
  );

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () async {
              await showPackPreviewDialog(
                context,
                pack: pack,
                plan: plan,
                readFile: readFile ?? (String path) async => '',
              );
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
