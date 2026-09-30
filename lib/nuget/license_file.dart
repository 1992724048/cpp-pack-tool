import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/shared/format.dart';

final RegExp _licenseNamePattern = RegExp(r'^(license|licence|copying|unlicense|notice)([-.][a-z0-9]+)*$');

final RegExp _directorySeparator = RegExp(r'[/\\]');

bool isLicenseFileName(String name) => _licenseNamePattern.hasMatch(name.toLowerCase());

/// 归一化后的源路径是否落在「根级许可文件」特例上：无路径分隔符且名字命中许可名模式。
bool isRootLicenseFile(String normalizedPath) =>
    !_directorySeparator.hasMatch(normalizedPath) &&
    isLicenseFileName(baseName(normalizedPath));

/// 全部根级许可文件的源路径，按小写路径字典序（确定性）。
List<String> findLicensePaths(List<FileModel> files) {
  final List<String> paths = <String>[
    for (final FileModel file in files)
      if (isRootLicenseFile(file.path)) file.path,
  ]..sort(_compareLicensePaths);
  return List<String>.unmodifiable(paths);
}

int _compareLicensePaths(String first, String second) {
  final int insensitive = first.toLowerCase().compareTo(second.toLowerCase());
  return insensitive != 0 ? insensitive : first.compareTo(second);
}
