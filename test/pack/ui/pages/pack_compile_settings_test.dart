import 'dart:async';

import 'package:cpp_nuget_pack/pack/model/build_model.dart';
import 'package:cpp_nuget_pack/pack/model/cmd_model.dart';
import 'package:cpp_nuget_pack/pack/model/dependency_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/lib_dir_model.dart';
import 'package:cpp_nuget_pack/pack/model/library_model.dart';
import 'package:cpp_nuget_pack/pack/model/macro_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/pack/ui/pages/pack_compile_settings.dart';
import 'package:cpp_nuget_pack/shared/colors.dart';
import 'package:cpp_nuget_pack/shared/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('5 个空分区渲染紧凑标题、卡片表头与添加按钮', (tester) async {
    await _pumpPage(tester, _page(_pack('demo')));

    final List<({String title, String columnLabel, Key addKey})>
    sections = <({String title, String columnLabel, Key addKey})>[
      (title: '宏定义', columnLabel: '宏定义', addKey: const Key('addMacroButton')),
      (
        title: '编译前命令',
        columnLabel: '命令',
        addKey: const Key('addPreBuildCmdButton'),
      ),
      (
        title: '编译后命令',
        columnLabel: '命令',
        addKey: const Key('addPostBuildCmdButton'),
      ),
      (
        title: '附加库目录',
        columnLabel: '目录路径',
        addKey: const Key('addLibDirButton'),
      ),
      (title: '附加库', columnLabel: '库名称', addKey: const Key('addLibraryButton')),
    ];

    for (final ({String title, String columnLabel, Key addKey}) section
        in sections) {
      final Finder scope = _sectionScope(tester, section.title);
      expect(scope, findsOneWidget, reason: '缺少分区：${section.title}');
      expect(_sectionTitle(tester, section.title), findsOneWidget);
      expect(_sectionHeader(scope, section.columnLabel), findsOneWidget);
      expect(_sectionHeader(scope, '构建配置'), findsOneWidget);
      expect(_sectionHeader(scope, '操作'), findsOneWidget);
      expect(
        find.descendant(of: scope, matching: find.byKey(section.addKey)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: scope, matching: find.byType(Card)),
        findsOneWidget,
      );
    }

    expect(find.byType(Card), findsNWidgets(5));
    expect(find.text('添加'), findsNWidgets(5));
    expect(find.byType(Divider), findsOneWidget);
    for (final String empty in <String>[
      '暂无宏定义',
      '暂无编译前命令',
      '暂无编译后命令',
      '暂无附加库目录',
      '暂无附加库',
    ]) {
      expect(find.text(empty), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表渲染条目、构建配置标签与操作按钮', (tester) async {
    final PackModel pack = _pack('demo')
      ..commands = <CmdModel>[
        const CmdModel(
          command: 'echo pre',
          type: CmdType.preBuild,
          buildModel: BuildModel.release,
        ),
        const CmdModel(command: 'echo post', type: CmdType.postBuild),
      ]
      ..macros = <MacroModel>[const MacroModel(value: 'MY_MACRO=1')]
      ..libDirectories = <LibDirModel>[
        const LibDirModel(path: r'third_party\lib'),
      ]
      ..libraries = <LibraryModel>[
        const LibraryModel(name: 'mylib.lib', buildModel: BuildModel.debug),
      ];

    await _pumpPage(tester, _page(pack));

    expect(find.text('MY_MACRO=1'), findsOneWidget);
    expect(find.text('echo pre'), findsOneWidget);
    expect(find.text('echo post'), findsOneWidget);
    expect(find.text(r'third_party\lib'), findsOneWidget);
    expect(find.text('mylib.lib'), findsOneWidget);

    expect(find.byKey(const Key('macroEditButton_0')), findsOneWidget);
    expect(find.byKey(const Key('macroDeleteButton_0')), findsOneWidget);
    expect(find.byKey(const Key('preBuildCmdEditButton_0')), findsOneWidget);
    expect(find.byKey(const Key('postBuildCmdEditButton_1')), findsOneWidget);
    expect(find.byKey(const Key('libDirEditButton_0')), findsOneWidget);
    expect(find.byKey(const Key('libraryEditButton_0')), findsOneWidget);

    final List<Tag> tags = tester.widgetList<Tag>(find.byType(Tag)).toList();
    expect(tags, hasLength(5));
    expect(tags[0].text, 'ALL');
    expect(tags[0].color, MarkerColors.blue);
    expect(tags[1].text, 'Release');
    expect(tags[1].color, MarkerColors.green);
    expect(tags[2].text, 'ALL');
    expect(tags[3].text, 'ALL');
    expect(tags[4].text, 'Debug');
    expect(tags[4].color, MarkerColors.orange);

    final List<({String title, String columnLabel, int entryCount})> sections =
        <({String title, String columnLabel, int entryCount})>[
          (title: '宏定义', columnLabel: '宏定义', entryCount: 1),
          (title: '编译前命令', columnLabel: '命令', entryCount: 1),
          (title: '编译后命令', columnLabel: '命令', entryCount: 1),
          (title: '附加库目录', columnLabel: '目录路径', entryCount: 1),
          (title: '附加库', columnLabel: '库名称', entryCount: 1),
        ];
    for (final ({String title, String columnLabel, int entryCount}) section
        in sections) {
      final Finder scope = _sectionScope(tester, section.title);
      expect(scope, findsOneWidget, reason: '缺少分区：${section.title}');
      expect(_sectionTitle(tester, section.title), findsOneWidget);
      expect(_sectionHeader(scope, section.columnLabel), findsOneWidget);
      expect(_sectionHeader(scope, '构建配置'), findsOneWidget);
      expect(_sectionHeader(scope, '操作'), findsOneWidget);
      expect(
        find.descendant(of: scope, matching: find.byType(Card)),
        findsNWidgets(section.entryCount + 1),
      );
    }

    expect(find.text('暂无宏定义'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统命令条目展示系统标记且编辑删除禁用', (tester) async {
    final PackModel pack = _pack('demo')
      ..commands = <CmdModel>[
        const CmdModel(
          command:
              r'"$(MSBuildThisFileDirectory)files\pre.bat" "$(TargetPath)"',
          type: CmdType.preBuild,
          system: true,
        ),
        const CmdModel(command: 'echo post', type: CmdType.postBuild),
      ];

    await _pumpPage(tester, _page(pack));

    expect(find.text('系统'), findsOneWidget);
    final IconButton lockedEdit = tester.widget<IconButton>(
      find.byKey(const Key('preBuildCmdEditButton_0')),
    );
    final IconButton lockedDelete = tester.widget<IconButton>(
      find.byKey(const Key('preBuildCmdDeleteButton_0')),
    );
    final IconButton userEdit = tester.widget<IconButton>(
      find.byKey(const Key('postBuildCmdEditButton_1')),
    );
    expect(lockedEdit.onPressed, isNull);
    expect(lockedDelete.onPressed, isNull);
    expect(userEdit.onPressed, isNotNull);
    expect(find.byTooltip('由构建管线注册，禁止修改/删除'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('分区表格的表头与条目列对齐', (tester) async {
    final PackModel pack = _pack('demo')
      ..macros = <MacroModel>[
        const MacroModel(value: 'A=1', buildModel: BuildModel.all),
        const MacroModel(value: 'B=2', buildModel: BuildModel.debug),
      ];

    await _pumpPage(tester, _page(pack));

    final Finder scope = _sectionScope(tester, '宏定义');
    final Finder sectionTags = find.descendant(
      of: scope,
      matching: find.byType(Tag),
    );
    final Rect firstText = tester.getRect(find.text('A=1'));
    final Rect secondText = tester.getRect(find.text('B=2'));
    final Rect firstTag = tester.getRect(sectionTags.first);
    final Rect secondTag = tester.getRect(sectionTags.last);
    final Rect buildHeader = tester.getRect(_sectionHeader(scope, '构建配置'));
    final Rect actionHeader = tester.getRect(_sectionHeader(scope, '操作'));
    final Rect firstEdit = tester.getRect(
      find.byKey(const Key('macroEditButton_0')),
    );
    final Rect secondEdit = tester.getRect(
      find.byKey(const Key('macroEditButton_1')),
    );
    final Rect firstDelete = tester.getRect(
      find.byKey(const Key('macroDeleteButton_0')),
    );

    expect(firstText.left, secondText.left);
    expect(firstTag.center.dx, secondTag.center.dx);
    expect(firstTag.center.dx, buildHeader.center.dx);
    expect(firstEdit.left, secondEdit.left);
    expect(
      (firstEdit.center.dx + firstDelete.center.dx) / 2,
      actionHeader.center.dx,
    );
  });

  testWidgets('添加宏定义后回调收到含新宏的完整包并提示已添加', (tester) async {
    final PackModel pack =
        PackModel(
            name: 'demo',
            version: '1.2.3',
            author: '张三',
            description: '描述',
            license: 'MIT',
            iconPath: 'assets/logo.svg',
            sourcePath: r'D:\libs\demo',
          )
          ..files = <FileModel>[
            FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
          ]
          ..commands = <CmdModel>[
            const CmdModel(command: 'echo pre', type: CmdType.preBuild),
          ]
          ..dependencies = <DependencyModel>[
            const DependencyModel(name: 'libfoo', version: '1.0'),
          ]
          ..macros = <MacroModel>[const MacroModel(value: 'OLD=1')]
          ..libDirectories = <LibDirModel>[const LibDirModel(path: 'libs')]
          ..libraries = <LibraryModel>[const LibraryModel(name: 'old.lib')];
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await _addEntry(
      tester,
      addKey: const Key('addMacroButton'),
      text: 'NEW_MACRO=2',
      buildModelLabel: 'Release',
    );

    expect(find.text('添加宏定义'), findsNothing);
    expect(saved, isNotNull);
    expect(saved!.name, 'demo');
    expect(saved!.version, '1.2.3');
    expect(saved!.author, '张三');
    expect(saved!.description, '描述');
    expect(saved!.license, 'MIT');
    expect(saved!.iconPath, 'assets/logo.svg');
    expect(saved!.sourcePath, r'D:\libs\demo');
    expect(saved!.files.single.path, 'include/foo.h');
    expect(saved!.commands.single.command, 'echo pre');
    expect(saved!.dependencies.single.name, 'libfoo');
    expect(saved!.macros, hasLength(2));
    expect(saved!.macros[0].value, 'OLD=1');
    expect(saved!.macros[1].value, 'NEW_MACRO=2');
    expect(saved!.macros[1].buildModel, BuildModel.release);
    expect(saved!.libDirectories.single.path, 'libs');
    expect(saved!.libraries.single.name, 'old.lib');
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('编译前后命令按钮打开对应标题的对话框并保存所选类型', (tester) async {
    PackModel? saved;
    await _pumpPage(
      tester,
      _page(
        _pack('demo'),
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await _openAddDialog(tester, const Key('addPreBuildCmdButton'));
    expect(find.text('添加编译前命令'), findsOneWidget);
    await _tapCancel(tester);

    await _openAddDialog(tester, const Key('addPostBuildCmdButton'));
    expect(find.text('添加编译后命令'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('compileEntryTextField')),
      'echo post',
    );
    await tester.pump();
    await _selectBuildModel(tester, 'Debug');
    await _tapConfirm(tester);

    expect(saved, isNotNull);
    expect(saved!.commands.single.command, 'echo post');
    expect(saved!.commands.single.type, CmdType.postBuild);
    expect(saved!.commands.single.buildModel, BuildModel.debug);
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('命令对话框提供脚本与宏下拉，其他分区对话框不提供', (tester) async {
    final PackModel pack = _pack('demo')
      ..files = <FileModel>[
        FileModel(name: 'build.bat', path: 'scripts/build.bat'),
        FileModel(name: 'gen.py', path: 'tools/gen.py'),
        FileModel(name: 'app.exe', path: 'bin/app.exe'),
        FileModel(name: 'main.cpp', path: 'src/main.cpp'),
        FileModel(name: 'notes.md', path: 'docs/notes.md'),
      ];

    await _pumpPage(tester, _page(pack));

    await _openAddDialog(tester, const Key('addPreBuildCmdButton'));
    expect(
      _scriptCombo(tester).items!
          .map((ComboBoxItem<FileModel> item) => item.value!.path)
          .toList(),
      <String>['scripts/build.bat', 'tools/gen.py', 'bin/app.exe'],
    );
    expect(find.byKey(const Key('compileEntryScriptField')), findsOneWidget);
    expect(find.byKey(const Key('compileEntryMacroField')), findsOneWidget);
    await _tapCancel(tester);

    for (final Key addKey in <Key>[
      const Key('addMacroButton'),
      const Key('addLibDirButton'),
      const Key('addLibraryButton'),
    ]) {
      await _openAddDialog(tester, addKey);
      expect(find.byKey(const Key('compileEntryScriptField')), findsNothing);
      expect(find.byKey(const Key('compileEntryMacroField')), findsNothing);
      await _tapCancel(tester);
    }
  });

  testWidgets('命令对话框选择脚本与宏后插入并保存引用文本', (tester) async {
    final PackModel pack = _pack('demo')
      ..files = <FileModel>[
        FileModel(name: 'build.bat', path: 'scripts/build.bat'),
      ];
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await _openAddDialog(tester, const Key('addPreBuildCmdButton'));
    await _selectDialogComboItem(
      tester,
      const Key('compileEntryScriptField'),
      'scripts/build.bat',
    );
    await _selectDialogComboItem(
      tester,
      const Key('compileEntryMacroField'),
      r'$(OutDir)',
    );
    await _tapConfirm(tester);

    expect(saved, isNotNull);
    expect(
      saved!.commands.single.command,
      r'"$(MSBuildThisFileDirectory)files\scripts\build.bat"$(OutDir)',
    );
    expect(saved!.commands.single.type, CmdType.preBuild);
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('添加附加库目录经浏览填入并保存', (tester) async {
    int pickCount = 0;
    PackModel? saved;
    await _pumpPage(
      tester,
      _page(
        _pack('demo'),
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
        pickDirectory: () async {
          pickCount++;
          return r'D:\libs\third_party';
        },
      ),
    );

    await _openAddDialog(tester, const Key('addLibDirButton'));
    expect(find.text('添加附加库目录'), findsOneWidget);

    await tester.tap(find.byKey(const Key('compileEntryBrowseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(pickCount, 1);
    expect(_dialogTextBox(tester).controller!.text, r'D:\libs\third_party');

    await _tapConfirm(tester);

    expect(saved, isNotNull);
    expect(saved!.libDirectories.single.path, r'D:\libs\third_party');
    expect(saved!.libDirectories.single.buildModel, BuildModel.all);
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('添加附加库并保存所选构建配置', (tester) async {
    PackModel? saved;
    await _pumpPage(
      tester,
      _page(
        _pack('demo'),
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await _addEntry(
      tester,
      addKey: const Key('addLibraryButton'),
      text: 'mylib.lib',
      buildModelLabel: 'Release',
    );

    expect(saved, isNotNull);
    expect(saved!.libraries.single.name, 'mylib.lib');
    expect(saved!.libraries.single.buildModel, BuildModel.release);
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('编辑宏定义预填并保存', (tester) async {
    final PackModel pack = _pack('demo')
      ..macros = <MacroModel>[
        const MacroModel(value: 'OLD=1', buildModel: BuildModel.release),
      ];
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('macroEditButton_0')));
    await tester.tap(find.byKey(const Key('macroEditButton_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('编辑宏定义'), findsOneWidget);
    expect(_dialogTextBox(tester).controller!.text, 'OLD=1');
    expect(_dialogBuildModel(tester), BuildModel.release);

    await tester.enterText(
      find.byKey(const Key('compileEntryTextField')),
      'NEW=2',
    );
    await tester.pump();
    await _selectBuildModel(tester, 'Debug');
    await _tapConfirm(tester);

    expect(saved, isNotNull);
    expect(saved!.macros.single.value, 'NEW=2');
    expect(saved!.macros.single.buildModel, BuildModel.debug);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('删除宏定义无需确认并提示已删除', (tester) async {
    final PackModel pack = _pack('demo')
      ..macros = <MacroModel>[
        const MacroModel(value: 'A=1'),
        const MacroModel(value: 'B=2'),
      ];
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('macroDeleteButton_0')));
    await tester.tap(find.byKey(const Key('macroDeleteButton_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
    expect(saved, isNotNull);
    expect(saved!.macros.single.value, 'B=2');
    expect(find.text('已删除'), findsOneWidget);
  });

  testWidgets('两条目宏分区渲染同宽表头卡与条目卡', (tester) async {
    final PackModel pack = _pack('demo')
      ..macros = <MacroModel>[
        const MacroModel(value: 'A=1'),
        const MacroModel(value: 'B=2'),
      ];

    await _pumpPage(tester, _page(pack));

    final Finder cards = find.descendant(
      of: _sectionScope(tester, '宏定义'),
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(3));
    final List<Rect> cardRects = <Rect>[
      for (int index = 0; index < 3; index++) tester.getRect(cards.at(index)),
    ];
    for (final Rect cardRect in cardRects) {
      expect(cardRect.left, cardRects.first.left);
      expect(cardRect.right, cardRects.first.right);
    }
    expect(cardRects[1].top, greaterThanOrEqualTo(cardRects[0].bottom));
    expect(cardRects[2].top, greaterThanOrEqualTo(cardRects[1].bottom));
    expect(find.byType(Divider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败时不显示成功提示', (tester) async {
    PackModel? saved;
    await _pumpPage(
      tester,
      _page(
        _pack('demo'),
        onSave: (PackModel updated) async {
          saved = updated;
          return false;
        },
      ),
    );

    await _addEntry(tester, addKey: const Key('addMacroButton'), text: 'A=1');

    expect(saved, isNotNull);
    expect(saved!.macros, hasLength(1));
    expect(find.text('已添加'), findsNothing);
  });

  testWidgets('保存挂起期间重复提交不重入', (tester) async {
    final Completer<bool> pending = Completer<bool>();
    int saveCount = 0;
    await _pumpPage(
      tester,
      _page(
        _pack('demo'),
        onSave: (PackModel updated) {
          saveCount++;
          return pending.future;
        },
      ),
    );

    await _addEntry(tester, addKey: const Key('addMacroButton'), text: 'A=1');
    await _addEntry(tester, addKey: const Key('addMacroButton'), text: 'B=2');

    expect(saveCount, 1);

    pending.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('切换包时列表随新包更新', (tester) async {
    final PackModel first = _pack('demo')
      ..macros = <MacroModel>[const MacroModel(value: 'A=1')];
    final PackModel second = _pack('other')
      ..macros = <MacroModel>[const MacroModel(value: 'B=2')];

    await _pumpPage(tester, _page(first));
    expect(find.text('A=1'), findsOneWidget);

    await _pumpPage(tester, _page(second));

    expect(find.text('B=2'), findsOneWidget);
    expect(find.text('A=1'), findsNothing);
  });
}

PackModel _pack(String name) =>
    PackModel(name: name, version: '1.0.0', author: 'tester');

PackCompileSettings _page(
  PackModel pack, {
  Future<bool> Function(PackModel pack)? onSave,
  Future<String?> Function()? pickDirectory,
}) {
  return PackCompileSettings(
    pack: pack,
    onSave: onSave ?? (PackModel updated) async => true,
    pickDirectory: pickDirectory ?? () async => null,
  );
}

Future<void> _pumpPage(WidgetTester tester, PackCompileSettings page) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(home: page));
  await tester.pump();
}

Finder _sectionTitle(WidgetTester tester, String title) {
  return find.descendant(
    of: find.byType(PackCompileSettings),
    matching: find.byWidgetPredicate((Widget widget) {
      return widget is Text &&
          widget.data == title &&
          widget.style?.fontSize == 16;
    }),
  );
}

Finder _sectionScope(WidgetTester tester, String title) {
  return find
      .ancestor(of: _sectionTitle(tester, title), matching: find.byType(Column))
      .at(1);
}

Finder _sectionHeader(Finder scope, String text) {
  return find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((Widget widget) {
      return widget is Text &&
          widget.data == text &&
          widget.style?.fontSize == 12;
    }),
  );
}

Future<void> _addEntry(
  WidgetTester tester, {
  required Key addKey,
  required String text,
  String? buildModelLabel,
}) async {
  await _openAddDialog(tester, addKey);
  await tester.enterText(find.byKey(const Key('compileEntryTextField')), text);
  await tester.pump();
  if (buildModelLabel != null) {
    await _selectBuildModel(tester, buildModelLabel);
  }
  await _tapConfirm(tester);
}

Future<void> _openAddDialog(WidgetTester tester, Key addKey) async {
  final Finder button = find.byKey(addKey);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _selectBuildModel(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('compileEntryBuildModelField')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _selectDialogComboItem(
  WidgetTester tester,
  Key fieldKey,
  String label,
) async {
  await tester.tap(find.byKey(fieldKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('compileEntryConfirmButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _tapCancel(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('compileEntryCancelButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

TextBox _dialogTextBox(WidgetTester tester) =>
    tester.widget<TextBox>(find.byKey(const Key('compileEntryTextField')));

ComboBox<FileModel> _scriptCombo(WidgetTester tester) =>
    tester.widget<ComboBox<FileModel>>(
      find.byKey(const Key('compileEntryScriptField')),
    );

BuildModel _dialogBuildModel(WidgetTester tester) => tester
    .widget<ComboBox<BuildModel>>(
      find.byKey(const Key('compileEntryBuildModelField')),
    )
    .value!;
