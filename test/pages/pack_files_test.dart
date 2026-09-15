import 'dart:async';

import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/pages/pack_files.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

  // 目录节点由文件路径派生，不存在空目录节点（计数恒 ≥1），故无空目录展示口径。
  testWidgets('目录名称后显示后代文件计数', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'README.md', path: 'README.md', size: 100),
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 2048),
      FileModel(name: 'bar.h', path: 'include/detail/bar.h', size: 1024),
      FileModel(name: 'baz.h', path: 'include/detail/baz.h', size: 512),
      FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 512),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    _expectRowSize('include', '(3 个文件)');
    _expectRowSize('src', '(1 个文件)');
    expect(find.text('(2 个文件)'), findsNothing);

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));
    _expectRowSize('detail', '(2 个文件)');

    await tester.tap(find.text('detail'));
    await tester.pump(const Duration(milliseconds: 400));
    _expectRowSize('foo.h', '2.0 KB');
    _expectRowSize('bar.h', '1.0 KB');
  });

  testWidgets('文件行不显示文件计数', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'README.md', path: 'README.md', size: 100),
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    expect(find.textContaining('个文件'), findsOneWidget);

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('foo.h'), findsOneWidget);
    expect(find.textContaining('个文件'), findsOneWidget);
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

  testWidgets('双击文件行以绝对路径调用 openFile', (tester) async {
    final List<String> opened = <String>[];
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
    ], sourcePath: r'C:\libs\foo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        openFile: (String path) async {
          opened.add(path);
          return true;
        },
      ),
    );

    await tester.tap(find.text('include'));
    await tester.pump(const Duration(milliseconds: 400));

    await _doubleTapFile(tester, 'foo.h');

    expect(opened, <String>[r'C:\libs\foo/include/foo.h']);
  });

  testWidgets('缺少源目录信息时双击文件提示错误且不调用 openFile', (tester) async {
    bool called = false;
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'foo.h', path: 'foo.h', size: 10),
    ]);

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        openFile: (String path) async {
          called = true;
          return true;
        },
      ),
    );

    await _doubleTapFile(tester, 'foo.h');

    expect(called, isFalse);
    expect(find.text('该包缺少源目录信息，无法打开文件'), findsOneWidget);
  });

  testWidgets('打开失败时显示错误提示', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'foo.h', path: 'foo.h', size: 10),
    ], sourcePath: r'C:\libs\foo');

    await _pumpPage(
      tester,
      PackFiles(pack: pack, openFile: (String path) async => false),
    );

    await _doubleTapFile(tester, 'foo.h');

    expect(find.text('无法打开文件：foo.h'), findsOneWidget);
  });

  testWidgets('Release 路径的二进制文件显示绿色 Release 标签', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'mylib.lib', path: 'release/mylib.lib', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    await tester.tap(find.text('release'));
    await tester.pump(const Duration(milliseconds: 400));

    final Tag tag = tester.widget<Tag>(find.byType(Tag));
    expect(tag.text, releaseBuildLabel);
    expect(tag.color, UCColors.flavor.green);
    expect(tag.fontSize, 10);
  });

  testWidgets('Debug 路径的二进制文件显示橙色 Debug 标签', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'mylib.pdb', path: r'out\debug\mylib.pdb', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    await tester.tap(find.text('out'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('debug'));
    await tester.pump(const Duration(milliseconds: 400));

    final Tag tag = tester.widget<Tag>(find.byType(Tag));
    expect(tag.text, debugBuildLabel);
    expect(tag.color, UCColors.flavor.peach);
  });

  testWidgets('构建标签紧贴名称右侧 5px', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'mylib.lib', path: 'release/mylib.lib', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    await tester.tap(find.text('release'));
    await tester.pump(const Duration(milliseconds: 400));

    final Rect nameRect = tester.getRect(find.text('mylib.lib'));
    final Rect tagRect = tester.getRect(find.byType(Tag));
    expect(tagRect.left - nameRect.right, 5);
  });

  testWidgets('超长名称先省略且标签完整可见', (tester) async {
    final String longName = '${'long_component_name_' * 10}mylib.lib';
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: longName, path: 'release/$longName', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    await tester.tap(find.text('release'));
    await tester.pump(const Duration(milliseconds: 400));

    final Finder row = find
        .ancestor(of: find.text(longName), matching: find.byType(Row))
        .at(1);
    final Rect nameRect = tester.getRect(find.text(longName));
    final Rect tagRect = tester.getRect(find.byType(Tag));
    final Rect sizeRect = tester.getRect(
      find.descendant(of: row, matching: find.text('10 B')),
    );

    expect(tagRect.left - nameRect.right, 5);
    expect(sizeRect.left - tagRect.right, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('路径无构建配置段时不显示标签', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'mylib.lib', path: 'mylib.lib', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(find.text('mylib.lib'), findsOneWidget);
    expect(find.byType(Tag), findsNothing);
  });

  testWidgets('非二进制类型不显示构建标签', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'foo.cpp', path: 'release/foo.cpp', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));
    await tester.tap(find.text('release'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('foo.cpp'), findsOneWidget);
    expect(find.byType(Tag), findsNothing);
  });

  testWidgets('exe 与 msi 文件使用 exe 图标', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'tool.exe', path: 'tool.exe', size: 10),
      FileModel(name: 'setup.msi', path: 'setup.msi', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    final List<String> exeIcons = _iconAssets(tester)
        .where((String icon) => icon == _latte('exe'))
        .toList();
    expect(exeIcons.length, 2);
  });

  testWidgets('根级 build.py 且注入回调时显示构建按钮并回调当前包', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'build.py', path: 'build.py', size: 10),
      FileModel(name: 'main.cpp', path: 'main.cpp', size: 20),
    ]);
    PackModel? built;

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {
          built = value;
        },
      ),
    );

    final Finder button = find.byKey(const Key('buildPackButton'));
    expect(button, findsOneWidget);
    expect(find.text('构建'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(built, same(pack));
  });

  testWidgets('无回调时不显示构建按钮', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'Build.py', path: 'Build.py', size: 10),
    ]);

    await _pumpPage(tester, PackFiles(pack: pack));

    expect(find.byKey(const Key('buildPackButton')), findsNothing);
    expect(find.text('构建'), findsNothing);
    expect(find.text('Build.py'), findsOneWidget);
  });

  testWidgets('子目录 build.py 不显示构建按钮', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[
      FileModel(name: 'build.py', path: 'scripts/build.py', size: 10),
    ]);

    await _pumpPage(
      tester,
      PackFiles(pack: pack, onBuildPack: (PackModel value) async {}),
    );

    expect(find.byKey(const Key('buildPackButton')), findsNothing);
  });

  testWidgets('空文件列表不显示构建按钮', (tester) async {
    final PackModel pack = _pack('demo', <FileModel>[]);

    await _pumpPage(
      tester,
      PackFiles(pack: pack, onBuildPack: (PackModel value) async {}),
    );

    expect(find.text('该包暂无文件'), findsOneWidget);
    expect(find.byKey(const Key('buildPackButton')), findsNothing);
  });

  testWidgets('声明选项时渲染控件且显示默认值', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('buildOption_tbb')), findsOneWidget);
    expect(find.text('tbb'), findsOneWidget);
    final ComboBox<String> combo = _optionCombo(tester, 'tbb');
    expect(combo.value, 'off');
    expect(
      <String>[
        for (final ComboBoxItem<String> item in combo.items ?? const [])
          item.value!,
      ],
      <String>['off', 'on'],
    );
  });

  testWidgets('已保存的选项值优先于默认值', (tester) async {
    final PackModel pack = _buildPack('demo')
      ..buildOptions = <String, String>{'tbb': 'on'};

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    expect(_optionCombo(tester, 'tbb').value, 'on');
  });

  testWidgets('选择选项后保存全字段拷贝并提示已保存', (tester) async {
    final PackModel pack = _buildPack('demo')
      ..buildOptions = <String, String>{'other': 'keep'};
    PackModel? saved;

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async {
          saved = value;
          return true;
        },
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    await _selectBuildOption(tester, 'tbb', 'on');

    expect(saved, isNotNull);
    expect(saved, isNot(same(pack)));
    expect(saved!.buildOptions, <String, String>{'other': 'keep', 'tbb': 'on'});
    expect(saved!.name, 'demo');
    expect(saved!.version, '1.0.0');
    expect(saved!.author, 'tester');
    expect(saved!.files, same(pack.files));
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('保存失败时提示保存失败', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => false,
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    await _selectBuildOption(tester, 'tbb', 'on');

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('保存抛异常时提示保存失败且不崩溃', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => throw StateError('磁盘写入失败'),
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    await _selectBuildOption(tester, 'tbb', 'on');

    expect(find.text('保存失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未声明选项时不渲染选项分区但保留运行库选择器', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('buildPackButton')), findsOneWidget);
    expect(find.byKey(const Key('buildOptionsSection')), findsNothing);
    expect(find.byKey(const Key('buildOptionsToggle')), findsNothing);
    expect(find.byKey(const Key('buildRuntimeSelector')), findsOneWidget);
    expect(find.byKey(const Key('buildRuntimeHelp')), findsOneWidget);
  });

  testWidgets('未提供保存回调时不渲染选项分区且运行库下拉禁用', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('buildPackButton')), findsOneWidget);
    expect(find.byKey(const Key('buildOptionsSection')), findsNothing);
    expect(find.byKey(const Key('buildOptionsToggle')), findsNothing);
    expect(find.byKey(const Key('buildOption_tbb')), findsNothing);
    expect(_runtimeCombo(tester).onChanged, isNull);
  });

  testWidgets('头部加载失败时不渲染选项分区且不崩溃', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async =>
            throw const FormatException('头部损坏'),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('buildPackButton')), findsOneWidget);
    expect(find.byKey(const Key('buildOptionsSection')), findsNothing);
    expect(find.byKey(const Key('buildOption_tbb')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('构建脚本路径变化时重新加载选项', (tester) async {
    int calls = 0;
    Future<BuildScriptHeader?> loadHeader(PackModel pack) async {
      calls++;
      return _header(options: const <BuildScriptOption>[_tbbOption]);
    }

    Future<bool> onSave(PackModel pack) async => true;
    Future<void> onBuild(PackModel pack) async {}

    final PackModel before = _pack('demo', <FileModel>[
      FileModel(name: 'main.cpp', path: 'main.cpp', size: 20),
    ]);

    await _pumpPage(
      tester,
      PackFiles(
        pack: before,
        onBuildPack: onBuild,
        onSave: onSave,
        loadHeader: loadHeader,
      ),
    );
    await tester.pump();

    expect(calls, 1);
    expect(find.byKey(const Key('buildOption_tbb')), findsNothing);

    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: onBuild,
        onSave: onSave,
        loadHeader: loadHeader,
      ),
    );
    await tester.pump();

    expect(calls, 2);
    expect(find.byKey(const Key('buildOption_tbb')), findsOneWidget);
  });

  testWidgets('切换包时按新脚本重新加载选项', (tester) async {
    int calls = 0;
    Future<BuildScriptHeader?> loadHeader(PackModel pack) async {
      calls++;
      return pack.name == 'demo'
          ? _header(options: const <BuildScriptOption>[_tbbOption])
          : _header(
              options: const <BuildScriptOption>[
                BuildScriptOption(
                  name: 'target',
                  values: <String>['x64', 'x86'],
                ),
              ],
            );
    }

    Future<bool> onSave(PackModel pack) async => true;
    Future<void> onBuild(PackModel pack) async {}

    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: onBuild,
        onSave: onSave,
        loadHeader: loadHeader,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('buildOption_tbb')), findsOneWidget);

    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('other'),
        onBuildPack: onBuild,
        onSave: onSave,
        loadHeader: loadHeader,
      ),
    );
    await tester.pump();

    expect(calls, 2);
    expect(find.byKey(const Key('buildOption_tbb')), findsNothing);
    expect(find.byKey(const Key('buildOption_target')), findsOneWidget);
  });

  testWidgets('构建选项默认展开且可折叠与展开', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('buildOptionsToggle')), findsOneWidget);
    expect(find.byKey(const Key('buildOption_tbb')), findsOneWidget);

    await tester.tap(find.byKey(const Key('buildOptionsToggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('buildOption_tbb')), findsNothing);
    expect(find.byKey(const Key('buildOptionsToggle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('buildOptionsToggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('buildOption_tbb')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未声明选项或不提供保存回调时不显示折叠开关', (tester) async {
    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('buildOptionsToggle')), findsNothing);

    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('buildOptionsToggle')), findsNothing);
    expect(find.byKey(const Key('buildOption_tbb')), findsNothing);
  });

  testWidgets('大量构建选项不溢出且可纵向滚动', (tester) async {
    final List<BuildScriptOption> options = <BuildScriptOption>[
      for (int index = 0; index < 10; index++)
        BuildScriptOption(
          name: 'opt$index',
          values: const <String>['off', 'on'],
        ),
    ];

    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async => _header(options: options),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('buildOption_opt9')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('buildOptionsScroll'))).height,
      lessThanOrEqualTo(168),
    );

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('buildOptionsScroll')),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      find.byKey(const Key('buildOptionsScroll')),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('三型选项按声明顺序混排渲染', (tester) async {
    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async => _header(
          options: const <BuildScriptOption>[
            _tbbOption,
            _useNasmOption,
            _accelOption,
          ],
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget(find.byKey(const Key('buildOption_tbb'))),
      isA<ComboBox<String>>(),
    );
    expect(
      tester.widget(find.byKey(const Key('buildOption_use_nasm'))),
      isA<Checkbox>(),
    );
    expect(
      tester.widget(find.byKey(const Key('buildOption_accel'))),
      isA<Wrap>(),
    );

    final double tbbY = tester
        .getTopLeft(find.byKey(const Key('buildOptionRow_tbb')))
        .dy;
    final double nasmY = tester
        .getTopLeft(find.byKey(const Key('buildOptionRow_use_nasm')))
        .dy;
    final double accelY = tester
        .getTopLeft(find.byKey(const Key('buildOptionRow_accel')))
        .dy;
    expect(tbbY, lessThan(nasmY));
    expect(nasmY, lessThan(accelY));
  });

  testWidgets('非法保存值显示回退默认值', (tester) async {
    final PackModel pack = _buildPack('demo')
      ..buildOptions = <String, String>{'tbb': 'banana'};

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    expect(_optionCombo(tester, 'tbb').value, 'off');
  });

  testWidgets('复选框行整行可点击切换并保存勾选值', (tester) async {
    final List<PackModel> saves = <PackModel>[];
    Widget page(PackModel pack) => PackFiles(
      pack: pack,
      onBuildPack: (PackModel value) async {},
      onSave: (PackModel value) async {
        saves.add(value);
        return true;
      },
      loadHeader: (PackModel value) async =>
          _header(options: const <BuildScriptOption>[_useNasmOption]),
    );

    PackModel pack = _buildPack('demo');
    await _pumpPage(tester, page(pack));
    await tester.pump();

    expect(
      tester.widget<Checkbox>(find.byKey(const Key('buildOption_use_nasm'))).checked,
      isTrue,
      reason: '首值为勾选态（默认 ON）',
    );

    await tester.tap(find.text('use_nasm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saves.single.buildOptions, <String, String>{'use_nasm': 'OFF'});
    expect(find.text('已保存'), findsOneWidget);

    pack = saves.single;
    await _pumpPage(tester, page(pack));
    await tester.pump();
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('buildOption_use_nasm'))).checked,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('buildOption_use_nasm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saves, hasLength(2));
    expect(saves.last.buildOptions, <String, String>{'use_nasm': 'ON'});
  });

  testWidgets('复选框行悬停显示行背景', (tester) async {
    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_useNasmOption]),
      ),
    );
    await tester.pump();

    final Finder row = find.byKey(const Key('buildOptionRow_use_nasm'));
    expect(_rowDecoration(tester, row).color, Colors.transparent);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('use_nasm')));
    await tester.pump();
    expect(_rowDecoration(tester, row).color, UCColors.flavor.surface0);

    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('buildPackButton'))),
    );
    await tester.pump();
    expect(_rowDecoration(tester, row).color, Colors.transparent);
  });

  testWidgets('多选组渲染勾选态并按声明序以分号连接保存', (tester) async {
    final List<PackModel> saves = <PackModel>[];
    Widget page(PackModel pack) => PackFiles(
      pack: pack,
      onBuildPack: (PackModel value) async {},
      onSave: (PackModel value) async {
        saves.add(value);
        return true;
      },
      loadHeader: (PackModel value) async =>
          _header(options: const <BuildScriptOption>[_accelOption]),
    );

    PackModel pack = _buildPack('demo');
    await _pumpPage(tester, page(pack));
    await tester.pump();

    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('buildOptionValue_accel_SSE2')))
          .checked,
      isFalse,
      reason: '未保存时全部未勾选',
    );

    await tester.tap(find.byKey(const Key('buildOptionValue_accel_AVX2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(saves.single.buildOptions, <String, String>{'accel': 'AVX2'});

    pack = saves.single;
    await _pumpPage(tester, page(pack));
    await tester.pump();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('buildOptionValue_accel_AVX2')))
          .checked,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('buildOptionValue_accel_NEON')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(saves.last.buildOptions, <String, String>{'accel': 'AVX2;NEON'});

    pack = saves.last;
    await _pumpPage(tester, page(pack));
    await tester.pump();
    await tester.tap(find.byKey(const Key('buildOptionValue_accel_AVX2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(saves.last.buildOptions, <String, String>{'accel': 'NEON'});

    pack = saves.last;
    await _pumpPage(tester, page(pack));
    await tester.pump();
    await tester.tap(find.byKey(const Key('buildOptionValue_accel_NEON')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      saves.last.buildOptions,
      <String, String>{'accel': ''},
      reason: '多选允许全不选并保存空串',
    );
  });

  testWidgets('运行库选择器渲染三项且工具栏顺序正确', (tester) async {
    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();

    final ComboBox<String> combo = _runtimeCombo(tester);
    expect(combo.value, 'default');
    expect(
      <String>[
        for (final ComboBoxItem<String> item in combo.items ?? const [])
          item.value!,
      ],
      <String>['default', 'MD', 'MT'],
    );

    final double buttonX = tester
        .getTopLeft(find.byKey(const Key('buildPackButton')))
        .dx;
    final double labelX = tester.getTopLeft(find.text('运行库')).dx;
    final double comboX = tester
        .getTopLeft(find.byKey(const Key('buildRuntimeSelector')))
        .dx;
    final double helpX = tester
        .getTopLeft(find.byKey(const Key('buildRuntimeHelp')))
        .dx;
    expect(buttonX, lessThan(labelX));
    expect(labelX, lessThan(comboX));
    expect(comboX, lessThan(helpX));
  });

  testWidgets('运行库保存值显示为显式项且非法值回退默认项', (tester) async {
    Widget page(PackModel pack) => PackFiles(
      pack: pack,
      onBuildPack: (PackModel value) async {},
      onSave: (PackModel value) async => true,
      loadHeader: (PackModel value) async => _header(),
    );

    await _pumpPage(
      tester,
      page(_buildPack('demo')..buildOptions = <String, String>{'runtime': 'MT'}),
    );
    await tester.pump();
    expect(_runtimeCombo(tester).value, 'MT');

    await _pumpPage(
      tester,
      page(
        _buildPack('demo2')
          ..buildOptions = <String, String>{'runtime': 'gnu'},
      ),
    );
    await tester.pump();
    expect(_runtimeCombo(tester).value, 'default');
  });

  testWidgets('选择运行库 MT 后按写入口径保存并提示已保存', (tester) async {
    PackModel? saved;
    final PackModel pack = _buildPack('demo')
      ..buildOptions = <String, String>{'other': 'keep'};

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async {
          saved = value;
          return true;
        },
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();

    await _selectComboItem(
      tester,
      const Key('buildRuntimeSelector'),
      'MT（静态运行库）',
    );

    expect(saved!.buildOptions, <String, String>{
      'other': 'keep',
      'runtime': 'MT',
    });
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('选择运行库默认项时移除保留键', (tester) async {
    PackModel? saved;
    final PackModel pack = _buildPack('demo')
      ..buildOptions = <String, String>{'runtime': 'MT', 'other': 'keep'};

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async {
          saved = value;
          return true;
        },
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();

    await _selectComboItem(
      tester,
      const Key('buildRuntimeSelector'),
      '默认（跟随配方）',
    );

    expect(saved!.buildOptions, <String, String>{'other': 'keep'});
  });

  testWidgets('选择相同运行库不触发保存', (tester) async {
    int saveCalls = 0;
    final PackModel pack = _buildPack('demo')
      ..buildOptions = <String, String>{'runtime': 'MD'};

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async {
          saveCalls++;
          return true;
        },
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();

    await _selectComboItem(
      tester,
      const Key('buildRuntimeSelector'),
      'MD（动态运行库）',
    );

    expect(saveCalls, 0);
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('帮助按钮悬停显示运行库说明', (tester) async {
    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();

    expect(find.textContaining('MDd'), findsNothing);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('buildRuntimeHelp'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.textContaining('MDd / MTd'), findsOneWidget);
    expect(find.textContaining('优先 MD 并随包分发共享 dll'), findsOneWidget);
    expect(find.textContaining('运行库（MSVC CRT）'), findsOneWidget);
  });

  testWidgets('选项分区位于版本行上方', (tester) async {
    final PackModel pack = _buildPack('demo')..sourceVersion = 'v1.0.0';

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) async => true,
        loadHeader: (PackModel value) async =>
            _header(options: const <BuildScriptOption>[_tbbOption]),
      ),
    );
    await tester.pump();

    final double sectionY = tester
        .getTopLeft(find.byKey(const Key('buildOptionsSection')))
        .dy;
    final double versionY = tester
        .getTopLeft(find.byKey(const Key('packRepoVersionLabel')))
        .dy;
    expect(sectionY, lessThan(versionY));
    expect(find.byKey(const Key('buildPackButton')), findsOneWidget);
  });

  testWidgets('保存挂起时选项控件与运行库下拉禁用', (tester) async {
    final Completer<bool> pending = Completer<bool>();

    await _pumpPage(
      tester,
      PackFiles(
        pack: _buildPack('demo'),
        onBuildPack: (PackModel value) async {},
        onSave: (PackModel value) => pending.future,
        loadHeader: (PackModel value) async => _header(
          options: const <BuildScriptOption>[_tbbOption, _useNasmOption],
        ),
      ),
    );
    await tester.pump();

    await _selectBuildOption(tester, 'tbb', 'on');

    expect(_optionCombo(tester, 'tbb').onChanged, isNull);
    expect(_runtimeCombo(tester).onChanged, isNull);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('buildOption_use_nasm'))).onChanged,
      isNull,
    );

    pending.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('已保存'), findsOneWidget);
    expect(_runtimeCombo(tester).onChanged, isNotNull);
    expect(_optionCombo(tester, 'tbb').onChanged, isNotNull);
  });

  testWidgets('有仓库时显示当前与最新版本', (tester) async {
    final Completer<String?> latest = Completer<String?>();
    final PackModel pack = _buildPack('demo')..sourceVersion = 'v1.0.0';

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        loadHeader: (PackModel value) async => _header(),
        loadLatestVersion: (String repoUrl) => latest.future,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('packRepoVersionLabel')), findsOneWidget);
    expect(find.text('当前版本：v1.0.0'), findsOneWidget);
    expect(find.text('最新版本：查询中…'), findsOneWidget);

    latest.complete('v2.0.0');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('最新版本：v2.0.0'), findsOneWidget);
    expect(find.text('最新版本：查询中…'), findsNothing);
  });

  testWidgets('未注入最新版本加载器时显示占位', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        loadHeader: (PackModel value) async => _header(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('packRepoVersionLabel')), findsOneWidget);
    expect(find.text('当前版本：—'), findsOneWidget);
    expect(find.text('最新版本：—'), findsOneWidget);
  });

  testWidgets('无仓库的包不显示版本行', (tester) async {
    final PackModel pack = _buildPack('demo');

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        loadHeader: (PackModel value) async => null,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('packRepoVersionLabel')), findsNothing);
  });

  testWidgets('最新版本查询失败时显示占位', (tester) async {
    final PackModel pack = _buildPack('demo')..sourceVersion = 'v1.0.0';

    await _pumpPage(
      tester,
      PackFiles(
        pack: pack,
        onBuildPack: (PackModel value) async {},
        loadHeader: (PackModel value) async => _header(),
        loadLatestVersion: (String repoUrl) async => null,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('当前版本：v1.0.0'), findsOneWidget);
    expect(find.text('最新版本：—'), findsOneWidget);
  });
}

PackModel _pack(String name, List<FileModel> files, {String? sourcePath}) {
  return PackModel(
    name: name,
    version: '1.0.0',
    author: 'tester',
    sourcePath: sourcePath,
  )..files = files;
}

PackModel _buildPack(String name) => _pack(name, <FileModel>[
  FileModel(name: 'build.py', path: 'build.py', size: 10),
  FileModel(name: 'main.cpp', path: 'main.cpp', size: 20),
]);

const BuildScriptOption _tbbOption = BuildScriptOption(
  name: 'tbb',
  values: <String>['off', 'on'],
);

const BuildScriptOption _useNasmOption = BuildScriptOption(
  name: 'use_nasm',
  values: <String>['ON', 'OFF'],
  control: BuildOptionControl.checkbox,
);

const BuildScriptOption _accelOption = BuildScriptOption(
  name: 'accel',
  values: <String>['SSE2', 'AVX2', 'NEON'],
  control: BuildOptionControl.multiselect,
);

BuildScriptHeader _header({
  List<BuildScriptOption> options = const <BuildScriptOption>[],
}) {
  return BuildScriptHeader(
    repo: 'https://example.com/demo.git',
    options: options,
  );
}

ComboBox<String> _optionCombo(WidgetTester tester, String name) =>
    tester.widget<ComboBox<String>>(find.byKey(Key('buildOption_$name')));

ComboBox<String> _runtimeCombo(WidgetTester tester) =>
    tester.widget<ComboBox<String>>(
      find.byKey(const Key('buildRuntimeSelector')),
    );

BoxDecoration _rowDecoration(WidgetTester tester, Finder row) =>
    tester.widget<Container>(row).decoration! as BoxDecoration;

Future<void> _selectBuildOption(
  WidgetTester tester,
  String name,
  String value,
) async {
  await _selectComboItem(tester, Key('buildOption_$name'), value);
}

Future<void> _selectComboItem(
  WidgetTester tester,
  Key key,
  String label,
) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 名称所在行链（目录行内嵌名称+计数行，大小位于外层行）。
Finder _contentRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Row));

void _expectRowSize(String name, String size) {
  expect(
    find.descendant(of: _contentRow(name), matching: find.text(size)),
    findsAtLeastNWidgets(1),
    reason: '「$name」行应显示「$size」',
  );
}

Future<void> _doubleTapFile(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(name));
  await tester.pump(const Duration(milliseconds: 400));
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
