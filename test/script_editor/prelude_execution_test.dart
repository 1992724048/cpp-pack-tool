import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/prelude.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实执行 prelude 辅助函数的冒烟测试（仅 Windows）。
///
/// 与 `powershell_syntax_test.dart` 的 `Parser::ParseFile`（只解析、不执行）
/// 不同，本文件用真实 `powershell.exe` **执行**「helper 片段 + 驱动片段」，
/// 锁定语义：`ConvertFrom-CnpHex` 往返与异常路径、`Get-CnpFileHash -Algorithm
/// crc32` 已知向量。脚本只由本文件拼接（helper 片段取自仓库常量
/// [preludeLibrary]/[crc32Prelude]），不执行其他脚本。
final Object? _nonWindowsSkip = Platform.isWindows
    ? null
    : '仅 Windows 平台执行（依赖 powershell.exe 执行 helper 片段）';

/// 拼接 `param` 头 + 显式传入的 helper 片段 + 驱动体（LF 分隔）。
String _buildScript({
  required Iterable<String> fragments,
  required String driver,
}) {
  return <String>[
    r'param([string]$TestFile)',
    r"$ErrorActionPreference = 'Stop'",
    ...fragments,
    driver,
  ].join('\n\n');
}

/// 以 UTF-8 BOM 写脚本文件：PS 5.1 无 BOM 时按本地代码页解析，
/// 驱动片段中的中文消息断言要求 BOM。
void _writeScript(String path, String script) {
  File(path).writeAsStringSync('\uFEFF$script', encoding: utf8);
}

ProcessResult _runScript(String scriptPath, {String? testFile}) {
  return Process.runSync('powershell.exe', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    scriptPath,
    if (testFile != null) ...<String>['-TestFile', testFile],
  ]);
}

Directory _createTempDir(String name) {
  final Directory tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  return tempDir;
}

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

/// while 累加器图（M4.3 同款）：count = 0 → while (count < 5) { count += 1 } →
/// 输出 count；真实执行后 stdout 恰为 `5`。
ScriptProjectModel _whileAccumulatorProject() {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: 'while 累加器',
    trigger: ScriptTrigger.pre,
  );
  project.nodes = <ScriptNodeModel>[
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
    _node(
      'n12',
      'variable.getNumber',
      params: <String, Object?>{'name': 'count'},
    ),
    _node('n13', 'math.numberToString'),
    _node('n14', 'log.message'),
  ];
  project.edges = <ScriptEdgeModel>[
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
    _edge('n7', 'completed', 'n14', 'exec'),
    _edge('n12', 'result', 'n13', 'value'),
    _edge('n13', 'result', 'n14', 'message'),
  ];
  return project;
}

/// hex 往返（空白与连字符混合）+ 奇数长度/非法字符的异常路径（正反例成对）。
const String _hexDriver =
    r"$roundtrip = [System.Text.Encoding]::ASCII.GetString((ConvertFrom-CnpHex '48 65-6C 6C 6F'))"
    '\n'
    r"Write-Output ('hex_roundtrip=' + $roundtrip)"
    '\n'
    r"try { [void](ConvertFrom-CnpHex 'ABC'); Write-Output 'odd=no_throw' } "
    r"catch { if ($_.Exception.Message -eq '十六进制字符串长度必须为偶数') { Write-Output 'odd=even_length_error' } else { Write-Output 'odd=unexpected_error' } }"
    '\n'
    r"try { [void](ConvertFrom-CnpHex 'ZZ'); Write-Output 'illegal=no_throw' } "
    r"catch { if ($_.Exception.Message -eq '十六进制字符串包含非法字符') { Write-Output 'illegal=illegal_char_error' } else { Write-Output 'illegal=unexpected_error' } }";

/// crc32（ISO-HDLC 标准向量 `123456789` → `cbf43926`）+ sha256 对照。
///
/// 首行归一 PSModulePath：父进程若继承 PowerShell 7（Store/MSIX 安装）的
/// 模块路径，其 `Microsoft.PowerShell.Utility` 兼容 shim 会排到 Windows
/// PowerShell 5.1 自带模块之前，令 `Get-FileHash` 无法自动加载；冒烟只锁定
/// helper 自身语义，故在驱动片段中还原 WPS 默认模块路径（仅测试脚手架，
/// 不改产品行为）。
const String _hashDriver =
    r'$env:PSModulePath = "$PSHOME\Modules"'
    '\n'
    r"Write-Output ('crc32=' + (Get-CnpFileHash -Path $TestFile -Algorithm crc32))"
    '\n'
    r"Write-Output ('sha256=' + (Get-CnpFileHash -Path $TestFile -Algorithm sha256))";

void main() {
  group('prelude helper 真实执行（仅 Windows）', () {
    test('ConvertFrom-CnpHex：真实执行 hex 往返与奇数/非法字符异常路径', () {
      final Directory tempDir = _createTempDir('cnp_prelude_hex_');
      final String scriptPath = joinPath(tempDir.path, 'hex.ps1');
      _writeScript(
        scriptPath,
        _buildScript(
          fragments: <String>[preludeLibrary['ConvertFrom-CnpHex']!],
          driver: _hexDriver,
        ),
      );

      final ProcessResult result = _runScript(scriptPath);
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(stdout, contains('hex_roundtrip=Hello'));
      expect(stdout, contains('odd=even_length_error'));
      expect(stdout, contains('illegal=illegal_char_error'));
    }, skip: _nonWindowsSkip);

    test('Get-CnpFileHash：真实执行 crc32 已知向量（附 sha256 对照）', () {
      final Directory tempDir = _createTempDir('cnp_prelude_hash_');
      final File vector = File(joinPath(tempDir.path, 'vector.txt'));
      vector.writeAsStringSync('123456789', encoding: ascii);
      final String scriptPath = joinPath(tempDir.path, 'hash.ps1');
      _writeScript(
        scriptPath,
        _buildScript(
          fragments: <String>[
            preludeLibrary['Get-CnpFileHash']!,
            crc32Prelude,
          ],
          driver: _hashDriver,
        ),
      );

      final ProcessResult result = _runScript(scriptPath, testFile: vector.path);
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(stdout, contains('crc32=cbf43926'));
      expect(
        stdout,
        contains(
          'sha256=15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225',
        ),
      );
    }, skip: _nonWindowsSkip);
  });

  group('生成脚本真实执行（仅 Windows，脏 PSModulePath 链）', () {
    test('PSModulePath 加固行生效：while 累加脚本输出 5 且退出码 0', () {
      final ScriptCompileResult compiled = PowerShell5Generator().compile(
        _whileAccumulatorProject(),
        packName: 'demo',
      );
      expect(
        compiled.hasErrors,
        isFalse,
        reason: compiled.diagnostics
            .map((ScriptDiagnostic diagnostic) => diagnostic.message)
            .join('；'),
      );
      final String code = compiled.code!;
      // 入口加固：模块路径在脚本内归一，不依赖中间进程链的环境。
      expect(code, contains(r'$env:PSModulePath = "$PSHOME\Modules"'));

      final Directory tempDir = _createTempDir('cnp_generated_script_');
      final String scriptPath = joinPath(tempDir.path, 'accumulator.ps1');
      // 生成代码自带 UTF-8 BOM，直接落盘（`_writeScript` 会再前置一次 BOM）。
      File(scriptPath).writeAsStringSync(code, encoding: utf8);

      final ProcessResult result = _runScript(scriptPath);
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      expect(result.stdout.toString(), contains('5'));
    }, skip: _nonWindowsSkip);
  });
}
