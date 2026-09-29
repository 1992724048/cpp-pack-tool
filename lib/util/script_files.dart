import 'package:cpp_nuget_pack/util/format.dart';

const Set<String> scriptFileExtensions = <String>{'bat', 'cmd', 'exe', 'ps1', 'py'};

bool isScriptFilePath(String path) {
  final String name = baseName(path);
  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return false;
  }
  return scriptFileExtensions.contains(name.substring(dot + 1).toLowerCase());
}
