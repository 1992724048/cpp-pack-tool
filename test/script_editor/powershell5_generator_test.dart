import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/code_writer.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/prelude.dart';
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

/// math 二元节点真实消费链：value.number(a) → 节点.a、value.number(b) → 节点.b，
/// number 输出经 math.numberToString 转文本后写入 log.message。
ScriptProjectModel _mathBinaryGraph({
  required String typeKey,
  required num a,
  required num b,
  String? operator,
}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.number', params: <String, Object?>{'value': a}),
      _node('n3', 'value.number', params: <String, Object?>{'value': b}),
      _node(
        'n4',
        typeKey,
        params: operator == null
            ? null
            : <String, Object?>{'operator': operator},
      ),
      _node('n5', 'math.numberToString'),
      _node('n6', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n6', 'exec'),
      _edge('n2', 'result', 'n4', 'a'),
      _edge('n3', 'result', 'n4', 'b'),
      _edge('n4', 'result', 'n5', 'value'),
      _edge('n5', 'result', 'n6', 'message'),
    ],
  );
}

/// math 一元数值节点真实消费链：value.number(value) → 节点.value →
/// numberToString → log.message。
ScriptProjectModel _mathUnaryGraph({
  required String typeKey,
  required num value,
}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.number', params: <String, Object?>{'value': value}),
      _node('n3', typeKey),
      _node('n4', 'math.numberToString'),
      _node('n5', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n5', 'exec'),
      _edge('n2', 'result', 'n3', 'value'),
      _edge('n3', 'result', 'n4', 'value'),
      _edge('n4', 'result', 'n5', 'message'),
    ],
  );
}

/// 文本转数值消费链：value.text(text) → stringToNumber → numberToString → log.message。
ScriptProjectModel _stringToNumberGraph({required String text}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': text}),
      _node('n3', 'math.stringToNumber'),
      _node('n4', 'math.numberToString'),
      _node('n5', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n5', 'exec'),
      _edge('n2', 'result', 'n3', 'value'),
      _edge('n3', 'result', 'n4', 'value'),
      _edge('n4', 'result', 'n5', 'message'),
    ],
  );
}

/// 数值比较真实消费链：value.number(a/b) → logic.compareNumber →
/// flow.branch 条件（operator 缺省时走注册表默认 `lt`）。
ScriptProjectModel _compareNumberGraph({
  String? operator,
  num a = 3,
  num b = 5,
}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.number', params: <String, Object?>{'value': a}),
      _node('n3', 'value.number', params: <String, Object?>{'value': b}),
      _node(
        'n4',
        'logic.compareNumber',
        params: <String, Object?>{'operator': ?operator},
      ),
      _node('n5', 'flow.branch'),
      _node('n6', 'value.text', params: <String, Object?>{'value': '小于'}),
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

/// Base64 编码真实消费链：value.text(path) → base64Encode → log.message。
ScriptProjectModel _base64EncodeGraph({String path = r'C:\x.bin'}) {
  return _dataLogGraph(
    _node('n4', 'crypto.base64Encode'),
    inputs: <ScriptNodeModel>[
      _node('n2', 'value.text', params: <String, Object?>{'value': path}),
    ],
    inputEdges: <ScriptEdgeModel>[_edge('n2', 'result', 'n4', 'path')],
  );
}

/// 文件哈希真实消费链：value.text(path) → fileHash（缺省走注册表默认 sha256）→
/// log.message。
ScriptProjectModel _fileHashGraph({
  String? algorithm,
  String path = r'C:\x.bin',
}) {
  return _dataLogGraph(
    _node(
      'n4',
      'crypto.fileHash',
      params: algorithm == null
          ? null
          : <String, Object?>{'algorithm': algorithm},
    ),
    inputs: <ScriptNodeModel>[
      _node('n2', 'value.text', params: <String, Object?>{'value': path}),
    ],
    inputEdges: <ScriptEdgeModel>[_edge('n2', 'result', 'n4', 'path')],
  );
}

/// AES 加/解密真实执行链：value.text(source/destination) → aes 节点 →
/// log.message（口令参数在节点 params 上提供）。
ScriptProjectModel _aesGraph({
  required String typeKey,
  String? password,
  String? passwordEnv,
  String source = r'C:\a.bin',
  String destination = r'D:\b.bin',
}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': source}),
      _node(
        'n3',
        'value.text',
        params: <String, Object?>{'value': destination},
      ),
      _node(
        'n4',
        typeKey,
        params: <String, Object?>{
          'password': ?password,
          'passwordEnv': ?passwordEnv,
        },
      ),
      _node('n5', 'value.text', params: <String, Object?>{'value': '已处理'}),
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
}

/// 代码签名真实执行链：value.text(path) → signFile → value.text → log.message。
ScriptProjectModel _signFileGraph({
  String? pfxPath,
  String? thumbprint,
  String? password,
  String? passwordEnv,
  String? timestampServer,
  String path = r'C:\app.exe',
}) {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': path}),
      _node(
        'n3',
        'crypto.signFile',
        params: <String, Object?>{
          'pfxPath': ?pfxPath,
          'thumbprint': ?thumbprint,
          'password': ?password,
          'passwordEnv': ?passwordEnv,
          'timestampServer': ?timestampServer,
        },
      ),
      _node('n4', 'value.text', params: <String, Object?>{'value': '已签名'}),
      _node('n5', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n3', 'exec'),
      _edge('n2', 'result', 'n3', 'path'),
      _edge('n3', 'out', 'n5', 'exec'),
      _edge('n4', 'result', 'n5', 'message'),
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
      // 指数记法仅在 VM 定界外出现：`e+` 归一为 `e`（canonical 形式）
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

    test('防御收紧：非有限值被校验阻断生成（生成器侧回退 0 为纵深防御）', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.number',
            params: <String, Object?>{'value': double.infinity},
          ),
          _node('n3', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n3', 'exec'),
          _edge('n2', 'result', 'n3', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isTrue);
      expect(result.code, isNull);
      expect(
        result.diagnostics.any(
          (ScriptDiagnostic diagnostic) =>
              diagnostic.isError &&
              diagnostic.nodeId == 'n2' &&
              diagnostic.message.contains('必须为数字'),
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

  group('math 节点发射（M4.2 T3）', () {
    test('math.arithmetic：add 默认，value.number 字面量真实消费链', () {
      final ScriptCompileResult leftLiteral = _compile(
        _mathBinaryGraph(typeKey: 'math.arithmetic', a: 3, b: 5),
      );
      expect(leftLiteral.hasErrors, isFalse);
      expect(
        leftLiteral.code,
        contains(
          '    Write-Host (Convert.ToString((3 + 5), '
          '[Globalization.CultureInfo]::InvariantCulture))\n',
        ),
      );

      // value.number(3) → math.arithmetic(b)：右操作数亦为真实字面量
      final ScriptCompileResult rightLiteral = _compile(
        _mathBinaryGraph(typeKey: 'math.arithmetic', a: 10, b: 3),
      );
      expect(rightLiteral.hasErrors, isFalse);
      expect(rightLiteral.code, contains('(10 + 3)'));
    });

    test('math.arithmetic：五种运算符映射', () {
      const Map<String, String> symbols = <String, String>{
        'add': '+',
        'subtract': '-',
        'multiply': '*',
        'divide': '/',
        'modulo': '%',
      };
      for (final MapEntry<String, String> entry in symbols.entries) {
        final ScriptCompileResult result = _compile(
          _mathBinaryGraph(
            typeKey: 'math.arithmetic',
            a: 6,
            b: 4,
            operator: entry.key,
          ),
        );
        expect(result.hasErrors, isFalse, reason: entry.key);
        expect(
          result.code,
          contains('(6 ${entry.value} 4)'),
          reason: entry.key,
        );
      }
    });

    test('math.bitwise：and 默认与 shiftLeft 显式 Int64 定宽', () {
      final ScriptCompileResult andResult = _compile(
        _mathBinaryGraph(typeKey: 'math.bitwise', a: 12, b: 10),
      );
      expect(andResult.hasErrors, isFalse);
      expect(
        andResult.code,
        contains(
          '    Write-Host (Convert.ToString(([long](12) -band [long](10)), '
          '[Globalization.CultureInfo]::InvariantCulture))\n',
        ),
      );

      final ScriptCompileResult shiftResult = _compile(
        _mathBinaryGraph(
          typeKey: 'math.bitwise',
          a: 1,
          b: 4,
          operator: 'shiftLeft',
        ),
      );
      expect(shiftResult.hasErrors, isFalse);
      expect(shiftResult.code, contains('([long](1) -shl [long](4))'));
    });

    test('math.bitwise：or / xor / shiftRight 映射', () {
      expect(
        _compile(
          _mathBinaryGraph(typeKey: 'math.bitwise', a: 1, b: 2, operator: 'or'),
        ).code,
        contains('([long](1) -bor [long](2))'),
      );
      expect(
        _compile(
          _mathBinaryGraph(
            typeKey: 'math.bitwise',
            a: 1,
            b: 2,
            operator: 'xor',
          ),
        ).code,
        contains('([long](1) -bxor [long](2))'),
      );
      expect(
        _compile(
          _mathBinaryGraph(
            typeKey: 'math.bitwise',
            a: 8,
            b: 2,
            operator: 'shiftRight',
          ),
        ).code,
        contains('([long](8) -shr [long](2))'),
      );
    });

    test('math.bitNot：数值真实消费链（-bnot [long]）', () {
      final ScriptCompileResult result = _compile(
        _mathUnaryGraph(typeKey: 'math.bitNot', value: 7),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    Write-Host (Convert.ToString((-bnot [long](7)), '
          '[Globalization.CultureInfo]::InvariantCulture))\n',
        ),
      );
    });

    test('math.numberToString：数值转文本（InvariantCulture）', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'math.numberToString'),
          inputs: <ScriptNodeModel>[
            _node('n2', 'value.number', params: <String, Object?>{'value': 5}),
          ],
          inputEdges: <ScriptEdgeModel>[_edge('n2', 'result', 'n4', 'value')],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          '    Write-Host (Convert.ToString(5, '
          '[Globalization.CultureInfo]::InvariantCulture))\n',
        ),
      );
    });

    test('math.stringToNumber：文本转数值（[double]::Parse）', () {
      final ScriptCompileResult result = _compile(
        _stringToNumberGraph(text: '3.5'),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Write-Host (Convert.ToString(([double]::Parse('3.5', "
          '[Globalization.CultureInfo]::InvariantCulture)), '
          '[Globalization.CultureInfo]::InvariantCulture))\n',
        ),
      );
    });
  });

  group('string.upperCase 与 logic.compareNumber 发射（M4.2 T4）', () {
    test('string.upperCase：ToUpperInvariant（value.text 真实消费链）', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n4', 'string.upperCase'),
          inputs: <ScriptNodeModel>[
            _node(
              'n2',
              'value.text',
              params: <String, Object?>{'value': 'abc'},
            ),
          ],
          inputEdges: <ScriptEdgeModel>[_edge('n2', 'result', 'n4', 'value')],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host ('abc'.ToUpperInvariant())\n"),
      );
    });

    test('string.upperCase：upperCase(concat) 组合链递归内联', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node('n2', 'value.text', params: <String, Object?>{'value': 'a'}),
          _node('n3', 'value.text', params: <String, Object?>{'value': 'B'}),
          _node('n4', 'string.concat'),
          _node('n5', 'string.upperCase'),
          _node('n6', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n6', 'exec'),
          _edge('n2', 'result', 'n4', 'a'),
          _edge('n3', 'result', 'n4', 'b'),
          _edge('n4', 'result', 'n5', 'value'),
          _edge('n5', 'result', 'n6', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains("    Write-Host (('a' + 'B').ToUpperInvariant())\n"),
      );
    });

    test('logic.compareNumber：六种运算符映射（number 字面量真实消费链）', () {
      const Map<String, String> operators = <String, String>{
        'lt': '-lt',
        'le': '-le',
        'gt': '-gt',
        'ge': '-ge',
        'eq': '-eq',
        'ne': '-ne',
      };
      for (final MapEntry<String, String> entry in operators.entries) {
        final ScriptCompileResult result = _compile(
          _compareNumberGraph(operator: entry.key, a: 6, b: 4),
        );
        expect(result.hasErrors, isFalse, reason: entry.key);
        expect(
          result.code,
          contains('    if ((6 ${entry.value} 4)) {\n'),
          reason: entry.key,
        );
      }
    });

    test('logic.compareNumber：缺省参数走注册表默认 lt', () {
      final ScriptCompileResult result = _compile(_compareNumberGraph());
      expect(result.hasErrors, isFalse);
      expect(result.code, contains('    if ((3 -lt 5)) {\n'));
    });
  });

  group('file 硬链接与十六进制发射（M4.2 T5）', () {
    test('file.hardLink：创建硬链接命令并续接 out 链', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\src\a.dll'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': r'D:\dst\a.dll'},
          ),
          _node('n4', 'file.hardLink'),
          _node('n5', 'value.text', params: <String, Object?>{'value': '已创建'}),
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
          "    New-Item -ItemType HardLink -Path 'D:\\dst\\a.dll' "
          "-Target 'C:\\src\\a.dll' -Force -ErrorAction Stop\n"
          "    Write-Host '已创建'\n",
        ),
      );
    });

    test('file.readHex：十六进制字符串表达式内联进消费链', () {
      final ScriptCompileResult result = _compile(
        _dataLogGraph(
          _node('n2', 'file.readHex'),
          inputs: <ScriptNodeModel>[
            _node(
              'n3',
              'value.text',
              params: <String, Object?>{'value': r'C:\x.bin'},
            ),
          ],
          inputEdges: <ScriptEdgeModel>[_edge('n3', 'result', 'n2', 'path')],
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Write-Host ([BitConverter]::ToString("
          "[IO.File]::ReadAllBytes('C:\\x.bin'))"
          ".Replace('-','').ToLowerInvariant())\n",
        ),
      );
    });

    test('file.writeHex：WriteAllBytes + ConvertFrom-CnpHex 并自动注入 helper', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\x.bin'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': '48656C6C6F'},
          ),
          _node('n4', 'file.writeHex'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'path'),
          _edge('n3', 'result', 'n4', 'hex'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        code,
        contains(
          "    [IO.File]::WriteAllBytes('C:\\x.bin', "
          "(ConvertFrom-CnpHex ('48656C6C6F')))\n",
        ),
      );
      expect(
        RegExp(r'function ConvertFrom-CnpHex \{').allMatches(code).length,
        1,
      );
      final int stopIndex = code.indexOf(r"$ErrorActionPreference = 'Stop'");
      final int functionIndex = code.indexOf('function ConvertFrom-CnpHex {');
      final int tryIndex = code.indexOf('\n\ntry {\n');
      expect(stopIndex, lessThan(functionIndex));
      expect(functionIndex, lessThan(tryIndex));
      expect(code, contains("throw '十六进制字符串长度必须为偶数'"));
      expect(code, contains("throw '十六进制字符串包含非法字符'"));
      expect(code, isNot(contains('function Get-CnpFileHash {')));
    });

    test('file.writeHex：readHex 输出作为 hex 输入递归内联（往返链）', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a.bin'},
          ),
          _node('n3', 'file.readHex'),
          _node(
            'n4',
            'value.text',
            params: <String, Object?>{'value': r'D:\b.bin'},
          ),
          _node('n5', 'file.writeHex'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n5', 'exec'),
          _edge('n2', 'result', 'n3', 'path'),
          _edge('n3', 'result', 'n5', 'hex'),
          _edge('n4', 'result', 'n5', 'path'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    [IO.File]::WriteAllBytes('D:\\b.bin', (ConvertFrom-CnpHex "
          "(([BitConverter]::ToString([IO.File]::ReadAllBytes('C:\\a.bin'))"
          ".Replace('-','').ToLowerInvariant()))))\n",
        ),
      );
    });

    test('file.writeHex 幂等：两个节点仅注入一次 helper', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a.bin'},
          ),
          _node('n3', 'value.text', params: <String, Object?>{'value': 'AA'}),
          _node('n4', 'file.writeHex'),
          _node(
            'n5',
            'value.text',
            params: <String, Object?>{'value': r'C:\b.bin'},
          ),
          _node('n6', 'value.text', params: <String, Object?>{'value': 'BB'}),
          _node('n7', 'file.writeHex'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'path'),
          _edge('n3', 'result', 'n4', 'hex'),
          _edge('n4', 'out', 'n7', 'exec'),
          _edge('n5', 'result', 'n7', 'path'),
          _edge('n6', 'result', 'n7', 'hex'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        RegExp(r'function ConvertFrom-CnpHex \{').allMatches(code).length,
        1,
      );
      expect(
        code,
        contains(
          "    [IO.File]::WriteAllBytes('C:\\a.bin', "
          "(ConvertFrom-CnpHex ('AA')))\n",
        ),
      );
      expect(
        code,
        contains(
          "    [IO.File]::WriteAllBytes('C:\\b.bin', "
          "(ConvertFrom-CnpHex ('BB')))\n",
        ),
      );
    });
  });

  group('crypto 节点发射（M4.2 T6）', () {
    test('crypto.base64Encode：ToBase64String(ReadAllBytes) 表达式内联进消费链', () {
      final ScriptCompileResult result = _compile(_base64EncodeGraph());
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Write-Host ([Convert]::ToBase64String("
          "[IO.File]::ReadAllBytes('C:\\x.bin')))\n",
        ),
      );
      // 二进制语义：经 ReadAllBytes 读取，不得用 Get-Content 类文本读取
      expect(result.code, isNot(contains('Get-Content')));
    });

    test('crypto.base64Decode：FromBase64String + WriteAllBytes 并续接 out 链', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': 'SGVsbG8='},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': r'D:\out.bin'},
          ),
          _node('n4', 'crypto.base64Decode'),
          _node('n5', 'value.text', params: <String, Object?>{'value': '已写入'}),
          _node('n6', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'text'),
          _edge('n3', 'result', 'n4', 'path'),
          _edge('n4', 'out', 'n6', 'exec'),
          _edge('n5', 'result', 'n6', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    [IO.File]::WriteAllBytes('D:\\out.bin', "
          "[Convert]::FromBase64String('SGVsbG8='))\n"
          "    Write-Host '已写入'\n",
        ),
      );
      // 非法 Base64 由 [Convert]::FromBase64String 运行时抛错（EAP=Stop）；
      // 发射不预置额外校验、不注入任何 helper
      expect(result.code, isNot(contains('function Get-CnpFileHash {')));
      expect(result.code, isNot(contains('ConvertFrom-CnpHex')));
    });

    test('crypto.base64Encode → base64Decode：编码解码往返链递归内联', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a.bin'},
          ),
          _node('n3', 'crypto.base64Encode'),
          _node(
            'n4',
            'value.text',
            params: <String, Object?>{'value': r'D:\b.bin'},
          ),
          _node('n5', 'crypto.base64Decode'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n5', 'exec'),
          _edge('n2', 'result', 'n3', 'path'),
          _edge('n3', 'result', 'n5', 'text'),
          _edge('n4', 'result', 'n5', 'path'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    [IO.File]::WriteAllBytes('D:\\b.bin', "
          "[Convert]::FromBase64String(([Convert]::ToBase64String("
          "[IO.File]::ReadAllBytes('C:\\a.bin')))))\n",
        ),
      );
    });

    test('crypto.fileHash：sha256（缺省）注入 helper 且无 crc32 注入块', () {
      final ScriptCompileResult result = _compile(_fileHashGraph());
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        code,
        contains(
          "    Write-Host (Get-CnpFileHash -Path 'C:\\x.bin' "
          "-Algorithm 'sha256')\n",
        ),
      );
      expect(RegExp(r'function Get-CnpFileHash \{').allMatches(code).length, 1);
      final int stopIndex = code.indexOf(r"$ErrorActionPreference = 'Stop'");
      final int functionIndex = code.indexOf('function Get-CnpFileHash {');
      final int tryIndex = code.indexOf('\n\ntry {\n');
      expect(stopIndex, lessThan(functionIndex));
      expect(functionIndex, lessThan(tryIndex));
      // 非 crc32 算法不得注入 Add-Type 块（helper 体内的 crc32 分支不执行）
      expect(code, isNot(contains('PSTypeName')));
      expect(code, isNot(contains('Add-Type')));
      expect(code, isNot(contains('public static class CnpCrc32')));
    });

    test('crypto.fileHash：crc32 注入 CnpCrc32 块（PSTypeName 守卫）', () {
      final ScriptCompileResult result = _compile(
        _fileHashGraph(algorithm: 'crc32'),
      );
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        code,
        contains(
          "    Write-Host (Get-CnpFileHash -Path 'C:\\x.bin' "
          "-Algorithm 'crc32')\n",
        ),
      );
      expect(RegExp(r'function Get-CnpFileHash \{').allMatches(code).length, 1);
      expect(code, contains('[CnpCrc32]::Hash'));
      expect(
        code,
        contains("[System.Management.Automation.PSTypeName]'CnpCrc32'"),
      );
      expect(code, contains('Add-Type -TypeDefinition'));
      expect(code, contains('public static class CnpCrc32'));
      final int functionIndex = code.indexOf('function Get-CnpFileHash {');
      final int crc32Index = code.indexOf('PSTypeName');
      final int tryIndex = code.indexOf('\n\ntry {\n');
      expect(functionIndex, lessThan(crc32Index));
      expect(crc32Index, lessThan(tryIndex));
    });

    test('crypto.fileHash：sha1 / sha512 / md5 参数映射透传', () {
      for (final String algorithm in <String>['sha1', 'sha512', 'md5']) {
        final ScriptCompileResult result = _compile(
          _fileHashGraph(algorithm: algorithm),
        );
        expect(result.hasErrors, isFalse, reason: algorithm);
        expect(
          result.code,
          contains("-Algorithm '$algorithm')"),
          reason: algorithm,
        );
        expect(result.code, isNot(contains('PSTypeName')), reason: algorithm);
      }
    });

    test('crypto.fileHash 幂等：两节点（一个 crc32）各片段仅注册一次', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a.bin'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': r'C:\b.bin'},
          ),
          _node('n4', 'crypto.fileHash'),
          _node(
            'n5',
            'crypto.fileHash',
            params: <String, Object?>{'algorithm': 'crc32'},
          ),
          _node('n6', 'log.message'),
          _node('n7', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n6', 'exec'),
          _edge('n6', 'out', 'n7', 'exec'),
          _edge('n2', 'result', 'n4', 'path'),
          _edge('n3', 'result', 'n5', 'path'),
          _edge('n4', 'result', 'n6', 'message'),
          _edge('n5', 'result', 'n7', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(RegExp(r'function Get-CnpFileHash \{').allMatches(code).length, 1);
      expect(RegExp('PSTypeName').allMatches(code).length, 1);
      expect(RegExp('public static class CnpCrc32').allMatches(code).length, 1);
      expect(
        code,
        contains(
          "    Write-Host (Get-CnpFileHash -Path 'C:\\a.bin' "
          "-Algorithm 'sha256')\n",
        ),
      );
      expect(
        code,
        contains(
          "    Write-Host (Get-CnpFileHash -Path 'C:\\b.bin' "
          "-Algorithm 'crc32')\n",
        ),
      );
    });
  });

  group('crypto AES 与代码签名发射（M4.2 T7）', () {
    test('crypto.aesEncrypt：口令字面量、helper 注册与 out 链续接', () {
      final ScriptCompileResult result = _compile(
        _aesGraph(typeKey: 'crypto.aesEncrypt', password: 's3cret'),
      );
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        code,
        contains(
          "    Invoke-CnpAesTransform -Mode Encrypt -Source 'C:\\a.bin' "
          "-Destination 'D:\\b.bin' -Password 's3cret'\n"
          "    Write-Host '已处理'\n",
        ),
      );
      expect(
        RegExp(r'function Invoke-CnpAesTransform \{').allMatches(code).length,
        1,
      );
      final int functionIndex = code.indexOf(
        'function Invoke-CnpAesTransform {',
      );
      final int tryIndex = code.indexOf('\n\ntry {\n');
      expect(functionIndex, greaterThan(0));
      expect(functionIndex, lessThan(tryIndex));
    });

    test('crypto.aesEncrypt：passwordEnv 走 \$env:<名> 读取', () {
      final ScriptCompileResult result = _compile(
        _aesGraph(typeKey: 'crypto.aesEncrypt', passwordEnv: 'CNP_AES_KEY'),
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.code,
        contains(
          "    Invoke-CnpAesTransform -Mode Encrypt -Source 'C:\\a.bin' "
          "-Destination 'D:\\b.bin' -Password \$env:CNP_AES_KEY\n",
        ),
      );
    });

    test('crypto.aesEncrypt：password 与 passwordEnv 并存时字面量优先', () {
      final ScriptCompileResult result = _compile(
        _aesGraph(
          typeKey: 'crypto.aesEncrypt',
          password: 'fromParam',
          passwordEnv: 'CNP_AES_KEY',
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(result.code, contains("-Password 'fromParam'\n"));
      expect(result.code, isNot(contains(r'$env:CNP_AES_KEY')));
    });

    test('crypto.aesDecrypt：-Mode Decrypt 与 helper 注册', () {
      final ScriptCompileResult result = _compile(
        _aesGraph(typeKey: 'crypto.aesDecrypt', password: 's3cret'),
      );
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        code,
        contains(
          "    Invoke-CnpAesTransform -Mode Decrypt -Source 'C:\\a.bin' "
          "-Destination 'D:\\b.bin' -Password 's3cret'\n",
        ),
      );
      expect(
        RegExp(r'function Invoke-CnpAesTransform \{').allMatches(code).length,
        1,
      );
    });

    test('crypto.aesEncrypt 幂等：两个节点仅注入一次 helper', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a.bin'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': r'D:\b.bin'},
          ),
          _node(
            'n4',
            'crypto.aesEncrypt',
            params: <String, Object?>{'password': 'p1'},
          ),
          _node(
            'n5',
            'value.text',
            params: <String, Object?>{'value': r'D:\c.bin'},
          ),
          _node(
            'n6',
            'value.text',
            params: <String, Object?>{'value': r'E:\d.bin'},
          ),
          _node(
            'n7',
            'crypto.aesEncrypt',
            params: <String, Object?>{'passwordEnv': 'CNP_AES_KEY'},
          ),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'source'),
          _edge('n3', 'result', 'n4', 'destination'),
          _edge('n4', 'out', 'n7', 'exec'),
          _edge('n5', 'result', 'n7', 'source'),
          _edge('n6', 'result', 'n7', 'destination'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        RegExp(r'function Invoke-CnpAesTransform \{').allMatches(code).length,
        1,
      );
      expect(
        code,
        contains(
          "    Invoke-CnpAesTransform -Mode Encrypt -Source 'C:\\a.bin' "
          "-Destination 'D:\\b.bin' -Password 'p1'\n",
        ),
      );
      expect(
        code,
        contains(
          "    Invoke-CnpAesTransform -Mode Encrypt -Source 'D:\\c.bin' "
          "-Destination 'E:\\d.bin' -Password \$env:CNP_AES_KEY\n",
        ),
      );
    });

    test('crypto.signFile：PFX + 口令 + 时间戳全参数发射', () {
      final ScriptCompileResult result = _compile(
        _signFileGraph(
          pfxPath: r'C:\cert.pfx',
          password: 'pw',
          timestampServer: 'http://ts.example.com',
        ),
      );
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        code,
        contains(
          "    Invoke-CnpSignFile -Path 'C:\\app.exe' -PfxPath 'C:\\cert.pfx' "
          "-Password 'pw' -TimestampServer 'http://ts.example.com'\n"
          "    Write-Host '已签名'\n",
        ),
      );
      expect(
        RegExp(r'function Invoke-CnpSignFile \{').allMatches(code).length,
        1,
      );
      final int functionIndex = code.indexOf('function Invoke-CnpSignFile {');
      final int tryIndex = code.indexOf('\n\ntry {\n');
      expect(functionIndex, greaterThan(0));
      expect(functionIndex, lessThan(tryIndex));
    });

    test('crypto.signFile：指纹来源省略 PfxPath/Password，时间戳省略', () {
      final ScriptCompileResult result = _compile(
        _signFileGraph(thumbprint: 'ABCDEF0123'),
      );
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        code,
        contains(
          "    Invoke-CnpSignFile -Path 'C:\\app.exe' "
          "-Thumbprint 'ABCDEF0123'\n",
        ),
      );
      expect(code, isNot(contains('-PfxPath')));
      expect(code, isNot(contains('-Password')));
      expect(code, isNot(contains('-TimestampServer')));
    });

    test('crypto.signFile：passwordEnv 走 \$env:<名> 读取', () {
      final ScriptCompileResult result = _compile(
        _signFileGraph(thumbprint: 'ABCDEF0123', passwordEnv: 'CNP_SIGN_PWD'),
      );
      expect(result.hasErrors, isFalse);
      expect(result.code, contains("-Password \$env:CNP_SIGN_PWD\n"));
    });

    test('helper 门控：AES 图不注入签名 helper，签名图不注入 AES helper', () {
      final ScriptCompileResult aes = _compile(
        _aesGraph(typeKey: 'crypto.aesEncrypt', password: 'x'),
      );
      expect(aes.hasErrors, isFalse);
      expect(aes.code, isNot(contains('function Invoke-CnpSignFile {')));

      final ScriptCompileResult sign = _compile(
        _signFileGraph(pfxPath: 'cert.pfx'),
      );
      expect(sign.hasErrors, isFalse);
      expect(sign.code, isNot(contains('function Invoke-CnpAesTransform {')));
    });

    test('helper 顺序：同图 AES 与签名 helper 按 preludeOrder 各一次', () {
      final ScriptProjectModel project = _project(
        <ScriptNodeModel>[
          _node('n1', 'flow.entry'),
          _node(
            'n2',
            'value.text',
            params: <String, Object?>{'value': r'C:\a.bin'},
          ),
          _node(
            'n3',
            'value.text',
            params: <String, Object?>{'value': r'D:\b.bin'},
          ),
          _node(
            'n4',
            'crypto.aesEncrypt',
            params: <String, Object?>{'password': 'x'},
          ),
          _node(
            'n5',
            'value.text',
            params: <String, Object?>{'value': r'C:\app.exe'},
          ),
          _node(
            'n6',
            'crypto.signFile',
            params: <String, Object?>{'pfxPath': 'cert.pfx'},
          ),
          _node('n7', 'value.text', params: <String, Object?>{'value': '完成'}),
          _node('n8', 'log.message'),
        ],
        edges: <ScriptEdgeModel>[
          _edge('n1', 'out', 'n4', 'exec'),
          _edge('n2', 'result', 'n4', 'source'),
          _edge('n3', 'result', 'n4', 'destination'),
          _edge('n4', 'out', 'n6', 'exec'),
          _edge('n5', 'result', 'n6', 'path'),
          _edge('n6', 'out', 'n8', 'exec'),
          _edge('n7', 'result', 'n8', 'message'),
        ],
      );
      final ScriptCompileResult result = _compile(project);
      expect(result.hasErrors, isFalse);
      final String code = result.code!;
      expect(
        RegExp(r'function Invoke-CnpAesTransform \{').allMatches(code).length,
        1,
      );
      expect(
        RegExp(r'function Invoke-CnpSignFile \{').allMatches(code).length,
        1,
      );
      final int aesIndex = code.indexOf('function Invoke-CnpAesTransform {');
      final int signIndex = code.indexOf('function Invoke-CnpSignFile {');
      final int tryIndex = code.indexOf('\n\ntry {\n');
      expect(aesIndex, greaterThan(0));
      expect(signIndex, greaterThan(aesIndex));
      expect(signIndex, lessThan(tryIndex));
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

  group('prelude 机制（M4.2 T2）', () {
    const String m41LinearGolden =
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
        '}\n';

    test('零变化守护：无 prelude 时骨架与 M4.1 golden 逐字节一致', () {
      final ScriptCompileResult result = _compile(
        _linearLogGraph(message: '开始构建'),
      );
      expect(result.code, m41LinearGolden);
    });

    test('零变化守护：空收集器路径同样不注入任何片段', () {
      final ScriptCompileResult result = PowerShell5Generator()
          .compileWithPrelude(
            _linearLogGraph(message: '开始构建'),
            packName: 'demo',
            preludeCollector: (PreludeRegistrar register) {},
          );
      expect(result.code, m41LinearGolden);
    });

    test('注入位置：片段位于 Stop 之后、try { 之前，片段前后各空一行', () {
      final ScriptCompileResult result = PowerShell5Generator()
          .compileWithPrelude(
            _linearLogGraph(message: '开始构建'),
            packName: 'demo',
            preludeCollector: (PreludeRegistrar register) {
              register('ConvertFrom-CnpHex');
            },
          );
      final String code = result.code!;
      expect(result.hasErrors, isFalse);
      expect(
        code,
        contains(
          r"$ErrorActionPreference = 'Stop'"
          '\n\n'
          'function ConvertFrom-CnpHex {\n',
        ),
      );
      expect(code, contains('}\n\ntry {\n'));
      final int stopIndex = code.indexOf(r"$ErrorActionPreference = 'Stop'");
      final int functionIndex = code.indexOf('function ConvertFrom-CnpHex {');
      final int tryIndex = code.indexOf('\n\ntry {\n');
      expect(stopIndex, lessThan(functionIndex));
      expect(functionIndex, lessThan(tryIndex));
      expect(code, contains("    Write-Host '开始构建'\n"));
    });

    test('幂等：同键重复注册只注入一次', () {
      final ScriptCompileResult result = PowerShell5Generator()
          .compileWithPrelude(
            _linearLogGraph(message: '开始构建'),
            packName: 'demo',
            preludeCollector: (PreludeRegistrar register) {
              register('ConvertFrom-CnpHex');
              register('ConvertFrom-CnpHex');
              register('Get-CnpFileHash');
              register('Get-CnpFileHash');
            },
          );
      final String code = result.code!;
      expect(
        RegExp(r'function ConvertFrom-CnpHex \{').allMatches(code).length,
        1,
      );
      expect(RegExp(r'function Get-CnpFileHash \{').allMatches(code).length, 1);
    });

    test('顺序：按 preludeOrder 输出（注册逆序 + crc32/vars 动态键）', () {
      final ScriptCompileResult result = PowerShell5Generator()
          .compileWithPrelude(
            _linearLogGraph(message: '开始构建'),
            packName: 'demo',
            preludeCollector: (PreludeRegistrar register) {
              register('vars', content: r'$var_count = 0');
              register('crc32', content: crc32Prelude);
              register('Invoke-CnpSignFile');
              register('Get-CnpFileHash');
              register('ConvertFrom-CnpHex');
            },
          );
      final String code = result.code!;
      final int hexIndex = code.indexOf('function ConvertFrom-CnpHex {');
      final int hashIndex = code.indexOf('function Get-CnpFileHash {');
      final int signIndex = code.indexOf('function Invoke-CnpSignFile {');
      final int crc32Index = code.indexOf('PSTypeName');
      final int varsIndex = code.indexOf(r'$var_count = 0');
      expect(hexIndex, greaterThan(0));
      expect(hashIndex, greaterThan(hexIndex));
      expect(signIndex, greaterThan(hashIndex));
      expect(crc32Index, greaterThan(signIndex));
      expect(varsIndex, greaterThan(crc32Index));
    });

    test('crc32 动态块：content 覆盖注入且含 PSTypeName 守卫', () {
      final ScriptCompileResult result = PowerShell5Generator()
          .compileWithPrelude(
            _linearLogGraph(message: '开始构建'),
            packName: 'demo',
            preludeCollector: (PreludeRegistrar register) {
              register('crc32', content: crc32Prelude);
            },
          );
      final String code = result.code!;
      expect(code, contains('PSTypeName'));
      expect(code, contains('Add-Type -TypeDefinition'));
      expect(code, contains('public static class CnpCrc32'));
      expect(code.indexOf('PSTypeName'), lessThan(code.indexOf('\n\ntry {\n')));
    });

    test('未知键且无 content → ArgumentError（vars 内容由 M4.3 提供）', () {
      expect(
        () => PowerShell5Generator().compileWithPrelude(
          _linearLogGraph(message: '开始构建'),
          packName: 'demo',
          preludeCollector: (PreludeRegistrar register) => register('vars'),
        ),
        throwsArgumentError,
      );
    });

    test('content 含 CRLF 时归一化为 LF（片段行尾口径）', () {
      final ScriptCompileResult result = PowerShell5Generator()
          .compileWithPrelude(
            _linearLogGraph(message: '开始构建'),
            packName: 'demo',
            preludeCollector: (PreludeRegistrar register) {
              register('vars', content: r'$var_a = 0' '\r\n' r'$var_b = 0');
            },
          );
      final String code = result.code!;
      expect(code, isNot(contains('\r')));
      expect(code, contains(r'$var_a = 0' '\n' r'$var_b = 0'));
    });
  });
}
