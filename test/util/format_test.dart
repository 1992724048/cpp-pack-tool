import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('joinPath', () {
    test('base 末尾无分隔符时以 / 拼接', () {
      expect(
        joinPath('C:/libs/foo', 'assets/logo.svg'),
        'C:/libs/foo/assets/logo.svg',
      );
    });

    test('base 末尾的反斜杠被去除', () {
      expect(
        joinPath('C:\\libs\\foo\\', 'assets/logo.svg'),
        r'C:\libs\foo/assets/logo.svg',
      );
    });

    test('base 末尾多个正斜杠被去除', () {
      expect(
        joinPath('C:/libs/foo//', 'assets/logo.svg'),
        'C:/libs/foo/assets/logo.svg',
      );
    });

    test('base 末尾混合分隔符被去除', () {
      expect(
        joinPath('C:/libs/foo\\/', 'assets/logo.svg'),
        'C:/libs/foo/assets/logo.svg',
      );
    });
  });
}
