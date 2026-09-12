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

ScriptProjectModel _dataLogGraph(
  ScriptNodeModel dataNode, {
  List<ScriptNodeModel> inputs = const <ScriptNodeModel>[],
  List<ScriptEdgeModel> inputEdges = const <ScriptEdgeModel>[],
}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      ...inputs,
      dataNode,
      _node('n9', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n9', 'exec'),
      ...inputEdges,
      _edge(dataNode.id, 'result', 'n9', 'message'),
    ],
  );
}

ScriptProjectModel _compareStringGraph({
  String? operator,
  bool? ignoreCase,
  String a = 'a',
  String b = 'A',
}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': a}),
      _node('n3', 'value.text', params: <String, Object?>{'value': b}),
      _node(
        'n4',
        'logic.compareString',
        params: <String, Object?>{
          'operator': ?operator,
          'ignoreCase': ?ignoreCase,
        },
      ),
      _node('n5', 'flow.branch'),
      _node('n6', 'value.text', params: <String, Object?>{'value': '相等'}),
      _node('n7', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n5', 'exec'),
      _edge('n2', 'result', 'n4', 'a'),
      _edge('n3', 'result', 'n4', 'b'),
      _edge('n4', 'result', 'n5', 'condition'),
      _edge('n5', 'then', 'n7', 'exec'),
      _edge('n6', 'result', 'n7', 'message'),
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

  group('文件节点发射', () {
    test('file.copy：复制命令并续接 out 链', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': r'D:\b'},
          ),
          _node('n4', 'file.copy'),
          _node('n5', 'value.text', params: <String, Object?>{'value': '完成'}),
          _node('n6', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'source'),
          _edge('n3', 'result', 'n4', 'destination'),
          _edge('n4', 'out', 'n6', 'exec'),
          _edge('n5', 'result', 'n6', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Copy-Item -LiteralPath 'C:\\a' -Destination 'D:\\b' -Recurse -Force\n"
          "    Write-Host '完成'\n",
        ),
      );
    });

    test('file.move：移动命令', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': r'D:\b'},
          ),
          _node('n4', 'file.move'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'source'),
          _edge('n3', 'result', 'n4', 'destination'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Move-Item -LiteralPath 'C:\\a' -Destination 'D:\\b' -Force\n",
        ),
      );
    });

    test('file.delete：默认缺失时忽略，追加 -ErrorAction SilentlyContinue', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\x'},
          ),
          _node('n3', 'file.delete'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'path'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Remove-Item -LiteralPath 'C:\\x' -Recurse -Force "
          '-ErrorAction SilentlyContinue\n',
        ),
      );
    });

    test('file.delete：missingIgnored=false 时不追加静默参数', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\x'},
          ),
          _node(
            'n3',
            'file.delete',
            params: <String, Object?>{'missingIgnored': false},
          ),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'path'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Remove-Item -LiteralPath 'C:\\x' -Recurse -Force\n"),
      );
    });

    test('file.makeDirectory：创建目录命令', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\out'},
          ),
          _node('n3', 'file.makeDirectory'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'path'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    New-Item -ItemType Directory -Force -Path 'C:\\out'\n"),
      );
    });

    test('file.exists：布尔表达式内联进分支条件', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\x'},
          ),
          _node('n3', 'file.exists'),
          _node('n4', 'flow.branch'),
          _node('n5', 'value.text', params: <String, Object?>{'value': '存在'}),
          _node('n6', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n3', 'path'),
          _edge('n3', 'result', 'n4', 'condition'),
          _edge('n4', 'then', 'n6', 'exec'),
          _edge('n5', 'result', 'n6', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    if ((Test-Path -LiteralPath \'C:\\x\' -PathType Any)) {\n'
          "        Write-Host '存在'\n"
          '    } else {\n'
          '    }\n',
        ),
      );
    });
  });

  group('process.run 发射', () {
    test('默认（失败中断）：参数按行拆分并以数组 splatting 调用', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text', params: <String, Object?>{'value': 'cmd'}),
          _node('n3', 'value.text', params: <String, Object?>{'value': 'a'}),
          _node('n4', 'process.run'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'program'),
          _edge('n3', 'result', 'n4', 'arguments'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    \$proc_1 = \'cmd\'\n'
          '    \$args_1 = @(\'a\' -split "\\r?\\n" | '
          'Where-Object { \$_ -ne \'\' })\n'
          '    & \$proc_1 @args_1\n'
          '    if (\$LASTEXITCODE -ne 0) { throw "外部程序退出码 \$LASTEXITCODE" }\n',
        ),
      );
    });

    test('abortOnFailure=false：警告替代 throw，参数未连接为 @()', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': 'x.exe'},
          ),
          _node(
            'n3',
            'process.run',
            params: <String, Object?>{'abortOnFailure': false},
          ),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'program'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    \$proc_1 = \'x.exe\'\n'
          '    \$args_1 = @()\n'
          '    & \$proc_1 @args_1\n'
          "    Write-Host ('[警告] 外部程序退出码 ' + \$LASTEXITCODE) "
          '-ForegroundColor Yellow\n',
        ),
      );
    });

    test('工作目录已连接：Push-Location / Pop-Location 包裹调用行', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text', params: <String, Object?>{'value': 'cmd'}),
          _node('n3', 'value.text', params: <String, Object?>{'value': 'a'}),
          _node(
            'n4',
            'value.text',
            params: <String, Object?>{'value': r'C:\work'},
          ),
          _node('n5', 'process.run'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n5', 'exec'),
          _edge('n2', 'result', 'n5', 'program'),
          _edge('n3', 'result', 'n5', 'arguments'),
          _edge('n4', 'result', 'n5', 'workingDirectory'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    \$proc_1 = \'cmd\'\n'
          '    \$args_1 = @(\'a\' -split "\\r?\\n" | '
          'Where-Object { \$_ -ne \'\' })\n'
          "    Push-Location -LiteralPath 'C:\\work'\n"
          '    & \$proc_1 @args_1\n'
          '    Pop-Location\n'
          '    if (\$LASTEXITCODE -ne 0) { throw "外部程序退出码 \$LASTEXITCODE" }\n',
        ),
      );
    });

    test('多个运行节点：\$proc_N / \$args_N 按序递增且全局唯一', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text', params: <String, Object?>{'value': '一'}),
          _node('n3', 'process.run'),
          _node('n4', 'value.text', params: <String, Object?>{'value': '二'}),
          _node('n5', 'process.run'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'program'),
          _edge('n3', 'out', 'n5', 'exec'),
          _edge('n4', 'result', 'n5', 'program'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    \$proc_1 = \'一\'\n'
          '    \$args_1 = @()\n'
          '    & \$proc_1 @args_1\n'
          '    if (\$LASTEXITCODE -ne 0) { throw "外部程序退出码 \$LASTEXITCODE" }\n'
          '    \$proc_2 = \'二\'\n'
          '    \$args_2 = @()\n'
          '    & \$proc_2 @args_2\n'
          '    if (\$LASTEXITCODE -ne 0) { throw "外部程序退出码 \$LASTEXITCODE" }\n',
        ),
      );
    });
  });

  group('上下文节点发射', () {
    test('context.macro：未填写参数取注册表默认 OutDir', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(_node('n2', 'context.macro')),
      );
      expect(result.hasErrors, isFalse);
      expect(result.code, contains('    Write-Host \$env:CNP_OutDir\n'));
    });

    test('context.macro：宏键经 macroEnvName 映射（TargetPath）', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node(
            'n2',
            'context.macro',
            params: <String, Object?>{'macro': 'TargetPath'},
          ),
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(result.code, contains('    Write-Host \$env:CNP_TargetPath\n'));
    });

    test('context.environment：输出 \$env:<NAME>', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node(
            'n2',
            'context.environment',
            params: <String, Object?>{'name': 'PATH'},
          ),
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(result.code, contains('    Write-Host \$env:PATH\n'));
    });

    test('context.packageFile：包内相对路径 lib/x.lib → lib\\x.lib', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node(
            'n2',
            'context.packageFile',
            params: <String, Object?>{'path': 'lib/x.lib'},
          ),
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Write-Host (Join-Path \$env:CNP_PackageRoot 'lib\\x.lib')\n",
        ),
      );
    });

    test('context.packageFile：嵌套包内相对路径 sub/a.h → sub\\a.h', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node(
            'n2',
            'context.packageFile',
            params: <String, Object?>{'path': 'sub/a.h'},
          ),
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Write-Host (Join-Path \$env:CNP_PackageRoot 'sub\\a.h')\n",
        ),
      );
    });

    test('context.packageFile：files/scripts/task.bat 原样保留相对路径', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node(
            'n2',
            'context.packageFile',
            params: <String, Object?>{'path': 'files/scripts/task.bat'},
          ),
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Write-Host (Join-Path \$env:CNP_PackageRoot "
          "'files\\scripts\\task.bat')\n",
        ),
      );
    });
  });

  group('value.number 数字字面量', () {
    test('numberLiteral：int 直出，负值整体加括号', () {
      expect(numberLiteral(0), '0');
      expect(numberLiteral(5), '5');
      expect(numberLiteral(-5), '(-5)');
    });

    test('numberLiteral：double invariant 文本，`e+` 归一为 `e`', () {
      expect(numberLiteral(5.5), '5.5');
      expect(numberLiteral(-0.5), '(-0.5)');
      expect(numberLiteral(5.0), '5.0');
      // Dart VM 对 |指数| 有限值使用固定记法（与区域无关、无 e 记号）
      expect(numberLiteral(1e20), '100000000000000000000.0');
      expect(numberLiteral(1e-5), '0.00001');
      // 指数记法仅在 VM 定界外出现：`e+` 必须归一为 `e`（PS 5.1 字面量歧义）
      expect(numberLiteral(1e21), '1e21');
      expect(numberLiteral(-1e21), '(-1e21)');
      expect(numberLiteral(1e-7), '1e-7');
    });

    test('未消费 value.number：compile 成功、无错误诊断、保留未使用警告', () {
      final ScriptCompileResult result = _compile(
        _project(<ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.number'),
        ]),
      );
      expect(result.hasErrors, isFalse);
      expect(result.code, isNotNull);
      expect(
        result.diagnostics.any(
          (ScriptDiagnostic diagnostic) =>
              !diagnostic.isError && diagnostic.message.contains('未被使用'),
        ),
        isTrue,
      );
    });
  });

  group('字符串与路径节点发射', () {
    test('string.concat：双操作数相加并加括号', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'string.concat'),
          inputs: <ScriptNodeModel>[
            _node('n2', 'value.text', params: <String, Object?>{'value': 'a'}),
            _node('n3', 'value.text', params: <String, Object?>{'value': 'b'}),
          ],
          inputEdges: <ScriptEdgeModel>[
            _edge('n2', 'result', 'n4', 'a'),
            _edge('n3', 'result', 'n4', 'b'),
          ],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(result.code, contains("    Write-Host ('a' + 'b')\n"));
    });

    test('string.replace：字面替换（.Replace）', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'string.replace'),
          inputs: <ScriptNodeModel>[
            _node(
              'n2',
              'value.text',
              params: <String, Object?>{'value': 'a-b-c'},
            ),
            _node('n3', 'value.text', params: <String, Object?>{'value': '-'}),
            _node('n5', 'value.text', params: <String, Object?>{'value': '_'}),
          ],
          inputEdges: <ScriptEdgeModel>[
            _edge('n2', 'result', 'n4', 'input'),
            _edge('n3', 'result', 'n4', 'find'),
            _edge('n5', 'result', 'n4', 'replace'),
          ],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host ('a-b-c'.Replace('-', '_'))\n"),
      );
    });

    test('string.lowerCase：ToLowerInvariant', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'string.lowerCase'),
          inputs: <ScriptNodeModel>[
            _node(
              'n2',
              'value.text',
              params: <String, Object?>{'value': 'ABC'},
            ),
          ],
          inputEdges: <ScriptEdgeModel>[_edge('n2', 'result', 'n4', 'input')],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host ('ABC'.ToLowerInvariant())\n"),
      );
    });

    test('string.fileName：Split-Path -Leaf', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'string.fileName'),
          inputs: <ScriptNodeModel>[
            _node(
              'n2',
              'value.text',
              params: <String, Object?>{'value': r'C:\a\b.txt'},
            ),
          ],
          inputEdges: <ScriptEdgeModel>[_edge('n2', 'result', 'n4', 'path')],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host (Split-Path -Leaf 'C:\\a\\b.txt')\n"),
      );
    });

    test('string.directoryName：Split-Path -Parent', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'string.directoryName'),
          inputs: <ScriptNodeModel>[
            _node(
              'n2',
              'value.text',
              params: <String, Object?>{'value': r'C:\a\b.txt'},
            ),
          ],
          inputEdges: <ScriptEdgeModel>[_edge('n2', 'result', 'n4', 'path')],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host (Split-Path -Parent 'C:\\a\\b.txt')\n"),
      );
    });

    test('path.join：Join-Path 双操作数', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'path.join'),
          inputs: <ScriptNodeModel>[
            _node(
              'n2',
              'value.text',
              params: <String, Object?>{'value': r'C:\a'},
            ),
            _node(
              'n3',
              'value.text',
              params: <String, Object?>{'value': 'b.txt'},
            ),
          ],
          inputEdges: <ScriptEdgeModel>[
            _edge('n2', 'result', 'n4', 'left'),
            _edge('n3', 'result', 'n4', 'right'),
          ],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host (Join-Path 'C:\\a' 'b.txt')\n"),
      );
    });

    test('嵌套组合：lowerCase(concat) 递归内联加括号', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text', params: <String, Object?>{'value': 'A'}),
          _node('n3', 'value.text', params: <String, Object?>{'value': 'B'}),
          _node('n4', 'string.concat'),
          _node('n5', 'string.lowerCase'),
          _node('n6', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n6', 'exec'),
          _edge('n2', 'result', 'n4', 'a'),
          _edge('n3', 'result', 'n4', 'b'),
          _edge('n4', 'result', 'n5', 'input'),
          _edge('n5', 'result', 'n6', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host (('A' + 'B').ToLowerInvariant())\n"),
      );
    });
  });

  group('逻辑节点发射', () {
    test('logic.not：内联进分支条件', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.boolean',
            params: <String, Object?>{'value': true},
          ),
          _node('n3', 'logic.not'),
          _node('n4', 'flow.branch'),
          _node('n5', 'value.text', params: <String, Object?>{'value': '跳过'}),
          _node('n6', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n3', 'input'),
          _edge('n3', 'result', 'n4', 'condition'),
          _edge('n4', 'then', 'n6', 'exec'),
          _edge('n5', 'result', 'n6', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    if ((-not (\$true))) {\n'
          "        Write-Host '跳过'\n"
          '    } else {\n'
          '    }\n',
        ),
      );
    });

    test('logic.compareString：等于（大小写敏感，默认参数）→ -ceq', () {
      expect(
        _compile(_compareStringGraph()).code,
        contains("    if (('a' -ceq 'A')) {\n"),
      );
    });

    test('logic.compareString：不等于（大小写敏感）→ -cne', () {
      expect(
        _compile(_compareStringGraph(operator: 'ne', ignoreCase: false)).code,
        contains("    if (('a' -cne 'A')) {\n"),
      );
    });

    test('logic.compareString：包含（大小写敏感）→ .Contains', () {
      expect(
        _compile(
          _compareStringGraph(
            operator: 'contains',
            ignoreCase: false,
            a: 'Abc',
            b: 'b',
          ),
        ).code,
        contains("    if (('Abc'.Contains('b'))) {\n"),
      );
    });

    test('logic.compareString：等于（忽略大小写）→ -ieq', () {
      expect(
        _compile(_compareStringGraph(operator: 'eq', ignoreCase: true)).code,
        contains("    if (('a' -ieq 'A')) {\n"),
      );
    });

    test('logic.compareString：不等于（忽略大小写）→ -ine', () {
      expect(
        _compile(_compareStringGraph(operator: 'ne', ignoreCase: true)).code,
        contains("    if (('a' -ine 'A')) {\n"),
      );
    });

    test('logic.compareString：包含（忽略大小写）→ OrdinalIgnoreCase', () {
      expect(
        _compile(
          _compareStringGraph(
            operator: 'contains',
            ignoreCase: true,
            a: 'Abc',
            b: 'b',
          ),
        ).code,
        contains(
          "    if (('Abc'.IndexOf('b', "
          '[System.StringComparison]::OrdinalIgnoreCase) -ge 0)) {\n',
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
  });
}
