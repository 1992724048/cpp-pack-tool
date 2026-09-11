import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScriptProjectModel 序列化', () {
    test('序列化往返（含参数与视口）', () {
      final ScriptProjectModel project =
          ScriptProjectModel(
              id: 'script_1',
              name: '生成版本头',
              trigger: ScriptTrigger.pre,
              buildModel: BuildModel.release,
            )
            ..viewX = 10
            ..viewY = -5
            ..viewScale = 0.8;
      project.nodes.add(
        ScriptNodeModel(id: 'n1', type: 'flow.entry', x: 40, y: 60),
      );
      project.nodes.add(
        ScriptNodeModel(id: 'n2', type: 'value.text')
          ..params['value'] = r'$(OutDir)',
      );
      project.edges.add(
        ScriptEdgeModel(
          from: const ScriptEdgeEndpoint(node: 'n1', pin: 'out'),
          to: const ScriptEdgeEndpoint(node: 'n2', pin: 'exec'),
        ),
      );

      final ScriptProjectModel back = ScriptProjectModel.fromMap(
        project.toMap(),
      );

      expect(back.id, 'script_1');
      expect(back.name, '生成版本头');
      expect(back.trigger, ScriptTrigger.pre);
      expect(back.buildModel, BuildModel.release);
      expect(back.nodes, hasLength(2));
      expect(back.nodes[0].x, 40);
      expect(back.nodes[0].y, 60);
      expect(back.nodes[1].params['value'], r'$(OutDir)');
      expect(back.edges.single.from.node, 'n1');
      expect(back.edges.single.to.pin, 'exec');
      expect(back.viewX, 10);
      expect(back.viewY, -5);
      expect(back.viewScale, 0.8);
    });

    test('toMap 写出 version 1 与 viewport 结构', () {
      final ScriptProjectModel project = ScriptProjectModel(
        id: 'script_1',
        name: 'x',
        trigger: ScriptTrigger.post,
      );

      final Map<String, Object?> map = project.toMap();

      expect(map['version'], 1);
      expect(map['trigger'], 'post');
      expect(map['buildModel'], 'all');
      expect(map['nodes'], isEmpty);
      expect(map['edges'], isEmpty);
      expect(map['viewport'], <String, Object?>{
        'x': 0.0,
        'y': 0.0,
        'scale': 1.0,
      });
    });

    test('toMap 仅写出 string/bool/List<String> 参数', () {
      final ScriptNodeModel node = ScriptNodeModel(
        id: 'n1',
        type: 'value.text',
      );
      node.params['text'] = 'hi';
      node.params['enabled'] = false;
      node.params['names'] = <String>['a'];
      node.params['count'] = 3;
      node.params['ratio'] = 1.5;
      node.params['nothing'] = null;
      final ScriptProjectModel project = ScriptProjectModel(
        id: 'script_1',
        name: 'x',
        trigger: ScriptTrigger.pre,
      )..nodes.add(node);

      final Map<String, Object?> map = project.toMap();
      final Map<String, Object?> nodeMap =
          (map['nodes']! as List<Object?>).single! as Map<String, Object?>;
      final Map<String, Object?> params =
          nodeMap['params']! as Map<String, Object?>;

      expect(params, <String, Object?>{
        'text': 'hi',
        'enabled': false,
        'names': <String>['a'],
      });
    });
  });

  group('ScriptProjectModel 容错解析', () {
    test('trigger 非法抛 FormatException', () {
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'before',
        }),
        throwsFormatException,
      );
    });

    test('trigger 缺失或非字符串抛 FormatException', () {
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'id': 'script_1',
          'name': 'x',
        }),
        throwsFormatException,
      );
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 1,
        }),
        throwsFormatException,
      );
    });

    test('id/name 缺失或非字符串抛 FormatException', () {
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'name': 'x',
          'trigger': 'pre',
        }),
        throwsFormatException,
      );
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'id': 'script_1',
          'trigger': 'pre',
        }),
        throwsFormatException,
      );
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'id': 1,
          'name': 'x',
          'trigger': 'pre',
        }),
        throwsFormatException,
      );
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'id': 'script_1',
          'name': '',
          'trigger': 'pre',
        }),
        throwsFormatException,
      );
    });

    test('缺失 buildModel 回退 all', () {
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{'id': 'script_1', 'name': 'x', 'trigger': 'post'},
      );

      expect(project.buildModel, BuildModel.all);
    });

    test('buildModel 非法值抛 FormatException', () {
      expect(
        () => ScriptProjectModel.fromMap(<String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'buildModel': 'fast',
        }),
        throwsFormatException,
      );
    });

    test('缺失 version 可加载且未知 version 被忽略', () {
      final ScriptProjectModel missing = ScriptProjectModel.fromMap(
        <String, Object?>{'id': 'script_1', 'name': 'x', 'trigger': 'pre'},
      );
      final ScriptProjectModel unknown = ScriptProjectModel.fromMap(
        <String, Object?>{
          'version': 99,
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
        },
      );

      expect(missing.id, 'script_1');
      expect(missing.nodes, isEmpty);
      expect(missing.edges, isEmpty);
      expect(unknown.name, 'x');
      expect(unknown.nodes, isEmpty);
    });

    test('viewport 缺失或非数值回退默认视口', () {
      final ScriptProjectModel missing = ScriptProjectModel.fromMap(
        <String, Object?>{'id': 'script_1', 'name': 'x', 'trigger': 'pre'},
      );
      final ScriptProjectModel broken = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'viewport': <String, Object?>{'x': 'left', 'y': null, 'scale': 'big'},
        },
      );

      expect(missing.viewX, 0);
      expect(missing.viewY, 0);
      expect(missing.viewScale, 1.0);
      expect(broken.viewX, 0);
      expect(broken.viewY, 0);
      expect(broken.viewScale, 1.0);
    });

    test('缺少 id 或 type 的节点被丢弃', () {
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'nodes': <Object?>[
            <String, Object?>{'id': 'n1', 'type': 'flow.entry'},
            <String, Object?>{'id': 'n2'},
            <String, Object?>{'type': 'value.text'},
            <String, Object?>{'id': '', 'type': 'value.text'},
            'not a map',
          ],
        },
      );

      expect(project.nodes, hasLength(1));
      expect(project.nodes.single.id, 'n1');
    });

    test('节点 x/y 非数值回退 0，整数转为 double', () {
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'n1',
              'type': 'flow.entry',
              'x': 'left',
              'y': null,
            },
            <String, Object?>{
              'id': 'n2',
              'type': 'flow.entry',
              'x': 5,
              'y': 6.5,
            },
          ],
        },
      );

      expect(project.nodes[0].x, 0);
      expect(project.nodes[0].y, 0);
      expect(project.nodes[1].x, 5.0);
      expect(project.nodes[1].y, 6.5);
    });

    test('params 非 map 回退空且仅保留 string/bool/List<String>', () {
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'n1',
              'type': 'value.text',
              'params': 'oops',
            },
            <String, Object?>{
              'id': 'n2',
              'type': 'value.text',
              'params': <String, Object?>{
                'text': 'hello',
                'enabled': true,
                'names': <String>['a', 'b'],
                'loose': <Object?>['x', 'y'],
                'count': 3,
                'ratio': 1.5,
                'nothing': null,
                'mixed': <Object?>['a', 1],
              },
            },
          ],
        },
      );

      expect(project.nodes[0].params, isEmpty);
      final Map<String, Object?> params = project.nodes[1].params;
      expect(params, hasLength(4));
      expect(params['text'], 'hello');
      expect(params['enabled'], isTrue);
      expect(params['names'], <String>['a', 'b']);
      expect(params['loose'], <String>['x', 'y']);
    });

    test('悬空边与端点非法边被丢弃', () {
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'nodes': <Object?>[
            <String, Object?>{'id': 'n1', 'type': 'flow.entry'},
            <String, Object?>{'id': 'n2', 'type': 'value.text'},
          ],
          'edges': <Object?>[
            <String, Object?>{
              'from': <String, Object?>{'node': 'n1', 'pin': 'out'},
              'to': <String, Object?>{'node': 'n2', 'pin': 'exec'},
            },
            <String, Object?>{
              'from': <String, Object?>{'node': 'n2', 'pin': 'out'},
              'to': <String, Object?>{'node': 'ghost', 'pin': 'in'},
            },
            <String, Object?>{
              'from': <String, Object?>{'node': 'n1'},
              'to': <String, Object?>{'node': 'n2', 'pin': 'in'},
            },
            <String, Object?>{
              'from': 'n1',
              'to': <String, Object?>{'node': 'n2', 'pin': 'in'},
            },
            42,
          ],
        },
      );

      expect(project.edges, hasLength(1));
      expect(project.edges.single.from.node, 'n1');
      expect(project.edges.single.to.node, 'n2');
    });

    test('重复节点 id 保留首个且引用其的边保留', () {
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'nodes': <Object?>[
            <String, Object?>{'id': 'n1', 'type': 'flow.entry'},
            <String, Object?>{'id': 'n1', 'type': 'value.text'},
          ],
          'edges': <Object?>[
            <String, Object?>{
              'from': <String, Object?>{'node': 'n1', 'pin': 'out'},
              'to': <String, Object?>{'node': 'n1', 'pin': 'exec'},
            },
          ],
        },
      );

      expect(project.nodes, hasLength(1));
      expect(project.nodes.single.type, 'flow.entry');
      expect(project.edges, hasLength(1));
    });

    test('重复节点 id 向 warnings 追加警告并保留首个', () {
      final List<String> warnings = <String>[];
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'nodes': <Object?>[
            <String, Object?>{'id': 'n1', 'type': 'flow.entry'},
            <String, Object?>{'id': 'n1', 'type': 'value.text'},
          ],
        },
        warnings: warnings,
      );

      expect(project.nodes, hasLength(1));
      expect(project.nodes.single.type, 'flow.entry');
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('script_1'));
      expect(warnings.single, contains('n1'));
    });

    test('不传 warnings 时重复节点 id 静默去重', () {
      final ScriptProjectModel project = ScriptProjectModel.fromMap(
        <String, Object?>{
          'id': 'script_1',
          'name': 'x',
          'trigger': 'pre',
          'nodes': <Object?>[
            <String, Object?>{'id': 'n1', 'type': 'flow.entry'},
            <String, Object?>{'id': 'n1', 'type': 'value.text'},
          ],
        },
      );

      expect(project.nodes, hasLength(1));
      expect(project.nodes.single.type, 'flow.entry');
    });
  });
}
