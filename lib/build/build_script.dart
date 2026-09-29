import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

const String _buildScriptName = 'build.py';
const String packCacheDirName = '.cache';
const String packSourceDirName = 'src';
const String packTmpDirName = 'tmp';

bool isBuildScriptPath(String relativePath) {
  if (relativePath.contains('/') || relativePath.contains('\\')) {
    return false;
  }
  return relativePath.toLowerCase() == _buildScriptName;
}

FileModel? findBuildScript(List<FileModel> files) {
  final List<FileModel> candidates = files.where((FileModel file) => isBuildScriptPath(file.path)).toList()
    ..sort((FileModel first, FileModel second) => first.path.compareTo(second.path));
  return candidates.isEmpty ? null : candidates.first;
}

String packSourceDirectory(String packageRoot) =>
    _joinWindowsPath(joinPath(packageRoot, packCacheDirName), packSourceDirName);

String packTmpDirectory(String packageRoot) =>
    _joinWindowsPath(joinPath(packageRoot, packCacheDirName), packTmpDirName);

Future<void> clearPackTmpDirectory(String packageRoot) async {
  final Directory tmp = Directory(packTmpDirectory(packageRoot));
  if (await tmp.exists()) {
    await tmp.delete(recursive: true);
  }
  await tmp.create(recursive: true);
}

String _joinWindowsPath(String parent, String child) => joinPath(parent, child).replaceAll('/', r'\');
