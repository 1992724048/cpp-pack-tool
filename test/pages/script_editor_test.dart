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

Future<void> _pumpEditor(WidgetTester tester, PackModel pack) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: ScriptEditorPage(
        pack: pack,
        onSave: (PackModel updated) async => true,
      ),
    ),
  );
  await tester.pump();
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
