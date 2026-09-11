import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

ScriptNodeModel _node(String id, String type, {double x = 0, double y = 0}) {
  return ScriptNodeModel(id: id, type: type, x: x, y: y);
}

ScriptProjectModel _project({
  List<ScriptNodeModel>? nodes,
  List<ScriptEdgeModel>? edges,
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '测试脚本',
    trigger: ScriptTrigger.pre,
  );
  project.nodes = nodes ?? <ScriptNodeModel>[];
  project.edges = edges ?? <ScriptEdgeModel>[];
  return project;
}

ScriptEdgeModel _edge(
  String fromNode,
  String fromPin,
  String toNode,
  String toPin,
) {
  return ScriptEdgeModel(
    from: _endpoint(fromNode, fromPin),
    to: _endpoint(toNode, toPin),
  );
}

ScriptEdgeEndpoint _endpoint(String node, String pin) {
  return ScriptEdgeEndpoint(node: node, pin: pin);
}

bool _hasEdge(
  ScriptProjectModel project,
  String fromNode,
  String fromPin,
  String toNode,
  String toPin,
) {
  return project.edges.any(
    (ScriptEdgeModel edge) =>
        edge.from.node == fromNode &&
        edge.from.pin == fromPin &&
        edge.to.node == toNode &&
        edge.to.pin == toPin,
  );
}

List<ScriptDiagnostic> _errors(GraphEditorController controller) {
  return controller.diagnostics
      .where((ScriptDiagnostic diagnostic) => diagnostic.isError)
      .toList();
}

ScriptProjectModel _connectGraph() {
  return _project(
    nodes: <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'log.message'),
      _node('n3', 'value.text'),
      _node('n4', 'value.boolean'),
      _node('n5', 'file.copy'),
      _node('n6', 'flow.branch'),
      _node('n7', 'file.list'),
      _node('n8', 'log.message'),
      _node('n9', 'flow.foreach'),
      _node('n10', 'value.text'),
    ],
  );
}

void main() {
  group('addNode', () {
    test('空图返回 n1 并写入场景坐标', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      expect(controller.addNode('value.text', const Offset(12, 34)), 'n1');
      final ScriptNodeModel node = controller.project.nodes.single;
      expect(node.type, 'value.text');
      expect(node.x, 12);
      expect(node.y, 34);
    });

    test('id 取现有 n 数字 id 最大值 +1，忽略非数字 id', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n2', 'value.text'),
            _node('n7', 'value.boolean'),
            _node('x9', 'value.text'),
            _node('entry', 'flow.entry'),
          ],
        ),
      );
      expect(controller.addNode('value.text', Offset.zero), 'n8');
    });

    test('params 取注册表默认值，无参节点为空 map', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      final String deleteId = controller.addNode('file.delete', Offset.zero);
      final String branchId = controller.addNode('flow.branch', Offset.zero);
      expect(
        controller.project.nodes
            .firstWhere((ScriptNodeModel node) => node.id == deleteId)
            .params,
        <String, Object?>{'missingIgnored': true},
      );
      expect(
        controller.project.nodes
            .firstWhere((ScriptNodeModel node) => node.id == branchId)
            .params,
        isEmpty,
      );
    });

    test('未知 typeKey 抛 ArgumentError 且不改图', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      expect(
        () => controller.addNode('missing.type', Offset.zero),
        throwsArgumentError,
      );
      expect(controller.project.nodes, isEmpty);
      expect(notifications, 0);
    });
  });

  group('moveNode', () {
    test('写入新坐标并通知', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 1, y: 2)],
        ),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.moveNode('n1', const Offset(30, 40));
      expect(controller.project.nodes.single.x, 30);
      expect(controller.project.nodes.single.y, 40);
      expect(notifications, 1);
    });

    test('节点不存在或坐标未变时无操作', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[_node('n1', 'value.text', x: 1, y: 2)],
        ),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.moveNode('missing', const Offset(30, 40));
      controller.moveNode('n1', const Offset(1, 2));
      expect(notifications, 0);
    });
  });

  group('removeNode', () {
    test('连带删除相邻边（出边与入边）并清空被删节点选中', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
            _node('n3', 'value.text'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('n1', 'out', 'n2', 'exec'),
            _edge('n3', 'result', 'n2', 'message'),
          ],
        ),
      );
      controller.selectNode('n2');
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.removeNode('n2');
      expect(
        controller.project.nodes
            .map((ScriptNodeModel node) => node.id)
            .toList(),
        <String>['n1', 'n3'],
      );
      expect(controller.project.edges, isEmpty);
      expect(controller.selectedNodeId, isNull);
      expect(notifications, 1);
    });

    test('被删节点的相邻边若处于选中态则清空选中', () {
      final ScriptEdgeModel edge = _edge('n1', 'out', 'n2', 'exec');
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[edge],
        ),
      );
      controller.selectEdge(edge);
      controller.removeNode('n1');
      expect(controller.selectedEdge, isNull);
      expect(controller.project.edges, isEmpty);
    });

    test('节点不存在时无操作', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'value.text')]),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.removeNode('missing');
      expect(controller.project.nodes, hasLength(1));
      expect(notifications, 0);
    });
  });

  group('updateNodeParam', () {
    test('接受 String / bool / List<String> 并写回', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'value.text'),
            _node('n2', 'value.boolean'),
            _node('n3', 'file.list'),
          ],
        ),
      );
      controller.updateNodeParam('n1', 'value', 'hello');
      controller.updateNodeParam('n2', 'value', true);
      controller.updateNodeParam('n3', 'filter', '*.dll');
      controller.updateNodeParam('n3', 'recursive', false);
      controller.updateNodeParam('n3', 'extraList', <String>['a', 'b']);
      expect(controller.project.nodes[0].params['value'], 'hello');
      expect(controller.project.nodes[1].params['value'], true);
      expect(controller.project.nodes[2].params['filter'], '*.dll');
      expect(controller.project.nodes[2].params['recursive'], false);
      expect(controller.project.nodes[2].params['extraList'], <String>[
        'a',
        'b',
      ]);
    });

    test('List<String> 值写入防御性拷贝', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'file.list')]),
      );
      final List<String> values = <String>['a'];
      controller.updateNodeParam('n1', 'extraList', values);
      values.add('b');
      expect(controller.project.nodes.single.params['extraList'], <String>[
        'a',
      ]);
    });

    test('值域外类型忽略：不写入、不通知、不抛错', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'value.text')]),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.updateNodeParam('n1', 'value', 42);
      controller.updateNodeParam('n1', 'value', 3.14);
      controller.updateNodeParam('n1', 'value', null);
      controller.updateNodeParam('n1', 'value', <Object?>['a', 1]);
      controller.updateNodeParam('n1', 'value', <int>[1, 2]);
      expect(
        controller.project.nodes.single.params.containsKey('value'),
        isFalse,
      );
      expect(notifications, 0);
    });

    test('值未变化时不通知（含内容相同的列表）', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'value.text')]),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.updateNodeParam('n1', 'value', 'hello');
      controller.updateNodeParam('n1', 'value', 'hello');
      controller.updateNodeParam('n1', 'list', <String>['a']);
      controller.updateNodeParam('n1', 'list', <String>['a']);
      expect(notifications, 2);
    });

    test('节点不存在时忽略', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'value.text')]),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.updateNodeParam('missing', 'value', 'hello');
      expect(notifications, 0);
    });
  });

  group('connect', () {
    test('合法 exec 连接：返回 null、建边并通知', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      final String? reason = controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n2', 'exec'),
      );
      expect(reason, isNull);
      expect(controller.project.edges, hasLength(1));
      expect(_hasEdge(controller.project, 'n1', 'out', 'n2', 'exec'), isTrue);
      expect(notifications, 1);
    });

    test('合法 data 连接：类型匹配即可', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      final String? reason = controller.connect(
        from: _endpoint('n3', 'result'),
        to: _endpoint('n2', 'message'),
      );
      expect(reason, isNull);
      expect(
        _hasEdge(controller.project, 'n3', 'result', 'n2', 'message'),
        isTrue,
      );
    });

    test('data 输入已占用：静默替换旧边', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      controller.connect(
        from: _endpoint('n3', 'result'),
        to: _endpoint('n2', 'message'),
      );
      final String? reason = controller.connect(
        from: _endpoint('n10', 'result'),
        to: _endpoint('n2', 'message'),
      );
      expect(reason, isNull);
      expect(controller.project.edges, hasLength(1));
      expect(
        _hasEdge(controller.project, 'n10', 'result', 'n2', 'message'),
        isTrue,
      );
      expect(
        _hasEdge(controller.project, 'n3', 'result', 'n2', 'message'),
        isFalse,
      );
    });

    test('exec 输出已占用：静默替换旧边', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n2', 'exec'),
      );
      final String? reason = controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n8', 'exec'),
      );
      expect(reason, isNull);
      expect(controller.project.edges, hasLength(1));
      expect(_hasEdge(controller.project, 'n1', 'out', 'n8', 'exec'), isTrue);
      expect(_hasEdge(controller.project, 'n1', 'out', 'n2', 'exec'), isFalse);
    });

    test('data 输出允许多连（扇出）', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      expect(
        controller.connect(
          from: _endpoint('n3', 'result'),
          to: _endpoint('n2', 'message'),
        ),
        isNull,
      );
      expect(
        controller.connect(
          from: _endpoint('n3', 'result'),
          to: _endpoint('n8', 'message'),
        ),
        isNull,
      );
      expect(controller.project.edges, hasLength(2));
      expect(
        _hasEdge(controller.project, 'n3', 'result', 'n2', 'message'),
        isTrue,
      );
      expect(
        _hasEdge(controller.project, 'n3', 'result', 'n8', 'message'),
        isTrue,
      );
    });

    test('重复相同连接：幂等成功，不重复建边、不通知', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      expect(
        controller.connect(
          from: _endpoint('n1', 'out'),
          to: _endpoint('n2', 'exec'),
        ),
        isNull,
      );
      expect(
        controller.connect(
          from: _endpoint('n1', 'out'),
          to: _endpoint('n2', 'exec'),
        ),
        isNull,
      );
      expect(controller.project.edges, hasLength(1));
      expect(notifications, 1);
    });

    test('kind 不匹配拒绝：data 输出 → exec 输入', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      final String? reason = controller.connect(
        from: _endpoint('n3', 'result'),
        to: _endpoint('n2', 'exec'),
      );
      expect(reason, '无法连接：目标引脚需要 执行');
      expect(controller.project.edges, isEmpty);
      expect(notifications, 0);
    });

    test('kind 不匹配拒绝：exec 输出 → data 输入', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      final String? reason = controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n2', 'message'),
      );
      expect(reason, '无法连接：目标引脚需要 string');
      expect(controller.project.edges, isEmpty);
    });

    test('data 类型不匹配拒绝：以目标引脚所需类型提示', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      expect(
        controller.connect(
          from: _endpoint('n4', 'result'),
          to: _endpoint('n2', 'message'),
        ),
        '无法连接：目标引脚需要 string',
      );
      expect(
        controller.connect(
          from: _endpoint('n3', 'result'),
          to: _endpoint('n6', 'condition'),
        ),
        '无法连接：目标引脚需要 bool',
      );
      expect(
        controller.connect(
          from: _endpoint('n3', 'result'),
          to: _endpoint('n9', 'list'),
        ),
        '无法连接：目标引脚需要 list<string>',
      );
      expect(
        controller.connect(
          from: _endpoint('n7', 'result'),
          to: _endpoint('n2', 'message'),
        ),
        '无法连接：目标引脚需要 string',
      );
      expect(controller.project.edges, isEmpty);
    });

    test('自连拒绝', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      final String? reason = controller.connect(
        from: _endpoint('n5', 'out'),
        to: _endpoint('n5', 'source'),
      );
      expect(reason, '无法连接：不能连接到同一节点');
      expect(controller.project.edges, isEmpty);
    });

    test('输出引脚作为落点：拒绝并提示方向', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      final String? reason = controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n2', 'out'),
      );
      expect(reason, '无法连接：请从输出引脚拖向输入引脚');
      expect(controller.project.edges, isEmpty);
    });

    test('从输入引脚拖出：拒绝并提示方向', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      final String? reason = controller.connect(
        from: _endpoint('n2', 'exec'),
        to: _endpoint('n8', 'exec'),
      );
      expect(reason, '无法连接：请从输出引脚拖向输入引脚');
      expect(controller.project.edges, isEmpty);
    });

    test('节点或引脚不存在：拒绝', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      expect(
        controller.connect(
          from: _endpoint('n1', 'out'),
          to: _endpoint('n2', 'missing'),
        ),
        '无法连接：引脚不存在',
      );
      expect(
        controller.connect(
          from: _endpoint('n1', 'missing'),
          to: _endpoint('n2', 'exec'),
        ),
        '无法连接：引脚不存在',
      );
      expect(
        controller.connect(
          from: _endpoint('missing', 'out'),
          to: _endpoint('n2', 'exec'),
        ),
        '无法连接：引脚不存在',
      );
      expect(
        controller.connect(
          from: _endpoint('n1', 'out'),
          to: _endpoint('missing', 'exec'),
        ),
        '无法连接：引脚不存在',
      );
      expect(controller.project.edges, isEmpty);
    });

    test('拒绝时保留已被占用的旧边（不改图）', () {
      final GraphEditorController controller = GraphEditorController(
        _connectGraph(),
      );
      controller.connect(
        from: _endpoint('n3', 'result'),
        to: _endpoint('n2', 'message'),
      );
      final String? reason = controller.connect(
        from: _endpoint('n4', 'result'),
        to: _endpoint('n2', 'message'),
      );
      expect(reason, '无法连接：目标引脚需要 string');
      expect(controller.project.edges, hasLength(1));
      expect(
        _hasEdge(controller.project, 'n3', 'result', 'n2', 'message'),
        isTrue,
      );
    });

    test('成环连接不阻断：成功建立并由诊断即时报告', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'log.message'),
            _node('n2', 'log.message'),
          ],
        ),
      );
      expect(
        controller.connect(
          from: _endpoint('n1', 'out'),
          to: _endpoint('n2', 'exec'),
        ),
        isNull,
      );
      expect(
        controller.connect(
          from: _endpoint('n2', 'out'),
          to: _endpoint('n1', 'exec'),
        ),
        isNull,
      );
      expect(controller.project.edges, hasLength(2));
      expect(
        controller.diagnostics.any(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.isError && diagnostic.message.contains('执行连接存在环'),
        ),
        isTrue,
      );
    });
  });

  group('removeEdge / removeSelectedEdge', () {
    test('removeEdge 删除指定边并通知', () {
      final ScriptEdgeModel edge = _edge('n1', 'out', 'n2', 'exec');
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[edge],
        ),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.removeEdge(edge);
      expect(controller.project.edges, isEmpty);
      expect(notifications, 1);
    });

    test('removeEdge 对不存在的边无操作', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'value.text')]),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.removeEdge(_edge('n1', 'result', 'n2', 'message'));
      expect(notifications, 0);
    });

    test('removeSelectedEdge 删除选中边并清空选中', () {
      final ScriptEdgeModel edge = _edge('n1', 'out', 'n2', 'exec');
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[edge],
        ),
      );
      controller.selectEdge(edge);
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.removeSelectedEdge();
      expect(controller.project.edges, isEmpty);
      expect(controller.selectedEdge, isNull);
      expect(notifications, 1);
    });

    test('无选中边时 removeSelectedEdge 无操作', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'value.text')]),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.removeSelectedEdge();
      expect(notifications, 0);
    });

    test('删除边后诊断即时重算', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
            _node('n3', 'value.text'),
          ],
        ),
      );
      controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n2', 'exec'),
      );
      controller.connect(
        from: _endpoint('n3', 'result'),
        to: _endpoint('n2', 'message'),
      );
      expect(_errors(controller), isEmpty);
      final ScriptEdgeModel edge = controller.project.edges.firstWhere(
        (ScriptEdgeModel candidate) => candidate.from.pin == 'out',
      );
      controller.selectEdge(edge);
      controller.removeSelectedEdge();
      expect(
        _errors(controller).any(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.message.contains('必填输入「执行」未连接'),
        ),
        isTrue,
      );
    });
  });

  group('选中', () {
    test('节点与边选中互斥', () {
      final ScriptEdgeModel edge = _edge('n1', 'out', 'n2', 'exec');
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[edge],
        ),
      );
      controller.selectNode('n1');
      expect(controller.selectedNodeId, 'n1');
      expect(controller.selectedEdge, isNull);
      controller.selectEdge(edge);
      expect(controller.selectedNodeId, isNull);
      expect(identical(controller.selectedEdge, edge), isTrue);
      controller.selectNode('n2');
      expect(controller.selectedNodeId, 'n2');
      expect(controller.selectedEdge, isNull);
    });

    test('重复选中同一对象不通知；选中不存在的对象忽略', () {
      final ScriptEdgeModel edge = _edge('n1', 'out', 'n2', 'exec');
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[edge],
        ),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.selectNode('missing');
      controller.selectEdge(_edge('n1', 'out', 'n2', 'exec'));
      expect(notifications, 0);
      controller.selectNode('n1');
      controller.selectNode('n1');
      expect(notifications, 1);
      controller.selectEdge(edge);
      controller.selectEdge(edge);
      expect(notifications, 2);
      expect(identical(controller.selectedEdge, edge), isTrue);
    });

    test('selectNode(null) / selectEdge(null) 清空选中', () {
      final ScriptEdgeModel edge = _edge('n1', 'out', 'n2', 'exec');
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[edge],
        ),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.selectNode('n1');
      controller.selectNode(null);
      expect(controller.selectedNodeId, isNull);
      expect(controller.selectedEdge, isNull);
      expect(notifications, 2);
      controller.selectEdge(edge);
      controller.selectEdge(null);
      expect(controller.selectedNodeId, isNull);
      expect(controller.selectedEdge, isNull);
      expect(notifications, 4);
    });

    test('clearSelection 清空并通知；空选中时无操作', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'flow.entry')]),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.clearSelection();
      expect(notifications, 0);
      controller.selectNode('n1');
      controller.clearSelection();
      controller.clearSelection();
      expect(controller.selectedNodeId, isNull);
      expect(notifications, 2);
    });
  });

  group('setViewport', () {
    test('写入视口并通知', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.setViewport(x: 10, y: 20, scale: 1.5);
      expect(controller.project.viewX, 10);
      expect(controller.project.viewY, 20);
      expect(controller.project.viewScale, 1.5);
      expect(notifications, 1);
    });

    test('与当前值一致时不通知', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.setViewport(x: 0, y: 0, scale: 1.0);
      expect(notifications, 0);
    });
  });

  group('loadProject', () {
    test('切换项目：替换实例、清选中、重算诊断并通知', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'flow.entry')]),
      );
      controller.selectNode('n1');
      int notifications = 0;
      controller.addListener(() => notifications++);
      final ScriptProjectModel next = _project(
        nodes: <ScriptNodeModel>[_node('n9', 'value.text')],
      );
      controller.loadProject(next);
      expect(identical(controller.project, next), isTrue);
      expect(controller.selectedNodeId, isNull);
      expect(controller.selectedEdge, isNull);
      expect(
        _errors(controller).any(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.message.contains('当前没有入口节点'),
        ),
        isTrue,
      );
      expect(notifications, 1);
    });

    test('切换后使用新项目视口', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      final ScriptProjectModel next = _project();
      next.viewX = 5;
      next.viewY = 6;
      next.viewScale = 2;
      controller.loadProject(next);
      expect(controller.project.viewX, 5);
      expect(controller.project.viewY, 6);
      expect(controller.project.viewScale, 2);
    });
  });

  group('diagnostics', () {
    test('构造时即计算：初始无入口报错', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      expect(_errors(controller).single.message, contains('当前没有入口节点'));
    });

    test('添加第二个入口后即时报告，删除后恢复', () {
      final GraphEditorController controller = GraphEditorController(
        _project(nodes: <ScriptNodeModel>[_node('n1', 'flow.entry')]),
      );
      expect(_errors(controller), isEmpty);
      final String entryId = controller.addNode('flow.entry', Offset.zero);
      expect(_errors(controller).single.message, contains('当前有 2 个'));
      controller.removeNode(entryId);
      expect(_errors(controller), isEmpty);
    });

    test('参数变更后即时重算', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
            _node('n3', 'value.text'),
          ],
        ),
      );
      controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n2', 'exec'),
      );
      controller.connect(
        from: _endpoint('n3', 'result'),
        to: _endpoint('n2', 'message'),
      );
      expect(_errors(controller), isEmpty);
      controller.updateNodeParam('n2', 'level', 'bogus');
      expect(_errors(controller).single.message, contains('参数「级别」的值「bogus」非法'));
      controller.updateNodeParam('n2', 'level', 'warn');
      expect(_errors(controller), isEmpty);
    });

    test('连接后即时重算：必填输入错误随连接消失', () {
      final GraphEditorController controller = GraphEditorController(
        _project(
          nodes: <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
            _node('n3', 'value.text'),
          ],
        ),
      );
      expect(_errors(controller), hasLength(2));
      controller.connect(
        from: _endpoint('n1', 'out'),
        to: _endpoint('n2', 'exec'),
      );
      expect(_errors(controller), hasLength(1));
      controller.connect(
        from: _endpoint('n3', 'result'),
        to: _endpoint('n2', 'message'),
      );
      expect(_errors(controller), isEmpty);
    });
  });

  group('listener 计数', () {
    test('仅实际变更通知，每次变更恰好一次', () {
      final GraphEditorController controller = GraphEditorController(
        _project(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);
      final String id = controller.addNode('flow.entry', Offset.zero);
      controller.moveNode(id, const Offset(5, 5));
      controller.moveNode(id, const Offset(5, 5));
      controller.selectNode(id);
      controller.selectNode(id);
      controller.clearSelection();
      controller.clearSelection();
      controller.setViewport(x: 1, y: 2, scale: 1.5);
      controller.setViewport(x: 1, y: 2, scale: 1.5);
      controller.updateNodeParam(id, 'ignored', 42);
      controller.removeNode('missing');
      expect(notifications, 5);
    });
  });
}
