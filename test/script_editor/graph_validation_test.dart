import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_validation.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

ScriptNodeModel _node(String id, String type, {Map<String, Object?>? params}) {
  final ScriptNodeModel node = ScriptNodeModel(id: id, type: type);
  if (params != null) {
    node.params = params;
  }
  return node;
}

ScriptEdgeModel _edge(
  String fromNode,
  String fromPin,
  String toNode,
  String toPin,
) {
  return ScriptEdgeModel(
    from: ScriptEdgeEndpoint(node: fromNode, pin: fromPin),
    to: ScriptEdgeEndpoint(node: toNode, pin: toPin),
  );
}

ScriptProjectModel _project(
  List<ScriptNodeModel> nodes, {
  List<ScriptEdgeModel> edges = const <ScriptEdgeModel>[],
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '测试脚本',
    trigger: ScriptTrigger.pre,
  );
  project.nodes = List<ScriptNodeModel>.of(nodes);
  project.edges = List<ScriptEdgeModel>.of(edges);
  return project;
}

List<ScriptDiagnostic> _validate(
  List<ScriptNodeModel> nodes, {
  List<ScriptEdgeModel> edges = const <ScriptEdgeModel>[],
}) {
  return GraphValidator.validate(_project(nodes, edges: edges));
}

List<ScriptDiagnostic> _errors(List<ScriptDiagnostic> diagnostics) {
  return diagnostics
      .where((ScriptDiagnostic diagnostic) => diagnostic.isError)
      .toList();
}

List<ScriptDiagnostic> _warnings(List<ScriptDiagnostic> diagnostics) {
  return diagnostics
      .where((ScriptDiagnostic diagnostic) => !diagnostic.isError)
      .toList();
}

List<ScriptDiagnostic> _paramErrors(List<ScriptDiagnostic> diagnostics) {
  return _errors(diagnostics)
      .where((ScriptDiagnostic diagnostic) => diagnostic.message.contains('参数'))
      .toList();
}

List<ScriptDiagnostic> _variableNameErrors(List<ScriptDiagnostic> diagnostics) {
  return diagnostics
      .where(
        (ScriptDiagnostic diagnostic) =>
            diagnostic.message.contains('变量名须以字母或下划线开头，且仅含字母、数字、下划线'),
      )
      .toList();
}

List<ScriptDiagnostic> _typeMismatchErrors(List<ScriptDiagnostic> diagnostics) {
  return diagnostics
      .where(
        (ScriptDiagnostic diagnostic) => diagnostic.message.contains('类型不一致'),
      )
      .toList();
}

ScriptDiagnostic _diagnosticWith(
  List<ScriptDiagnostic> diagnostics,
  String fragment,
) {
  return diagnostics.firstWhere(
    (ScriptDiagnostic diagnostic) => diagnostic.message.contains(fragment),
    orElse: () => fail('未找到包含「$fragment」的诊断：$diagnostics'),
  );
}

void main() {
  group('合法图零诊断', () {
    test('线性图：入口 → 日志（消息来自文本）', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': 'hello'},
          ),
          _node('n3', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'message'),
        ],
      );
      expect(diagnostics, isEmpty);
    });

    test('分支 + 遍历 + 循环出口全接线', () {
      final List<ScriptNodeModel> nodes = <ScriptNodeModel>[
        _node('n1', 'flow.entry'),
        _node('n2', 'flow.branch'),
        _node('n3', 'flow.foreach'),
        _node('n4', 'file.list'),
        _node(
          'n5',
          'value.text',
          params: <String, Object?>{'value': r'C:\pkg'},
        ),
        _node('n6', 'value.boolean', params: <String, Object?>{'value': true}),
        _node('n7', 'log.message', params: <String, Object?>{'level': 'warn'}),
        _node('n8', 'log.message'),
        _node('n9', 'log.message', params: <String, Object?>{'level': 'error'}),
        _node(
          'n10',
          'context.macro',
          params: <String, Object?>{'macro': 'OutDir'},
        ),
      ];
      final List<ScriptEdgeModel> edges = <ScriptEdgeModel>[
        _edge('n1', 'out', 'n2', 'exec'),
        _edge('n6', 'result', 'n2', 'condition'),
        _edge('n2', 'then', 'n3', 'exec'),
        _edge('n2', 'else', 'n7', 'exec'),
        _edge('n5', 'result', 'n7', 'message'),
        _edge('n4', 'result', 'n3', 'list'),
        _edge('n5', 'result', 'n4', 'directory'),
        _edge('n3', 'body', 'n8', 'exec'),
        _edge('n3', 'item', 'n8', 'message'),
        _edge('n3', 'completed', 'n9', 'exec'),
        _edge('n10', 'result', 'n9', 'message'),
      ];
      expect(GraphValidator.validate(_project(nodes, edges: edges)), isEmpty);
    });

    test('数据输出可扇出到多个输入', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text', params: <String, Object?>{'value': 'x'}),
          _node('n3', 'log.message'),
          _node('n4', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'message'),
          _edge('n2', 'result', 'n4', 'message'),
          _edge('n3', 'out', 'n4', 'exec'),
        ],
      );
      expect(diagnostics, isEmpty);
    });
  });

  group('入口规则', () {
    test('无入口报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(<ScriptNodeModel>[_node('n1', 'value.text')]),
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('开始'));
      expect(errors.single.isError, isTrue);
    });

    test('两个入口报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(<ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'flow.entry'),
        ]),
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('2 个'));
    });

    test('空图报缺少入口', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        const <ScriptNodeModel>[],
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.isError, isTrue);
      expect(diagnostics.single.message, contains('开始'));
    });
  });

  group('连接规则', () {
    test('必填数据输入未连接报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'file.copy'),
          ],
          edges: <ScriptEdgeModel>[_edge('n1', 'out', 'n2', 'exec')],
        ),
      );
      expect(errors, hasLength(2));
      expect(_diagnosticWith(errors, '源路径').message, contains('必填输入'));
      expect(_diagnosticWith(errors, '目标路径').message, contains('必填输入'));
    });

    test('必填执行输入未连接报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
            _node('n3', 'value.text'),
          ],
          edges: <ScriptEdgeModel>[_edge('n3', 'result', 'n2', 'message')],
        ),
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('必填输入'));
      expect(errors.single.nodeId, 'n2');
    });

    test('string 输出接 bool 输入报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'value.text'),
            _node('n3', 'logic.not'),
          ],
          edges: <ScriptEdgeModel>[_edge('n2', 'result', 'n3', 'input')],
        ),
      );
      final ScriptDiagnostic mismatch = _diagnosticWith(errors, '数据类型不匹配');
      expect(mismatch.nodeId, 'n3');
      expect(mismatch.message, contains('bool'));
      expect(mismatch.isError, isTrue);
    });

    test('exec 输出接 data 输入报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[_edge('n1', 'out', 'n2', 'message')],
        ),
      );
      final ScriptDiagnostic mismatch = _diagnosticWith(errors, '引脚种类不匹配');
      expect(mismatch.nodeId, 'n2');
    });

    test('data 输出接 exec 输入报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'value.text'),
            _node('n2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[_edge('n1', 'result', 'n2', 'exec')],
        ),
      );
      expect(_diagnosticWith(errors, '引脚种类不匹配'), isNotNull);
    });

    test('list<string> 输出接 string 输入报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'value.text'),
            _node('n2', 'file.list'),
            _node('n3', 'string.concat'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('n1', 'result', 'n2', 'directory'),
            _edge('n2', 'result', 'n3', 'a'),
            _edge('n1', 'result', 'n3', 'b'),
          ],
        ),
      );
      final ScriptDiagnostic mismatch = _diagnosticWith(errors, '数据类型不匹配');
      expect(mismatch.message, contains('list<string>'));
    });

    test('number 输出接 string 输入报错：消息含「数值」标签', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'value.number'),
            _node('n3', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('n1', 'out', 'n3', 'exec'),
            _edge('n2', 'result', 'n3', 'message'),
          ],
        ),
      );
      expect(errors, hasLength(1));
      final ScriptDiagnostic mismatch = _diagnosticWith(errors, '数据类型不匹配');
      expect(
        mismatch.message,
        '数据类型不匹配：「n2.result」输出 数值，「n3.message」需要 string',
      );
      expect(mismatch.nodeId, 'n3');
      expect(mismatch.isError, isTrue);
    });

    test('exec 输出被多条边连接报错', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'log.message'),
          _node('n3', 'log.message'),
          _node('n4', 'value.text'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n2', 'exec'),
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n4', 'result', 'n2', 'message'),
          _edge('n4', 'result', 'n3', 'message'),
        ],
      );
      final List<ScriptDiagnostic> errors = _errors(diagnostics);
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('执行输出'));
      expect(errors.single.message, contains('条边连接'));
      expect(errors.single.nodeId, 'n1');
    });

    test('exec 输入被多条边连接报错', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'flow.branch'),
          _node('n3', 'value.boolean'),
          _node('n4', 'log.message'),
          _node('n5', 'value.text'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n2', 'exec'),
          _edge('n3', 'result', 'n2', 'condition'),
          _edge('n2', 'then', 'n4', 'exec'),
          _edge('n2', 'else', 'n4', 'exec'),
          _edge('n5', 'result', 'n4', 'message'),
        ],
      );
      final List<ScriptDiagnostic> errors = _errors(diagnostics);
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('执行输入'));
      expect(errors.single.message, contains('2 条边连接'));
      expect(errors.single.nodeId, 'n4');
      expect(_warnings(diagnostics), isEmpty);
    });

    test('data 输入被多条边连接报错', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text'),
          _node('n3', 'value.text'),
          _node('n4', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'message'),
          _edge('n3', 'result', 'n4', 'message'),
        ],
      );
      final List<ScriptDiagnostic> errors = _errors(diagnostics);
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('数据输入'));
      expect(errors.single.nodeId, 'n4');
    });
  });

  group('环检测', () {
    test('数据环 A→B→A 返回诊断且不挂起', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('a', 'string.concat'),
            _node('b', 'string.lowerCase'),
            _node('v', 'value.text'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('b', 'result', 'a', 'a'),
            _edge('a', 'result', 'b', 'input'),
            _edge('v', 'result', 'a', 'b'),
          ],
        ),
      );
      final ScriptDiagnostic cycle = _diagnosticWith(errors, '数据连接存在环');
      expect(cycle.isError, isTrue);
      expect(cycle.nodeId, anyOf('a', 'b'));
    });

    test('执行环返回诊断且不挂起', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('l1', 'log.message'),
            _node('l2', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('l1', 'out', 'l2', 'exec'),
            _edge('l2', 'out', 'l1', 'exec'),
          ],
        ),
      );
      expect(_diagnosticWith(errors, '执行连接存在环').isError, isTrue);
    });

    test('节点自环报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[_node('n1', 'logic.not')],
          edges: <ScriptEdgeModel>[_edge('n1', 'result', 'n1', 'input')],
        ),
      );
      final ScriptDiagnostic cycle = _diagnosticWith(errors, '数据连接存在环');
      expect(cycle.nodeId, 'n1');
    });
  });

  group('未知节点与引脚', () {
    test('未知节点类型报错且保留原始数据', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'mystery.node', params: <String, Object?>{'x': 'y'}),
        ],
        edges: <ScriptEdgeModel>[_edge('n1', 'out', 'n2', 'exec')],
      );
      final List<ScriptDiagnostic> errors = _errors(
        GraphValidator.validate(project),
      );
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('未知节点类型'));
      expect(errors.single.nodeId, 'n2');
      expect(project.nodes.last.type, 'mystery.node');
      expect(project.nodes.last.params, <String, Object?>{'x': 'y'});
    });

    test('未知输出引脚报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'value.text'),
            _node('n3', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('n1', 'out', 'n3', 'exec'),
            _edge('n2', 'bogus', 'n3', 'message'),
          ],
        ),
      );
      final ScriptDiagnostic unknownPin = _diagnosticWith(errors, '不存在引脚');
      expect(unknownPin.nodeId, 'n2');
      expect(unknownPin.message, contains('bogus'));
    });

    test('未知输入引脚报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[
            _node('n1', 'flow.entry'),
            _node('n2', 'value.text'),
            _node('n3', 'log.message'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('n1', 'out', 'n3', 'exec'),
            _edge('n2', 'result', 'n3', 'bogus'),
          ],
        ),
      );
      final ScriptDiagnostic unknownPin = _diagnosticWith(errors, '不存在引脚');
      expect(unknownPin.nodeId, 'n3');
      expect(unknownPin.message, contains('bogus'));
    });

    test('悬空边指向不存在节点报错', () {
      final List<ScriptDiagnostic> errors = _errors(
        _validate(
          <ScriptNodeModel>[_node('n1', 'flow.entry')],
          edges: <ScriptEdgeModel>[_edge('n1', 'out', 'ghost', 'exec')],
        ),
      );
      final ScriptDiagnostic dangling = _diagnosticWith(errors, '不存在的节点');
      expect(dangling.nodeId, 'ghost');
    });
  });

  group('参数校验', () {
    test('macroKey 必须在白名单内', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'context.macro',
            params: <String, Object?>{'macro': 'Nope'},
          ),
        ]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('Nope'));
      expect(paramErrors.single.message, contains('MSBuild 宏白名单'));
      expect(paramErrors.single.nodeId, 'n1');

      final List<ScriptDiagnostic> explicit = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'context.macro',
            params: <String, Object?>{'macro': 'Configuration'},
          ),
        ]),
      );
      expect(explicit, isEmpty);

      final List<ScriptDiagnostic> byDefault = _paramErrors(
        _validate(<ScriptNodeModel>[_node('n1', 'context.macro')]),
      );
      expect(byDefault, isEmpty);
    });

    test('logLevel 取值受限', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'log.message',
            params: <String, Object?>{'level': 'verbose'},
          ),
        ]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('verbose'));
      expect(paramErrors.single.message, contains('info / warn / error'));

      for (final String level in <String>['info', 'warn', 'error']) {
        final List<ScriptDiagnostic> good = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'log.message',
              params: <String, Object?>{'level': level},
            ),
          ]),
        );
        expect(good, isEmpty, reason: '级别 $level 应合法');
      }
    });

    test('stringOperator 取值受限', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'logic.compareString',
            params: <String, Object?>{'operator': 'gt'},
          ),
        ]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('gt'));
      expect(paramErrors.single.message, contains('eq / ne / contains'));

      for (final String operator in <String>['eq', 'ne', 'contains']) {
        final List<ScriptDiagnostic> good = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'logic.compareString',
              params: <String, Object?>{'operator': operator},
            ),
          ]),
        );
        expect(good, isEmpty, reason: '运算符 $operator 应合法');
      }
    });

    test('mathOperator 取值受限', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'math.arithmetic',
            params: <String, Object?>{'operator': 'pow'},
          ),
        ]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('pow'));
      expect(paramErrors.single.message, contains('非法'));
      expect(
        paramErrors.single.message,
        contains('add / subtract / multiply / divide / modulo'),
      );
      expect(paramErrors.single.nodeId, 'n1');

      for (final String operator in <String>[
        'add',
        'subtract',
        'multiply',
        'divide',
        'modulo',
      ]) {
        final List<ScriptDiagnostic> good = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'math.arithmetic',
              params: <String, Object?>{'operator': operator},
            ),
          ]),
        );
        expect(good, isEmpty, reason: '运算符 $operator 应合法');
      }

      final List<ScriptDiagnostic> byDefault = _paramErrors(
        _validate(<ScriptNodeModel>[_node('n1', 'math.arithmetic')]),
      );
      expect(byDefault, isEmpty);
    });

    test('bitwiseOperator 取值受限', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'math.bitwise',
            params: <String, Object?>{'operator': 'nand'},
          ),
        ]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('nand'));
      expect(paramErrors.single.message, contains('非法'));
      expect(
        paramErrors.single.message,
        contains('and / or / xor / shiftLeft / shiftRight'),
      );

      for (final String operator in <String>[
        'and',
        'or',
        'xor',
        'shiftLeft',
        'shiftRight',
      ]) {
        final List<ScriptDiagnostic> good = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'math.bitwise',
              params: <String, Object?>{'operator': operator},
            ),
          ]),
        );
        expect(good, isEmpty, reason: '运算符 $operator 应合法');
      }
    });

    test('numberOperator 取值受限', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'logic.compareNumber',
            params: <String, Object?>{'operator': 'bogus'},
          ),
        ]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('bogus'));
      expect(
        paramErrors.single.message,
        contains('lt / le / gt / ge / eq / ne'),
      );

      for (final String operator in <String>[
        'lt',
        'le',
        'gt',
        'ge',
        'eq',
        'ne',
      ]) {
        final List<ScriptDiagnostic> good = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'logic.compareNumber',
              params: <String, Object?>{'operator': operator},
            ),
          ]),
        );
        expect(good, isEmpty, reason: '运算符 $operator 应合法');
      }

      final List<ScriptDiagnostic> nonString = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'logic.compareNumber',
            params: <String, Object?>{'operator': 5},
          ),
        ]),
      );
      expect(nonString, hasLength(1));
      expect(nonString.single.message, contains('非法'));
    });

    test('hashAlgorithm 取值受限', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'crypto.fileHash',
            params: <String, Object?>{'algorithm': 'sha3'},
          ),
        ]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('sha3'));
      expect(paramErrors.single.message, contains('非法'));
      expect(
        paramErrors.single.message,
        contains('sha256 / sha1 / sha512 / md5 / crc32'),
      );

      for (final String algorithm in <String>[
        'sha256',
        'sha1',
        'sha512',
        'md5',
        'crc32',
      ]) {
        final List<ScriptDiagnostic> good = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'crypto.fileHash',
              params: <String, Object?>{'algorithm': algorithm},
            ),
          ]),
        );
        expect(good, isEmpty, reason: '算法 $algorithm 应合法');
      }
    });

    test('number 参数必须为有限数字', () {
      for (final Object? invalid in <Object?>[
        'abc',
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final List<ScriptDiagnostic> paramErrors = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'value.number',
              params: <String, Object?>{'value': invalid},
            ),
          ]),
        );
        expect(paramErrors, hasLength(1), reason: '「$invalid」应判非法');
        expect(paramErrors.single.message, contains('必须为数字'));
        expect(paramErrors.single.isError, isTrue);
        expect(paramErrors.single.nodeId, 'n1');
      }

      for (final num valid in <num>[0, 5, -3, 5.5]) {
        final List<ScriptDiagnostic> paramErrors = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'value.number',
              params: <String, Object?>{'value': valid},
            ),
          ]),
        );
        expect(paramErrors, isEmpty, reason: '「$valid」应合法');
      }

      final List<ScriptDiagnostic> byDefault = _paramErrors(
        _validate(<ScriptNodeModel>[_node('n1', 'value.number')]),
      );
      expect(byDefault, isEmpty);
    });

    test('packageFilePath 不能为空', () {
      final List<ScriptDiagnostic> paramErrors = _paramErrors(
        _validate(<ScriptNodeModel>[_node('n1', 'context.packageFile')]),
      );
      expect(paramErrors, hasLength(1));
      expect(paramErrors.single.message, contains('相对路径'));

      final List<ScriptDiagnostic> good = _paramErrors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'context.packageFile',
            params: <String, Object?>{'path': r'files\a.dll'},
          ),
        ]),
      );
      expect(good, isEmpty);
    });

    test('scriptFilePath 不能为空', () {
      const ScriptNodeTypeDescriptor descriptor = ScriptNodeTypeDescriptor(
        typeKey: 'context.scriptFile',
        displayName: '包内脚本文件',
        category: ScriptNodeCategory.context,
        pins: <ScriptPinDescriptor>[],
      );
      const ScriptParamDescriptor param = ScriptParamDescriptor(
        key: 'file',
        label: '文件',
        type: ScriptParamType.scriptFilePath,
        defaultValue: '',
      );
      for (final String valid in <String>[
        'files/run.bat',
        r'files\scripts\build.ps1',
        'a',
      ]) {
        expect(
          GraphValidator.paramErrorMessage(descriptor, param, valid),
          isNull,
          reason: '「$valid」应合法',
        );
      }
      for (final Object? empty in <Object?>[null, '', '   ', 5]) {
        expect(
          GraphValidator.paramErrorMessage(descriptor, param, empty),
          '参数「文件」不能为空',
          reason: '「$empty」应判空',
        );
      }
    });

    test('textLines 无参数级错误规则（清洗在写入侧）', () {
      const ScriptNodeTypeDescriptor descriptor = ScriptNodeTypeDescriptor(
        typeKey: 'system.findTool',
        displayName: '查找工具',
        category: ScriptNodeCategory.system,
        pins: <ScriptPinDescriptor>[],
      );
      const ScriptParamDescriptor param = ScriptParamDescriptor(
        key: 'candidates',
        label: '候选路径',
        type: ScriptParamType.textLines,
        defaultValue: <String>[],
      );
      for (final Object? value in <Object?>[
        null,
        '',
        <String>[],
        <String>['a', 'b'],
        5,
      ]) {
        expect(
          GraphValidator.paramErrorMessage(descriptor, param, value),
          isNull,
          reason: '「$value」不应报参数错误',
        );
      }
    });

    test('环境变量名格式受限', () {
      for (final String invalid in <String>['', '1BAD', 'A-B', 'A B']) {
        final List<ScriptDiagnostic> paramErrors = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'context.environment',
              params: <String, Object?>{'name': invalid},
            ),
          ]),
        );
        expect(paramErrors, hasLength(1), reason: '「$invalid」应判非法');
        expect(paramErrors.single.message, contains('不是合法环境变量名'));
      }

      for (final String valid in <String>[
        'PATH',
        'A_B1',
        '_private',
        'Path2',
      ]) {
        final List<ScriptDiagnostic> paramErrors = _paramErrors(
          _validate(<ScriptNodeModel>[
            _node(
              'n1',
              'context.environment',
              params: <String, Object?>{'name': valid},
            ),
          ]),
        );
        expect(paramErrors, isEmpty, reason: '「$valid」应合法');
      }
    });
  });

  group('节点级参数规则（M4.2 T7）', () {
    test('AES 口令二选一：均空报错，任一非空（含并存）通过', () {
      for (final String typeKey in <String>[
        'crypto.aesEncrypt',
        'crypto.aesDecrypt',
      ]) {
        final List<ScriptDiagnostic> missing = _errors(
          _validate(<ScriptNodeModel>[_node('n1', typeKey)]),
        );
        final ScriptDiagnostic ruleError = _diagnosticWith(
          missing,
          '口令或口令环境变量名需二选一',
        );
        expect(ruleError.nodeId, 'n1');
        expect(ruleError.isError, isTrue);

        for (final Map<String, Object?> params in <Map<String, Object?>>[
          <String, Object?>{'password': 'secret'},
          <String, Object?>{'passwordEnv': 'CNP_AES_KEY'},
          <String, Object?>{'password': 'secret', 'passwordEnv': 'CNP_AES_KEY'},
        ]) {
          final List<ScriptDiagnostic> diagnostics = _validate(
            <ScriptNodeModel>[_node('n1', typeKey, params: params)],
          );
          expect(
            diagnostics.where(
              (ScriptDiagnostic diagnostic) =>
                  diagnostic.message.contains('口令或口令环境变量名需二选一'),
            ),
            isEmpty,
            reason: '$typeKey $params',
          );
        }
      }
    });

    test('AES 口令二选一：显式空串按空处理', () {
      final List<ScriptDiagnostic> diagnostics = _errors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'crypto.aesEncrypt',
            params: <String, Object?>{'password': '', 'passwordEnv': ''},
          ),
        ]),
      );
      expect(_diagnosticWith(diagnostics, '口令或口令环境变量名需二选一').nodeId, 'n1');
    });

    test('signFile 证书来源二选一：均空报错，pfxPath / thumbprint 任一通过', () {
      final List<ScriptDiagnostic> missing = _errors(
        _validate(<ScriptNodeModel>[_node('n1', 'crypto.signFile')]),
      );
      final ScriptDiagnostic ruleError = _diagnosticWith(
        missing,
        'PFX 路径或证书指纹需二选一',
      );
      expect(ruleError.nodeId, 'n1');
      expect(ruleError.isError, isTrue);

      for (final Map<String, Object?> params in <Map<String, Object?>>[
        <String, Object?>{'pfxPath': 'cert.pfx'},
        <String, Object?>{'thumbprint': 'ABCDEF0123'},
        <String, Object?>{'pfxPath': 'cert.pfx', 'thumbprint': 'ABCDEF0123'},
      ]) {
        final List<ScriptDiagnostic> diagnostics = _validate(<ScriptNodeModel>[
          _node('n1', 'crypto.signFile', params: params),
        ]);
        expect(
          diagnostics.where(
            (ScriptDiagnostic diagnostic) =>
                diagnostic.message.contains('PFX 路径或证书指纹需二选一'),
          ),
          isEmpty,
          reason: '$params',
        );
      }
    });

    test('passwordEnv 非空时须为合法环境变量名', () {
      for (final String invalid in <String>['1BAD', 'A-B', 'A B', '口令']) {
        for (final String typeKey in <String>[
          'crypto.aesEncrypt',
          'crypto.signFile',
        ]) {
          final List<ScriptDiagnostic> diagnostics = _errors(
            _validate(<ScriptNodeModel>[
              _node(
                'n1',
                typeKey,
                params: <String, Object?>{
                  'password': '',
                  'passwordEnv': invalid,
                  if (typeKey == 'crypto.signFile') 'pfxPath': 'cert.pfx',
                },
              ),
            ]),
          );
          final ScriptDiagnostic envError = _diagnosticWith(
            diagnostics,
            '不是合法环境变量名',
          );
          expect(envError.nodeId, 'n1', reason: '$typeKey「$invalid」');
          expect(envError.message, contains(invalid), reason: typeKey);
        }
      }

      for (final String valid in <String>[
        'PATH',
        'A_B1',
        '_private',
        'Path2',
      ]) {
        final List<ScriptDiagnostic> diagnostics = _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'crypto.aesEncrypt',
            params: <String, Object?>{'passwordEnv': valid},
          ),
        ]);
        expect(
          diagnostics.where(
            (ScriptDiagnostic diagnostic) =>
                diagnostic.message.contains('不是合法环境变量名'),
          ),
          isEmpty,
          reason: valid,
        );
      }
    });

    test('signFile：password 非空不豁免口令环境变量名校验', () {
      final List<ScriptDiagnostic> diagnostics = _errors(
        _validate(<ScriptNodeModel>[
          _node(
            'n1',
            'crypto.signFile',
            params: <String, Object?>{
              'pfxPath': 'cert.pfx',
              'password': 'pw',
              'passwordEnv': 'BAD-NAME',
            },
          ),
        ]),
      );
      final ScriptDiagnostic envError = _diagnosticWith(
        diagnostics,
        '不是合法环境变量名',
      );
      expect(envError.nodeId, 'n1');
      expect(envError.message, contains('BAD-NAME'));
    });

    test('passwordEnv 为空时不校验（默认参数只报二选一）', () {
      final List<ScriptDiagnostic> diagnostics = _errors(
        _validate(<ScriptNodeModel>[_node('n1', 'crypto.aesEncrypt')]),
      );
      expect(
        diagnostics.where(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.message.contains('不是合法环境变量名'),
        ),
        isEmpty,
      );
      expect(_diagnosticWith(diagnostics, '需二选一').nodeId, 'n1');
    });

    test('诊断顺序：参数错误 → 节点级规则 → 必填输入', () {
      final List<ScriptDiagnostic> diagnostics = _validate(<ScriptNodeModel>[
        _node('n1', 'flow.entry'),
        _node('n2', 'crypto.signFile'),
        _node(
          'n3',
          'crypto.aesEncrypt',
          params: <String, Object?>{'passwordEnv': 'BAD-NAME'},
        ),
        _node('n4', 'context.packageFile'),
      ]);
      final int paramIndex = diagnostics.indexWhere(
        (ScriptDiagnostic diagnostic) => diagnostic.message.contains('相对路径'),
      );
      final int signRuleIndex = diagnostics.indexWhere(
        (ScriptDiagnostic diagnostic) =>
            diagnostic.message.contains('PFX 路径或证书指纹需二选一'),
      );
      final int envIndex = diagnostics.indexWhere(
        (ScriptDiagnostic diagnostic) =>
            diagnostic.message.contains('不是合法环境变量名'),
      );
      final int requiredIndex = diagnostics.indexWhere(
        (ScriptDiagnostic diagnostic) => diagnostic.message.contains('必填输入'),
      );
      expect(paramIndex, greaterThanOrEqualTo(0));
      expect(paramIndex, lessThan(signRuleIndex));
      expect(signRuleIndex, lessThan(envIndex));
      expect(envIndex, lessThan(requiredIndex));
    });

    test('节点级规则错误挂在对应节点', () {
      final List<ScriptDiagnostic> diagnostics = _errors(
        _validate(<ScriptNodeModel>[
          _node('n1', 'crypto.aesEncrypt'),
          _node('n2', 'crypto.signFile'),
          _node('n3', 'value.text', params: <String, Object?>{'value': 'x'}),
        ]),
      );
      expect(
        diagnostics.where(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.message.contains('口令或口令环境变量名需二选一'),
        ),
        hasLength(1),
      );
      expect(_diagnosticWith(diagnostics, '口令或口令环境变量名需二选一').nodeId, 'n1');
      expect(_diagnosticWith(diagnostics, 'PFX 路径或证书指纹需二选一').nodeId, 'n2');
    });
  });

  group('变量名校验（M4.3 T2）', () {
    const List<String> variableTypes = <String>[
      'variable.setNumber',
      'variable.getNumber',
      'variable.setString',
      'variable.getString',
    ];

    test('四类节点：name 非空且匹配正则，非法报错、合法通过', () {
      for (final String typeKey in variableTypes) {
        for (final String invalid in <String>['', '1BAD', 'A-B', 'A B', '口令']) {
          final List<ScriptDiagnostic> errors = _variableNameErrors(
            _validate(<ScriptNodeModel>[
              _node('n1', typeKey, params: <String, Object?>{'name': invalid}),
            ]),
          );
          expect(errors, hasLength(1), reason: '$typeKey「$invalid」应判非法');
          expect(errors.single.isError, isTrue);
          expect(errors.single.nodeId, 'n1');
        }

        for (final String valid in <String>[
          'PATH',
          'A_B1',
          '_private',
          'Path2',
        ]) {
          final List<ScriptDiagnostic> errors = _variableNameErrors(
            _validate(<ScriptNodeModel>[
              _node('n1', typeKey, params: <String, Object?>{'name': valid}),
            ]),
          );
          expect(errors, isEmpty, reason: '$typeKey「$valid」应合法');
        }
      }
    });

    test('未填写 name（默认空串）报错', () {
      for (final String typeKey in variableTypes) {
        final List<ScriptDiagnostic> errors = _variableNameErrors(
          _validate(<ScriptNodeModel>[_node('n1', typeKey)]),
        );
        expect(errors, hasLength(1), reason: typeKey);
        expect(errors.single.nodeId, 'n1');
      }
    });

    test('同名同类型重复出现（含 set/get 组合）合法', () {
      final List<ScriptDiagnostic> diagnostics = _validate(<ScriptNodeModel>[
        _node(
          'n1',
          'variable.setNumber',
          params: <String, Object?>{'name': 'count'},
        ),
        _node(
          'n2',
          'variable.getNumber',
          params: <String, Object?>{'name': 'count'},
        ),
        _node(
          'n3',
          'variable.setString',
          params: <String, Object?>{'name': 'label'},
        ),
        _node(
          'n4',
          'variable.getString',
          params: <String, Object?>{'name': 'label'},
        ),
        _node(
          'n5',
          'variable.setNumber',
          params: <String, Object?>{'name': 'other'},
        ),
        _node(
          'n6',
          'variable.setString',
          params: <String, Object?>{'name': 'other2'},
        ),
      ]);
      expect(_typeMismatchErrors(diagnostics), isEmpty);
    });

    test('同名 number/string 混用：恰一条错误指向后出现节点', () {
      for (final (String first, String second) in <(String, String)>[
        ('variable.setNumber', 'variable.getString'),
        ('variable.getString', 'variable.setNumber'),
        ('variable.getNumber', 'variable.setString'),
        ('variable.setString', 'variable.getNumber'),
      ]) {
        final List<ScriptDiagnostic> mismatches = _typeMismatchErrors(
          _validate(<ScriptNodeModel>[
            _node('n1', first, params: <String, Object?>{'name': 'count'}),
            _node('n2', second, params: <String, Object?>{'name': 'count'}),
          ]),
        );
        expect(mismatches, hasLength(1), reason: '$first → $second');
        expect(mismatches.single.isError, isTrue);
        expect(mismatches.single.nodeId, 'n2');
        expect(mismatches.single.message, '变量 count 类型不一致');
      }
    });

    test('名称非法的节点只报名称错误，不参与类型一致性判定', () {
      final List<ScriptDiagnostic> diagnostics = _validate(<ScriptNodeModel>[
        _node(
          'n1',
          'variable.setNumber',
          params: <String, Object?>{'name': '1bad'},
        ),
        _node(
          'n2',
          'variable.getString',
          params: <String, Object?>{'name': '1bad'},
        ),
      ]);
      expect(_variableNameErrors(diagnostics), hasLength(2));
      expect(_typeMismatchErrors(diagnostics), isEmpty);
    });

    test('诊断顺序：变量名参数错误 → 类型不一致 → 必填输入', () {
      final List<ScriptDiagnostic> diagnostics = _validate(<ScriptNodeModel>[
        _node(
          'n1',
          'variable.setString',
          params: <String, Object?>{'name': '1bad'},
        ),
        _node(
          'n2',
          'variable.getNumber',
          params: <String, Object?>{'name': 'x'},
        ),
        _node(
          'n3',
          'variable.setString',
          params: <String, Object?>{'name': 'x'},
        ),
      ]);
      final int nameIndex = diagnostics.indexWhere(
        (ScriptDiagnostic diagnostic) =>
            diagnostic.message.contains('变量名须以字母或下划线开头'),
      );
      final int mismatchIndex = diagnostics.indexWhere(
        (ScriptDiagnostic diagnostic) => diagnostic.message.contains('类型不一致'),
      );
      final int requiredIndex = diagnostics.indexWhere(
        (ScriptDiagnostic diagnostic) => diagnostic.message.contains('必填输入'),
      );
      expect(nameIndex, greaterThanOrEqualTo(0));
      expect(mismatchIndex, greaterThanOrEqualTo(0));
      expect(requiredIndex, greaterThanOrEqualTo(0));
      expect(nameIndex, lessThan(mismatchIndex));
      expect(mismatchIndex, lessThan(requiredIndex));
    });
  });

  group('警告规则', () {
    test('入口输出未连接警告', () {
      final List<ScriptDiagnostic> diagnostics = _validate(<ScriptNodeModel>[
        _node('n1', 'flow.entry'),
      ]);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.isError, isFalse);
      expect(diagnostics.single.message, contains('未连接'));
      expect(diagnostics.single.nodeId, 'n1');
    });

    test('分支双出口均未连接警告', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'flow.branch'),
          _node('n3', 'value.boolean'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n2', 'exec'),
          _edge('n3', 'result', 'n2', 'condition'),
        ],
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.isError, isFalse);
      expect(diagnostics.single.message, contains('两个出口均未连接'));
      expect(diagnostics.single.nodeId, 'n2');
    });

    test('分支单出口连接不警告', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'flow.branch'),
          _node('n3', 'value.boolean'),
          _node('n4', 'log.message'),
          _node('n5', 'value.text'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n2', 'exec'),
          _edge('n3', 'result', 'n2', 'condition'),
          _edge('n2', 'then', 'n4', 'exec'),
          _edge('n5', 'result', 'n4', 'message'),
        ],
      );
      expect(diagnostics, isEmpty);
    });

    test('孤立数据节点警告（isError=false）', () {
      final List<ScriptDiagnostic> diagnostics = _validate(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'log.message'),
          _node('n3', 'value.text'),
          _node('n4', 'value.text'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n2', 'exec'),
          _edge('n3', 'result', 'n2', 'message'),
        ],
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.isError, isFalse);
      expect(diagnostics.single.nodeId, 'n4');
      expect(diagnostics.single.message, contains('未被使用'));
    });

    test('未消费数据链全部警告', () {
      final List<ScriptDiagnostic> warnings = _warnings(
        _validate(
          <ScriptNodeModel>[
            _node('a', 'string.concat'),
            _node('v1', 'value.text'),
            _node('v2', 'value.text'),
          ],
          edges: <ScriptEdgeModel>[
            _edge('v1', 'result', 'a', 'a'),
            _edge('v2', 'result', 'a', 'b'),
          ],
        ),
      );
      expect(warnings, hasLength(3));
      expect(
        warnings.map((ScriptDiagnostic warning) => warning.nodeId).toSet(),
        <String>{'a', 'v1', 'v2'},
      );
    });
  });
}
