import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/code_writer.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/graph_validation.dart';
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
  String name = '生成版本头',
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: name,
    trigger: ScriptTrigger.pre,
  );
  project.nodes = List<ScriptNodeModel>.of(nodes);
  project.edges = List<ScriptEdgeModel>.of(edges);
  return project;
}

ScriptProjectModel _linearLogGraph({required String message, String? level}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': message}),
      _node(
        'n3',
        'log.message',
        params: level == null ? null : <String, Object?>{'level': level},
      ),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n3', 'exec'),
      _edge('n2', 'result', 'n3', 'message'),
    ],
  );
}

ScriptCompileResult _compile(
  ScriptProjectModel project, {
  String packName = 'demo',
}) {
  return PowerShell5Generator().compile(project, packName: packName);
}

void main() {
  group('CodeWriter', () {
    test('缩进、空白行与嵌套', () {
      final CodeWriter writer = CodeWriter();
      writer.writeln('a');
      writer.indent(() {
        writer.writeln('b');
        writer.writeln();
        writer.indent(() {
          writer.writeln('c');
        });
      });
      writer.writeln('d');
      expect(writer.toString(), 'a\n    b\n\n        c\nd\n');
    });

    test('indent 体内抛出异常时缩进深度恢复', () {
      final CodeWriter writer = CodeWriter(indentText: '  ');
      expect(
        () => writer.indent(() => throw StateError('boom')),
        throwsStateError,
      );
      writer.writeln('after');
      expect(writer.toString(), 'after\n');
    });
  });

  group('骨架与线性发射', () {
    test('fileExtension 为 ps1', () {
      expect(PowerShell5Generator().fileExtension, 'ps1');
    });

    test('线性链完整 golden（entry → log）', () {
      final ScriptCompileResult result = _compile(
        _linearLogGraph(message: '开始构建'),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        '\uFEFF'
        '# 由 cpp_nuget_pack 生成 — demo / 生成版本头。请使用节点编辑器修改，勿手工编辑本文件。\n'
        r"$ErrorActionPreference = 'Stop'"
        '\n'
        'try {\n'
        "    Write-Host '开始构建'\n"
        '} catch {\n'
        r'    Write-Host "脚本执行失败: $($_.Exception.Message)" -ForegroundColor Red'
        '\n'
        '    exit 1\n'
        '}\n',
      );
    });

    test('brief 断言：BOM 开头、Stop 偏好、消息、exit 1', () {
      final ScriptCompileResult result = _compile(
        _linearLogGraph(message: '开始构建'),
      );
      expect(
        result.code,
        startsWith('\uFEFF# 由 cpp_nuget_pack 生成 — demo / 生成版本头'),
      );
      expect(result.code, contains(r"$ErrorActionPreference = 'Stop'"));
      expect(result.code, contains("Write-Host '开始构建'"));
      expect(result.code, contains('exit 1'));
    });

    test('换行仅为 LF', () {
      final String? code = _compile(_linearLogGraph(message: 'x')).code;
      expect(code, isNotNull);
      expect(code, isNot(contains('\r')));
    });

    test('入口无下游 → 空脚本体且保留警告诊断', () {
      final ScriptCompileResult result = _compile(
        _project(<ScriptNodeModel>[_node('n1', 'flow.entry')], name: '空脚本'),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        '\uFEFF'
        '# 由 cpp_nuget_pack 生成 — demo / 空脚本。请使用节点编辑器修改，勿手工编辑本文件。\n'
        r"$ErrorActionPreference = 'Stop'"
        '\n'
        'try {\n'
        '} catch {\n'
        r'    Write-Host "脚本执行失败: $($_.Exception.Message)" -ForegroundColor Red'
        '\n'
        '    exit 1\n'
        '}\n',
      );
      expect(result.diagnostics, isNotEmpty);
      expect(
        result.diagnostics.every(
          (ScriptDiagnostic diagnostic) => !diagnostic.isError,
        ),
        isTrue,
      );
      expect(result.diagnostics.single.message, contains('未连接'));
    });

    test('多节点链依边顺序发射', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text', params: <String, Object?>{'value': '第一'}),
          _node('n3', 'log.message'),
          _node('n4', 'value.text', params: <String, Object?>{'value': '第二'}),
          _node(
            'n5',
            'log.message',
            params: <String, Object?>{'level': 'warn'},
          ),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'message'),
          _edge('n3', 'out', 'n5', 'exec'),
          _edge('n4', 'result', 'n5', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(result.code, contains("    Write-Host '第一'\n"));
      expect(
        result.code,
        contains("    Write-Host ('[警告] ' + '第二') -ForegroundColor Yellow\n"),
      );
      expect(
        result.code!.indexOf("'第一'"),
        lessThan(result.code!.indexOf("'第二'")),
      );
    });
  });

  group('log.message 三个级别', () {
    test('默认级别 info', () {
      final String? code = _compile(_linearLogGraph(message: '开始构建')).code;
      expect(code, contains("Write-Host '开始构建'"));
    });

    test('warn 级别带黄色警告前缀', () {
      final String? code = _compile(
        _linearLogGraph(message: '注意', level: 'warn'),
      ).code;
      expect(
        code,
        contains("Write-Host ('[警告] ' + '注意') -ForegroundColor Yellow"),
      );
    });

    test('error 级别带红色错误前缀', () {
      final String? code = _compile(
        _linearLogGraph(message: '失败', level: 'error'),
      ).code;
      expect(
        code,
        contains("Write-Host ('[错误] ' + '失败') -ForegroundColor Red"),
      );
    });

    test('单引号转义与中文', () {
      final String? code = _compile(_linearLogGraph(message: "it's 中文")).code;
      expect(code, contains(r"Write-Host 'it''s 中文'"));
    });
  });

  group('控制流发射', () {
    test('分支：then/else 双链', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
          _node('n3', 'flow.branch'),
          _node('n4', 'value.text', params: <String, Object?>{'value': '满足'}),
          _node('n5', 'log.message'),
          _node('n6', 'value.text', params: <String, Object?>{'value': '不满足'}),
          _node('n7', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'condition'),
          _edge('n3', 'then', 'n5', 'exec'),
          _edge('n4', 'result', 'n5', 'message'),
          _edge('n3', 'else', 'n7', 'exec'),
          _edge('n6', 'result', 'n7', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    if (\$true) {\n'
          "        Write-Host '满足'\n"
          '    } else {\n'
          "        Write-Host '不满足'\n"
          '    }\n',
        ),
      );
    });

    test('分支：空 else 输出空块', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
          _node('n3', 'flow.branch'),
          _node('n4', 'value.text', params: <String, Object?>{'value': '满足'}),
          _node('n5', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'condition'),
          _edge('n3', 'then', 'n5', 'exec'),
          _edge('n4', 'result', 'n5', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    if (\$true) {\n'
          "        Write-Host '满足'\n"
          '    } else {\n'
          '    }\n',
        ),
      );
    });

    test('分支：空 then 输出空块', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
          _node('n3', 'flow.branch'),
          _node('n4', 'value.text', params: <String, Object?>{'value': '不满足'}),
          _node('n5', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'condition'),
          _edge('n3', 'else', 'n5', 'exec'),
          _edge('n4', 'result', 'n5', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    if (\$true) {\n'
          '    } else {\n'
          "        Write-Host '不满足'\n"
          '    }\n',
        ),
      );
    });

    test('分支：两个出口均未连接时输出双空块并保留警告', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
          _node('n3', 'flow.branch'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'condition'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    if (\$true) {\n'
          '    } else {\n'
          '    }\n',
        ),
      );
      expect(
        result.diagnostics.any(
          (ScriptDiagnostic diagnostic) =>
              !diagnostic.isError && diagnostic.message.contains('两个出口均未连接'),
        ),
        isTrue,
      );
    });

    test('foreach：循环体与 completed 后继续链', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\in'},
          ),
          _node('n3', 'file.list'),
          _node('n4', 'flow.foreach'),
          _node('n5', 'log.message'),
          _node('n6', 'value.text', params: <String, Object?>{'value': '完成'}),
          _node('n7', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n3', 'directory'),
          _edge('n3', 'result', 'n4', 'list'),
          _edge('n4', 'body', 'n5', 'exec'),
          _edge('n4', 'item', 'n5', 'message'),
          _edge('n4', 'completed', 'n7', 'exec'),
          _edge('n6', 'result', 'n7', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    foreach (\$item_1 in @(Get-ChildItem -LiteralPath 'C:\\in' -File | Select-Object -ExpandProperty FullName)) {\n"
          '        Write-Host \$item_1\n'
          '    }\n'
          "    Write-Host '完成'\n",
        ),
      );
    });

    test('while：条件内联与 completed 后继续链', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
          _node('n3', 'flow.while'),
          _node('n4', 'value.text', params: <String, Object?>{'value': '循环体'}),
          _node('n5', 'log.message'),
          _node('n6', 'value.text', params: <String, Object?>{'value': '完成'}),
          _node('n7', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'condition'),
          _edge('n3', 'body', 'n5', 'exec'),
          _edge('n4', 'result', 'n5', 'message'),
          _edge('n3', 'completed', 'n7', 'exec'),
          _edge('n6', 'result', 'n7', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    while (\$true) {\n'
          "        Write-Host '循环体'\n"
          '    }\n'
          "    Write-Host '完成'\n",
        ),
      );
    });

    test('嵌套：foreach 体内含 branch', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\src'},
          ),
          _node('n3', 'file.list'),
          _node('n4', 'flow.foreach'),
          _node('n5', 'flow.branch'),
          _node(
            'n6',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
          _node('n7', 'log.message'),
          _node('n8', 'value.text', params: <String, Object?>{'value': '跳过'}),
          _node('n9', 'log.message'),
          _node('n10', 'value.text', params: <String, Object?>{'value': '完成'}),
          _node('n11', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n3', 'directory'),
          _edge('n3', 'result', 'n4', 'list'),
          _edge('n4', 'body', 'n5', 'exec'),
          _edge('n6', 'result', 'n5', 'condition'),
          _edge('n5', 'then', 'n7', 'exec'),
          _edge('n4', 'item', 'n7', 'message'),
          _edge('n5', 'else', 'n9', 'exec'),
          _edge('n8', 'result', 'n9', 'message'),
          _edge('n4', 'completed', 'n11', 'exec'),
          _edge('n10', 'result', 'n11', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    foreach (\$item_1 in @(Get-ChildItem -LiteralPath 'C:\\src' -File | Select-Object -ExpandProperty FullName)) {\n"
          '        if (\$true) {\n'
          '            Write-Host \$item_1\n'
          '        } else {\n'
          "            Write-Host '跳过'\n"
          '        }\n'
          '    }\n'
          "    Write-Host '完成'\n",
        ),
      );
    });

    test('循环变量唯一化：两个 foreach → \$item_1 / \$item_2', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a'},
          ),
          _node('n3', 'file.list'),
          _node('n4', 'flow.foreach'),
          _node('n5', 'log.message'),
          _node(
            'n6',
            'value.text',
            params: <String, Object?>{'value': r'C:\b'},
          ),
          _node(
            'n7',
            'file.list',
            params: <String, Object?>{'filter': '*.dll', 'recursive': true},
          ),
          _node('n8', 'flow.foreach'),
          _node('n9', 'log.message'),
          _node('n10', 'value.text', params: <String, Object?>{'value': '双完成'}),
          _node('n11', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n3', 'directory'),
          _edge('n3', 'result', 'n4', 'list'),
          _edge('n4', 'body', 'n5', 'exec'),
          _edge('n4', 'item', 'n5', 'message'),
          _edge('n4', 'completed', 'n8', 'exec'),
          _edge('n6', 'result', 'n7', 'directory'),
          _edge('n7', 'result', 'n8', 'list'),
          _edge('n8', 'body', 'n9', 'exec'),
          _edge('n8', 'item', 'n9', 'message'),
          _edge('n8', 'completed', 'n11', 'exec'),
          _edge('n10', 'result', 'n11', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    foreach (\$item_1 in @(Get-ChildItem -LiteralPath 'C:\\a' -File | Select-Object -ExpandProperty FullName)) {\n"
          '        Write-Host \$item_1\n'
          '    }\n'
          "    foreach (\$item_2 in @(Get-ChildItem -LiteralPath 'C:\\b' -Filter '*.dll' -Recurse -File | Select-Object -ExpandProperty FullName)) {\n"
          '        Write-Host \$item_2\n'
          '    }\n'
          "    Write-Host '双完成'\n",
        ),
      );
    });
  });

  group('编译错误', () {
    test('无入口图 → code 为 null 且含诊断', () {
      final ScriptCompileResult result = _compile(
        _project(<ScriptNodeModel>[
          _node('n2', 'value.text', params: <String, Object?>{'value': 'x'}),
        ]),
      );
      expect(result.code, isNull);
      expect(result.hasErrors, isTrue);
      expect(
        result.diagnostics.any(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.isError && diagnostic.message.contains('「开始」'),
        ),
        isTrue,
      );
    });

    test('必填输入未连接 → code 为 null 且含诊断', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[_edge('n1', 'out', 'n2', 'exec')],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.code, isNull);
      expect(result.hasErrors, isTrue);
      expect(
        result.diagnostics.any(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.isError && diagnostic.message.contains('消息'),
        ),
        isTrue,
      );
    });

    test('错误图返回全部校验诊断（与校验器一致，含警告）', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'log.message'),
          _node(
            'n3',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
        ],
        edges: <ScriptEdgeModel>[_edge('n1', 'out', 'n2', 'exec')],
      );
      final List<ScriptDiagnostic> expected = GraphValidator.validate(project);
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isTrue);
      expect(result.diagnostics.length, expected.length);
      expect(
        result.diagnostics.map((ScriptDiagnostic d) => d.message),
        expected.map((ScriptDiagnostic d) => d.message),
      );
    });

    test('未实现节点类型按扩展点抛出（T5 边界，T6/T7/T8 补齐后替换）', () {
      final ScriptProjectModel execBoundary = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': 'C:\\a'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': 'D:\\b'},
          ),
          _node('n4', 'file.copy'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'source'),
          _edge('n3', 'result', 'n4', 'destination'),
        ],
      );
      expect(() => _compile(execBoundary), throwsUnsupportedError);

      final ScriptProjectModel dataBoundary = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'context.macro',
            params: <String, Object?>{'macro': 'OutDir'},
          ),
          _node('n3', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'message'),
        ],
      );
      expect(() => _compile(dataBoundary), throwsUnsupportedError);
    });
  });
}
