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
