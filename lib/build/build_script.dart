import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

const String _buildScriptName = 'build.py';

/// 包内预置源码目录的固定名（工具自动探测，配方无需声明）。
///
/// 双重身份：备源分叉的唯一判据（见 [hasPresetSource]），也须出现在构建输出清理
/// 的白名单（`isPreservedEntryName`）中。白名单是 `build_cleanup.dart` 内的独立
/// 字面量，两者的一致性由清理侧的契约测试钉住：改动任一处都必须同步另一处，
/// 否则源码会在首次构建后的输出清理中被删除。
const String presetSourceDirName = '.cnp-src';

/// 是否为根级 `build.py`：不含任何路径分隔符且文件名大小写不敏感。
bool isBuildScriptPath(String relativePath) {
  if (relativePath.contains('/') || relativePath.contains('\\')) {
    return false;
  }
  return relativePath.toLowerCase() == _buildScriptName;
}

/// 根级 `build.py` 的字典序首个候选；无候选返回 null。
FileModel? findBuildScript(List<FileModel> files) {
  final List<FileModel> candidates =
      files.where((FileModel file) => isBuildScriptPath(file.path)).toList()
        ..sort(
          (FileModel first, FileModel second) =>
              first.path.compareTo(second.path),
        );
  return candidates.isEmpty ? null : candidates.first;
}

/// 包源目录 [sourcePath] 下的 [presetSourceDirName] 是否存在且含文件。
///
/// 备源分叉的唯一判据：备源实现（`build_runner.dart`）与构建对话框的
/// `sourceNone` 标记共用本函数，任一侧改动都会同时生效，不存在判据漂移。
Future<bool> hasPresetSource(String sourcePath) async {
  final Directory directory = Directory(
    joinPath(sourcePath, presetSourceDirName),
  );
  if (!await directory.exists()) {
    return false;
  }
  return _treeHasFile(directory);
}

/// 目录树内是否至少含一个文件（目录递归下探；不跟随链接）。
Future<bool> _treeHasFile(Directory directory) async {
  await for (final FileSystemEntity entry in directory.list(
    followLinks: false,
  )) {
    if (entry is File) {
      return true;
    }
    if (entry is Directory && await _treeHasFile(entry)) {
      return true;
    }
  }
  return false;
}
