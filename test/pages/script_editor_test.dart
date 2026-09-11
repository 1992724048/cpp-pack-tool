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
