import 'dart:convert';

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

String? buildNativeRelativePath(String packagePath) {
  const String prefix = 'build/native/';
  if (!packagePath.startsWith(prefix)) {
    return null;
  }
  return packagePath.substring(prefix.length);
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
