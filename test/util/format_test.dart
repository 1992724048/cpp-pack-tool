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

  group('parentDirectory', () {
    test('返回父目录（/ 与 \\ 分隔符均可）', () {
      expect(
        parentDirectory(r'C:\msys64\ucrt64\bin\gcc.exe'),
        r'C:\msys64\ucrt64\bin',
      );
      expect(
        parentDirectory('C:/msys64/ucrt64/bin/gcc.exe'),
        'C:/msys64/ucrt64/bin',
      );
      expect(parentDirectory(r'C:\LLVM\bin/clang-cl.exe'), r'C:\LLVM\bin');
    });

    test('无分隔符时返回原路径', () {
      expect(parentDirectory('gcc.exe'), 'gcc.exe');
      expect(parentDirectory(''), '');
    });
  });

  group('formatError', () {
    test('FormatException 返回去前缀的消息文本', () {
      expect(
        formatError(const FormatException('缺少 version 字段')),
        '缺少 version 字段',
      );
    });

    test('FormatException 带来源与偏移时仍只返回消息文本', () {
      expect(
        formatError(
          const FormatException('字段 name 类型错误，应为字符串', 'packs/foo.yaml', 3),
        ),
        '字段 name 类型错误，应为字符串',
      );
    });

    test('FormatException 无消息时回退为 toString', () {
      final FormatException error = const FormatException();
      expect(formatError(error), error.toString());
    });

    test('ArgumentError 消息非空时原样返回', () {
      expect(formatError(ArgumentError('自定义消息')), '自定义消息');
    });

    test('未知异常回退为 toString', () {
      final StateError error = StateError('boom');
      expect(formatError(error), error.toString());
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
