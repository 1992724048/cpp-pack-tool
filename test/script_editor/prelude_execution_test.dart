import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/script_editor/codegen/prelude.dart';
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
}
