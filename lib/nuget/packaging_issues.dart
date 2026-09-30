import 'package:cpp_nuget_pack/nuget/package_plan.dart';

class PackagingIssue {
  const PackagingIssue({required this.label, required this.message});
  
  final String label;
  final String message;
}

List<PackagingIssue> collectDuplicatePathIssues(PackagePlan plan) {
  final List<PackagingIssue> issues = <PackagingIssue>[
    for (final String path in duplicatePackagePaths(plan))
      PackagingIssue(label: '包内路径', message: '包内路径重复：$path'),
  ];
  return List<PackagingIssue>.unmodifiable(issues);
}

List<PackagingIssue> collectExecutableWarnings(PackagePlan plan) {
  final List<PackagingIssue> warnings = <PackagingIssue>[];
  for (final PackageEntry entry in plan.entries) {
    if (entry.packagePath.toLowerCase().endsWith('.exe')) {
      warnings.add(PackagingIssue(label: entry.packagePath, message: '可执行二进制随包分发'));
    }
  }
  return List<PackagingIssue>.unmodifiable(warnings);
}
