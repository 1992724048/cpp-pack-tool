import 'package:cpp_nuget_pack/controls/script_editor/node_library_panel.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/pages/script_editor.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('点击添加落点公式', () {
    test('落点 = 视口中心 − (104, 卡片高/2) 叠加级联偏移', () {
      final ScriptNodeTypeDescriptor text = NodeRegistry.byType('value.text')!;
      // 文本卡高 88（M4.1 值条 +22）：y = 300 − 44。
      expect(
        nodeLibraryAddPosition(
          viewportCenterScene: const Offset(400, 300),
          descriptor: text,
          existingNodeCount: 0,
        ),
        const Offset(296, 256),
      );

      // 级联：24 × (10 % 8) = 48
      expect(
        nodeLibraryAddPosition(
          viewportCenterScene: const Offset(400, 300),
          descriptor: text,
          existingNodeCount: 10,
        ),
        const Offset(344, 304),
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

      final Finder searchBoxFinder = find.byKey(
        const Key('nodeLibrarySearch'),
      );
      final TextBox searchBox = tester.widget<TextBox>(searchBoxFinder);
      expect(searchBox.placeholder, '搜索节点');

      // prefix 间距（M4.1 定稿）：图标左缘距框左缘 8、图标右内边距 6（§4.1）
      final Finder searchIcon = find.descendant(
        of: searchBoxFinder,
        matching: find.byIcon(FluentIcons.search),
      );
      final Rect iconRect = tester.getRect(searchIcon);
      final Rect boxRect = tester.getRect(searchBoxFinder);
      expect(iconRect.left - boxRect.left, closeTo(8, 0.01));
      final Icon prefixIcon = tester.widget<Icon>(searchIcon);
      expect(prefixIcon.size, 14);
      final Padding prefix = searchBox.prefix! as Padding;
      expect(prefix.padding, const EdgeInsets.only(left: 8, right: 6));
      expect(tester.getSize(searchBoxFinder).height, 32);

      // 顶部可见的分组头自上而下 = 声明序；分组头高 28
      // （初始构建组数随懒构建窗口而定：file 分类扩至 9 条后首屏构建前 5 组；
      // 声明序完整性由下方逐组滚动循环继续保证）
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
      expect(visibleTops.length, greaterThanOrEqualTo(5));
      expect(visibleTops, List<double>.of(visibleTops)..sort());
      expect(
        tester.getSize(find.byKey(const Key('nodeLibraryGroup_flow'))).height,
        28,
      );

      // 顶部首组条目默认可见，条目高 28
      for (final String typeKey in <String>[
        'flow.entry',
        'flow.branch',
        'flow.foreach',
        'flow.while',
      ]) {
        expect(find.byKey(Key('nodeLibraryItem_$typeKey')), findsOneWidget);
      }
      expect(
        tester
            .getSize(find.byKey(const Key('nodeLibraryItem_flow.entry')))
            .height,
        28,
      );

      // 逐个滚到目标：全部分组头与条目均已构建，且分组头按声明序浮出
      // （默认全展开；列表懒加载——内容超出构建窗口后不能只跳到底部一次性断言）。
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(Scrollbar),
          matching: find.byType(Scrollable),
        ),
      );
      double? previousGroupContentTop;
      for (final ScriptNodeCategory category in ScriptNodeCategory.values) {
        final Finder group = find.byKey(
          Key('nodeLibraryGroup_${category.name}'),
        );
        await _scrollLibraryUntilVisible(tester, scrollable, group);
        expect(group, findsOneWidget, reason: category.name);
        // 内容坐标 = 窗口坐标 + 滚动偏移（滚动下不变），跨滚动步比较才有效。
        final double groupContentTop =
            tester.getTopLeft(group).dy + scrollable.position.pixels;
        if (previousGroupContentTop != null) {
          expect(
            groupContentTop,
            greaterThan(previousGroupContentTop),
            reason: '${category.name} 分组头未按声明序',
          );
        }
        previousGroupContentTop = groupContentTop;

        for (final ScriptNodeTypeDescriptor descriptor
            in NodeRegistry.byCategory(category)) {
          final Finder item = find.byKey(
            Key('nodeLibraryItem_${descriptor.typeKey}'),
          );
          if (item.evaluate().isEmpty) {
            await _scrollLibraryUntilVisible(tester, scrollable, item);
          }
          expect(item, findsOneWidget, reason: descriptor.typeKey);
        }
      }
    });

    testWidgets('条目 tooltip 为类型键、悬停背景为悬停填充色', (WidgetTester tester) async {
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

      expect(
        _itemColor(tester, item),
        FluentTheme.of(
          tester.element(item),
        ).resources.controlFillColorSecondary,
      );
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

      // 分类名匹配：文件 → 文件组全部 9 项
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

      await _revealLibraryItem(tester, 'value.text');
      await tester.tap(find.byKey(const Key('nodeLibraryItem_value.text')));
      await tester.pump();

      expect(project.nodes, hasLength(1));
      final ScriptNodeModel node = project.nodes.single;
      expect(node.type, 'value.text');
      // 画布视口 768×718，中心 (384, 359)；文本卡高 88（M4.1 值条 +22）
      expect(node.x, 280);
      expect(node.y, 315);
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

      await _revealLibraryItem(tester, 'value.text');
      await tester.tap(find.byKey(const Key('nodeLibraryItem_value.text')));
      await tester.pump();

      expect(project.nodes, hasLength(2));
      final ScriptNodeModel node = project.nodes.last;
      expect(node.id, 'n2');
      // 中心场景 = (384 + 100, 359 + 50) = (484, 409)；级联 = 24 × (1 % 8)；
      // 文本卡高 88（M4.1 值条 +22）：y = 409 − 44 + 24。
      expect(node.x, 404);
      expect(node.y, 389);
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

/// 在节点库列表中逐段前滚，直到 [target] 被懒加载构建（或已到滚动尽头）。
Future<void> _scrollLibraryUntilVisible(
  WidgetTester tester,
  ScrollableState scrollable,
  Finder target,
) async {
  while (target.evaluate().isEmpty) {
    final ScrollPosition position = scrollable.position;
    final double candidate = position.pixels + 100;
    final double next = candidate > position.maxScrollExtent
        ? position.maxScrollExtent
        : candidate;
    if (next <= position.pixels) {
      return; // 已到尽头仍不可见：交由调用方断言失败
    }
    position.jumpTo(next);
    await tester.pump();
  }
}

/// 页面布局下节点库列表的 Scrollable（页面含多面板滚动区，按面板键与
/// Scrollbar 归属定位，避免命中搜索框内建滚动区）。
ScrollableState _pageLibraryScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(
    find.descendant(
      of: find.descendant(
        of: find.byKey(const Key('nodeLibraryPanel')),
        matching: find.byType(Scrollbar),
      ),
      matching: find.byType(Scrollable),
    ),
  );
}

/// 页面用例：51 类节点下目标条目可能位于懒构建窗口之外；滚动至可见再点击
/// （逐段滚动后 ensureVisible 保证条目完整进入视口，命中测试不落空）。
Future<void> _revealLibraryItem(WidgetTester tester, String typeKey) async {
  final Finder item = find.byKey(Key('nodeLibraryItem_$typeKey'));
  await _scrollLibraryUntilVisible(
    tester,
    _pageLibraryScrollable(tester),
    item,
  );
  await tester.ensureVisible(item);
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
