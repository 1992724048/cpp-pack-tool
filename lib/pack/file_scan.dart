import 'dart:io';

import 'package:cpp_nuget_pack/pack/model/file_model.dart';

abstract final class FileScan {
  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  /// 构建产物目录名，任意层级都跳。`__pycache__` 虽非隐藏目录，但同属产物目录：
  /// 包源根住着 build.py，任何 import 它的测试 / IDE 都会在原地留下 .pyc。
  /// 生态里其余工具缓存（.mypy_cache / .pytest_cache / .ruff_cache / .tox 等）都是
  /// `.` 开头，已由 [shouldSkipDirectory] 的隐藏目录规则覆盖。
  static const Set<String> _artifactDirectories = <String>{'build', 'out', '__pycache__'};

  static Future<List<FileModel>> scan(String directoryPath) async {
    final FileSystemEntityType type = FileSystemEntity.typeSync(directoryPath);
    if (type == FileSystemEntityType.notFound) {
      throw ArgumentError('目录不存在: $directoryPath');
    }
    if (type != FileSystemEntityType.directory) {
      throw ArgumentError('不是目录: $directoryPath');
    }

    final List<FileModel> files = [];
    await _collectFiles(Directory(directoryPath), '', files);
    files.sort(_compareByPath);
    return files;
  }

  static Future<void> _collectFiles(Directory directory, String relativePrefix, List<FileModel> files) async {
    await for (final FileSystemEntity entity in directory.list(followLinks: false)) {
      final String name = _baseName(entity.path);
      final String relativePath = relativePrefix.isEmpty ? name : '$relativePrefix/$name';

      if (entity is File) {
        final FileStat stat = await entity.stat();
        files.add(FileModel(name: name, path: relativePath, size: stat.size));
        continue;
      }
      if (entity is Directory && !shouldSkipDirectory(name)) {
        await _collectFiles(entity, relativePath, files);
      }
    }
  }

  static bool shouldSkipDirectory(String name) {
    final String lowerName = name.toLowerCase();
    return lowerName.startsWith('.') || _artifactDirectories.contains(lowerName);
  }

  static String _baseName(String path) => path.split(_pathSeparator).last;

  static int _compareByPath(FileModel first, FileModel second) {
    final int insensitive = first.path.toLowerCase().compareTo(second.path.toLowerCase());
    if (insensitive != 0) {
      return insensitive;
    }
    return first.path.compareTo(second.path);
  }
}
