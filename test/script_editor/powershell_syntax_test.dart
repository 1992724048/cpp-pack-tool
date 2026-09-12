import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// ASCII 检查脚本：仅用 PowerShell 5.1 的 `Parser::ParseFile` 做语法解析，
/// 收集 `$parseErrors` 并在存在语法错误时打印消息、以非零退出码结束；不执行目标脚本。
const String _parseCheckScript = r'''param([string]$Path)
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { $parseErrors | ForEach-Object { Write-Output $_.Message }; exit 1 }
exit 0
''';

/// 故意缺失右花括号的脚本，供检查器自检。
const String _brokenScript = r'''if ($true) {
    Write-Output 'broken'
''';

final Object? _nonWindowsSkip = Platform.isWindows
    ? null
    : '仅 Windows 平台执行（依赖 powershell.exe 的 Parser::ParseFile）';

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
  String name = '语法夹具',
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

ScriptProjectModel _linearFixture() {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': r'C:\out'}),
      _node('n3', 'file.makeDirectory'),
      _node(
        'n4',
        'value.text',
        params: <String, Object?>{'value': r'C:\src\a.h'},
      ),
      _node(
        'n5',
        'value.text',
        params: <String, Object?>{'value': r'C:\out\a.h'},
      ),
      _node('n6', 'file.copy'),
      _node(
        'n7',
        'value.text',
        params: <String, Object?>{'value': r'C:\out\old.h'},
      ),
      _node('n8', 'file.delete'),
      _node(
        'n9',
        'value.text',
        params: <String, Object?>{'value': "it's 开始构建"},
      ),
      _node('n10', 'log.message', params: <String, Object?>{'level': 'warn'}),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n3', 'exec'),
      _edge('n2', 'result', 'n3', 'path'),
      _edge('n3', 'out', 'n6', 'exec'),
      _edge('n4', 'result', 'n6', 'source'),
      _edge('n5', 'result', 'n6', 'destination'),
      _edge('n6', 'out', 'n8', 'exec'),
      _edge('n7', 'result', 'n8', 'path'),
      _edge('n8', 'out', 'n10', 'exec'),
      _edge('n9', 'result', 'n10', 'message'),
    ],
    name: '线性夹具',
  );
}

ScriptProjectModel _nestedControlFlowFixture() {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': r'C:\src'}),
      _node(
        'n3',
        'file.list',
        params: <String, Object?>{'filter': '*.h', 'recursive': true},
      ),
      _node('n4', 'flow.foreach'),
      _node('n5', 'value.text', params: <String, Object?>{'value': 'report.h'}),
      _node('n6', 'value.text', params: <String, Object?>{'value': '.h'}),
      _node(
        'n7',
        'logic.compareString',
        params: <String, Object?>{'operator': 'contains', 'ignoreCase': true},
      ),
      _node('n8', 'flow.branch'),
      _node('n9', 'log.message'),
      _node('n10', 'value.text', params: <String, Object?>{'value': '跳过'}),
      _node('n11', 'log.message'),
      _node('n12', 'value.boolean', params: <String, Object?>{'value': false}),
      _node('n13', 'logic.not'),
      _node('n14', 'flow.while'),
      _node('n15', 'value.text', params: <String, Object?>{'value': '循环体'}),
      _node('n16', 'log.message'),
      _node('n17', 'value.text', params: <String, Object?>{'value': '循环完成'}),
      _node('n18', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n4', 'exec'),
      _edge('n2', 'result', 'n3', 'directory'),
      _edge('n3', 'result', 'n4', 'list'),
      _edge('n4', 'body', 'n8', 'exec'),
      _edge('n5', 'result', 'n7', 'a'),
      _edge('n6', 'result', 'n7', 'b'),
      _edge('n7', 'result', 'n8', 'condition'),
      _edge('n8', 'then', 'n9', 'exec'),
      _edge('n4', 'item', 'n9', 'message'),
      _edge('n8', 'else', 'n11', 'exec'),
      _edge('n10', 'result', 'n11', 'message'),
      _edge('n4', 'completed', 'n14', 'exec'),
      _edge('n12', 'result', 'n13', 'input'),
      _edge('n13', 'result', 'n14', 'condition'),
      _edge('n14', 'body', 'n16', 'exec'),
      _edge('n15', 'result', 'n16', 'message'),
      _edge('n14', 'completed', 'n18', 'exec'),
      _edge('n17', 'result', 'n18', 'message'),
    ],
    name: '嵌套控制流夹具',
  );
}

ScriptProjectModel _stringAndProcessFixture() {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.text', params: <String, Object?>{'value': 'tool.exe'}),
      _node(
        'n3',
        'value.text',
        params: <String, Object?>{'value': 'param=1\nverbose'},
      ),
      _node('n4', 'string.directoryName'),
      _node(
        'n5',
        'process.run',
        params: <String, Object?>{'abortOnFailure': false},
      ),
      _node('n6', 'string.replace'),
      _node('n7', 'string.fileName'),
      _node('n8', 'string.lowerCase'),
      _node('n9', 'value.text', params: <String, Object?>{'value': '.lib'}),
      _node('n10', 'value.text', params: <String, Object?>{'value': '.dll'}),
      _node('n11', 'path.join'),
      _node(
        'n12',
        'context.macro',
        params: <String, Object?>{'macro': 'OutDir'},
      ),
      _node('n13', 'value.text', params: <String, Object?>{'value': '产物: '}),
      _node(
        'n14',
        'context.packageFile',
        params: <String, Object?>{'path': 'lib/x.lib'},
      ),
      _node('n15', 'string.concat'),
      _node('n16', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n5', 'exec'),
      _edge('n2', 'result', 'n5', 'program'),
      _edge('n3', 'result', 'n5', 'arguments'),
      _edge('n14', 'result', 'n4', 'path'),
      _edge('n4', 'result', 'n5', 'workingDirectory'),
      _edge('n5', 'out', 'n16', 'exec'),
      _edge('n14', 'result', 'n7', 'path'),
      _edge('n7', 'result', 'n8', 'input'),
      _edge('n8', 'result', 'n6', 'input'),
      _edge('n9', 'result', 'n6', 'find'),
      _edge('n10', 'result', 'n6', 'replace'),
      _edge('n12', 'result', 'n11', 'left'),
      _edge('n6', 'result', 'n11', 'right'),
      _edge('n13', 'result', 'n15', 'a'),
      _edge('n11', 'result', 'n15', 'b'),
      _edge('n15', 'result', 'n16', 'message'),
    ],
    name: '字符串与进程夹具',
  );
}

/// M4.2 节点家族夹具：file 硬链接 → readHex→writeHex 往返 → crypto
/// （fileHash crc32 → Base64 解码 → AES 加密 → 代码签名）执行链，穿插
/// math.arithmetic 与 string.upperCase，触发全部 M4.2 新 helper
/// （ConvertFrom-CnpHex、Get-CnpFileHash + crc32 块、Invoke-CnpAesTransform、
/// Invoke-CnpSignFile）。
ScriptProjectModel _nodeFamiliesFixture() {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node(
        'n2',
        'value.text',
        params: <String, Object?>{'value': r'C:\src\a.h'},
      ),
      _node(
        'n3',
        'value.text',
        params: <String, Object?>{'value': r'C:\dst\a.h'},
      ),
      _node('n4', 'file.hardLink'),
      _node(
        'n5',
        'value.text',
        params: <String, Object?>{'value': r'C:\dst\a.h'},
      ),
      _node(
        'n6',
        'crypto.fileHash',
        params: <String, Object?>{'algorithm': 'crc32'},
      ),
      _node('n7', 'string.upperCase'),
      _node(
        'n8',
        'value.text',
        params: <String, Object?>{'value': r'C:\dst\a.b64'},
      ),
      _node('n9', 'crypto.base64Decode'),
      _node(
        'n10',
        'value.text',
        params: <String, Object?>{'value': r'C:\dst\a.enc'},
      ),
      _node(
        'n11',
        'crypto.aesEncrypt',
        params: <String, Object?>{'passwordEnv': 'CNP_AES_KEY'},
      ),
      _node(
        'n12',
        'value.text',
        params: <String, Object?>{'value': r'C:\dst\a.signed.h'},
      ),
      _node(
        'n13',
        'crypto.signFile',
        params: <String, Object?>{
          'pfxPath': r'C:\cert.pfx',
          'timestampServer': 'http://ts.example.com',
        },
      ),
      _node('n14', 'value.number', params: <String, Object?>{'value': 2}),
      _node('n15', 'value.number', params: <String, Object?>{'value': 3}),
      _node(
        'n16',
        'math.arithmetic',
        params: <String, Object?>{'operator': 'multiply'},
      ),
      _node('n17', 'math.numberToString'),
      _node('n18', 'log.message'),
      _node('n19', 'file.readHex'),
      _node('n20', 'file.writeHex'),
      _node(
        'n21',
        'value.text',
        params: <String, Object?>{'value': r'C:\dst\a.hex.bin'},
      ),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n4', 'exec'),
      _edge('n2', 'result', 'n4', 'source'),
      _edge('n3', 'result', 'n4', 'destination'),
      _edge('n4', 'out', 'n20', 'exec'),
      _edge('n3', 'result', 'n19', 'path'),
      _edge('n19', 'result', 'n20', 'hex'),
      _edge('n21', 'result', 'n20', 'path'),
      _edge('n20', 'out', 'n9', 'exec'),
      _edge('n5', 'result', 'n6', 'path'),
      _edge('n6', 'result', 'n7', 'value'),
      _edge('n7', 'result', 'n9', 'text'),
      _edge('n8', 'result', 'n9', 'path'),
      _edge('n9', 'out', 'n11', 'exec'),
      _edge('n5', 'result', 'n11', 'source'),
      _edge('n10', 'result', 'n11', 'destination'),
      _edge('n11', 'out', 'n13', 'exec'),
      _edge('n12', 'result', 'n13', 'path'),
      _edge('n13', 'out', 'n18', 'exec'),
      _edge('n14', 'result', 'n16', 'a'),
      _edge('n15', 'result', 'n16', 'b'),
      _edge('n16', 'result', 'n17', 'value'),
      _edge('n17', 'result', 'n18', 'message'),
    ],
    name: '节点家族夹具',
  );
}

/// M4.3 变量系统夹具：数值变量累加（set → while 条件重估 → 循环内 set）
/// + 文本变量写入/读回，触发顶部 `vars` 初始化块（count → 0、status → ''）。
ScriptProjectModel _variablesFixture() {
  return _project(
    <ScriptNodeModel>[
      _node('n1', 'flow.entry'),
      _node('n2', 'value.number', params: <String, Object?>{'value': 0}),
      _node(
        'n3',
        'variable.setNumber',
        params: <String, Object?>{'name': 'count'},
      ),
      _node(
        'n4',
        'variable.getNumber',
        params: <String, Object?>{'name': 'count'},
      ),
      _node('n5', 'value.number', params: <String, Object?>{'value': 5}),
      _node('n6', 'logic.compareNumber'),
      _node('n7', 'flow.while'),
      _node(
        'n8',
        'variable.getNumber',
        params: <String, Object?>{'name': 'count'},
      ),
      _node('n9', 'value.number', params: <String, Object?>{'value': 1}),
      _node('n10', 'math.arithmetic'),
      _node(
        'n11',
        'variable.setNumber',
        params: <String, Object?>{'name': 'count'},
      ),
      _node('n12', 'value.text', params: <String, Object?>{'value': '完成'}),
      _node(
        'n13',
        'variable.setString',
        params: <String, Object?>{'name': 'status'},
      ),
      _node(
        'n14',
        'variable.getString',
        params: <String, Object?>{'name': 'status'},
      ),
      _node('n15', 'log.message'),
    ],
    edges: <ScriptEdgeModel>[
      _edge('n1', 'out', 'n3', 'exec'),
      _edge('n2', 'result', 'n3', 'value'),
      _edge('n3', 'out', 'n7', 'exec'),
      _edge('n4', 'result', 'n6', 'a'),
      _edge('n5', 'result', 'n6', 'b'),
      _edge('n6', 'result', 'n7', 'condition'),
      _edge('n7', 'body', 'n11', 'exec'),
      _edge('n8', 'result', 'n10', 'a'),
      _edge('n9', 'result', 'n10', 'b'),
      _edge('n10', 'result', 'n11', 'value'),
      _edge('n7', 'completed', 'n13', 'exec'),
      _edge('n12', 'result', 'n13', 'value'),
      _edge('n13', 'out', 'n15', 'exec'),
      _edge('n14', 'result', 'n15', 'message'),
    ],
    name: '变量夹具',
  );
}

String _diagnosticMessages(ScriptCompileResult result) {
  return result.diagnostics
      .map((ScriptDiagnostic diagnostic) => diagnostic.message)
      .join('；');
}

void main() {
  group('生成文本 BOM 与文件头（纯 Dart，跨平台）', () {
    test('UTF-8 字节以 EF BB BF 开头且文件头为生成声明', () {
      final ScriptCompileResult result = PowerShell5Generator().compile(
        _linearFixture(),
        packName: 'demo',
      );
      expect(result.hasErrors, isFalse, reason: _diagnosticMessages(result));

      final String code = result.code!;
      final List<int> bytes = utf8.encode(code);
      expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      expect(code, startsWith('\uFEFF# 由 cpp_nuget_pack 生成'));
    });
  });

  group('PowerShell 5.1 语法解析（仅 Windows）', () {
    test('五张代表图生成的脚本均通过 Parser::ParseFile', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'cnp_ps_syntax_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final String checkPath = joinPath(tempDir.path, 'check.ps1');
      File(checkPath).writeAsStringSync(_parseCheckScript, encoding: ascii);

      final Map<String, ScriptProjectModel> fixtures =
          <String, ScriptProjectModel>{
            'linear': _linearFixture(),
            'nested_control_flow': _nestedControlFlowFixture(),
            'string_and_process': _stringAndProcessFixture(),
            'node_families': _nodeFamiliesFixture(),
            'variables': _variablesFixture(),
          };

      for (final MapEntry<String, ScriptProjectModel> fixture
          in fixtures.entries) {
        final ScriptCompileResult result = PowerShell5Generator().compile(
          fixture.value,
          packName: 'demo',
        );
        expect(
          result.hasErrors,
          isFalse,
          reason: '夹具「${fixture.key}」存在编译错误：${_diagnosticMessages(result)}',
        );

        final String scriptPath = joinPath(tempDir.path, '${fixture.key}.ps1');
        File(scriptPath).writeAsStringSync(result.code!, encoding: utf8);

        final ProcessResult check = Process.runSync('powershell.exe', <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          checkPath,
          '-Path',
          scriptPath,
        ]);
        expect(
          check.exitCode,
          0,
          reason:
              '夹具「${fixture.key}」语法解析失败：'
              'stdout=${check.stdout}\nstderr=${check.stderr}',
        );
      }
    }, skip: _nonWindowsSkip);

    test('检查脚本能检出故意语法错误（自检）', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'cnp_ps_syntax_broken_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final String checkPath = joinPath(tempDir.path, 'check.ps1');
      File(checkPath).writeAsStringSync(_parseCheckScript, encoding: ascii);
      final String brokenPath = joinPath(tempDir.path, 'broken.ps1');
      File(brokenPath).writeAsStringSync(_brokenScript, encoding: ascii);

      final ProcessResult check = Process.runSync('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        checkPath,
        '-Path',
        brokenPath,
      ]);
      expect(check.exitCode, isNot(0), reason: '检查脚本应报告故意语法错误，实际退出码为 0');
      expect(
        check.stdout.toString().trim(),
        isNotEmpty,
        reason: '检查脚本应打印解析错误消息',
      );
    }, skip: _nonWindowsSkip);
  });
}
