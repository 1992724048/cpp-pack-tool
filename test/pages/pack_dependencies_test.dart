import 'package:catppuccin_flutter/catppuccin_flutter.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/pages/pack_dependencies.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('空状态显示引导文案与添加按钮', (tester) async {
    await _pumpPage(tester, _page(_pack('demo')));

    expect(find.byKey(const Key('addDependencyButton')), findsOneWidget);
    expect(find.text('添加依赖'), findsOneWidget);
    expect(find.text('暂无依赖'), findsOneWidget);
    expect(find.text('点击「添加依赖」开始'), findsOneWidget);
  });

  testWidgets('列表渲染依赖名称、版本范围与操作按钮', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '[1.0,2.0)'),
        const DependencyModel(name: 'libbar', version: '1.0'),
      ];

    await _pumpPage(tester, _page(pack));

    expect(find.text('libfoo'), findsOneWidget);
    expect(find.text('[1.0,2.0)'), findsOneWidget);
    expect(find.text('libbar'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(
      find.byKey(const Key('dependencyEditButton_libfoo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('dependencyDeleteButton_libbar')),
      findsOneWidget,
    );
    expect(find.byIcon(FluentIcons.edit), findsNWidgets(2));
    expect(find.byIcon(FluentIcons.delete), findsNWidgets(2));
    expect(find.text('暂无依赖'), findsNothing);
    expect(find.text('包名'), findsOneWidget);
    expect(find.text('版本范围'), findsOneWidget);
    expect(find.text('操作'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('表头与两行依赖的列对齐', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '[1.0,2.0)'),
        const DependencyModel(name: 'libbar', version: '2.0'),
      ];

    await _pumpPage(
      tester,
      _page(
        pack,
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo'), _pack('libbar')],
      ),
    );

    final Rect firstName = tester.getRect(find.text('libfoo'));
    final Rect secondName = tester.getRect(find.text('libbar'));
    final Rect firstVersion = tester.getRect(find.text('[1.0,2.0)'));
    final Rect secondVersion = tester.getRect(find.text('2.0'));
    final Rect versionHeader = tester.getRect(find.text('版本范围'));
    final Rect actionHeader = tester.getRect(find.text('操作'));
    final Rect firstEdit = tester.getRect(
      find.byKey(const Key('dependencyEditButton_libfoo')),
    );
    final Rect secondEdit = tester.getRect(
      find.byKey(const Key('dependencyEditButton_libbar')),
    );
    final Rect firstDelete = tester.getRect(
      find.byKey(const Key('dependencyDeleteButton_libfoo')),
    );

    expect(firstName.left, secondName.left);
    expect(firstVersion.left, secondVersion.left);
    expect(firstVersion.left, versionHeader.left);
    expect(firstEdit.left, secondEdit.left);
    expect(
      (firstEdit.center.dx + firstDelete.center.dx) / 2,
      actionHeader.center.dx,
    );
  });

  testWidgets('分隔线水平范围与列表内容区对齐', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '1.0'),
        const DependencyModel(name: 'libbar', version: '2.0'),
      ];

    await _pumpPage(
      tester,
      _page(
        pack,
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo'), _pack('libbar')],
      ),
      theme: buildTheme(Brightness.light, catppuccin.latte, 'teal'),
    );

    // Divider 外层包裹水平外边距，需取内部绘制层比较实际线体范围
    final int dividerCount = tester.widgetList(find.byType(Divider)).length;
    final List<Rect> lineRects = <Rect>[
      for (int index = 0; index < dividerCount; index++)
        tester.getRect(
          find
              .descendant(
                of: find.byType(Divider).at(index),
                matching: find.byType(DecoratedBox),
              )
              .first,
        ),
    ];
    final Rect listRect = tester.getRect(find.byType(ListView));

    expect(lineRects, hasLength(2));
    for (final Rect lineRect in lineRects) {
      expect(lineRect.left, listRect.left);
      expect(lineRect.right, listRect.right);
    }
  });

  testWidgets('单条依赖仅渲染表头分隔线', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '1.0'),
      ];

    await _pumpPage(
      tester,
      _page(pack, allPacks: <PackModel>[_pack('libfoo')]),
    );

    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('依赖指向已删除的包时展示并标记缺失', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'gone', version: '1.0'),
      ];

    await _pumpPage(tester, _page(pack, allPacks: <PackModel>[_pack('demo')]));

    expect(find.text('gone'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('缺失'), findsOneWidget);
  });

  testWidgets('依赖对应的包存在时不显示缺失标签', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'LIBFOO', version: '1.0'),
      ];

    await _pumpPage(
      tester,
      _page(pack, allPacks: <PackModel>[_pack('demo'), _pack('libfoo')]),
    );

    expect(find.text('LIBFOO'), findsOneWidget);
    expect(find.text('缺失'), findsNothing);
  });

  testWidgets('添加依赖后回调收到含新依赖的完整包并提示已添加', (tester) async {
    final PackModel pack = _pack('demo')
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
      ]
      ..commands = <CmdModel>[
        CmdModel(command: 'echo hi', type: CmdType.preBuild),
      ]
      ..macros = <MacroModel>[const MacroModel(value: 'MY_MACRO=1')]
      ..libDirectories = <LibDirModel>[
        const LibDirModel(path: 'third_party/lib'),
      ]
      ..libraries = <LibraryModel>[const LibraryModel(name: 'mylib.lib')];
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo'), _pack('libbar')],
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await _tapAdd(tester);
    expect(find.byKey(const Key('dependencyDialog')), findsOneWidget);
    expect(_candidateNames(tester), <String>['libfoo', 'libbar']);

    await _selectPackage(tester, 'libfoo');
    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '[1.0,2.0)',
    );
    await tester.pump();
    await _tapConfirm(tester);

    expect(saved, isNotNull);
    expect(saved!.dependencies, hasLength(1));
    expect(saved!.dependencies.single.name, 'libfoo');
    expect(saved!.dependencies.single.version, '[1.0,2.0)');
    expect(saved!.files, hasLength(1));
    expect(saved!.commands, hasLength(1));
    expect(saved!.macros.single.value, 'MY_MACRO=1');
    expect(saved!.libDirectories.single.path, 'third_party/lib');
    expect(saved!.libraries.single.name, 'mylib.lib');
    expect(find.text('已添加'), findsOneWidget);
    expect(find.byKey(const Key('dependencyDialog')), findsNothing);
  });

  testWidgets('添加依赖后保存的包保留脚本', (tester) async {
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
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo')],
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await _addDependency(tester, package: 'libfoo', version: '1.0');

    expect(saved, isNotNull);
    expect(saved!.dependencies, hasLength(1));
    expect(saved!.scripts, hasLength(1));
    expect(saved!.scripts.single.id, 'script_1');
  });

  testWidgets('候选包排除自身与已添加的依赖', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '1.0'),
      ];

    await _pumpPage(
      tester,
      _page(
        pack,
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo'), _pack('libbar')],
      ),
    );

    await _tapAdd(tester);

    expect(_candidateNames(tester), <String>['libbar']);
  });

  testWidgets('无候选包时对话框显示提示且确定禁用', (tester) async {
    await _pumpPage(
      tester,
      _page(_pack('demo'), allPacks: <PackModel>[_pack('demo')]),
    );

    await _tapAdd(tester);

    expect(find.text('没有可添加的包'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('dependencyConfirmButton')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('无效版本范围实时提示并禁用确定', (tester) async {
    await _pumpPage(
      tester,
      _page(
        _pack('demo'),
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo')],
      ),
    );

    await _tapAdd(tester);
    await _selectPackage(tester, 'libfoo');

    expect(
      tester
          .widget<TextBox>(find.byKey(const Key('dependencyVersionField')))
          .controller!
          .text,
      '[1.0.0,)',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('dependencyConfirmButton')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '(1.0)',
    );
    await tester.pump();
    expect(find.text('单值范围必须写成 [版本] 形式'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('dependencyConfirmButton')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('编辑依赖仅修改版本范围并提示已保存', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '1.0'),
      ];
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo')],
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('dependencyEditButton_libfoo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('编辑依赖'), findsOneWidget);
    expect(
      tester
          .widget<TextBox>(find.byKey(const Key('dependencyVersionField')))
          .controller!
          .text,
      '1.0',
    );

    await tester.enterText(
      find.byKey(const Key('dependencyVersionField')),
      '2.0',
    );
    await tester.pump();
    await _tapConfirm(tester);

    expect(saved, isNotNull);
    expect(saved!.dependencies, hasLength(1));
    expect(saved!.dependencies.single.name, 'libfoo');
    expect(saved!.dependencies.single.version, '2.0');
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('删除依赖无需确认并提示已删除', (tester) async {
    final PackModel pack = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '1.0'),
        const DependencyModel(name: 'libbar', version: '2.0'),
      ];
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo'), _pack('libbar')],
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('dependencyDeleteButton_libfoo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
    expect(saved, isNotNull);
    expect(saved!.dependencies, hasLength(1));
    expect(saved!.dependencies.single.name, 'libbar');
    expect(find.text('已删除'), findsOneWidget);
  });

  testWidgets('保存失败时不显示成功提示', (tester) async {
    final PackModel pack = _pack('demo');
    PackModel? saved;

    await _pumpPage(
      tester,
      _page(
        pack,
        allPacks: <PackModel>[_pack('demo'), _pack('libfoo')],
        onSave: (PackModel updated) async {
          saved = updated;
          return false;
        },
      ),
    );

    await _addDependency(tester, package: 'libfoo', version: '1.0');

    expect(saved, isNotNull);
    expect(saved!.dependencies, hasLength(1));
    expect(find.text('已添加'), findsNothing);
  });

  testWidgets('切换包时列表随新包更新', (tester) async {
    final PackModel first = _pack('demo')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '1.0'),
      ];
    final PackModel second = _pack('other')
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libbar', version: '2.0'),
      ];

    await _pumpPage(tester, _page(first, allPacks: <PackModel>[first]));
    expect(find.text('libfoo'), findsOneWidget);

    await _pumpPage(tester, _page(second, allPacks: <PackModel>[second]));

    expect(find.text('libbar'), findsOneWidget);
    expect(find.text('libfoo'), findsNothing);
  });
}

PackModel _pack(String name) =>
    PackModel(name: name, version: '1.0.0', author: 'tester');

PackDependencies _page(
  PackModel pack, {
  List<PackModel>? allPacks,
  Future<bool> Function(PackModel pack)? onSave,
}) {
  return PackDependencies(
    pack: pack,
    allPacks: allPacks ?? <PackModel>[pack],
    onSave: onSave ?? (PackModel updated) async => true,
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  PackDependencies page, {
  FluentThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(theme: theme, home: page));
  await tester.pump();
}

Future<void> _tapAdd(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('addDependencyButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _addDependency(
  WidgetTester tester, {
  required String package,
  required String version,
}) async {
  await _tapAdd(tester);
  await _selectPackage(tester, package);
  await tester.enterText(
    find.byKey(const Key('dependencyVersionField')),
    version,
  );
  await tester.pump();
  await _tapConfirm(tester);
}

Future<void> _selectPackage(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('dependencyPackageField')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(name).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dependencyConfirmButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

List<String> _candidateNames(WidgetTester tester) {
  final ComboBox<String> combo = tester.widget<ComboBox<String>>(
    find.byKey(const Key('dependencyPackageField')),
  );
  return <String>[
    for (final ComboBoxItem<String> item in combo.items ?? const [])
      if (item.value != null) item.value!,
  ];
}
