import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';

abstract final class FileScan {
  static final RegExp _pathSeparator = RegExp(r'[/\\]');

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

  static Future<void> _collectFiles(
    Directory directory,
    String relativePrefix,
    List<FileModel> files,
  ) async {
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      final String name = _baseName(entity.path);
      final String relativePath = relativePrefix.isEmpty
          ? name
          : '$relativePrefix/$name';

      if (entity is File) {
        final FileStat stat = await entity.stat();
        files.add(FileModel(name: name, path: relativePath, size: stat.size));
        continue;
      }
      if (entity is Directory && !_shouldSkipDirectory(name)) {
        await _collectFiles(entity, relativePath, files);
      }
    }
  }

  static bool _shouldSkipDirectory(String name) {
    final String lowerName = name.toLowerCase();
    return lowerName.startsWith('.') ||
        lowerName == 'build' ||
        lowerName == 'out';
  }

  static String _baseName(String path) => path.split(_pathSeparator).last;

  static int _compareByPath(FileModel first, FileModel second) {
    final int insensitive = first.path.toLowerCase().compareTo(
      second.path.toLowerCase(),
    );
    if (insensitive != 0) {
      return insensitive;
    }
    return first.path.compareTo(second.path);
  }
}
