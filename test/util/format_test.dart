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

  group('formatTimestamp', () {
    test('输出 yyyy-MM-dd HH:mm:ss', () {
      expect(
        formatTimestamp(DateTime(2026, 9, 11, 14, 30, 5)),
        '2026-09-11 14:30:05',
      );
    });

    test('个位数月/日/时/分/秒补零', () {
      expect(
        formatTimestamp(DateTime(2026, 1, 2, 3, 4, 5)),
        '2026-01-02 03:04:05',
      );
    });
  });
}
