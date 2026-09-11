import 'package:cpp_nuget_pack/controls/script_editor/edge_painter.dart';
import 'package:cpp_nuget_pack/controls/script_editor/editor_canvas.dart';
import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
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
      expect(execInput.color, UCColors.flavor.text.withValues(alpha: 0.30));
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
        UCColors.flavor.text.withValues(alpha: 0.30),
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

    testWidgets('引脚环优先级：error > rejected > candidate', (
      WidgetTester tester,
    ) async {
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
              hasError: false,
              connectedPins: const <String>{},
              errorPins: const <String>{'exec'},
              rejectedPins: const <String>{'exec', 'source'},
              candidatePins: const <String>{'source', 'destination'},
            ),
          ),
        ),
      );

      expect(
        _ringDecoration(tester, 'n1', 'exec').border!.top.color,
        UCColors.flavor.red,
      );
      expect(
        _ringDecoration(tester, 'n1', 'source').border!.top.color,
        UCColors.flavor.red,
      );
      expect(
        _ringDecoration(tester, 'n1', 'destination').border!.top.color,
        UCColors.flavor.blue.withValues(alpha: 0.75),
      );
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

    testWidgets('fling 惯性结束后外部通知不回跳视口', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 40, y: 60)],
        ),
      );

      // 甩动：onInteractionEnd 在惯性开始前先把当时的矩阵写回模型。
      await tester.flingFrom(
        const Offset(640, 400),
        const Offset(-160, -110),
        1200,
      );
      // 有界推进惯性动画（约 0.3s）至结束。
      for (int frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final Matrix4 inertiaEnd = _transformation(tester).value.clone();
      expect(
        inertiaEnd.storage[12] == controller.project.viewX &&
            inertiaEnd.storage[13] == controller.project.viewY,
        isFalse,
        reason: '前置条件：惯性后矩阵应领先于 onInteractionEnd 写回的模型视口',
      );

      // 任一控制器通知（此处选中节点）不得把视口回跳到惯性起点。
      controller.selectNode('n1');
      await tester.pump();

      final Matrix4 afterNotify = _transformation(tester).value;
      expect(afterNotify.storage[12], inertiaEnd.storage[12]);
      expect(afterNotify.storage[13], inertiaEnd.storage[13]);
      expect(afterNotify.getMaxScaleOnAxis(), inertiaEnd.getMaxScaleOnAxis());
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

  group('连线渲染与选中', () {
    testWidgets('连线为 EdgePainter 且端点锚点/类型正确', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 400, y: 60),
          ],
          edges: <ScriptEdgeModel>[
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n1', pin: 'result'),
              to: ScriptEdgeEndpoint(node: 'n2', pin: 'source'),
            ),
          ],
        ),
      );

      final EdgePainter painter = _edgePainter(tester);
      expect(painter.edges, hasLength(1));
      final EdgeVisual edge = painter.edges.single;
      expect(edge.from, const Offset(248, 109));
      expect(edge.to, const Offset(400, 131));
      expect(edge.kind, ScriptPinKind.data);
      expect(edge.dataType, ScriptDataType.string);
      expect(edge.selected, isFalse);
      expect(edge.hovered, isFalse);
    });

    testWidgets('点击连线选中，点击空白取消选中', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 400, y: 60),
          ],
          edges: <ScriptEdgeModel>[
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n1', pin: 'result'),
              to: ScriptEdgeEndpoint(node: 'n2', pin: 'source'),
            ),
          ],
        ),
      );
      final ScriptEdgeModel edge = controller.project.edges.single;

      await tester.tapAt(const Offset(324, 120));
      await tester.pump();

      expect(controller.selectedEdge, same(edge));
      expect(_edgePainter(tester).edges.single.selected, isTrue);

      await tester.tapAt(const Offset(900, 700));
      await tester.pump();

      expect(controller.selectedEdge, isNull);
      expect(_edgePainter(tester).edges.single.selected, isFalse);
    });

    testWidgets('悬停连线高亮并切换光标', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 400, y: 60),
          ],
          edges: <ScriptEdgeModel>[
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n1', pin: 'result'),
              to: ScriptEdgeEndpoint(node: 'n2', pin: 'source'),
            ),
          ],
        ),
      );

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(const Offset(324, 120));
      await tester.pump();
      expect(_edgePainter(tester).edges.single.hovered, isTrue);
      expect(_sceneRegion(tester).cursor, SystemMouseCursors.click);

      await mouse.moveTo(const Offset(900, 700));
      await tester.pump();
      expect(_edgePainter(tester).edges.single.hovered, isFalse);
      expect(_sceneRegion(tester).cursor, SystemMouseCursors.basic);
    });

    test('连线几何与样式常量符合 §5.4', () {
      expect(edgeControlOffset(const Offset(0, 0), const Offset(100, 0)), 74);
      expect(edgeControlOffset(const Offset(0, 0), const Offset(10, 0)), 48);
      expect(edgeControlOffset(const Offset(0, 0), const Offset(600, 0)), 160);
      expect(
        edgePointAt(const Offset(0, 0), const Offset(100, 0), 0.5),
        const Offset(50, 0),
      );
      expect(edgeHitTolerance(1), 8);
      expect(edgeHitTolerance(0.5), 16);
      expect(edgeHitTolerance(2), 4);
      expect(EdgePainter.execWidth, 2.5);
      expect(EdgePainter.dataWidth, 2.0);
      expect(EdgePainter.selectedWidth, 3.0);
      expect(EdgePainter.endpointDotRadius, 4.0);
      expect(EdgePainter.normalExecAlpha, 0.70);
      expect(EdgePainter.normalDataAlpha, 0.95);
      expect(EdgePainter.previewAlpha, 0.85);
    });
  });

  group('引脚拖拽建连', () {
    testWidgets('拖到兼容输入引脚建立连接并即时重算诊断', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 400, y: 60),
          ],
        ),
      );
      expect(find.byKey(const Key('pinRing_n2_source')), findsOneWidget);

      await _dragPinToPin(tester, 'n1', 'result', 'n2', 'source');

      final ScriptEdgeModel edge = controller.project.edges.single;
      expect(edge.from.node, 'n1');
      expect(edge.from.pin, 'result');
      expect(edge.to.node, 'n2');
      expect(edge.to.pin, 'source');
      expect(find.byKey(const Key('floatingToast')), findsNothing);
      expect(find.byKey(const Key('pinRing_n2_source')), findsNothing);
    });

    testWidgets('从引脚命中盒扩展区（视觉外 6.5px）起拖仍可建连', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 400, y: 60),
          ],
        ),
      );

      // 起拖点 = 引脚中心 + 6.5px：在引脚视觉（Ø10）之外、命中盒（Ø16）之内。
      final TestGesture gesture = await _startPinDrag(
        tester,
        'n1',
        'result',
        offset: const Offset(6.5, 0),
      );
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('pin_n2_source'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(controller.project.edges, hasLength(1));
      final ScriptEdgeModel edge = controller.project.edges.single;
      expect(edge.from.node, 'n1');
      expect(edge.from.pin, 'result');
      expect(edge.to.node, 'n2');
      expect(edge.to.pin, 'source');
    });

    testWidgets('拖到输出引脚拒绝：提示 + 红环红闪 + 图不变', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 400, y: 60),
          ],
        ),
      );

      await _dragPinToPin(tester, 'n1', 'result', 'n2', 'out');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('无法连接：请从输出引脚拖向输入引脚'), findsOneWidget);
      expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
      expect(find.byKey(const Key('pinRing_n2_out')), findsOneWidget);
      expect(controller.project.edges, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byKey(const Key('pinRing_n2_out')), findsNothing);
    });

    testWidgets('拖到 kind 不符引脚拒绝：提示原因且图不变', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n0', 'flow.entry', x: 40, y: 60),
            _node('n1', 'value.text', x: 400, y: 60),
            _node('n2', 'file.copy', x: 760, y: 60),
          ],
          edges: <ScriptEdgeModel>[
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n0', pin: 'out'),
              to: ScriptEdgeEndpoint(node: 'n2', pin: 'exec'),
            ),
          ],
        ),
      );
      expect(find.byKey(const Key('pinRing_n2_exec')), findsNothing);

      await _dragPinToPin(tester, 'n1', 'result', 'n2', 'exec');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('无法连接：目标引脚需要 执行'), findsOneWidget);
      expect(find.byKey(const Key('pinRing_n2_exec')), findsOneWidget);
      expect(controller.project.edges, hasLength(1));
      expect(controller.project.edges.single.from.node, 'n0');
    });

    testWidgets('拖到占用输入引脚替换旧连接（静默）', (WidgetTester tester) async {
      final GraphEditorController controller = await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n0', 'flow.entry', x: 40, y: 60),
            _node('n1', 'value.text', x: 400, y: 60),
            _node('n2', 'file.copy', x: 760, y: 60),
            _node('n3', 'value.text', x: 40, y: 300),
          ],
          edges: <ScriptEdgeModel>[
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n0', pin: 'out'),
              to: ScriptEdgeEndpoint(node: 'n2', pin: 'exec'),
            ),
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n1', pin: 'result'),
              to: ScriptEdgeEndpoint(node: 'n2', pin: 'source'),
            ),
          ],
        ),
      );
      expect(controller.project.edges, hasLength(2));

      await _dragPinToPin(tester, 'n3', 'result', 'n2', 'source');
      await tester.pump();

      expect(controller.project.edges, hasLength(2));
      expect(
        controller.project.edges.any(
          (ScriptEdgeModel edge) =>
              edge.from.node == 'n3' && edge.to.pin == 'source',
        ),
        isTrue,
      );
      expect(
        controller.project.edges.any(
          (ScriptEdgeModel edge) => edge.from.node == 'n1',
        ),
        isFalse,
      );
      expect(find.byKey(const Key('floatingToast')), findsNothing);
    });

    testWidgets('拖拽预览线状态随悬停目标切换并随取消消失', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text', x: 40, y: 60),
            _node('n2', 'file.copy', x: 400, y: 60),
          ],
        ),
      );

      final TestGesture gesture = await _startPinDrag(tester, 'n1', 'result');
      EdgePainter painter = _edgePainter(tester);
      expect(painter.preview, isNotNull);
      expect(painter.preview!.state, EdgePreviewState.normal);
      expect(painter.preview!.color, UCColors.flavor.blue);
      expect(painter.preview!.from, const Offset(248, 109));
      expect(painter.preview!.to, const Offset(272, 109));

      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('pin_n2_source'))),
      );
      await tester.pump();
      painter = _edgePainter(tester);
      expect(painter.preview!.state, EdgePreviewState.compatible);

      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('pin_n2_exec'))),
      );
      await tester.pump();
      painter = _edgePainter(tester);
      expect(painter.preview!.state, EdgePreviewState.incompatible);

      await gesture.moveTo(const Offset(900, 700));
      await tester.pump();
      painter = _edgePainter(tester);
      expect(painter.preview!.state, EdgePreviewState.normal);

      await gesture.up();
      await tester.pump();
      expect(_edgePainter(tester).preview, isNull);
    });

    testWidgets('拖拽期间兼容引脚显示候选环、不可达引脚弱化', (WidgetTester tester) async {
      await _pumpCanvas(tester, _connectedProject());

      final TestGesture gesture = await _startPinDrag(tester, 'n3', 'result');

      expect(find.byKey(const Key('pinRing_n4_source')), findsOneWidget);
      expect(find.byKey(const Key('pinRing_n4_destination')), findsOneWidget);
      expect(find.byKey(const Key('pinRing_n4_exec')), findsNothing);
      final BoxDecoration candidateRing = _ringDecoration(
        tester,
        'n4',
        'source',
      );
      expect(
        candidateRing.border!.top.color,
        UCColors.flavor.blue.withValues(alpha: 0.75),
      );
      expect(candidateRing.border!.top.width, 2);
      expect(_pinOpacity(tester, 'n4', 'source'), 1.0);
      expect(_pinOpacity(tester, 'n4', 'exec'), 0.35);

      await gesture.up();
      await tester.pump();

      expect(find.byKey(const Key('pinRing_n4_source')), findsNothing);
      expect(find.byKey(const Key('pinRing_n4_destination')), findsNothing);
      expect(_pinOpacity(tester, 'n4', 'exec'), 1.0);
    });
  });

  group('诊断错误引脚红标', () {
    testWidgets('必填未连接的输入引脚显示 2px 红环', (WidgetTester tester) async {
      await _pumpCanvas(
        tester,
        _project(nodes: <ScriptNodeModel>[_node('n1', 'file.copy')]),
      );

      final BoxDecoration ring = _ringDecoration(tester, 'n1', 'source');
      expect(ring.border!.top.color, UCColors.flavor.red);
      expect(ring.border!.top.width, 2);
      expect(find.byKey(const Key('pinRing_n1_exec')), findsOneWidget);
      expect(find.byKey(const Key('pinRing_n1_destination')), findsOneWidget);
    });

    test('errorPinsByNode 按诊断消息定位引脚', () {
      final List<ScriptNodeModel> nodes = <ScriptNodeModel>[
        _node('n1', 'file.copy'),
        _node('n2', 'value.text'),
      ];
      final Map<String, Set<String>> result = errorPinsByNode(
        nodes,
        <ScriptDiagnostic>[
          const ScriptDiagnostic(
            message: '节点「n1」的必填输入「源路径」未连接',
            nodeId: 'n1',
            isError: true,
          ),
          const ScriptDiagnostic(
            message: '引脚种类不匹配：「n2.result」为数据引脚，「n1.exec」为执行引脚',
            nodeId: 'n1',
            isError: true,
          ),
          const ScriptDiagnostic(
            message: '节点「n1」不存在引脚「destination」',
            nodeId: 'n1',
            isError: true,
          ),
          const ScriptDiagnostic(
            message: '数据节点「n2」（文本）未被使用，不参与脚本生成',
            nodeId: 'n2',
            isError: false,
          ),
        ],
      );

      expect(result['n1'], <String>{'source', 'exec', 'destination'});
      expect(result['n2'], isNull);
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

EdgePainter _edgePainter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.byKey(const Key('editorEdges')),
  );
  return paint.painter! as EdgePainter;
}

MouseRegion _sceneRegion(WidgetTester tester) {
  return tester.widget<MouseRegion>(
    find
        .ancestor(
          of: find.byKey(const Key('editorScene')),
          matching: find.byType(MouseRegion),
        )
        .first,
  );
}

BoxDecoration _ringDecoration(
  WidgetTester tester,
  String nodeId,
  String pinId,
) {
  final Container container = tester.widget<Container>(
    find.byKey(Key('pinRing_${nodeId}_$pinId')),
  );
  return container.decoration! as BoxDecoration;
}

double _pinOpacity(WidgetTester tester, String nodeId, String pinId) {
  final Opacity opacity = tester.widget<Opacity>(
    find
        .ancestor(
          of: find.byKey(Key('pin_${nodeId}_$pinId')),
          matching: find.byType(Opacity),
        )
        .first,
  );
  return opacity.opacity;
}

Future<TestGesture> _startPinDrag(
  WidgetTester tester,
  String nodeId,
  String pinId, {
  Offset offset = Offset.zero,
}) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(find.byKey(Key('pin_${nodeId}_$pinId'))) + offset,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump();
  return gesture;
}

Future<void> _dragPinToPin(
  WidgetTester tester,
  String fromNode,
  String fromPin,
  String toNode,
  String toPin,
) async {
  final TestGesture gesture = await _startPinDrag(tester, fromNode, fromPin);
  await gesture.moveTo(
    tester.getCenter(find.byKey(Key('pin_${toNode}_$toPin'))),
  );
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// 全部必填输入已连接的五节点图（无错误诊断）：
/// n0 入口 → n4.exec，n1/n2 文本 → n4.source/destination，n3 为拖拽源。
ScriptProjectModel _connectedProject() {
  return _project(
    nodes: <ScriptNodeModel>[
      _node('n0', 'flow.entry', x: 40, y: 60),
      _node('n1', 'value.text', x: 400, y: 100),
      _node('n2', 'value.text', x: 400, y: 220),
      _node('n3', 'value.text', x: 400, y: 340),
      _node('n4', 'file.copy', x: 760, y: 60),
    ],
    edges: <ScriptEdgeModel>[
      ScriptEdgeModel(
        from: ScriptEdgeEndpoint(node: 'n0', pin: 'out'),
        to: ScriptEdgeEndpoint(node: 'n4', pin: 'exec'),
      ),
      ScriptEdgeModel(
        from: ScriptEdgeEndpoint(node: 'n1', pin: 'result'),
        to: ScriptEdgeEndpoint(node: 'n4', pin: 'source'),
      ),
      ScriptEdgeModel(
        from: ScriptEdgeEndpoint(node: 'n2', pin: 'result'),
        to: ScriptEdgeEndpoint(node: 'n4', pin: 'destination'),
      ),
    ],
  );
}
