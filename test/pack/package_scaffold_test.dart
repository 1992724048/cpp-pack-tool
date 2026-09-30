import 'dart:io';

import 'package:cpp_nuget_pack/pack/package_scaffold.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _scaffoldDirectories = <String>[
  'lib/x64/Debug',
  'lib/x64/Release',
  'bin/x64/Debug',
  'bin/x64/Release',
];

const List<String> _templateFileNames = <String>['build.py', 'pre.bat', 'post.bat'];

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('package_scaffold_test_');
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
  });

  group('createPackageStructure 包结构脚手架', () {
    test('创建四个产物目录与三个模板文件', () async {
      final ScaffoldOutcome outcome = await createPackageStructure(root.path);

      for (final String relative in _scaffoldDirectories) {
        expect(
          Directory('${root.path}/$relative').existsSync(),
          isTrue,
          reason: relative,
        );
      }
      for (final String name in _templateFileNames) {
        expect(File('${root.path}/$name').existsSync(), isTrue, reason: name);
      }
      expect(outcome.createdDirectories, _scaffoldDirectories);
      expect(outcome.createdFiles, _templateFileNames);
      expect(outcome.skippedFiles, isEmpty);
    });

    test('绝不覆盖已存在的文件', () async {
      const String ownRecipe = '# 我自己的配方，不要动我';
      final File existing = File('${root.path}/build.py')
        ..writeAsStringSync(ownRecipe);

      final ScaffoldOutcome outcome = await createPackageStructure(root.path);

      expect(existing.readAsStringSync(), ownRecipe);
      expect(outcome.skippedFiles, contains('build.py'));
      expect(outcome.createdFiles, <String>['pre.bat', 'post.bat']);
    });

    test('重复运行不新建任何东西', () async {
      await createPackageStructure(root.path);

      final ScaffoldOutcome outcome = await createPackageStructure(root.path);

      expect(outcome.createdDirectories, isEmpty);
      expect(outcome.createdFiles, isEmpty);
      expect(outcome.skippedFiles, _templateFileNames);
    });

    test('目标目录不存在时自动创建', () async {
      final Directory nested = Directory('${root.path}/a/b/c');

      final ScaffoldOutcome outcome = await createPackageStructure(nested.path);

      expect(nested.existsSync(), isTrue);
      expect(outcome.createdDirectories, <String>['.', ..._scaffoldDirectories]);
      for (final String relative in _scaffoldDirectories) {
        expect(
          Directory('${nested.path}/$relative').existsSync(),
          isTrue,
          reason: relative,
        );
      }
      expect(File('${nested.path}/build.py').existsSync(), isTrue);
    });

    test('build.py 模板列出全部环境变量与落盘禁区', () async {
      await createPackageStructure(root.path);

      final String content = File('${root.path}/build.py').readAsStringSync();
      expect(content, contains('CNP_PACKAGE_ROOT'));
      expect(content, contains('CNP_SRC_DIR'));
      expect(content, contains('CNP_TMP_DIR'));
      expect(content, contains('CNP_TOOLS_DIR'));
      expect(content, contains('CNP_COMPILER'));
      expect(content, contains('build'));
      expect(content, contains('out'));
    });

    test('批处理模板只有 @echo off 与注释，无活动逻辑', () async {
      await createPackageStructure(root.path);

      for (final String name in <String>['pre.bat', 'post.bat']) {
        final List<String> lines = File('${root.path}/$name')
            .readAsLinesSync()
            .where(
              (String line) =>
                  line.trim().isNotEmpty && !line.trimLeft().startsWith('rem '),
            )
            .toList();
        expect(lines, <String>['@echo off'], reason: name);
      }
    });

    test('目标路径被目录占位时抛 PackageScaffoldException', () async {
      Directory(joinPath(root.path, 'build.py')).createSync();

      await expectLater(
        createPackageStructure(root.path),
        throwsA(
          isA<PackageScaffoldException>().having(
            (PackageScaffoldException error) => error.message,
            'message',
            allOf(
              contains('无法创建包结构'),
              contains(joinPath(root.path, 'build.py')),
            ),
          ),
        ),
      );
    });

    test('中途失败不回滚已写入的模板文件', () async {
      Directory(joinPath(root.path, 'post.bat')).createSync();

      await expectLater(
        createPackageStructure(root.path),
        throwsA(isA<PackageScaffoldException>()),
      );

      for (final String name in <String>['build.py', 'pre.bat']) {
        expect(File(joinPath(root.path, name)).existsSync(), isTrue, reason: name);
      }
    });

    test('根路径带尾分隔符时上报的失败路径是规范化后的路径', () async {
      Directory(joinPath(root.path, 'post.bat')).createSync();

      await expectLater(
        createPackageStructure('${root.path}\\'),
        throwsA(
          isA<PackageScaffoldException>().having(
            (PackageScaffoldException error) => error.message,
            'message',
            contains(joinPath(root.path, 'post.bat')),
          ),
        ),
      );
    });
  });
}
