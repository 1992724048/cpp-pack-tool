import 'package:cpp_nuget_pack/pack/model/file_model.dart';

final RegExp _licenseNamePattern = RegExp(r'^(license|licence|copying|unlicense|notice)([-.][a-z0-9]+)*$');

final RegExp _directorySeparator = RegExp(r'[/\\]');

const List<String> _coreNamePriority = <String>['license', 'licence', 'copying', 'unlicense', 'notice'];

bool isLicenseFileName(String name) => _licenseNamePattern.hasMatch(name.toLowerCase());

String? findPrimaryLicensePath(List<FileModel> files) {
  FileModel? primary;
  for (final FileModel file in files) {
    if (_directorySeparator.hasMatch(file.path) || !isLicenseFileName(file.name)) {
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
    if (lowerName == coreName || lowerName.startsWith('$coreName-') || lowerName.startsWith('$coreName.')) {
      return index;
    }
  }
  return _coreNamePriority.length;
}
