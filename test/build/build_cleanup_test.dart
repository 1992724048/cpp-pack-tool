import 'dart:io';

import 'package:cpp_nuget_pack/build/build_cleanup.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('白名单识别', () {
    test('保留 build.py（大小写不敏感）、icon.*、pre/post.bat、.git 与许可证类文件', () {
      for (final String name in <String>[
        'build.py',
        'BUILD.PY',
        'icon.png',
        'icon.svg',
        'ICON.ico',
        'pre.bat',
        'post.bat',
        '.git',
        '.GIT',
        'LICENSE',
        'license',
        'LICENCE',
        'LICENSE-MIT',
        'COPYING.LESSER',
        'UNLICENSE',
        'NOTICE.md',
        'TBB-LICENSE',
      ]) {
        expect(
          isPreservedEntryName(name),
          isTrue,
          reason: '$name 应保留',
        );
      }
    });

    test('不保留普通文件与近似名（下划线不算分隔符、.git* 需精确匹配）', () {
      for (final String name in <String>[
        'stale.txt',
        'BUILD.DEP',
        'myicon.png',
        'pre.bat.old',
        'license_checker.py',
        'ICON',
        '.gitignore',
        '.gitmodules',
      ]) {
        expect(
          isPreservedEntryName(name),
          isFalse,
          reason: '$name 应删除',
        );
      }
    });
  });

  group('cleanupBuildOutput', () {
    test('根不存在时静默返回', () async {
      final Directory root = _tempDirectory();

      await cleanupBuildOutput(joinPath(root.path, 'missing'));
    });

    test('白名单文件保留、其余文件与目录递归删除', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      _writeFile(sourcePath, 'stale.txt', 'stale');
      _writeFile(sourcePath, 'stale/BUILD.DEP', 'dep');
      _writeFile(sourcePath, 'build-release/CMakeCache.txt', 'x');
      _writeFile(sourcePath, 'nested/deep/out.obj', 'obj');
      _writeFile(sourcePath, 'bin/old.dll', 'dll');
      _writeFile(sourcePath, '.git/config', 'git');
      _writeFile(sourcePath, '.git/objects/aa/blob', 'blob');
      _writeFile(sourcePath, '.gitignore', 'ignored');

      await cleanupBuildOutput(sourcePath);

      for (final String name in <String>[
        'build.py',
        'icon.png',
        'LICENSE',
        'TBB-LICENSE',
        'pre.bat',
        'post.bat',
      ]) {
        expect(
          File(joinPath(sourcePath, name)).existsSync(),
          isTrue,
          reason: '$name 应保留',
        );
      }
      expect(
        File(joinPath(sourcePath, '.git/config')).existsSync(),
        isTrue,
        reason: '根级 .git 目录应保留（用户把源目录当工作仓库时防灾难性删除）',
      );
      expect(
        File(joinPath(sourcePath, '.git/objects/aa/blob')).existsSync(),
        isTrue,
        reason: '.git 目录内容应整体保留',
      );
      expect(
        File(joinPath(sourcePath, '.gitignore')).existsSync(),
        isFalse,
        reason: '.git* 近似名不保留（仅精确 .git）',
      );

      expect(File(joinPath(sourcePath, 'stale.txt')).existsSync(), isFalse);
      expect(
        Directory(joinPath(sourcePath, 'stale')).existsSync(),
        isFalse,
      );
      expect(
        Directory(joinPath(sourcePath, 'build-release')).existsSync(),
        isFalse,
      );
      expect(
        Directory(joinPath(sourcePath, 'nested')).existsSync(),
        isFalse,
      );
      expect(Directory(joinPath(sourcePath, 'bin')).existsSync(), isFalse);
    });

    test('保留根级图标变体与许可证前缀变体', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      _writeFile(sourcePath, 'icon.jpg', 'x');
      _writeFile(sourcePath, 'COPYING', 'x');
      _writeFile(sourcePath, 'lib/x.lib', 'x');

      await cleanupBuildOutput(sourcePath);

      final List<String> remaining = Directory(sourcePath)
          .listSync()
          .map((FileSystemEntity entity) => baseName(entity.path))
          .toList()
        ..sort();
      expect(remaining, <String>[
        'COPYING',
        'LICENSE',
        'TBB-LICENSE',
        'build.py',
        'icon.jpg',
        'icon.png',
        'post.bat',
        'pre.bat',
      ]);
    });

    test('幂等：连续两次清理不报错且结果一致', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      _writeFile(sourcePath, 'stale.txt', 'x');

      await cleanupBuildOutput(sourcePath);
      await cleanupBuildOutput(sourcePath);

      expect(File(joinPath(sourcePath, 'build.py')).existsSync(), isTrue);
      expect(File(joinPath(sourcePath, 'stale.txt')).existsSync(), isFalse);
    });

    test('文件被占用无法删除时抛错且文案列出失败路径', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final File locked = File(joinPath(sourcePath, 'locked.dat'))
        ..writeAsStringSync('busy');
      final RandomAccessFile handle = locked.openSync(mode: FileMode.append);
      addTearDown(handle.closeSync);

      await expectLater(
        cleanupBuildOutput(sourcePath),
        throwsA(
          isA<BuildCleanupException>().having(
            (BuildCleanupException error) => error.message,
            'message',
            allOf(contains('清理构建输出目录失败'), contains('locked.dat')),
          ),
        ),
      );
    });
  });
}

Directory _tempDirectory() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'cpp_nuget_pack_cleanup_',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

/// 源目录骨架：白名单文件齐备（脚本 / 图标 / 许可证变体 / 钩子脚本）。
String _createSource(Directory root, String scriptContent) {
  final String sourcePath = joinPath(root.path, 'src');
  Directory(sourcePath).createSync(recursive: true);
  File(joinPath(sourcePath, 'build.py')).writeAsStringSync(scriptContent);
  File(joinPath(sourcePath, 'icon.png')).writeAsStringSync('png');
  File(joinPath(sourcePath, 'LICENSE')).writeAsStringSync('license');
  File(joinPath(sourcePath, 'TBB-LICENSE')).writeAsStringSync('tbb');
  File(joinPath(sourcePath, 'pre.bat')).writeAsStringSync('pre');
  File(joinPath(sourcePath, 'post.bat')).writeAsStringSync('post');
  return sourcePath;
}

void _writeFile(String root, String relativePath, String content) {
  final File file = File(joinPath(root, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
