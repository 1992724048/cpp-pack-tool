import 'dart:async';

import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/pages/pack_compile_settings.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('5 个分区空态渲染标题、添加按钮与引导文案', (tester) async {
    await _pumpPage(tester, _page(_pack('demo')));

    for (final String title in <String>[
      '宏定义',
      '编译前命令',
      '编译后命令',
      '附加库目录',
      '附加库',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    for (final String empty in <String>[
      '暂无宏定义',
      '暂无编译前命令',
      '暂无编译后命令',
      '暂无附加库目录',
      '暂无附加库',
    ]) {
      expect(find.text(empty), findsOneWidget);
    }
    for (final Key key in <Key>[
      const Key('addMacroButton'),
      const Key('addPreBuildCmdButton'),
      const Key('addPostBuildCmdButton'),
      const Key('addLibDirButton'),
      const Key('addLibraryButton'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
    expect(find.text('添加'), findsNWidgets(5));
    expect(find.byType(Divider), findsNothing);
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
    expect(tags[0].color, UCColors.flavor.blue);
    expect(tags[1].text, 'Release');
    expect(tags[1].color, UCColors.flavor.green);
    expect(tags[2].text, 'ALL');
    expect(tags[3].text, 'ALL');
    expect(tags[4].text, 'Debug');
    expect(tags[4].color, UCColors.flavor.peach);

    expect(find.text('暂无宏定义'), findsNothing);
    expect(find.text('构建配置'), findsNWidgets(5));
    expect(find.text('操作'), findsNWidgets(5));
    expect(find.text('宏定义'), findsNWidgets(2));
    expect(find.text('命令'), findsNWidgets(2));
    expect(find.text('目录路径'), findsOneWidget);
    expect(find.text('库名称'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('分区表格的表头与条目列对齐', (tester) async {
    final PackModel pack = _pack('demo')
      ..macros = <MacroModel>[
        const MacroModel(value: 'A=1', buildModel: BuildModel.all),
        const MacroModel(value: 'B=2', buildModel: BuildModel.debug),
      ];

    await _pumpPage(tester, _page(pack));

    final Rect firstText = tester.getRect(find.text('A=1'));
    final Rect secondText = tester.getRect(find.text('B=2'));
    final Rect firstTag = tester.getRect(find.byType(Tag).first);
    final Rect secondTag = tester.getRect(find.byType(Tag).last);
    final Rect buildHeader = tester.getRect(find.text('构建配置'));
    final Rect actionHeader = tester.getRect(find.text('操作'));
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

  testWidgets('添加命令后保存的包保留 scripts', (tester) async {
    final PackModel pack = _pack('demo')
      ..scripts = <ScriptProjectModel>[
        ScriptProjectModel(
          id: 'script_1',
          name: '脚本 1',
          trigger: ScriptTrigger.pre,
        ),
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

    await _addEntry(
      tester,
      addKey: const Key('addPreBuildCmdButton'),
      text: 'echo hi',
    );

    expect(saved, isNotNull);
    expect(saved!.commands.single.command, 'echo hi');
    expect(saved!.scripts, hasLength(1));
    expect(saved!.scripts.single.id, 'script_1');
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

  testWidgets('两条目分区渲染表头与行间两条分隔线', (tester) async {
    final PackModel pack = _pack('demo')
      ..macros = <MacroModel>[
        const MacroModel(value: 'A=1'),
        const MacroModel(value: 'B=2'),
      ];

    await _pumpPage(tester, _page(pack));

    expect(find.byType(Divider), findsNWidgets(2));
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

  testWidgets('节点脚本分区空态渲染标题与打开按钮', (tester) async {
    await _pumpPage(tester, _page(_pack('demo')));

    expect(find.byKey(const Key('nodeScriptsSection')), findsOneWidget);
    expect(find.text('节点脚本'), findsOneWidget);
    expect(find.text('暂无节点脚本'), findsOneWidget);
    expect(find.byKey(const Key('openScriptEditorButton')), findsOneWidget);
    expect(find.text('打开节点编辑器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('节点脚本分区渲染四列表格与状态着色', (tester) async {
    final PackModel pack = _pack('demo')
      ..scripts = <ScriptProjectModel>[
        ScriptProjectModel(
            id: 'script_1',
            name: '构建头文件',
            trigger: ScriptTrigger.pre,
          )
          ..nodes = <ScriptNodeModel>[
            ScriptNodeModel(id: 'n1', type: 'flow.entry'),
          ],
        ScriptProjectModel(
          id: 'script_2',
          name: '收集产物',
          trigger: ScriptTrigger.post,
          buildModel: BuildModel.release,
        ),
        _validScript(),
      ];

    await _pumpPage(tester, _page(pack));

    for (final String header in <String>['名称', '触发时机', '构建标签', '状态']) {
      expect(find.text(header), findsOneWidget);
    }
    expect(find.text('构建头文件'), findsOneWidget);
    expect(find.text('收集产物'), findsOneWidget);
    expect(find.text('输出日志'), findsOneWidget);

    final List<Tag> tags = tester.widgetList<Tag>(find.byType(Tag)).toList();
    expect(tags, hasLength(6));
    expect(tags[0].text, '编译前');
    expect(tags[0].color, UCColors.flavor.sky);
    expect(tags[1].text, 'ALL');
    expect(tags[1].color, UCColors.flavor.blue);
    expect(tags[2].text, '编译后');
    expect(tags[2].color, UCColors.flavor.lavender);
    expect(tags[3].text, 'Release');
    expect(tags[3].color, UCColors.flavor.green);
    expect(tags[4].text, '编译前');
    expect(tags[4].color, UCColors.flavor.sky);
    expect(tags[5].text, 'Debug');
    expect(tags[5].color, UCColors.flavor.peach);

    expect(_statusText(tester, '1 个警告').style?.color, UCColors.flavor.yellow);
    expect(_statusText(tester, '1 个错误').style?.color, UCColors.flavor.red);
    expect(_statusText(tester, '正常').style?.color, UCColors.flavor.green);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击打开节点编辑器进入编辑页并可返回编译设置', (tester) async {
    final PackModel pack = _pack('demo')
      ..scripts = <ScriptProjectModel>[
        ScriptProjectModel(
          id: 'script_1',
          name: '脚本 1',
          trigger: ScriptTrigger.pre,
        ),
      ];
    await _pumpPage(tester, _page(pack));

    final Finder openButton = find.byKey(const Key('openScriptEditorButton'));
    await tester.ensureVisible(openButton);
    await tester.pump();
    await tester.tap(openButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('nodeEditorPage')), findsOneWidget);
    expect(find.text('节点编辑器 — demo'), findsOneWidget);

    await tester.tap(find.byTooltip('返回包管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('nodeEditorPage')), findsNothing);
    expect(find.text('节点脚本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

PackModel _pack(String name) =>
    PackModel(name: name, version: '1.0.0', author: 'tester');

/// 结构完整且无诊断的脚本：开始 → 输出信息，消息来自文本常量。
ScriptProjectModel _validScript() {
  final ScriptProjectModel script = ScriptProjectModel(
    id: 'script_3',
    name: '输出日志',
    trigger: ScriptTrigger.pre,
    buildModel: BuildModel.debug,
  );
  script.nodes = <ScriptNodeModel>[
    ScriptNodeModel(id: 'n1', type: 'flow.entry'),
    ScriptNodeModel(id: 'n2', type: 'log.message'),
    ScriptNodeModel(id: 'n3', type: 'value.text'),
  ];
  script.edges = <ScriptEdgeModel>[
    ScriptEdgeModel(
      from: ScriptEdgeEndpoint(node: 'n1', pin: 'out'),
      to: ScriptEdgeEndpoint(node: 'n2', pin: 'exec'),
    ),
    ScriptEdgeModel(
      from: ScriptEdgeEndpoint(node: 'n3', pin: 'result'),
      to: ScriptEdgeEndpoint(node: 'n2', pin: 'message'),
    ),
  ];
  return script;
}

Text _statusText(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text));

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
