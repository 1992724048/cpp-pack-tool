import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 许可证类文件名识别（大小写不敏感）：`LICENSE` / `LICENSE-MIT` /
/// `COPYING.LESSER` / `NOTICE.md` / 前缀变体（如 `TBB-LICENSE`）。
final RegExp _licenseNamePattern = RegExp(
  r'^(license|licence|copying|unlicense|notice)([-.][a-z0-9]+)*$',
);

const String _iconFilePrefix = 'icon.';

const Set<String> _reservedFileNames = <String>{'build.py', 'pre.bat', 'post.bat'};

/// 是否保留在包源目录根（清空白名单）：
///
/// - `build.py`（大小写不敏感）：构建脚本本体，由工具侧固定读取；
/// - `icon.*`：包图标（任意名称前缀为 `icon.` 的文件）；
/// - `pre.bat` / `post.bat`：注册为系统编译命令的钩子脚本；
/// - 许可证类文件（[isLicenseLikeFileName]）。
bool isPreservedEntryName(String name) {
  final String lowered = name.toLowerCase();
  return _reservedFileNames.contains(lowered) ||
      lowered.startsWith(_iconFilePrefix) ||
      isLicenseLikeFileName(name);
}

/// 许可证类文件名（含前缀变体）识别：
///
/// - 标准名与后缀变体：`LICENSE`、`LICENSE-MIT`、`COPYING.LESSER`、`NOTICE.md`；
/// - 前缀变体：以 `-` / `.` 分隔的末段命中标准名（如 `TBB-LICENSE`）；
/// - 排除 `license_checker.py` 一类词内下划线文件（下划线不是分隔符）。
bool isLicenseLikeFileName(String name) {
  final String lowered = name.toLowerCase();
  if (_licenseNamePattern.hasMatch(lowered)) {
    return true;
  }
  final RegExpMatch? separator = RegExp(r'[-.]').firstMatch(lowered);
  if (separator == null || separator.start == 0) {
    return false;
  }
  return _licenseNamePattern.hasMatch(lowered.substring(separator.start + 1));
}

/// 清空包源目录 `BUILD_OUT` 中除白名单（[isPreservedEntryName]）外的一切，
/// 使每次构建的产物从干净状态开始；目录内容递归删除。
///
/// 根不存在时静默返回（由后续构建脚本创建输出）；删除失败（文件被占用等）
/// 抛 [PackBuildException]，错误文案列出全部失败路径。
Future<void> cleanupBuildOutput(String sourcePath) async {
  final Directory root = Directory(sourcePath);
  if (!await root.exists()) {
    return;
  }
  final List<FileSystemEntity> entries;
  try {
    entries = await root.list(followLinks: false).toList();
  } on FileSystemException catch (error) {
    throw PackBuildException('清理构建输出目录失败：$sourcePath（$error）');
  }
  final List<String> failed = <String>[];
  for (final FileSystemEntity entity in entries) {
    final String name = baseName(entity.path);
    if (isPreservedEntryName(name)) {
      continue;
    }
    if (!await _deleteEntry(entity)) {
      failed.add(entity.path);
    }
  }
  if (failed.isNotEmpty) {
    final String detail = failed
        .map((String path) => '  ${baseName(path)}')
        .join('\n');
    throw PackBuildException(
      '清理构建输出目录失败（${failed.length} 项无法删除，可能被占用）：\n$detail',
    );
  }
}

/// 删除单条目（目录递归）：首次失败重试一次（句柄/只读等瞬时拒绝），
/// 仍失败返回 false；条目在尝试期间消失视为删除成功。
Future<bool> _deleteEntry(FileSystemEntity entity) async {
  for (int attempt = 0; attempt < 2; attempt++) {
    try {
      await entity.delete(recursive: true);
      return true;
    } on FileSystemException {
      if (!await entity.exists()) {
        return true;
      }
    }
  }
  return false;
}
