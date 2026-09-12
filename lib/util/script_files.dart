import 'package:cpp_nuget_pack/util/format.dart';

/// 打包管线识别的可执行脚本扩展名（小写、无点）。
///
/// 「编译设置」的从包中选择脚本与节点检查器的 `scriptFilePath` 建议
/// 列表共用；扩展名大小写不敏感。
const Set<String> scriptFileExtensions = <String>{'bat', 'cmd', 'exe', 'ps1', 'py'};

/// 包内路径（`/` 或 `\` 分隔）是否为脚本文件：取 basename 最后一个 `.`
/// 之后的扩展名（小写）判断；无扩展名或点号位于首/末位返回 false。
bool isScriptFilePath(String path) {
  final String name = baseName(path);
  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return false;
  }
  return scriptFileExtensions.contains(name.substring(dot + 1).toLowerCase());
}
