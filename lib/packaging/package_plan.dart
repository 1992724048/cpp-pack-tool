import 'dart:convert';

import 'package:cpp_nuget_pack/util/format.dart';

sealed class PackageEntrySource {
  const PackageEntrySource();

  int get size;
}

class PackageFileSource extends PackageEntrySource {
  const PackageFileSource({
    required this.path,
    required this.isBinary,
    required this.size,
  }) : assert(path != '');

  /// 相对于包源目录的相对路径。
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
  const PackageEntry({required this.packagePath, required this.source})
    : assert(packagePath != '');

  final String packagePath;
  final PackageEntrySource source;
}

class PackagePlan {
  PackagePlan({required List<PackageEntry> entries})
    : entries = List<PackageEntry>.unmodifiable(_sorted(entries));

  final List<PackageEntry> entries;

  int get fileCount => entries.length;

  int get totalSize => entries.fold<int>(
    0,
    (int sum, PackageEntry entry) => sum + entry.source.size,
  );

  static List<PackageEntry> _sorted(List<PackageEntry> entries) {
    final List<PackageEntry> sorted = entries.toList()
      ..sort(comparePackagePathsByEntry);
    return sorted;
  }
}

/// 包内路径重复项（大小写不敏感）：按 [PackagePlan.entries] 顺序返回每组首次出现的
/// 原样路径，同组只报一次；无重复时为空列表。
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

/// `build/native/` 下的包内相对路径（不含该前缀）；不在该前缀下时返回 null。
///
/// NuGet 布局的工具链引用（MSBuild 项目文件）与包内文件建议均以该相对路径
/// 为基准，含前缀会组合出重复路径。
String? buildNativeRelativePath(String packagePath) {
  const String prefix = 'build/native/';
  if (!packagePath.startsWith(prefix)) {
    return null;
  }
  return packagePath.substring(prefix.length);
}

/// 包内路径排序规则：大小写不敏感，完全相同时以原串兜底。
int comparePackagePaths(String first, String second) {
  final int insensitive = first.toLowerCase().compareTo(second.toLowerCase());
  if (insensitive != 0) {
    return insensitive;
  }
  return first.compareTo(second);
}

/// 头文件顶层命名空间目录：源目录名，缺失或为空时回退包名。
String includeNamespaceOf(String? sourcePath, String packageName) {
  final String folder = sourcePath == null || sourcePath.isEmpty
      ? ''
      : baseName(sourcePath);
  return folder.isEmpty ? packageName : folder;
}

/// 头文件剥离开头 `include/` 并在命名空间目录下的包内相对路径。
///
/// 剩余路径首段已与命名空间同名（大小写不敏感）时不再叠加，避免
/// `include/gtest/gtest.h` 映射为 `gtest/gtest/gtest.h` 这类重复层；
/// 平铺文件与异名目录维持前置命名空间。
String includePackageRelativePath(String path, String namespace) {
  final String relative = _stripLeadingInclude(path);
  final int separator = relative.indexOf('/');
  if (separator > 0 &&
      relative.substring(0, separator).toLowerCase() ==
          namespace.toLowerCase()) {
    return relative;
  }
  return '$namespace/$relative';
}

String _stripLeadingInclude(String path) {
  const String prefix = 'include/';
  if (path.length > prefix.length &&
      path.substring(0, prefix.length).toLowerCase() == prefix) {
    return path.substring(prefix.length);
  }
  return path;
}
