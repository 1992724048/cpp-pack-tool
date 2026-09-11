import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/pages/script_editor.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('外壳渲染顶栏、三栏区域与底部占位条', (tester) async {
    await _pumpEditor(tester, _packWithScript());

    expect(find.byKey(const Key('nodeEditorPage')), findsOneWidget);
    expect(find.byKey(const Key('editorTopBar')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('editorTopBar'))).height, 48);
    expect(find.text('节点编辑器 — demo'), findsOneWidget);
    expect(find.byTooltip('返回包管理'), findsOneWidget);
    expect(find.byKey(const Key('editorTopBarActions')), findsOneWidget);

    final Rect library = tester.getRect(
      find.byKey(const Key('nodeLibraryPanel')),
    );
    final Rect canvas = tester.getRect(find.byKey(const Key('editorCanvas')));
    final Rect inspector = tester.getRect(
      find.byKey(const Key('inspectorPanel')),
    );
    expect(library.width, 232);
    expect(inspector.width, 280);
    expect(canvas.width, 768);
    expect(library.right, canvas.left);
    expect(canvas.right, inspector.left);
    expect(tester.getSize(find.byKey(const Key('outputPanel'))).height, 34);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无脚本项目时中区显示空态占位且左右面板禁用', (tester) async {
    await _pumpEditor(tester, _pack('demo'));

    expect(find.text('暂无脚本项目'), findsOneWidget);
    expect(find.text('请先新建脚本项目'), findsOneWidget);
    expect(_panelOpacity(tester, const Key('nodeLibraryPanel')), 0.5);
    expect(_panelOpacity(tester, const Key('inspectorPanel')), 0.5);
    expect(_panelIgnoring(tester, const Key('nodeLibraryPanel')), isTrue);
    expect(_panelIgnoring(tester, const Key('inspectorPanel')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有脚本项目时中区无空态占位且左右面板可用', (tester) async {
    await _pumpEditor(tester, _packWithScript());

    expect(find.text('暂无脚本项目'), findsNothing);
    expect(find.text('脚本项目'), findsOneWidget);
    expect(find.text('执行顺序'), findsOneWidget);
    expect(_panelOpacity(tester, const Key('nodeLibraryPanel')), 1.0);
    expect(_panelOpacity(tester, const Key('inspectorPanel')), 1.0);
    expect(_panelIgnoring(tester, const Key('nodeLibraryPanel')), isFalse);
    expect(_panelIgnoring(tester, const Key('inspectorPanel')), isFalse);
    expect(find.byKey(const Key('editorCanvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶栏生成预览按钮：无项目时禁用，有项目时可用', (WidgetTester tester) async {
    await _pumpEditor(tester, _pack('demo'));

    expect(find.byTooltip('生成 PowerShell 代码预览'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('generatePreviewButton')))
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpEditor(tester, _packWithEntryScript());

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('generatePreviewButton')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('顶栏生成预览：点击后展开底部面板并显示生成代码', (WidgetTester tester) async {
    await _pumpEditor(tester, _packWithEntryScript());

    await tester.tap(find.byKey(const Key('generatePreviewButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(find.byKey(const Key('outputPanel'))).height, 220);
    expect(find.textContaining('由 cpp_nuget_pack 生成'), findsOneWidget);
    expect(find.textContaining('已生成 · 7 行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画布节点错误红点：诊断为错误的节点显示红点', (WidgetTester tester) async {
    await _pumpEditor(tester, _packWithInvalidNodeScript());

    // n1（复制）缺必填输入 → 错误红点；n0（入口）仅警告 → 无红点。
    expect(find.byKey(const Key('nodeErrorDot_n1')), findsOneWidget);
    expect(find.byKey(const Key('nodeErrorDot_n0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存状态初始为「已保存」且位于生成预览按钮之前', (WidgetTester tester) async {
    await _pumpEditor(tester, _packWithScript());

    expect(find.byKey(const Key('saveStatus')), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('saveStatus'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('generatePreviewButton'))).dx,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑参数后防抖保存：scripts 更新且其他字段保留', (WidgetTester tester) async {
    final PackModel pack = _fullPackWithTextNode();
    final List<PackModel> saved = <PackModel>[];
    await _pumpEditor(
      tester,
      pack,
      debounce: const Duration(milliseconds: 20),
      onSave: (PackModel updated) async {
        saved.add(updated);
        return true;
      },
    );

    await _editTextNode(tester, 'hello');
    expect(find.text('未保存'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(saved, hasLength(1));
    final PackModel updated = saved.single;
    expect(updated.scripts.single.nodes.single.params['value'], 'hello');
    expect(identical(updated.scripts.single, pack.scripts.single), isTrue);
    expect(updated.name, 'demo');
    expect(updated.version, '2.1.0');
    expect(updated.author, 'tester');
    expect(updated.description, '描述');
    expect(updated.license, 'MIT');
    expect(updated.iconPath, 'icon.png');
    expect(updated.sourcePath, r'D:\src');
    expect(updated.files, same(pack.files));
    expect(updated.dependencies, same(pack.dependencies));
    expect(updated.commands, same(pack.commands));
    expect(updated.macros, same(pack.macros));
    expect(updated.libDirectories, same(pack.libDirectories));
    expect(updated.libraries, same(pack.libraries));
    expect(updated.history, same(pack.history));
    expect(find.text('已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败显示「保存失败」与重试按钮，重试成功恢复「已保存」', (WidgetTester tester) async {
    final List<PackModel> saved = <PackModel>[];
    bool succeed = false;
    await _pumpEditor(
      tester,
      _fullPackWithTextNode(),
      debounce: const Duration(milliseconds: 20),
      onSave: (PackModel updated) async {
        if (!succeed) {
          return false;
        }
        saved.add(updated);
        return true;
      },
    );

    await _editTextNode(tester, 'x');
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.byKey(const Key('retrySaveButton')), findsOneWidget);

    succeed = true;
    await tester.tap(find.byKey(const Key('retrySaveButton')));
    await tester.pump();
    await tester.pump();
    // fluent_ui 悬停按钮在点击后启动 100ms 内部计时，推进以免测试收尾挂起。
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('已保存'), findsOneWidget);
    expect(saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回：保存完成后 pop 回上一页', (WidgetTester tester) async {
    final List<PackModel> saved = <PackModel>[];
    await _pumpEditorInRoute(
      tester,
      _fullPackWithTextNode(),
      debounce: const Duration(milliseconds: 20),
      onSave: (PackModel updated) async {
        saved.add(updated);
        return true;
      },
    );

    await _editTextNode(tester, 'hello');
    await tester.tap(find.byTooltip('返回包管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('nodeEditorPage')), findsNothing);
    expect(saved, isNotEmpty);
    expect(saved.last.scripts.single.nodes.single.params['value'], 'hello');
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回：保存失败弹确认对话框，点「仍返回」仍 pop', (WidgetTester tester) async {
    int attempts = 0;
    await _pumpEditorInRoute(
      tester,
      _fullPackWithTextNode(),
      debounce: const Duration(milliseconds: 20),
      onSave: (PackModel updated) async {
        attempts++;
        throw const FormatException('磁盘写入失败');
      },
    );

    await _editTextNode(tester, 'x');
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    expect(find.text('保存失败'), findsOneWidget);

    await tester.tap(find.byTooltip('返回包管理'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.byKey(const Key('saveFailedDialog')), findsOneWidget);
    expect(find.textContaining('脚本项目「脚本 1」保存失败：磁盘写入失败'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveFailedLeaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('nodeEditorPage')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回：保存失败对话框点「重试」成功后 pop', (WidgetTester tester) async {
    final List<PackModel> saved = <PackModel>[];
    bool succeed = false;
    await _pumpEditorInRoute(
      tester,
      _fullPackWithTextNode(),
      debounce: const Duration(milliseconds: 20),
      onSave: (PackModel updated) async {
        if (!succeed) {
          throw const FormatException('磁盘写入失败');
        }
        saved.add(updated);
        return true;
      },
    );

    await _editTextNode(tester, 'x');
    await tester.tap(find.byTooltip('返回包管理'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('saveFailedDialog')), findsOneWidget);

    succeed = true;
    await tester.tap(find.byKey(const Key('saveFailedRetryButton')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('nodeEditorPage')), findsNothing);
    expect(saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fling 惯性终点视口在防抖后写入保存且不回跳', (WidgetTester tester) async {
    final PackModel pack = _packWithScript();
    pack.scripts.single.nodes.add(
      ScriptNodeModel(id: 'n1', type: 'value.text', x: 40, y: 60),
    );
    final List<PackModel> saved = <PackModel>[];
    await _pumpEditor(
      tester,
      pack,
      debounce: const Duration(milliseconds: 20),
      onSave: (PackModel updated) async {
        saved.add(updated);
        return true;
      },
    );

    await tester.flingFrom(
      const Offset(640, 400),
      const Offset(-160, -110),
      1200,
    );
    // 有界推进惯性动画（约 1.3s）至结束。
    for (int frame = 0; frame < 80; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final TransformationController transformation = _editorTransformation(
      tester,
    );
    final Matrix4 settled = transformation.value.clone();
    expect(settled.storage[12], isNot(0));

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    final Matrix4 after = transformation.value;
    expect(after.storage[12], settled.storage[12]);
    expect(after.storage[13], settled.storage[13]);
    expect(after.getMaxScaleOnAxis(), settled.getMaxScaleOnAxis());

    expect(saved, isNotEmpty);
    final ScriptProjectModel persisted = saved.last.scripts.single;
    expect(persisted.viewX, closeTo(settled.storage[12], 1e-9));
    expect(persisted.viewY, closeTo(settled.storage[13], 1e-9));
    expect(persisted.viewScale, closeTo(settled.getMaxScaleOnAxis(), 1e-9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('诊断行程序化居中后同样防抖写回保存', (WidgetTester tester) async {
    final List<PackModel> saved = <PackModel>[];
    await _pumpEditor(
      tester,
      _packWithEntryScript(),
      debounce: const Duration(milliseconds: 20),
      onSave: (PackModel updated) async {
        saved.add(updated);
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('generatePreviewButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('outputTabDiagnostics')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('diagnosticRow_0')));
    await tester.pump();

    final TransformationController transformation = _editorTransformation(
      tester,
    );
    final double centeredX = transformation.value.storage[12];
    expect(centeredX, isNot(0));

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(saved, isNotEmpty);
    final ScriptProjectModel persisted = saved.last.scripts.single;
    expect(persisted.viewX, closeTo(centeredX, 1e-9));
    expect(persisted.viewY, closeTo(transformation.value.storage[13], 1e-9));
    expect(persisted.viewScale, closeTo(1.0, 1e-9));
    expect(tester.takeException(), isNull);
  });

  test('页面构造接受 generator 与 packagePaths 注入', () {
    final PackModel pack = _pack('demo');
    final ScriptEditorPage page = ScriptEditorPage(
      pack: pack,
      onSave: (PackModel updated) async => true,
      generator: PowerShell5Generator(),
      packagePaths: const <String>['lib/x.lib'],
    );

    expect(page.pack, same(pack));
    expect(page.generator, isA<PowerShell5Generator>());
    expect(page.packagePaths, const <String>['lib/x.lib']);
  });
}

PackModel _pack(String name) =>
    PackModel(name: name, version: '1.0.0', author: 'tester');

PackModel _packWithScript() {
  return _pack('demo')
    ..scripts = <ScriptProjectModel>[
      ScriptProjectModel(
        id: 'script_1',
        name: '脚本 1',
        trigger: ScriptTrigger.pre,
      ),
    ];
}

/// 仅含一个未连线入口节点的脚本（生成 7 行 PowerShell、含一条警告）。
PackModel _packWithEntryScript() {
  final PackModel pack = _packWithScript();
  pack.scripts.single.nodes.add(
    ScriptNodeModel(id: 'n1', type: 'flow.entry', x: 40, y: 60),
  );
  return pack;
}

/// 入口（仅警告）+ 缺必填输入的复制节点（错误）的脚本。
PackModel _packWithInvalidNodeScript() {
  final PackModel pack = _packWithScript();
  pack.scripts.single.nodes
    ..add(ScriptNodeModel(id: 'n0', type: 'flow.entry', x: 40, y: 60))
    ..add(ScriptNodeModel(id: 'n1', type: 'file.copy', x: 400, y: 60));
  return pack;
}

/// 全字段包（覆盖包字段与八类列表）+ 单个 `value.text` 节点的脚本。
PackModel _fullPackWithTextNode() {
  final PackModel pack =
      PackModel(
          name: 'demo',
          version: '2.1.0',
          author: 'tester',
          description: '描述',
          license: 'MIT',
          iconPath: 'icon.png',
          sourcePath: r'D:\src',
        )
        ..files = <FileModel>[
          FileModel(name: 'a.h', path: 'include/a.h', size: 10),
        ]
        ..dependencies = <DependencyModel>[
          const DependencyModel(name: 'dep', version: '[1.0,)'),
        ]
        ..commands = <CmdModel>[
          const CmdModel(command: 'echo hi', type: CmdType.preBuild),
        ]
        ..macros = <MacroModel>[const MacroModel(value: 'FOO=1')]
        ..libDirectories = <LibDirModel>[
          const LibDirModel(path: r'third_party\lib'),
        ]
        ..libraries = <LibraryModel>[const LibraryModel(name: 'a.lib')]
        ..history = <HistoryModel>[
          HistoryModel(
            time: DateTime(2026, 9, 12),
            type: HistoryType.created,
            message: '创建',
          ),
        ];
  pack.scripts = <ScriptProjectModel>[
    ScriptProjectModel(id: 'script_1', name: '脚本 1', trigger: ScriptTrigger.pre)
      ..nodes.add(ScriptNodeModel(id: 'n1', type: 'value.text', x: 40, y: 60)),
  ];
  return pack;
}

Future<void> _pumpEditor(
  WidgetTester tester,
  PackModel pack, {
  Future<bool> Function(PackModel pack)? onSave,
  Duration debounce = const Duration(milliseconds: 400),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: ScriptEditorPage(
        pack: pack,
        onSave: onSave ?? (PackModel updated) async => true,
        debounce: debounce,
      ),
    ),
  );
  await tester.pump();
}

/// 经 [FluentPageRoute] 压入编辑器（返回按钮的 pop 行为需要真实路由栈）。
Future<void> _pumpEditorInRoute(
  WidgetTester tester,
  PackModel pack, {
  required Future<bool> Function(PackModel pack) onSave,
  Duration debounce = const Duration(milliseconds: 400),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: FilledButton(
            key: const Key('openEditorButton'),
            onPressed: () => Navigator.of(context).push<void>(
              FluentPageRoute(
                builder: (_) => ScriptEditorPage(
                  pack: pack,
                  onSave: onSave,
                  debounce: debounce,
                ),
              ),
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('openEditorButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.byKey(const Key('nodeEditorPage')), findsOneWidget);
}

/// 选中 `n1` 文本节点并在检查器「值」字段输入文本（触发控制器变更）。
Future<void> _editTextNode(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const Key('nodeCard_n1')));
  await tester.pump();
  await tester.enterText(find.byKey(const Key('inspectorField_value')), text);
  await tester.pump();
}

TransformationController _editorTransformation(WidgetTester tester) {
  final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  return viewer.transformationController!;
}

double _panelOpacity(WidgetTester tester, Key key) =>
    tester.widget<Opacity>(find.byKey(key)).opacity;

bool _panelIgnoring(WidgetTester tester, Key key) => tester
    .widget<IgnorePointer>(
      // 面板子树可能含控件内建 IgnorePointer（如 TextBox），取最外层（页面级）
      find
          .descendant(of: find.byKey(key), matching: find.byType(IgnorePointer))
          .first,
    )
    .ignoring;
