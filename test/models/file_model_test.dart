import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileModel 文件类型识别', () {
    test('头文件 .h/.hpp 映射为 header', () {
      expect(FileModel(name: 'widget.h', path: '').type, FileType.header);
      expect(FileModel(name: 'widget.hpp', path: '').type, FileType.header);
    });

    test('源文件 .c/.cpp 映射为 source', () {
      expect(FileModel(name: 'main.c', path: '').type, FileType.source);
      expect(FileModel(name: 'main.cpp', path: '').type, FileType.source);
    });

    test('资源文件 .rc 映射为 resource', () {
      expect(FileModel(name: 'app.rc', path: '').type, FileType.resource);
    });

    test('库文件 .lib/.dll 映射为 lib 与 dll', () {
      expect(FileModel(name: 'mylib.lib', path: '').type, FileType.lib);
      expect(FileModel(name: 'mylib.dll', path: '').type, FileType.dll);
    });

    test('未知扩展名或无扩展名映射为 other', () {
      expect(FileModel(name: 'readme.md', path: '').type, FileType.other);
      expect(FileModel(name: 'LICENSE', path: '').type, FileType.other);
      expect(FileModel(name: 'trailing.', path: '').type, FileType.other);
    });

    test('扩展名大小写不敏感', () {
      expect(FileModel(name: 'FOO.H', path: '').type, FileType.header);
      expect(FileModel(name: 'BAR.CPP', path: '').type, FileType.source);
      expect(FileModel(name: 'Baz.DLL', path: '').extension, 'dll');
    });
  });
}
