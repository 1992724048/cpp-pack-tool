import 'package:cpp_nuget_pack/controls/script_editor/node_library_panel.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/pages/script_editor.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('点击添加落点公式', () {
    test('落点 = 视口中心 − (104, 卡片高/2) 叠加级联偏移', () {
      final ScriptNodeTypeDescriptor text = NodeRegistry.byType('value.text')!;
      expect(
        nodeLibraryAddPosition(
          viewportCenterScene: const Offset(400, 300),
          descriptor: text,
          existingNodeCount: 0,
        ),
        const Offset(296, 267),
      );

      // 级联：24 × (10 % 8) = 48
      expect(
        nodeLibraryAddPosition(
          viewportCenterScene: const Offset(400, 300),
          descriptor: text,
          existingNodeCount: 10,
        ),
        const Offset(344, 315),
      );
    });

    test('负坐标 clamp 到 0 场景坐标', () {
      final ScriptNodeTypeDescriptor copy = NodeRegistry.byType('file.copy')!;
      expect(
        nodeLibraryAddPosition(
          viewportCenterScene: const Offset(50, 20),
          descriptor: copy,
          existingNodeCount: 0,
        ),
        Offset.zero,
      );
      expect(
        nodeLibraryAddPosition(
          viewportCenterScene: const Offset(50, 120),
          descriptor: copy,
          existingNodeCount: 0,
        ),
        const Offset(0, 65),
      );
    });
  });

  group('分组与搜索', () {
    testWidgets('搜索框与分组按声明序渲染、默认全部展开', (WidgetTester tester) async {
      await _pumpPanel(tester);

      final TextBox searchBox = tester.widget<TextBox>(
        find.byKey(const Key('nodeLibrarySearch')),
      );
      expect(searchBox.placeholder, '搜索节点');
      final Icon prefix = searchBox.prefix! as Icon;
      expect(prefix.icon, FluentIcons.search);
      expect(prefix.size, 14);
      expect(
        tester.getSize(find.byKey(const Key('nodeLibrarySearch'))).height,
        32,
      );

      // 顶部可见的分组头自上而下 = 声明序；分组头高 28
      final List<double> visibleTops = <double>[
        for (final ScriptNodeCategory category in ScriptNodeCategory.values)
          if (find
              .byKey(Key('nodeLibraryGroup_${category.name}'))
              .evaluate()
              .isNotEmpty)
            tester
                .getTopLeft(
                  find.byKey(Key('nodeLibraryGroup_${category.name}')),
                )
                .dy,
      ];
      expect(visibleTops.length, greaterThanOrEqualTo(6));
      expect(visibleTops, List<double>.of(visibleTops)..sort());
      expect(
        tester.getSize(find.byKey(const Key('nodeLibraryGroup_flow'))).height,
        28,
      );

      // 顶部首组条目默认可见
      for (final String typeKey in <String>[
        'flow.entry',
        'flow.branch',
        'flow.foreach',
        'flow.while',
      ]) {
        expect(find.byKey(Key('nodeLibraryItem_$typeKey')), findsOneWidget);
      }

      // 滚到底：全部 8 组头与 25 个条目均已构建（默认全展开；列表懒加载）
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(Scrollbar),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();

      // 尾部两组头仍按声明序
      final double logTop = tester
          .getTopLeft(find.byKey(const Key('nodeLibraryGroup_log')))
          .dy;
      final double logicTop = tester
          .getTopLeft(find.byKey(const Key('nodeLibraryGroup_logic')))
          .dy;
      expect(logicTop, greaterThan(logTop));

      for (final ScriptNodeCategory category in ScriptNodeCategory.values) {
        expect(
          find.byKey(
            Key('nodeLibraryGroup_${category.name}'),
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: category.name,
        );
      }
      for (final ScriptNodeTypeDescriptor descriptor in NodeRegistry.all) {
        expect(
          find.byKey(
            Key('nodeLibraryItem_${descriptor.typeKey}'),
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: descriptor.typeKey,
        );
      }
      expect(
        tester
            .getSize(
              find.byKey(
                const Key('nodeLibraryItem_flow.entry'),
                skipOffstage: false,
              ),
            )
            .height,
        28,
      );
    });

    testWidgets('条目 tooltip 为类型键、悬停背景 surface0', (WidgetTester tester) async {
      await _pumpPanel(tester);
      final Finder item = find.byKey(const Key('nodeLibraryItem_flow.entry'));

      final Tooltip tooltip = tester.widget<Tooltip>(
        find.ancestor(of: item, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, 'flow.entry');
      expect(_itemColor(tester, item), Colors.transparent);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(item));
      await tester.pump();

      expect(_itemColor(tester, item), UCColors.flavor.surface0);
    });

    testWidgets('搜索按显示名/类型键/分类名大小写不敏感过滤且命中组自动展开', (WidgetTester tester) async {
      await _pumpPanel(tester);

      // 先收起「文件」分组
      await tester.tap(find.byKey(const Key('nodeLibraryGroup_file')));
      await tester.pump();
      expect(find.byKey(const Key('nodeLibraryItem_file.copy')), findsNothing);

      // 类型键匹配（大小写不敏感）：COPY → 仅文件组、命中组自动展开
      await tester.enterText(
        find.byKey(const Key('nodeLibrarySearch')),
        'COPY',
      );
      await tester.pump();
      expect(find.byKey(const Key('nodeLibraryGroup_file')), findsOneWidget);
      expect(
        find.byKey(const Key('nodeLibraryItem_file.copy')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('nodeLibraryGroup_flow')), findsNothing);
      expect(find.byKey(const Key('nodeLibraryItem_flow.entry')), findsNothing);

      // 显示名匹配：替换 → 仅 string.replace
      await tester.enterText(find.byKey(const Key('nodeLibrarySearch')), '替换');
      await tester.pump();
      expect(
        find.byKey(const Key('nodeLibraryItem_string.replace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nodeLibraryItem_string.concat')),
        findsNothing,
      );
      expect(find.text('字符串'), findsOneWidget);

      // 分类名匹配：文件 → 文件组全部 6 项
      await tester.enterText(find.byKey(const Key('nodeLibrarySearch')), '文件');
      await tester.pump();
      expect(
        find.byKey(const Key('nodeLibraryItem_file.copy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nodeLibraryItem_file.move')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nodeLibraryItem_log.message')),
        findsNothing,
      );

      // 无命中 → 空态文案
      await tester.enterText(find.byKey(const Key('nodeLibrarySearch')), 'zzz');
      await tester.pump();
      expect(find.text('未找到匹配的节点'), findsOneWidget);
      expect(find.byKey(const Key('nodeLibraryGroup_flow')), findsNothing);
    });

    testWidgets('拖拽时反馈迷你卡 160×34、原行 α0.4', (WidgetTester tester) async {
      await _pumpPanel(tester);
      final Finder item = find.byKey(const Key('nodeLibraryItem_flow.entry'));

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(item),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();

      final Finder feedback = find.byKey(const Key('nodeLibraryDragFeedback'));
      expect(feedback, findsOneWidget);
      expect(tester.getSize(feedback), const Size(160, 34));
      expect(
        find.descendant(of: feedback, matching: find.text('开始')),
        findsOneWidget,
      );

      final Opacity draggingRow = tester.widget<Opacity>(
        find.ancestor(of: item, matching: find.byType(Opacity)).first,
      );
      expect(draggingRow.opacity, 0.4);

      await gesture.up();
      await tester.pump();
      expect(find.byKey(const Key('nodeLibraryDragFeedback')), findsNothing);
    });
  });

  group('页面接线', () {
    testWidgets('点击条目在画布视口中心添加节点并写入默认参数', (WidgetTester tester) async {
      final ScriptProjectModel project = _script();
      await _pumpPage(tester, _packWithScripts(<ScriptProjectModel>[project]));

      await tester.tap(find.byKey(const Key('nodeLibraryItem_value.text')));
      await tester.pump();

      expect(project.nodes, hasLength(1));
      final ScriptNodeModel node = project.nodes.single;
      expect(node.type, 'value.text');
      // 画布视口 768×718，中心 (384, 359)；文本卡高 66
      expect(node.x, 280);
      expect(node.y, 326);
      expect(node.params, <String, Object?>{'value': ''});
    });

    testWidgets('按视口变换换算中心场景坐标并叠加级联偏移', (WidgetTester tester) async {
      final ScriptProjectModel project = _script(
        nodes: <ScriptNodeModel>[
          ScriptNodeModel(id: 'n1', type: 'flow.entry', x: 40, y: 60),
        ],
        viewX: -100,
        viewY: -50,
      );
      await _pumpPage(tester, _packWithScripts(<ScriptProjectModel>[project]));

      await tester.tap(find.byKey(const Key('nodeLibraryItem_value.text')));
      await tester.pump();

      expect(project.nodes, hasLength(2));
      final ScriptNodeModel node = project.nodes.last;
      expect(node.id, 'n2');
      // 中心场景 = (384 + 100, 359 + 50) = (484, 409)；级联 = 24 × (1 % 8)
      expect(node.x, 404);
      expect(node.y, 400);
    });

    testWidgets('重复添加「开始」不特殊禁用', (WidgetTester tester) async {
      final ScriptProjectModel project = _script();
      await _pumpPage(tester, _packWithScripts(<ScriptProjectModel>[project]));

      await tester.tap(find.byKey(const Key('nodeLibraryItem_flow.entry')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('nodeLibraryItem_flow.entry')));
      await tester.pump();

      expect(project.nodes, hasLength(2));
      expect(
        project.nodes.map((ScriptNodeModel node) => node.type),
        everyElement('flow.entry'),
      );
    });

    testWidgets('无项目时节点库整面板 α0.5 禁用', (WidgetTester tester) async {
      await _pumpPage(tester, _pack('demo'));

      final Opacity opacity = tester.widget<Opacity>(
        find.byKey(const Key('nodeLibraryPanel')),
      );
      expect(opacity.opacity, 0.5);
      // 面板子树可能含控件内建 IgnorePointer（如 TextBox），取最外层（页面级）
      final IgnorePointer ignorePointer = tester.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byKey(const Key('nodeLibraryPanel')),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignorePointer.ignoring, isTrue);
      expect(find.byKey(const Key('nodeLibrarySearch')), findsOneWidget);
    });
  });

  group('禁用态', () {
    testWidgets('onAddNode 为 null 时条目不可点击、不可拖拽', (WidgetTester tester) async {
      await _pumpPanel(tester, onAddNode: null);

      expect(find.byType(Draggable<ScriptNodeTypeDescriptor>), findsNothing);

      await tester.tap(find.byKey(const Key('nodeLibraryItem_value.text')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

void _noopAdd(ScriptNodeTypeDescriptor descriptor) {}

Future<void> _pumpPanel(
  WidgetTester tester, {
  ValueChanged<ScriptNodeTypeDescriptor>? onAddNode = _noopAdd,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Center(
        child: SizedBox(
          width: 232,
          height: 740,
          child: NodeLibraryPanel(onAddNode: onAddNode),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpPage(WidgetTester tester, PackModel pack) async {
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

PackModel _pack(String name) =>
    PackModel(name: name, version: '1.0.0', author: 'tester');

PackModel _packWithScripts(List<ScriptProjectModel> scripts) {
  return _pack('demo')..scripts = scripts;
}

ScriptProjectModel _script({
  List<ScriptNodeModel>? nodes,
  double viewX = 0,
  double viewY = 0,
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '脚本 1',
    trigger: ScriptTrigger.pre,
  );
  project.nodes = nodes ?? <ScriptNodeModel>[];
  project.viewX = viewX;
  project.viewY = viewY;
  return project;
}

Color? _itemColor(WidgetTester tester, Finder item) {
  final Container container = tester.widget<Container>(item);
  return (container.decoration! as BoxDecoration).color;
}
