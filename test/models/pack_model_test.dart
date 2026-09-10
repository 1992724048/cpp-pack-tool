import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackModel 序列化', () {
    test('toMap/fromMap 往返保留全部字段与文件列表', () {
      final PackModel pack =
          PackModel(
              name: 'MyLib',
              version: '1.0.0',
              author: '张三',
              description: '描述\n第二行',
              license: 'MIT',
              iconPath: 'assets/logo.svg',
              sourcePath: r'D:\libs\mylib',
            )
            ..files = <FileModel>[
              FileModel(name: 'foo.h', path: 'include/foo.h', size: 123),
            ];

      final PackModel loaded = PackModel.fromMap(pack.toMap());

      expect(loaded.name, pack.name);
      expect(loaded.version, pack.version);
      expect(loaded.author, pack.author);
      expect(loaded.description, pack.description);
      expect(loaded.license, pack.license);
      expect(loaded.iconPath, pack.iconPath);
      expect(loaded.sourcePath, pack.sourcePath);
      expect(loaded.files.single.path, 'include/foo.h');
      expect(loaded.files.single.name, 'foo.h');
      expect(loaded.files.single.size, 123);
      expect(loaded.files.single.type, FileType.header);
    });

    test('toMap 省略 null 字段', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      final Map<String, Object?> map = pack.toMap();

      expect(map.containsKey('description'), isFalse);
      expect(map.containsKey('license'), isFalse);
      expect(map.containsKey('iconPath'), isFalse);
      expect(map.containsKey('sourcePath'), isFalse);
      expect(map['files'], isEmpty);
    });

    test('fromMap 缺少 files 时默认空列表', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });

      expect(pack.files, isEmpty);
    });

    test('fromMap 从 path 推导文件名并兼容反斜杠分隔符', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
        'files': <Object?>[
          <String, Object?>{'path': 'include/foo.h', 'size': 1},
          <String, Object?>{'path': r'src\main.cpp', 'size': 2},
        ],
      });

      expect(pack.files[0].name, 'foo.h');
      expect(pack.files[0].type, FileType.header);
      expect(pack.files[1].name, 'main.cpp');
      expect(pack.files[1].type, FileType.source);
      expect(pack.files[1].path, r'src\main.cpp');
    });

    test('fromMap 缺少必填字段时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'version': '1.0.0',
          'author': 'tester',
        }),
        throwsFormatException,
      );
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'author': 'tester',
        }),
        throwsFormatException,
      );
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
        }),
        throwsFormatException,
      );
    });

    test('fromMap files 类型错误时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'files': 'oops',
        }),
        throwsFormatException,
      );
    });
  });

  group('FileModel 序列化', () {
    test('toMap 只包含 path 与 size', () {
      final FileModel file = FileModel(
        name: 'foo.h',
        path: 'include/foo.h',
        size: 42,
      );

      expect(file.toMap(), <String, Object?>{
        'path': 'include/foo.h',
        'size': 42,
      });
    });

    test('fromMap 缺失 size 时默认为 0', () {
      final FileModel file = FileModel.fromMap(<String, Object?>{
        'path': 'foo.h',
      });

      expect(file.size, 0);
      expect(file.name, 'foo.h');
    });

    test('fromMap 缺少 path 时抛出 FormatException', () {
      expect(
        () => FileModel.fromMap(<String, Object?>{}),
        throwsFormatException,
      );
    });
  });
}
