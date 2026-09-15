import 'package:cpp_nuget_pack/models/file_model.dart';

final RegExp _licenseNamePattern = RegExp(
  r'^(license|licence|copying|unlicense|notice)([-.][a-z0-9]+)*$',
);

final RegExp _directorySeparator = RegExp(r'[/\\]');

/// 核心名优先级：`license > licence > copying > unlicense > notice`。
const List<String> _coreNamePriority = <String>[
  'license',
  'licence',
  'copying',
  'unlicense',
  'notice',
];

/// 是否为许可证文件名（大小写不敏感）：`LICENSE`、`LICENSE-MIT`、
/// `COPYING.LESSER`、`NOTICE.md` 匹配；`license_checker.dart` 不匹配。
bool isLicenseFileName(String name) =>
    _licenseNamePattern.hasMatch(name.toLowerCase());

/// 源目录根部的首选许可证路径；无匹配返回 null。
///
/// 仅接受路径不含目录分隔符的条目（子目录许可证不参与）；先按核心名
/// 优先级，同核心名按小写文件名字典序（`LICENSE` 优先于 `LICENSE.txt`）。
String? findPrimaryLicensePath(List<FileModel> files) {
  FileModel? primary;
  for (final FileModel file in files) {
    if (_directorySeparator.hasMatch(file.path) ||
        !isLicenseFileName(file.name)) {
      continue;
    }
    if (primary == null || _precedes(file.name, primary.name)) {
      primary = file;
    }
  }
  return primary?.path;
}

bool _precedes(String candidateName, String currentName) {
  final String candidate = candidateName.toLowerCase();
  final String current = currentName.toLowerCase();
  final int candidateRank = _coreRank(candidate);
  final int currentRank = _coreRank(current);
  if (candidateRank != currentRank) {
    return candidateRank < currentRank;
  }
  return candidate.compareTo(current) < 0;
}

int _coreRank(String lowerName) {
  for (int index = 0; index < _coreNamePriority.length; index++) {
    final String coreName = _coreNamePriority[index];
    if (lowerName == coreName ||
        lowerName.startsWith('$coreName-') ||
        lowerName.startsWith('$coreName.')) {
      return index;
    }
  }
  return _coreNamePriority.length;
}
