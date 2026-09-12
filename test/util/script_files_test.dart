import 'package:cpp_nuget_pack/util/script_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scriptFileExtensions', () {
    test('集合为 {bat, cmd, exe, ps1, py}', () {
      expect(scriptFileExtensions, <String>{'bat', 'cmd', 'exe', 'ps1', 'py'});
    });
  });

  group('isScriptFilePath', () {
    test('脚本扩展名（大小写不敏感、/ 与 \\ 分隔）返回 true', () {
      for (final String path in <String>[
        'files/run.bat',
        'files/run.cmd',
        'files/app.exe',
        'files/scripts/script_1.ps1',
        r'files\scripts\build.PS1',
        r'files\scripts\BUILD.BAT',
        'tools/gen.py',
      ]) {
        expect(isScriptFilePath(path), isTrue, reason: path);
      }
    });

    test('非脚本扩展名、无扩展名与空路径返回 false', () {
      for (final String path in <String>[
        'lib/x.lib',
        'files/data.txt',
        'include/demo/header.h',
        'files/README',
        'files/no_ext.',
        'files/.ps1',
        '',
      ]) {
        expect(isScriptFilePath(path), isFalse, reason: path);
      }
    });
  });
}
