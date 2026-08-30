/// nuspec 生成器：将 [PackProject] 渲染为 NuGet `.nuspec` XML 文本。
///
/// - xmlns 沿用 `http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd`。
/// - metadata 段输出 id/version/authors/owners/requireLicenseAcceptance/
///   description/tags，license 与 repository 仅在非空时输出。
/// - files 段首个输出 MSBuild 集成文件条目（`build\native\{id}.props` 与
///   `{id}.targets`），随后按 `sourceDirs → mappings` 展开为 `<file src="..." target="..." />`。
/// - 所有动态值均做 XML 转义。
library;

import '../models/pack_project.dart';
import 'path_utils.dart';

/// 对 XML 文本做转义（& < > " '），用于属性值与元素文本。
String xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// 将 [PackProject] 生成为 nuspec 文本。
///
/// src 路径相对包工作目录（`baseDir`，由调用方传入，通常为打包输出目录）解析：
/// - 若 `srcGlob` 为绝对路径或已带 `..` 前导（即已是包相对路径），则原样使用；
/// - 否则若 `SourceDir.path` 在 `baseDir` 之外，用 `..` 相对路径拼接。
///
/// [baseDir] 为 null 或空时不做相对化，`srcGlob` 原样输出（按 nuspec 工作目录解析）。
String generate(PackProject project, {String? baseDir}) {
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
  sb.writeln(
    '<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">',
  );
  sb.writeln('  <metadata>');
  sb.writeln('    <id>${xmlEscape(project.packageId)}</id>');
  sb.writeln('    <version>${xmlEscape(project.version)}</version>');
  sb.writeln('    <authors>${xmlEscape(project.authors)}</authors>');
  sb.writeln('    <owners>${xmlEscape(project.owners)}</owners>');
  sb.writeln('    <requireLicenseAcceptance>false</requireLicenseAcceptance>');
  sb.writeln(
    '    <description>${xmlEscape(project.description)}</description>',
  );
  sb.writeln('    <tags>${xmlEscape(_normalizeTags(project.tags))}</tags>');
  if (project.license.trim().isNotEmpty) {
    sb.writeln('    <license>${xmlEscape(project.license)}</license>');
  }
  if (project.repository.trim().isNotEmpty) {
    sb.writeln('    <repository>${xmlEscape(project.repository)}</repository>');
  }
  sb.writeln('  </metadata>');
  sb.writeln('  <files>');
  _appendMsBuildEntries(sb, project.packageId.trim());
  for (final sourceDir in project.sourceDirs) {
    for (final mapping in sourceDir.mappings) {
      final src = _resolveSrc(baseDir, sourceDir, mapping);
      if (src.isEmpty) continue;
      sb.writeln(
        '    <file src="${xmlEscape(src)}" target="${xmlEscape(_resolveTarget(mapping))}" />',
      );
    }
  }
  sb.writeln('  </files>');
  sb.writeln('</package>');
  return sb.toString();
}

/// 写入 MSBuild 集成文件（props/targets）的 `<file>` 条目，置于 files 段最前。
///
/// 文件名与打包输出目录中的 `build\native\{id}.props` / `{id}.targets` 一致，
/// 使打包产物自带 MSBuild 集成（对照 V8.Native.nuspec 的 files 段前两条）。
void _appendMsBuildEntries(StringBuffer sb, String id) {
  for (final extension in const <String>['.props', '.targets']) {
    final entry = 'build\\native\\$id$extension';
    sb.writeln(
      '    <file src="${xmlEscape(entry)}" target="${xmlEscape(entry)}" />',
    );
  }
}

/// 将逗号分隔的标签字符串规范化为 NuGet 的空格分隔格式。
String _normalizeTags(String tags) =>
    tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).join(' ');

/// 解析某条文件映射在 nuspec 中的 src 值。
String _resolveSrc(String? baseDir, SourceDir sourceDir, FileMapping mapping) {
  final glob = mapping.srcGlob.trim();
  if (glob.isEmpty) return '';
  if (_isAbsolute(glob) || _startsWithParentSegment(glob)) {
    return glob;
  }

  final base = baseDir?.trim() ?? '';
  final sourcePath = sourceDir.path.trim();
  if (base.isEmpty || sourcePath.isEmpty) {
    return glob;
  }

  final rel = relativePath(base, sourcePath);
  if (rel.isEmpty) return glob;
  return '$rel$pathSeparator$glob';
}

/// 判断路径是否为绝对路径（如 `C:\...` 或 `\\server\...`）。
bool _isAbsolute(String path) {
  if (path.startsWith('\\') || path.startsWith('/')) return true;
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

/// 判断 glob 是否以 `..` 段开头（表示已是包相对路径）。
bool _startsWithParentSegment(String path) {
  final first = normalizeSeparators(path).split(pathSeparator).first;
  return first == '..';
}

/// 解析文件映射在 nuspec `<file>` 中的 target（包内路径）。
///
/// - 头文件映射（`mapping.isHeaderMapping`）的 target 语义为「最终 `#include`
///   路径」，此处展开为 `build\native\include\{target}`；
/// - 其余映射 target 原样输出。
/// - 向后兼容：若目标已带 `build\native\include\...` 前缀（旧配置），原样保留，
///   不重复添加前缀。
String _resolveTarget(FileMapping mapping) {
  final target = mapping.target.trim();
  if (target.isEmpty) return target;
  if (!mapping.isHeaderMapping) return target;
  if (startsWithMsBuildIncludeRoot(target)) return target;
  return joinPath(['build', 'native', 'include', target]);
}
