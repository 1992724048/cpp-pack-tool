import 'dart:convert';

import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/nuget/license_file.dart';
import 'package:cpp_nuget_pack/shared/format.dart';

sealed class PackageEntrySource {
  const PackageEntrySource();

  int get size;
}

class PackageFileSource extends PackageEntrySource {
  const PackageFileSource({required this.path, required this.isBinary, required this.size}) : assert(path != '');

  final String path;
  final bool isBinary;
  @override
  final int size;
}

class PackageGeneratedSource extends PackageEntrySource {
  const PackageGeneratedSource({required this.content}) : assert(content != '');

  final String content;

  @override
  int get size => utf8.encode(content).length;
}

class PackageEntry {
  const PackageEntry({required this.packagePath, required this.source}) : assert(packagePath != '');

  final String packagePath;
  final PackageEntrySource source;
}

class PackagePlan {
  PackagePlan({required List<PackageEntry> entries}) : entries = List<PackageEntry>.unmodifiable(_sorted(entries));

  final List<PackageEntry> entries;

  int get fileCount => entries.length;

  int get totalSize => entries.fold<int>(0, (int sum, PackageEntry entry) => sum + entry.source.size);

  static List<PackageEntry> _sorted(List<PackageEntry> entries) {
    final List<PackageEntry> sorted = entries.toList()..sort(comparePackagePathsByEntry);
    return sorted;
  }
}

List<String> duplicatePackagePaths(PackagePlan plan) {
  final Map<String, String> firstPathByKey = <String, String>{};
  final Set<String> reportedKeys = <String>{};
  final List<String> duplicates = <String>[];
  for (final PackageEntry entry in plan.entries) {
    final String key = entry.packagePath.toLowerCase();
    final String? firstPath = firstPathByKey[key];
    if (firstPath == null) {
      firstPathByKey[key] = entry.packagePath;
    } else if (reportedKeys.add(key)) {
      duplicates.add(firstPath);
    }
  }
  return List<String>.unmodifiable(duplicates);
}

int comparePackagePathsByEntry(PackageEntry first, PackageEntry second) =>
    comparePackagePaths(first.packagePath, second.packagePath);

/// 包内布局路径的单一事实源。nuget_builder 与 header_include_fixer 都从这里取，
/// 避免两处各写一份字面量导致载荷推导静默失配。
const String buildRoot = 'build';

/// [buildNativeRoot] 的末段，字面必须是 native —— 它恰是 NuGet 为 .vcxproj 硬编码的
/// 目标框架标识 native@0.0，改名后整个 .targets 静默不导入（规格 §8 第 1 条）。
const String nativeTfmSegment = 'native';

const String buildNativeRoot = '$buildRoot/$nativeTfmSegment';

/// 相对 [buildNativeRoot] 的根目录名 —— 搜索根与载荷判定共用这一坐标系。
const String includeRelativeRoot = 'include';
const String filesRelativeRoot = 'files';

const String includeRoot = '$buildNativeRoot/$includeRelativeRoot';
const String filesRoot = '$buildNativeRoot/$filesRelativeRoot';

/// files/ 下的源文件子目录名。§5.2 的动态搜索根只覆盖它之下更深的目录。
const String sourceSubdirectory = 'source';

/// files/ 下的源文件根（相对 [buildNativeRoot]）。
const String sourceRelativeRoot = '$filesRelativeRoot/$sourceSubdirectory';

/// files/ 下全部 12 个子目录，顺序即发射顺序（保证 .targets 可重现）。
const List<String> filesSubdirectories = <String>[
  sourceSubdirectory, 'library', 'assembly', 'resource', 'script', 'msbuild',
  'fortran', 'llvm', 'python', 'data', 'executable', 'other',
];

/// library 子目录下需剥掉的首段（大小写不敏感）。
const Set<String> _libraryLeadingSegments = <String>{'lib', 'bin'};

String? stripBuildNative(String packagePath) {
  final String prefix = '$buildNativeRoot/';
  if (!packagePath.startsWith(prefix)) {
    return null;
  }
  return packagePath.substring(prefix.length);
}

/// 包内载荷落点（完整包内路径）。normalizedPath 须以 '/' 分隔且已归一。
/// 判定顺序：根级许可文件特例 → header/module → 其余按 FileType 取子目录。
String buildNativePayloadPath(String normalizedPath, FileType type, String namespace) {
  if (isRootLicenseFile(normalizedPath)) {
    return '$filesRoot/${baseName(normalizedPath)}';
  }
  if (type == FileType.header || type == FileType.module) {
    return '$includeRoot/${includePackageRelativePath(normalizedPath, namespace)}';
  }
  final String? subdirectory = filesSubdirectoryOf(type);
  if (subdirectory == null) {
    return '$filesRoot/$normalizedPath';
  }
  if (subdirectory == filesSubdirectoryOf(FileType.lib)) {
    return '$filesRoot/$subdirectory/${_withoutLeadingLibOrBin(normalizedPath)}';
  }
  return '$filesRoot/$subdirectory/$normalizedPath';
}

String _withoutLeadingLibOrBin(String path) {
  final int separator = path.indexOf('/');
  if (separator <= 0) {
    return path;
  }
  final String leading = path.substring(0, separator).toLowerCase();
  return _libraryLeadingSegments.contains(leading) ? path.substring(separator + 1) : path;
}

/// `.targets` 发射到 `ClCompile/AdditionalIncludeDirectories` 的搜索根，相对
/// [buildNativeRoot]、`/` 分隔：`include` + files/ 下全部 12 个子目录 + files/source/ 之下
/// 每个实际含源文件的目录。入参与出参同坐标系 —— 载荷路径（[stripBuildNative] 的结果）。
///
/// nuget_builder 原样发射该列表，header_include_fixer 用同一份判断包内能否解析。两者
/// 口径一旦分裂，要么产出注定失效的改写，要么把能解析的引用误报成「跳树」。
List<String> payloadSearchRoots(Iterable<String> relativePayloadPaths) {
  final List<String> sourceDirectories = <String>[];
  final Set<String> seenSourceDirectories = <String>{};
  for (final String relative in relativePayloadPaths) {
    if (!relative.toLowerCase().startsWith('$sourceRelativeRoot/')) {
      continue;
    }
    final int separator = relative.lastIndexOf('/');
    if (separator > sourceRelativeRoot.length) {
      final String directory = relative.substring(0, separator);
      if (seenSourceDirectories.add(directory)) {
        sourceDirectories.add(directory);
      }
    }
  }
  sourceDirectories.sort();
  return List<String>.unmodifiable(<String>[
    includeRelativeRoot,
    for (final String subdirectory in filesSubdirectories) '$filesRelativeRoot/$subdirectory',
    ...sourceDirectories,
  ]);
}

int comparePackagePaths(String first, String second) {
  final int insensitive = first.toLowerCase().compareTo(second.toLowerCase());
  if (insensitive != 0) {
    return insensitive;
  }
  return first.compareTo(second);
}

String includeNamespaceOf(String? sourcePath, String packageName) {
  final String folder = sourcePath == null || sourcePath.isEmpty ? '' : baseName(sourcePath);
  return folder.isEmpty ? packageName : folder;
}

String includePackageRelativePath(String path, String namespace) {
  final String relative = _stripLeadingInclude(path);
  final int separator = relative.indexOf('/');
  if (separator > 0 && relative.substring(0, separator).toLowerCase() == namespace.toLowerCase()) {
    return relative;
  }
  return '$namespace/$relative';
}

String _stripLeadingInclude(String path) {
  const String prefix = 'include/';
  if (path.length > prefix.length && path.substring(0, prefix.length).toLowerCase() == prefix) {
    return path.substring(prefix.length);
  }
  return path;
}
