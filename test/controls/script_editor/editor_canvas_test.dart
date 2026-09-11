import 'package:cpp_nuget_pack/controls/script_editor/editor_canvas.dart';
import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('节点卡渲染', () {
    testWidgets('按场景坐标渲染每个节点卡且宽度固定 208', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 320, y: 140),
          ],
        ),
      );

      final Finder card1 = find.byKey(const Key('nodeCard_n1'));
      final Finder card2 = find.byKey(const Key('nodeCard_n2'));
      expect(card1, findsOneWidget);
      expect(card2, findsOneWidget);
      expect(tester.getTopLeft(card1), const Offset(40, 60));
      expect(tester.getTopLeft(card2), const Offset(320, 140));
      expect(tester.getSize(card1).width, 208);
      expect(tester.getSize(card2).width, 208);
      expect(
        find.descendant(of: card1, matching: find.text('文本')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card2, matching: find.text('复制')),
        findsOneWidget,
      );
    });

    testWidgets('典型节点卡高度为 66/88/110/132', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry', y: 0),
            _node('n2', 'flow.branch', y: 200),
            _node('n3', 'file.copy', y: 400),
            _node('n4', 'process.run', y: 600),
          ],
        ),
      );

      expect(tester.getSize(find.byKey(const Key('nodeCard_n1'))).height, 66);
      expect(tester.getSize(find.byKey(const Key('nodeCard_n2'))).height, 88);
      expect(tester.getSize(find.byKey(const Key('nodeCard_n3'))).height, 110);
      expect(tester.getSize(find.byKey(const Key('nodeCard_n4'))).height, 132);
    });

    testWidgets('引脚按注册表渲染静态形态且 Key 为 pin_<nodeId>_<pinId>', (
      WidgetTester tester,
    ) async {
      await _pumpCanvas(
        tester,
        _project(nodes: <ScriptNodeModel>[_node('n1', 'file.copy')]),
      );

      for (final String pinId in <String>[
        'exec',
        'source',
        'destination',
        'out',
      ]) {
        expect(find.byKey(Key('pin_n1_$pinId')), findsOneWidget);
      }

      final BoxDecoration execInput = _pinDecoration(tester, 'n1', 'exec');
      expect(
        tester.getSize(find.byKey(const Key('pin_n1_exec'))),
        const Size(14, 8),
      );
      expect(execInput.shape, BoxShape.rectangle);
      expect(execInput.color, UCColors.flavor.text.withValues(alpha: 0.35));
      expect(execInput.border!.top.color, UCColors.flavor.text);
      expect(execInput.border!.top.width, 1.5);

      final BoxDecoration stringInput = _pinDecoration(tester, 'n1', 'source');
      expect(
        tester.getSize(find.byKey(const Key('pin_n1_source'))),
        const Size(10, 10),
      );
      expect(stringInput.shape, BoxShape.circle);
      expect(stringInput.color, UCColors.flavor.blue.withValues(alpha: 0.35));
      expect(stringInput.border!.top.color, UCColors.flavor.blue);
    });

    testWidgets('已连接引脚为实心类型色', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'file.copy'),
            _node('n2', 'value.text'),
          ],
          edges: <ScriptEdgeModel>[
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n2', pin: 'result'),
              to: ScriptEdgeEndpoint(node: 'n1', pin: 'source'),
            ),
          ],
        ),
      );

      expect(
        _pinDecoration(tester, 'n2', 'result').color,
        UCColors.flavor.blue,
      );
      expect(
        _pinDecoration(tester, 'n1', 'source').color,
        UCColors.flavor.blue,
      );
      expect(
        _pinDecoration(tester, 'n1', 'exec').color,
        UCColors.flavor.text.withValues(alpha: 0.35),
      );
    });

    testWidgets('节点卡悬停态描边与背景变化，移出恢复', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
        ),
      );

      expect(_cardBorder(tester, 'n1').top.color, UCColors.flavor.overlay0);
      expect(_cardDecoration(tester, 'n1').color, UCColors.flavor.surface0);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('nodeCard_n1'))),
      );
      await tester.pump();

      expect(_cardBorder(tester, 'n1').top.color, UCColors.flavor.overlay1);
      expect(_cardDecoration(tester, 'n1').color, UCColors.flavor.surface1);

      await mouse.moveTo(const Offset(1200, 700));
      await tester.pump();

      expect(_cardBorder(tester, 'n1').top.color, UCColors.flavor.overlay0);
      expect(_cardDecoration(tester, 'n1').color, UCColors.flavor.surface0);
    });

    testWidgets('选中节点为 2px accent 描边且置顶渲染', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'value.text', x: 60, y: 80),
          ],
        ),
      );

      controller.selectNode('n1');
      await tester.pump();

      final BoxDecoration decoration = _cardDecoration(tester, 'n1');
      final Border border = _cardBorder(tester, 'n1');
      expect(border.top.color, UCColors.accent);
      expect(border.top.width, 2);
      expect(decoration.color, UCColors.flavor.surface0);

      final List<String> order = tester
          .widgetList<NodeCard>(
            find.descendant(
              of: find.byKey(const Key('editorScene')),
              matching: find.byType(NodeCard),
            ),
          )
          .map((NodeCard card) => card.nodeId)
          .toList();
      expect(order.last, 'n1');
    });

    testWidgets('错误接口位渲染右上角红点与引脚红环', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: NodeCard(
              nodeId: 'n1',
              typeKey: 'file.copy',
              descriptor: NodeRegistry.byType('file.copy'),
              selected: false,
              dragging: false,
              hasError: true,
              connectedPins: const <String>{},
              errorPins: const <String>{'source'},
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('nodeErrorDot_n1')), findsOneWidget);
      expect(find.byKey(const Key('pinRing_n1_source')), findsOneWidget);
      expect(find.byKey(const Key('pinRing_n1_destination')), findsNothing);
    });
  });

  group('节点拖动与选中', () {
    testWidgets('拖动卡片按屏幕位移写入 moveNode 并选中', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
        ),
      );

      await tester.drag(
        find.byKey(const Key('nodeCard_n1')),
        const Offset(60, 30),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      final ScriptNodeModel node = controller.project.nodes.single;
      expect(node.x, 100);
      expect(node.y, 90);
      expect(controller.selectedNodeId, 'n1');
    });

    testWidgets('缩放 2 倍时拖动位移按 scale 换算', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
        ),
      );
      await _setScale(tester, controller, 2.0);

      await tester.drag(
        find.byKey(const Key('nodeCard_n1')),
        const Offset(60, 30),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      final ScriptNodeModel node = controller.project.nodes.single;
      expect(node.x, 70);
      expect(node.y, 75);
    });

    testWidgets('单击选中；位移小于 3 屏幕 px 不写入坐标', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
        ),
      );
      final Finder card = find.byKey(const Key('nodeCard_n1'));

      await tester.tap(card);
      await tester.pump();
      expect(controller.selectedNodeId, 'n1');

      controller.clearSelection();
      await tester.pump();

      final TestGesture drag = await tester.startGesture(
        tester.getCenter(card),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(2.9, 0));
      await drag.up();
      await tester.pump();

      expect(controller.selectedNodeId, 'n1');
      final ScriptNodeModel node = controller.project.nodes.single;
      expect(node.x, 40);
      expect(node.y, 60);
    });
  });

  group('视口', () {
    testWidgets('初始变换恢复项目视口', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
          viewX: 120,
          viewY: -40,
          viewScale: 1.5,
        ),
      );

      final Matrix4 matrix = _transformation(tester).value;
      expect(matrix.storage[12], 120);
      expect(matrix.storage[13], -40);
      expect(matrix.getMaxScaleOnAxis(), 1.5);
    });

    testWidgets('loadProject 切换项目后应用新视口', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text')],
          viewX: 10,
          viewY: 20,
        ),
      );

      controller.loadProject(
        _project(
          nodes: <ScriptNodeModel>[_node('n2', 'value.text')],
          viewX: 200,
          viewY: 100,
          viewScale: 1.25,
        ),
      );
      await tester.pump();

      final Matrix4 matrix = _transformation(tester).value;
      expect(matrix.storage[12], 200);
      expect(matrix.storage[13], 100);
      expect(matrix.getMaxScaleOnAxis(), 1.25);
    });

    testWidgets('外部写回视口后画布变换同步', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(nodes: <ScriptNodeModel>[_node('n1', 'value.text')]),
      );

      controller.setViewport(x: 50, y: 60, scale: 1.25);
      await tester.pump();

      final Matrix4 matrix = _transformation(tester).value;
      expect(matrix.storage[12], 50);
      expect(matrix.storage[13], 60);
      expect(matrix.getMaxScaleOnAxis(), 1.25);
    });

    testWidgets('画布空白平移结束写回 setViewport', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
        ),
      );

      await tester.dragFrom(
        const Offset(900, 650),
        const Offset(60, 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      final Matrix4 matrix = _transformation(tester).value;
      expect(matrix.storage[12], isNot(0));
      expect(controller.project.viewX, matrix.storage[12]);
      expect(controller.project.viewY, matrix.storage[13]);
      expect(controller.project.viewScale, matrix.getMaxScaleOnAxis());
    });

    testWidgets('滚轮缩放改变变换并写回视口', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
        ),
      );
      expect(_transformation(tester).value.getMaxScaleOnAxis(), 1.0);

      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(const Offset(500, 400));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();

      final Matrix4 matrix = _transformation(tester).value;
      expect(matrix.getMaxScaleOnAxis(), greaterThan(1.0));
      expect(controller.project.viewScale, matrix.getMaxScaleOnAxis());
      expect(controller.project.viewX, matrix.storage[12]);
      expect(controller.project.viewY, matrix.storage[13]);
    });

    testWidgets('缩放低于 0.75 隐藏引脚标签，达到 0.75 恢复', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'file.copy', x: 40, y: 60)],
        ),
      );
      expect(find.text('源路径'), findsOneWidget);
      expect(find.text('目标路径'), findsOneWidget);

      await _setScale(tester, controller, 0.5);
      expect(find.text('源路径'), findsNothing);
      expect(find.text('目标路径'), findsNothing);
      expect(find.byKey(const Key('pin_n1_source')), findsOneWidget);

      await _setScale(tester, controller, 0.74);
      expect(find.text('源路径'), findsNothing);
      expect(find.text('目标路径'), findsNothing);
      expect(find.byKey(const Key('pin_n1_source')), findsOneWidget);

      await _setScale(tester, controller, 0.75);
      expect(find.text('源路径'), findsOneWidget);
      expect(find.text('目标路径'), findsOneWidget);
    });
  });

  group('场景与网格', () {
    testWidgets('场景尺寸按节点包围盒四周加 600 重算（最小 1600×1200）', (
      WidgetTester tester,
    ) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'value.text', x: 1600, y: 1300),
          ],
        ),
      );
      final Finder scene = find.byKey(const Key('editorScene'));
      expect(tester.getSize(scene), const Size(2968, 2506));

      controller.moveNode('n2', const Offset(40, 60));
      await tester.pump();
      expect(tester.getSize(scene), const Size(1600, 1266));

      controller.addNode('value.text', const Offset(3000, 2500));
      await tester.pump();
      expect(tester.getSize(scene), const Size(4368, 3706));
    });

    testWidgets('网格背景为 CustomPainter 且数值符合规范', (WidgetTester tester) async {
      await _pumpCanvas(tester, _project());

      final Finder grid = find.byKey(const Key('editorGrid'));
      expect(grid, findsOneWidget);
      final CustomPaint paint = tester.widget<CustomPaint>(grid);
      expect(paint.painter, isA<EditorGridPainter>());
      final EditorGridPainter painter = paint.painter! as EditorGridPainter;
      expect(painter.color, UCColors.flavor.overlay0);
      expect(EditorGridPainter.smallSpacing, 24);
      expect(EditorGridPainter.largeSpacing, 120);
      expect(EditorGridPainter.smallRadius, 1.2);
      expect(EditorGridPainter.largeRadius, 1.8);
      expect(EditorGridPainter.smallAlpha, 0.35);
      expect(EditorGridPainter.largeAlpha, 0.5);
    });
  });
}

ScriptNodeModel _node(String id, String type, {double x = 0, double y = 0}) {
  return ScriptNodeModel(id: id, type: type, x: x, y: y);
}

ScriptProjectModel _project({
  List<ScriptNodeModel>? nodes,
  List<ScriptEdgeModel>? edges,
  double viewX = 0,
  double viewY = 0,
  double viewScale = 1.0,
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '测试脚本',
    trigger: ScriptTrigger.pre,
  );
  project.nodes = nodes ?? <ScriptNodeModel>[];
  project.edges = edges ?? <ScriptEdgeModel>[];
  project.viewX = viewX;
  project.viewY = viewY;
  project.viewScale = viewScale;
  return project;
}

Future<GraphEditorController> _pumpCanvas(
  WidgetTester tester,
  ScriptProjectModel project,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final GraphEditorController controller = GraphEditorController(project);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    FluentApp(home: EditorCanvas(controller: controller)),
  );
  await tester.pump();
  return controller;
}

TransformationController _transformation(WidgetTester tester) {
  return tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!;
}

Future<void> _setScale(
  WidgetTester tester,
  GraphEditorController controller,
  double scale,
) async {
  _transformation(tester).value = Matrix4.identity()
    ..scaleByDouble(scale, scale, scale, 1);
  controller.setViewport(x: 0, y: 0, scale: scale);
  await tester.pump();
}

BoxDecoration _cardDecoration(WidgetTester tester, String nodeId) {
  final Container container = tester.widget<Container>(
    find.byKey(Key('nodeCard_$nodeId')),
  );
  return container.decoration! as BoxDecoration;
}

Border _cardBorder(WidgetTester tester, String nodeId) {
  final Container container = tester.widget<Container>(
    find.byKey(Key('nodeCard_$nodeId')),
  );
  return (container.foregroundDecoration! as BoxDecoration).border! as Border;
}

BoxDecoration _pinDecoration(WidgetTester tester, String nodeId, String pinId) {
  final Container container = tester.widget<Container>(
    find.byKey(Key('pin_${nodeId}_$pinId')),
  );
  return container.decoration! as BoxDecoration;
}
