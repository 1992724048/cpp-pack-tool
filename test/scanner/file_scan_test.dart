import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/scanner/file_scan.dart';
import 'package:flutter_test/flutter_test.dart';

const String _headerContent = '0123456789';
const String _sourceContent = 'int main() {}\n';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('file_scan_test_');
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
  });

  group('FileScan 包目录扫描', () {
    test('多层嵌套文件全部收集且数量正确', () async {
      await _createFixtureTree(root);

      final List<FileModel> files = await FileScan.scan(root.path);

      expect(files, hasLength(9));
      expect(
        files.map((file) => file.path),
        containsAll(<String>[
          '.gitignore',
          'README.md',
          'Zebra.txt',
          'app.rc',
          'include/foo.h',
          'include/nested/bar.hpp',
          'lib/x64/debug/foo.dll',
          'lib/x64/release/foo.lib',
          'src/main.cpp',
        ]),
      );
    });

    test('排除 .git/build/out 目录（任意深度），保留根目录 .gitignore', () async {
      await _createFixtureTree(root);

      final List<FileModel> files = await FileScan.scan(root.path);
      final Set<String> paths = files.map((file) => file.path).toSet();

      expect(paths, contains('.gitignore'));
      expect(paths, isNot(contains('.git/config')));
      expect(paths, isNot(contains('.dart_tool/package_config.json')));
      expect(paths, isNot(contains('build/generated.h')));
      expect(paths, isNot(contains('out/output.txt')));
      expect(paths, isNot(contains('src/build/generated.cpp')));
      expect(paths, isNot(contains('src/out/artifact.txt')));
    });

    test('同一文件只收集一次', () async {
      await _createFixtureTree(root);

      final List<FileModel> files = await FileScan.scan(root.path);
      final Set<String> paths = files.map((file) => file.path).toSet();

      expect(paths, hasLength(files.length));
    });

    test('path 为相对扫描根目录且分隔符统一为 /', () async {
      await _createFixtureTree(root);

      final List<FileModel> files = await FileScan.scan(root.path);

      expect(files.map((file) => file.path), contains('include/foo.h'));
      expect(files.every((file) => !file.path.contains(r'\')), isTrue);
    });

    test('name 为文件名，扩展名映射类型正确', () async {
      await _createFixtureTree(root);

      final List<FileModel> files = await FileScan.scan(root.path);
      FileModel fileByPath(String path) =>
          files.singleWhere((file) => file.path == path);

      expect(fileByPath('include/foo.h').name, 'foo.h');
      expect(fileByPath('include/foo.h').type, FileType.header);
      expect(fileByPath('include/nested/bar.hpp').type, FileType.header);
      expect(fileByPath('src/main.cpp').type, FileType.source);
      expect(fileByPath('lib/x64/release/foo.lib').type, FileType.lib);
      expect(fileByPath('lib/x64/debug/foo.dll').type, FileType.dll);
      expect(fileByPath('app.rc').type, FileType.resource);
      expect(fileByPath('README.md').type, FileType.other);
    });

    test('size 为文件实际字节数', () async {
      await _createFixtureTree(root);

      final List<FileModel> files = await FileScan.scan(root.path);

      expect(
        files.singleWhere((file) => file.path == 'include/foo.h').size,
        _headerContent.length,
      );
      expect(
        files.singleWhere((file) => file.path == 'src/main.cpp').size,
        _sourceContent.length,
      );
    });

    test('结果按 path 大小写不敏感排序', () async {
      await _createFixtureTree(root);

      final List<FileModel> files = await FileScan.scan(root.path);

      expect(files.map((file) => file.path).toList(), <String>[
        '.gitignore',
        'app.rc',
        'include/foo.h',
        'include/nested/bar.hpp',
        'lib/x64/debug/foo.dll',
        'lib/x64/release/foo.lib',
        'README.md',
        'src/main.cpp',
        'Zebra.txt',
      ]);
    });

    test('空目录返回空列表', () async {
      final List<FileModel> files = await FileScan.scan(root.path);

      expect(files, isEmpty);
    });

    test('目录不存在时抛出 ArgumentError', () async {
      final String missingPath = '${root.path}/missing_dir';

      await expectLater(
        FileScan.scan(missingPath),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('目录不存在'),
          ),
        ),
      );
    });

    test('传入文件路径时抛出 ArgumentError', () async {
      final File file = await _writeFile(root, 'plain.txt', 'content');

      await expectLater(
        FileScan.scan(file.path),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('不是目录'),
          ),
        ),
      );
    });
  });
}

Future<File> _writeFile(
  Directory root,
  String relativePath,
  String content,
) async {
  final File file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  return file;
}

Future<void> _createFixtureTree(Directory root) async {
  await _writeFile(root, '.gitignore', '*.log\n');
  await _writeFile(root, 'README.md', '# readme\n');
  await _writeFile(root, 'Zebra.txt', 'zebra\n');
  await _writeFile(root, 'app.rc', 'rc\n');
  await _writeFile(root, 'include/foo.h', _headerContent);
  await _writeFile(root, 'include/nested/bar.hpp', '#pragma once\n');
  await _writeFile(root, 'src/main.cpp', _sourceContent);
  await _writeFile(root, 'lib/x64/debug/foo.dll', 'dll\n');
  await _writeFile(root, 'lib/x64/release/foo.lib', 'lib\n');

  await _writeFile(root, '.git/config', '[core]\n');
  await _writeFile(root, '.dart_tool/package_config.json', '{}\n');
  await _writeFile(root, 'build/generated.h', 'generated\n');
  await _writeFile(root, 'out/output.txt', 'output\n');
  await _writeFile(root, 'src/build/generated.cpp', 'generated\n');
  await _writeFile(root, 'src/out/artifact.txt', 'artifact\n');
}
