import 'package:cpp_nuget_pack/models/file_model.dart';

const String _buildScriptName = 'build.py';

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

/// 解析 build.py 首行的 git 仓库地址（`# <仓库地址>`）。
///
/// 首行 trim 后必须以 `#` 开头且 `#` 之后仍有非空内容，否则返回 null。
String? parseBuildScriptRepo(String content) {
  final int breakIndex = content.indexOf('\n');
  final String firstLine =
      (breakIndex < 0 ? content : content.substring(0, breakIndex)).trim();
  if (!firstLine.startsWith('#')) {
    return null;
  }
  final String repository = firstLine.substring(1).trim();
  return repository.isEmpty ? null : repository;
}
