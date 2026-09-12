import 'package:cpp_nuget_pack/script_editor/codegen/prelude.dart';
import 'package:flutter_test/flutter_test.dart';

/// 工作树可能在 autocrlf 检出下含 CRLF；对常量按 LF 口径断言。
String _lf(String text) => text.replaceAll('\r\n', '\n');

void main() {
  group('preludeOrder', () {
    test('恰为 7 键且顺序固定（5 辅助函数 → crc32 → vars）', () {
      expect(preludeOrder, <String>[
        'ConvertFrom-CnpHex',
        'Find-CnpTool',
        'Get-CnpFileHash',
        'Invoke-CnpAesTransform',
        'Invoke-CnpSignFile',
        'crc32',
        'vars',
      ]);
    });

    test('辅助函数键均有 library 源码', () {
      for (final String key in preludeOrder) {
        if (key == 'crc32' || key == 'vars') {
          continue;
        }
        expect(preludeLibrary.containsKey(key), isTrue, reason: key);
      }
    });
  });

  group('preludeLibrary', () {
    test('恰含 5 个辅助函数（crc32/vars 为动态键，不在 library）', () {
      expect(preludeLibrary.keys.toSet(), <String>{
        'ConvertFrom-CnpHex',
        'Find-CnpTool',
        'Get-CnpFileHash',
        'Invoke-CnpAesTransform',
        'Invoke-CnpSignFile',
      });
    });

    test('全部片段为含 param( 的非空函数源码且无尾部换行', () {
      for (final String key in preludeLibrary.keys) {
        final String block = _lf(preludeLibrary[key]!);
        expect(block, isNotEmpty, reason: key);
        expect(block, contains('param('), reason: key);
        expect(block.endsWith('\n'), isFalse, reason: key);
      }
    });

    test('ConvertFrom-CnpHex：规整化、偶数长度/合法字符校验、返回 byte[]', () {
      final String block = _lf(preludeLibrary['ConvertFrom-CnpHex']!);
      expect(block, startsWith('function ConvertFrom-CnpHex {'));
      expect(block, contains(r"$Hex -replace '\s', '' -replace '-', ''"));
      expect(block, contains('% 2 -ne 0'));
      expect(block, contains('-notmatch'));
      expect(block, contains('[Convert]::ToByte'));
      expect(block, contains('New-Object byte[]'));
      expect(block, contains(r'return ,$result'));
    });

    test('Find-CnpTool：Get-Command 探测与候选路径回退', () {
      final String block = _lf(preludeLibrary['Find-CnpTool']!);
      expect(block, startsWith('function Find-CnpTool {'));
      expect(block, contains('Get-Command'));
      expect(block, contains('-CommandType Application'));
      expect(block, contains('[Environment]::ExpandEnvironmentVariables'));
      expect(block, contains('Test-Path -LiteralPath'));
      expect(block, contains(r'return $null'));
    });

    test('Get-CnpFileHash：Get-FileHash 与 CnpCrc32 分发', () {
      final String block = _lf(preludeLibrary['Get-CnpFileHash']!);
      expect(block, startsWith('function Get-CnpFileHash {'));
      expect(block, contains('Get-FileHash -LiteralPath'));
      expect(block, contains("'{0:x8}' -f"));
      expect(block, contains('[CnpCrc32]::Hash'));
      expect(block, contains('OpenRead'));
      expect(block, contains('.ToLowerInvariant()'));
    });

    test('Invoke-CnpAesTransform：PBKDF2 + AES-CBC + PKCS7 + 显式释放', () {
      final String block = _lf(preludeLibrary['Invoke-CnpAesTransform']!);
      expect(block, startsWith('function Invoke-CnpAesTransform {'));
      expect(block, contains('Rfc2898DeriveBytes'));
      expect(block, contains('10000'));
      expect(block, contains('GetBytes(32)'));
      expect(block, contains('CipherMode]::CBC'));
      expect(block, contains('PaddingMode]::PKCS7'));
      expect(block, contains('.Dispose()'));
      expect(block, contains(r'$output.Write($salt, 0, $salt.Length)'));
    });

    test('Invoke-CnpSignFile：signtool 探测与 Set-AuthenticodeSignature 回退', () {
      final String block = _lf(preludeLibrary['Invoke-CnpSignFile']!);
      expect(block, startsWith('function Invoke-CnpSignFile {'));
      expect(block, contains('signtool.exe'));
      expect(block, contains('Sort-Object -Property FullName -Descending'));
      expect(block, contains('@arguments'));
      expect(block, contains('Set-AuthenticodeSignature'));
      expect(block, contains('X509Certificate2'));
      expect(block, contains('TimestampServer'));
      expect(block, contains('Cert:'));
    });
  });

  group('crc32Prelude', () {
    test('PSTypeName 守卫 + Add-Type 注入 CnpCrc32（表法 0xEDB88320）', () {
      final String block = _lf(crc32Prelude);
      expect(block, contains('PSTypeName'));
      expect(block, contains('Add-Type -TypeDefinition'));
      expect(block, contains('public static class CnpCrc32'));
      expect(block, contains('public static uint Hash(Stream stream)'));
      expect(block, contains('0xEDB88320u'));
      expect(block, contains('0xFFFFFFFFu'));
      expect(block.endsWith('\n'), isFalse);
    });

    test('here-string 结构完整（闭合 \'@ 独占一行）且无 C# 5 禁止语法', () {
      final String block = _lf(crc32Prelude);
      expect(block, contains("\n'@\n"));
      // Add-Type 使用 C# 5 编译器：禁止字符串插值等新语法
      expect(block, isNot(contains(r'$"')));
      expect(block, isNot(contains('=>')));
      expect(block, isNot(contains('nameof(')));
    });
  });
}
