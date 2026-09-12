import 'package:cpp_nuget_pack/controls/script_editor/output_panel.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('面板开合', () {
    testWidgets('默认收起为 34 且不构建内容子树', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_validProject());
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);

      expect(_panelHeight(tester), 34);
      expect(find.text('输出'), findsOneWidget);
      expect(find.byTooltip('展开'), findsOneWidget);
      expect(find.byKey(const Key('outputTabCode')), findsNothing);
      expect(find.byKey(const Key('outputTabDiagnostics')), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('展开：150ms 有界动画至 220 并构建内容', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_validProject());
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);

      await tester.tap(find.byTooltip('展开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      expect(_panelHeight(tester), greaterThan(34));
      expect(_panelHeight(tester), lessThan(220));

      await tester.pump(const Duration(milliseconds: 150));

      expect(_panelHeight(tester), 220);
      expect(find.byKey(const Key('outputTabCode')), findsOneWidget);
      expect(find.byKey(const Key('outputTabDiagnostics')), findsOneWidget);
      expect(find.byTooltip('收起'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('展开后收起：动画回落至 34 且内容不再构建', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_validProject());
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);
      await _expand(tester);

      expect(_panelHeight(tester), 220);
      expect(find.byKey(const Key('outputTabCode')), findsOneWidget);

      await tester.tap(find.byTooltip('收起'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      expect(_panelHeight(tester), greaterThan(34));
      expect(_panelHeight(tester), lessThan(220));

      await tester.pump(const Duration(milliseconds: 150));

      expect(_panelHeight(tester), 34);
      expect(find.byKey(const Key('outputTabCode')), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('生成预览', () {
    testWidgets('无错误：展开 + 代码 tab + 生成内容与行数状态', (WidgetTester tester) async {
      final ScriptProjectModel project = _validProject();
      final GraphEditorController controller = _controller(project);
      addTearDown(controller.dispose);
      final GlobalKey<OutputPanelState> panelKey =
          GlobalKey<OutputPanelState>();
      await _pumpPanel(tester, controller: controller, panelKey: panelKey);

      // 前置：该图生成 9 行脚本（入口 + 输出信息 + 文本）。
      final String expectedCode = PowerShell5Generator()
          .compile(project, packName: 'demo')
          .code!;
      expect(expectedCode.split('\n').length - 1, 9);

      panelKey.currentState!.generatePreview();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_panelHeight(tester), 220);
      expect(find.textContaining('由 cpp_nuget_pack 生成'), findsOneWidget);
      expect(
        find.textContaining(r"$ErrorActionPreference = 'Stop'"),
        findsOneWidget,
      );
      expect(find.text('已生成 · 9 行'), findsOneWidget);
      expect(find.text('未生成'), findsNothing);
      // 生成不发提示（面板态即反馈）。
      expect(find.byKey(const Key('floatingToast')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('生成后收起：代码内容不再构建', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_validProject());
      addTearDown(controller.dispose);
      final GlobalKey<OutputPanelState> panelKey =
          GlobalKey<OutputPanelState>();
      await _pumpPanel(tester, controller: controller, panelKey: panelKey);

      panelKey.currentState!.generatePreview();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('由 cpp_nuget_pack 生成'), findsOneWidget);

      await tester.tap(find.byTooltip('收起'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_panelHeight(tester), 34);
      expect(find.textContaining('由 cpp_nuget_pack 生成'), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('有错误：展开 + 诊断 tab + 错误清单与状态文本', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_project());
      addTearDown(controller.dispose);
      final GlobalKey<OutputPanelState> panelKey =
          GlobalKey<OutputPanelState>();
      await _pumpPanel(tester, controller: controller, panelKey: panelKey);

      panelKey.currentState!.generatePreview();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_panelHeight(tester), 220);
      expect(find.byKey(const Key('diagnosticRow_0')), findsOneWidget);
      expect(find.text('脚本必须恰好有一个「开始」节点，当前没有入口节点'), findsOneWidget);
      expect(find.text('1 个错误 · 0 个警告'), findsOneWidget);
      expect(find.byKey(const Key('floatingToast')), findsNothing);

      // 代码 tab 显示编译错误提示文案（不生成代码）。
      await tester.tap(find.byKey(const Key('outputTabCode')));
      await tester.pump();

      expect(find.text('存在编译错误，未生成代码；请查看「诊断」'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('使用注入的生成器并以包名编译', (WidgetTester tester) async {
      final _RecordingGenerator generator = _RecordingGenerator();
      final GraphEditorController controller = _controller(_validProject());
      addTearDown(controller.dispose);
      final GlobalKey<OutputPanelState> panelKey =
          GlobalKey<OutputPanelState>();
      await _pumpPanel(
        tester,
        controller: controller,
        panelKey: panelKey,
        generator: generator,
      );

      panelKey.currentState!.generatePreview();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(generator.project, same(controller.project));
      expect(generator.packName, 'demo');
      // 注入器返回无末尾换行的代码：1 行。
      expect(find.text('已生成 · 1 行'), findsOneWidget);
      expect(find.textContaining('fake-code'), findsOneWidget);
    });

    testWidgets('未生成时代码视图显示引导文案', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_project());
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);
      await _expand(tester);

      expect(find.text('点击顶栏「生成预览」生成 PowerShell 5.1 代码'), findsOneWidget);
      expect(find.text('未生成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('生成后代码视图滚动到顶', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_longProject());
      addTearDown(controller.dispose);
      final GlobalKey<OutputPanelState> panelKey =
          GlobalKey<OutputPanelState>();
      await _pumpPanel(tester, controller: controller, panelKey: panelKey);

      panelKey.currentState!.generatePreview();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final ScrollableState scrollable = _codeScrollable(tester);
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);

      panelKey.currentState!.generatePreview();
      await tester.pump();

      expect(scrollable.position.pixels, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('复制代码：写入剪贴板并提示', (WidgetTester tester) async {
      final List<MethodCall> calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final GraphEditorController controller = _controller(_validProject());
      addTearDown(controller.dispose);
      final GlobalKey<OutputPanelState> panelKey =
          GlobalKey<OutputPanelState>();
      await _pumpPanel(tester, controller: controller, panelKey: panelKey);

      panelKey.currentState!.generatePreview();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('复制代码'));
      await tester.pump();

      final List<MethodCall> clipboardCalls = calls
          .where((MethodCall call) => call.method == 'Clipboard.setData')
          .toList();
      expect(clipboardCalls, hasLength(1));
      final Map<Object?, Object?> arguments =
          clipboardCalls.single.arguments as Map<Object?, Object?>;
      expect(arguments['text'], contains('由 cpp_nuget_pack 生成'));

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('已复制代码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('诊断清单', () {
    testWidgets('空诊断显示占位文案', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_validProject());
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);
      await _openDiagnosticsTab(tester);

      expect(find.text('没有发现错误或警告'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('诊断行：级别图标 + 消息 + 节点 chip', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'flow.entry', x: 40, y: 60)],
        ),
      );
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);
      await _openDiagnosticsTab(tester);

      expect(find.byKey(const Key('diagnosticRow_0')), findsOneWidget);
      expect(find.text('入口节点「n1」的输出未连接'), findsOneWidget);
      expect(find.text('开始'), findsOneWidget);
      expect(find.byIcon(FluentIcons.warning), findsOneWidget);
      final MouseRegion region = _rowRegion(tester, 0);
      expect(region.cursor, SystemMouseCursors.click);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点诊断行：选中节点并将视口居中', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'flow.entry', x: 40, y: 60)],
        ),
      );
      addTearDown(controller.dispose);
      final TransformationController transformation =
          TransformationController();
      addTearDown(transformation.dispose);
      await _pumpPanel(
        tester,
        controller: controller,
        transformation: transformation,
      );
      await _openDiagnosticsTab(tester);

      await tester.tap(find.byKey(const Key('diagnosticRow_0')));
      await tester.pump();

      expect(controller.selectedNodeId, 'n1');
      // 节点中心 = (40 + 104, 60 + 66/2) = (144, 93)；视口 768×532、scale 1：
      // 平移 = 视口中心 − 节点中心 × scale。
      final Matrix4 matrix = transformation.value;
      expect(matrix.storage[12], 768 / 2 - 144);
      expect(matrix.storage[13], 532 / 2 - 93);
      expect(matrix.getMaxScaleOnAxis(), 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点诊断行：保持当前缩放（不额外缩放）', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'flow.entry', x: 40, y: 60)],
        ),
      );
      addTearDown(controller.dispose);
      final TransformationController transformation =
          TransformationController();
      addTearDown(transformation.dispose);
      transformation.value = Matrix4.identity()
        ..translateByDouble(10, 20, 0, 1)
        ..scaleByDouble(1.5, 1.5, 1.5, 1);
      await _pumpPanel(
        tester,
        controller: controller,
        transformation: transformation,
      );
      await _openDiagnosticsTab(tester);

      await tester.tap(find.byKey(const Key('diagnosticRow_0')));
      await tester.pump();

      final Matrix4 matrix = transformation.value;
      expect(matrix.getMaxScaleOnAxis(), 1.5);
      expect(matrix.storage[12], closeTo(768 / 2 - 144 * 1.5, 1e-9));
      expect(matrix.storage[13], closeTo(532 / 2 - 93 * 1.5, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('诊断节点不存在时行不可点击', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'flow.entry', x: 40, y: 60)],
          edges: <ScriptEdgeModel>[
            ScriptEdgeModel(
              from: ScriptEdgeEndpoint(node: 'n1', pin: 'out'),
              to: ScriptEdgeEndpoint(node: 'ghost', pin: 'exec'),
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      final TransformationController transformation =
          TransformationController();
      addTearDown(transformation.dispose);
      final Matrix4 before = transformation.value.clone();
      await _pumpPanel(
        tester,
        controller: controller,
        transformation: transformation,
      );
      await _openDiagnosticsTab(tester);

      expect(find.byKey(const Key('diagnosticRow_0')), findsOneWidget);
      expect(find.text('边引用了不存在的节点「ghost」'), findsOneWidget);
      expect(_rowRegion(tester, 0).cursor, SystemMouseCursors.basic);

      await tester.tap(find.byKey(const Key('diagnosticRow_0')));
      await tester.pump();

      expect(controller.selectedNodeId, isNull);
      expect(transformation.value, before);
      expect(tester.takeException(), isNull);
    });
  });

  group('诊断计数', () {
    testWidgets('有错误为红、仅警告为黄、无问题为 subtext0', (WidgetTester tester) async {
      expect(await _countColorFor(tester, _project()), UCColors.flavor.red);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        await _countColorFor(
          tester,
          _project(nodes: <ScriptNodeModel>[_node('n1', 'flow.entry')]),
        ),
        UCColors.flavor.yellow,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        await _countColorFor(tester, _validProject()),
        UCColors.flavor.subtext0,
      );
    });

    testWidgets('图变更后计数即时刷新', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_project());
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);
      await _expand(tester);

      expect(_countColor(tester), UCColors.flavor.red);
      expect(find.text('（1）'), findsOneWidget);

      controller.addNode('flow.entry', const Offset(40, 60));
      await tester.pump();

      expect(find.text('（1）'), findsOneWidget);
      expect(_countColor(tester), UCColors.flavor.yellow);
      expect(tester.takeException(), isNull);
    });

    testWidgets('收起态显示「输出」与计数徽标', (WidgetTester tester) async {
      final GraphEditorController controller = _controller(_project());
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller: controller);

      expect(find.text('输出'), findsOneWidget);
      expect(find.text('1 个错误'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      final GraphEditorController warningController = _controller(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'flow.entry')]),
      );
      addTearDown(warningController.dispose);
      await _pumpPanel(tester, controller: warningController);

      expect(find.text('1 个警告'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('sortedDiagnostics：错误在前、同级保持校验器输出顺序且不修改入参', () {
    final List<ScriptDiagnostic> diagnostics = <ScriptDiagnostic>[
      const ScriptDiagnostic(message: 'w1', nodeId: 'a', isError: false),
      const ScriptDiagnostic(message: 'e1', nodeId: 'b', isError: true),
      const ScriptDiagnostic(message: 'w2', nodeId: 'c', isError: false),
      const ScriptDiagnostic(message: 'e2', nodeId: 'd', isError: true),
    ];

    final List<ScriptDiagnostic> sorted = sortedDiagnostics(diagnostics);

    expect(
      sorted.map((ScriptDiagnostic item) => item.message).toList(),
      <String>['e1', 'e2', 'w1', 'w2'],
    );
    expect(
      diagnostics.map((ScriptDiagnostic item) => item.message).toList(),
      <String>['w1', 'e1', 'w2', 'e2'],
    );
  });
}

const Size _viewportSize = Size(768, 532);

ScriptNodeModel _node(String id, String type, {double x = 0, double y = 0}) {
  return ScriptNodeModel(id: id, type: type, x: x, y: y);
}

ScriptProjectModel _project({
  List<ScriptNodeModel>? nodes,
  List<ScriptEdgeModel>? edges,
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '脚本 1',
    trigger: ScriptTrigger.pre,
  );
  project.nodes = nodes ?? <ScriptNodeModel>[];
  project.edges = edges ?? <ScriptEdgeModel>[];
  return project;
}

/// 无任何诊断的项目：入口 → 输出信息（消息来自文本节点）。
ScriptProjectModel _validProject() {
  return _project(
    nodes: <ScriptNodeModel>[
      _node('n1', 'flow.entry', x: 40, y: 60),
      _node('n2', 'log.message', x: 400, y: 60)..params['level'] = 'info',
      _node('n3', 'value.text', x: 760, y: 100)..params['value'] = '你好',
    ],
    edges: <ScriptEdgeModel>[
      ScriptEdgeModel(
        from: ScriptEdgeEndpoint(node: 'n1', pin: 'out'),
        to: ScriptEdgeEndpoint(node: 'n2', pin: 'exec'),
      ),
      ScriptEdgeModel(
        from: ScriptEdgeEndpoint(node: 'n3', pin: 'result'),
        to: ScriptEdgeEndpoint(node: 'n2', pin: 'message'),
      ),
    ],
  );
}

/// 22 行脚本：入口 + 14 个输出信息（每个消息来自一个文本节点）。
ScriptProjectModel _longProject() {
  final ScriptProjectModel project = _project();
  project.nodes.add(_node('n0', 'flow.entry', x: 40, y: 60));
  String previous = 'n0';
  for (int index = 1; index <= 14; index++) {
    project.nodes
      ..add(
        _node('t$index', 'value.text', x: 400, y: index * 80.0)
          ..params['value'] = '第 $index 条消息',
      )
      ..add(_node('n$index', 'log.message', x: 700, y: index * 80.0));
    project.edges
      ..add(
        ScriptEdgeModel(
          from: ScriptEdgeEndpoint(node: 't$index', pin: 'result'),
          to: ScriptEdgeEndpoint(node: 'n$index', pin: 'message'),
        ),
      )
      ..add(
        ScriptEdgeModel(
          from: ScriptEdgeEndpoint(node: previous, pin: 'out'),
          to: ScriptEdgeEndpoint(node: 'n$index', pin: 'exec'),
        ),
      );
    previous = 'n$index';
  }
  return project;
}

GraphEditorController _controller(ScriptProjectModel project) {
  return GraphEditorController(project);
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  GraphEditorController? controller,
  TransformationController? transformation,
  GlobalKey<OutputPanelState>? panelKey,
  ScriptCodeGenerator? generator,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          OutputPanel(
            key: panelKey,
            controller: controller,
            pack: PackModel(name: 'demo', version: '1.0.0', author: 'tester'),
            generator: generator,
            transformationController: transformation,
            viewportSizeProvider: () => _viewportSize,
          ),
        ],
      ),
    ),
  );
  await tester.pump();
}

double _panelHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(const Key('outputPanel'))).height;

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byTooltip('展开'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _openDiagnosticsTab(WidgetTester tester) async {
  await _expand(tester);
  await tester.tap(find.byKey(const Key('outputTabDiagnostics')));
  await tester.pump();
}

Color? _countColor(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const Key('outputTabDiagnosticsCount')))
      .style
      ?.color;
}

Future<Color?> _countColorFor(
  WidgetTester tester,
  ScriptProjectModel project,
) async {
  final GraphEditorController controller = _controller(project);
  addTearDown(controller.dispose);
  await _pumpPanel(tester, controller: controller);
  await _expand(tester);
  return _countColor(tester);
}

MouseRegion _rowRegion(WidgetTester tester, int index) {
  return tester.widget<MouseRegion>(
    find
        .descendant(
          of: find.byKey(Key('diagnosticRow_$index')),
          matching: find.byType(MouseRegion),
        )
        .first,
  );
}

ScrollableState _codeScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

/// 记录编译入参并返回固定代码的生成器替身。
class _RecordingGenerator implements ScriptCodeGenerator {
  ScriptProjectModel? project;
  String? packName;

  @override
  String get fileExtension => 'ps1';

  @override
  ScriptCompileResult compile(
    ScriptProjectModel project, {
    required String packName,
  }) {
    this.project = project;
    this.packName = packName;
    return const ScriptCompileResult(
      code: 'fake-code',
      diagnostics: <ScriptDiagnostic>[],
    );
  }
}
