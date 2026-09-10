import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/pages/pack_files.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('默认全部折叠所有目录', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'README.md', path: 'README.md', size: 100),
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 2048),
      FileModel(name: 'bar.h', path: 'include/detail/bar.h', size: 1024),
      FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 512),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('include'), findsOneWidget);
    expect(find.text('src'), findsOneWidget);
    expect(find.text('foo.h'), findsNothing);
    expect(find.text('detail'), findsNothing);
    expect(find.text('bar.h'), findsNothing);
    expect(find.text('main.cpp'), findsNothing);

    _expectRowSize('include', '3.0 KB');
    _expectRowSize('src', '512 B');
    _expectRowSize('README.md', '100 B');

    expect(_iconAssets(tester), contains(_latte('folder_include')));
    expect(find.byIcon(FluentIcons.chevron_down), findsNothing);
    expect(find.byIcon(FluentIcons.chevron_right), findsNWidgets(2));
  });

  testWidgets('点击目录行切换展开与折叠', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 2048),
      FileModel(name: 'bar.h', path: 'include/detail/bar.h', size: 1024),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    expect(find.text('bar.h'), findsNothing);
    expect(find.text('detail'), findsNothing);

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('foo.h'), findsOneWidget);
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.text('detail'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('bar.h'), findsOneWidget);

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('foo.h'), findsNothing);
    expect(find.text('detail'), findsNothing);

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('foo.h'), findsOneWidget);
    expect(find.text('bar.h'), findsOneWidget);
  });

  testWidgets('点击展开箭头切换展开与折叠', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'bar.h', path: 'include/detail/bar.h', size: 1024),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    expect(find.text('bar.h'), findsNothing);

    await tester.tap(find.byIcon(FluentIcons.chevron_right));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('detail'), findsOneWidget);
    expect(find.text('bar.h'), findsNothing);

    await tester.tap(find.byIcon(FluentIcons.chevron_right));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('bar.h'), findsOneWidget);
  });

  testWidgets('目录在前文件在后且名称大小写不敏感排序', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'a.cpp', path: 'src/a.cpp', size: 30),
      FileModel(name: 'Main.cpp', path: 'Main.cpp', size: 60),
      FileModel(name: 'b.cpp', path: 'Include/b.cpp', size: 20),
      FileModel(name: 'zeta.cpp', path: 'zeta.cpp', size: 70),
      FileModel(name: 'x.cpp', path: 'Beta/x.cpp', size: 40),
      FileModel(name: 'y.cpp', path: 'beta/y.cpp', size: 50),
      FileModel(name: 'c.cpp', path: 'alpha/c.cpp', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    final double yAlpha = tester.getTopLeft(find.text('alpha')).dy;
    final double yBeta = tester.getTopLeft(find.text('Beta')).dy;
    final double yBetaLower = tester.getTopLeft(find.text('beta')).dy;
    final double yInclude = tester.getTopLeft(find.text('Include')).dy;
    final double ySrc = tester.getTopLeft(find.text('src')).dy;
    final double yMain = tester.getTopLeft(find.text('Main.cpp')).dy;
    final double yZeta = tester.getTopLeft(find.text('zeta.cpp')).dy;

    expect(yAlpha, lessThan(yBeta));
    expect(yBeta, lessThan(yBetaLower));
    expect(yBetaLower, lessThan(yInclude));
    expect(yInclude, lessThan(ySrc));
    expect(ySrc, lessThan(yMain));
    expect(yMain, lessThan(yZeta));
  });

  testWidgets('空文件列表显示提示', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[]);

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(find.text('该包暂无文件'), findsOneWidget);
    expect(find.byType(TreeView), findsNothing);
  });

  testWidgets('切换包时重置为全部折叠', (tester) async {
    final PackModel first = _pack('demo', <FileModel>[
      FileModel(name: 'one.cpp', path: 'a/one/one.cpp', size: 10),
    ]);
    await _pumpPage(tester, PackFiles(pack: first));

    expect(find.text('a'), findsOneWidget);
    expect(find.text('one'), findsNothing);

    await tester.tap(find.text('a'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('one'), findsOneWidget);

    await tester.tap(find.text('one'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('one.cpp'), findsOneWidget);

    final PackModel second = _pack('other', <FileModel>[
      FileModel(name: 'two.cpp', path: 'a/one/two.cpp', size: 20),
    ]);
    await _pumpPage(tester, PackFiles(pack: second));

    expect(find.text('a'), findsOneWidget);
    expect(find.text('one'), findsNothing);
    expect(find.text('two.cpp'), findsNothing);
  });

  testWidgets('同包内容更新保持展开状态', (tester) async {
    final PackModel before = _pack('demo', <FileModel>[
      FileModel(name: 'one.cpp', path: 'a/one/one.cpp', size: 10),
    ]);
    await _pumpPage(tester, PackFiles(pack: before));

    expect(find.text('one'), findsNothing);

    await tester.tap(find.text('a'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('one'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('one.cpp'), findsOneWidget);

    final PackModel after = _pack('demo', <FileModel>[
      FileModel(name: 'one.cpp', path: 'a/one/one.cpp', size: 10),
      FileModel(name: 'extra.cpp', path: 'a/one/extra.cpp', size: 5),
    ]);
    await _pumpPage(tester, PackFiles(pack: after));

    expect(find.text('one'), findsOneWidget);
    expect(find.text('one.cpp'), findsOneWidget);
    expect(find.text('extra.cpp'), findsOneWidget);
  });

  testWidgets('兼容反斜杠路径分隔符', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'deep.cpp', path: r'src\win\deep.cpp', size: 7),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(find.text('src'), findsOneWidget);
    expect(find.text('win'), findsNothing);
    expect(find.text('deep.cpp'), findsNothing);

    await tester.tap(find.text('src'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('win'), findsOneWidget);

    await tester.tap(find.text('win'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('deep.cpp'), findsOneWidget);
  });

  testWidgets('目录与文件使用 catppuccin 图标', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'README.md', path: 'README.md', size: 100),
      FileModel(name: 'foo.h', path: 'foo.h', size: 2048),
      FileModel(name: 'main.cpp', path: 'main.cpp', size: 512),
      FileModel(name: 'tool.py', path: 'tool.py', size: 20),
      FileModel(name: 'unknown.xyz', path: 'unknown.xyz', size: 10),
      FileModel(name: 'bar.h', path: 'include/bar.h', size: 64),
      FileModel(name: 'deep.cpp', path: 'src/deep.cpp', size: 32),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    final List<String> icons = _iconAssets(tester);
    expect(icons, contains(_latte('readme')));
    expect(icons, contains(_latte('c-header')));
    expect(icons, contains(_latte('cpp')));
    expect(icons, contains(_latte('python')));
    expect(icons, contains(_latte('_file')));
    expect(icons, contains(_latte('folder_include')));
    expect(icons, contains(_latte('folder_src')));
    expect(icons, isNot(contains(_latte('folder_include_open'))));
    expect(icons, isNot(contains(_latte('folder_src_open'))));
    expect(find.byIcon(FluentIcons.folder), findsNothing);
    expect(find.byIcon(FluentIcons.document), findsNothing);
  });

  testWidgets('目录图标按名称解析且展开态切换为 _open', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'bar.h', path: 'include/detail/bar.h', size: 1024),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(_iconAssets(tester), contains(_latte('folder_include')));
    expect(_iconAssets(tester), isNot(contains(_latte('folder_include_open'))));
    expect(_iconAssets(tester), isNot(contains(_latte('_folder'))));

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_iconAssets(tester), contains(_latte('folder_include_open')));
    expect(_iconAssets(tester), contains(_latte('_folder')));

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_iconAssets(tester), contains(_latte('folder_include')));
    expect(_iconAssets(tester), isNot(contains(_latte('folder_include_open'))));
  });

  testWidgets('深色主题使用 mocha 图标', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'main.cpp', path: 'main.cpp', size: 10),
      FileModel(name: 'tool.py', path: 'src/tool.py', size: 5),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack), dark: true);

    expect(_iconAssets(tester), contains(_mocha('cpp')));
    expect(_iconAssets(tester), contains(_mocha('folder_src')));
  });
}

PackModel _pack(String name, List<FileModel> files) {
  return PackModel(name: name, version: '1.0.0', author: 'tester')
    ..files = files;
}

Finder _contentRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Row)).first;

void _expectRowSize(String name, String size) {
  expect(
    find.descendant(of: _contentRow(name), matching: find.text(size)),
    findsOneWidget,
  );
}

String _latte(String icon) => 'assets/icons/catppuccin/latte/$icon.svg';

String _mocha(String icon) => 'assets/icons/catppuccin/mocha/$icon.svg';

List<String> _iconAssets(WidgetTester tester) => tester
    .widgetList<SvgPicture>(find.byType(SvgPicture))
    .map(
      (SvgPicture picture) => (picture.bytesLoader as SvgAssetLoader).assetName,
    )
    .toList();

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      theme: dark ? FluentThemeData.dark() : FluentThemeData.light(),
      home: page,
    ),
  );
  await tester.pump();
}
