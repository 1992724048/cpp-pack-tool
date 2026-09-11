import 'dart:io';

import 'package:cpp_nuget_pack/util/file_opener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('explorerPath', () {
    test('混合分隔符路径统一为反斜杠', () {
      expect(
        explorerPath(File(r'C:\libs\foo/include/foo.h')),
        r'C:\libs\foo\include\foo.h',
      );
    });

    test('全反斜杠绝对路径保持不变', () {
      expect(
        explorerPath(File(r'C:\libs\foo\main.cpp')),
        r'C:\libs\foo\main.cpp',
      );
    });

    test('全正斜杠绝对路径统一为反斜杠', () {
      expect(
        explorerPath(File('C:/libs/foo/main.cpp')),
        r'C:\libs\foo\main.cpp',
      );
    });

    test('相对路径先取绝对路径再统一分隔符', () {
      final String result = explorerPath(File('sub dir/file.txt'));
      expect(result, endsWith(r'sub dir\file.txt'));
      expect(result, isNot(contains('/')));
    });
  });
}
