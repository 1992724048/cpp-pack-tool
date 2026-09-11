import 'dart:convert';

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

int comparePackagePathsByEntry(PackageEntry first, PackageEntry second) =>
    comparePackagePaths(first.packagePath, second.packagePath);

/// 包内路径排序规则：大小写不敏感，完全相同时以原串兜底。
int comparePackagePaths(String first, String second) {
  final int insensitive = first.toLowerCase().compareTo(second.toLowerCase());
  if (insensitive != 0) {
    return insensitive;
  }
  return first.compareTo(second);
}
