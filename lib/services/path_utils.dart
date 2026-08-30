/// 内部路径工具：用于 Windows 风格路径的拼接、相对化与目录名提取。
///
/// 这些工具刻意不依赖 `package:path`（该项目未声明该依赖，避免
/// `depend_on_referenced_packages` 告警），仅使用 `dart:core` 与 `dart:io`
/// 的平台常量。生成的路径统一使用 `\` 分隔符，与 nuspec/props/targets 惯例一致。
library;

/// 平台路径分隔符（Windows 上为 `\`）。
String get pathSeparator => '\\';

/// 规范化路径分隔符（`/` 与 `\` 统一为 `\`）。
String normalizeSeparators(String path) => path.replaceAll('/', pathSeparator);

/// 拼接路径段，忽略空段。
String joinPath(List<String> segments) {
  final parts = <String>[];
  for (final segment in segments) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) continue;
    parts.add(trimmed);
  }
  if (parts.isEmpty) return '';
  return parts.join(pathSeparator);
}

/// 取路径中的目录名/文件名（最后一个非空段）。
String basenameOf(String path) {
  final normalized = normalizeSeparators(path.trim());
  if (normalized.isEmpty) return '';
  final segments = normalized.split(pathSeparator);
  return segments.last;
}

/// 取路径的父目录（去掉最后一个非空段）。无父目录时返回空串。
String dirnameOf(String path) {
  final normalized = normalizeSeparators(path.trim());
  if (normalized.isEmpty) return '';
  final segments = normalized.split(pathSeparator);
  segments.removeLast();
  return segments.join(pathSeparator);
}

/// 判断两个路径是否属于同一盘符（如 `C:` 与 `D:` 不共享相对路径）。
bool sameVolume(String a, String b) {
  final rootA = _driveRootOf(a);
  final rootB = _driveRootOf(b);
  if (rootA == null || rootB == null) return true;
  return rootA.toLowerCase() == rootB.toLowerCase();
}

String? _driveRootOf(String path) {
  final normalized = normalizeSeparators(path);
  if (normalized.length >= 2 && RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    return normalized.substring(0, 2);
  }
  return null;
}

/// 计算从 [from] 到 [to] 的相对路径（均为目录）。
///
/// - 若两者在同一盘符，返回带 `..` 的相对路径（含空串表示同一目录）。
/// - 若在不同盘符，返回 `to` 的原样路径（无法用相对路径表示）。
String relativePath(String from, String to) {
  final fromNorm = _stripTrailing(normalizeSeparators(from.trim()));
  final toNorm = _stripTrailing(normalizeSeparators(to.trim()));
  if (fromNorm.isEmpty || toNorm.isEmpty) return toNorm;
  if (!sameVolume(fromNorm, toNorm)) return toNorm;

  final fromParts = fromNorm.split(pathSeparator);
  final toParts = toNorm.split(pathSeparator);
  var common = 0;
  final limit = fromParts.length < toParts.length
      ? fromParts.length
      : toParts.length;
  while (common < limit &&
      fromParts[common].toLowerCase() == toParts[common].toLowerCase()) {
    common++;
  }

  final up = List<String>.filled(fromParts.length - common, '..');
  final down = toParts.sublist(common);
  return [...up, ...down].join(pathSeparator);
}

/// 去除结尾的多余分隔符（用于目录路径）。
String _stripTrailing(String path) => path.endsWith(pathSeparator)
    ? path.substring(0, path.length - pathSeparator.length)
    : path;
