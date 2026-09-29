import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

const String _buildScriptName = 'build.py';

/// 包源目录下配方工作区的固定目录名（隐藏目录）。
const String packCacheDirName = '.cache';

/// [packCacheDirName] 下的源码区目录名，即 `CNP_SRC_DIR` 末段。
const String packSourceDirName = 'src';

/// [packCacheDirName] 下的中间产物区目录名，即 `CNP_TMP_DIR` 末段。
const String packTmpDirName = 'tmp';

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

/// 包源目录 [packageRoot] 下的源码区（`CNP_SRC_DIR`），全反斜杠。
String packSourceDirectory(String packageRoot) => _joinWindowsPath(
  joinPath(packageRoot, packCacheDirName),
  packSourceDirName,
);

/// 包源目录 [packageRoot] 下的中间产物区（`CNP_TMP_DIR`），全反斜杠。
String packTmpDirectory(String packageRoot) =>
    _joinWindowsPath(joinPath(packageRoot, packCacheDirName), packTmpDirName);

/// 清空并重建 [packTmpDirName]。配方自行放置中间产物，软件只保证每次构建从
/// 干净的 tmp 开始。
///
/// 不存在的 tmp 视为已清空（首次构建的常态）；不可读/不可写时向上抛错，不静默
/// 吞掉——静默会让配方在脏目录上构建，产出不可复现的结果。
Future<void> clearPackTmpDirectory(String packageRoot) async {
  final Directory tmp = Directory(packTmpDirectory(packageRoot));
  if (await tmp.exists()) {
    await tmp.delete(recursive: true);
  }
  await tmp.create(recursive: true);
}

String _joinWindowsPath(String parent, String child) =>
    joinPath(parent, child).replaceAll('/', r'\');
