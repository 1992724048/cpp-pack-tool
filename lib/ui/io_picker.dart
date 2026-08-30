/// 系统选择器封装：目录选择与可执行文件选择。
///
/// 统一封装 `package:file_selector`，便于测试时替换（本文件是全应用唯一
/// 直接导入该包的入口，缩小依赖面）。
library;

import 'package:file_selector/file_selector.dart';

/// 弹出系统目录选择器，返回选中的目录绝对路径；取消返回 null。
Future<String?> pickDirectory({String? initialDirectory}) {
  return getDirectoryPath(initialDirectory: initialDirectory);
}

/// 弹出系统文件选择器（限定 .exe），返回选中文件路径；取消返回 null。
Future<String?> pickExecutable() async {
  const typeGroup = XTypeGroup(label: '可执行文件', extensions: <String>['exe']);
  final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
  return file?.path;
}

/// 弹出系统文件选择器（限定 .bat/.cmd/.ps1/.exe），用于构建前/后脚本；
/// 返回选中文件路径；取消返回 null。
Future<String?> pickScript() async {
  const typeGroup = XTypeGroup(
    label: '脚本/可执行文件',
    extensions: <String>['bat', 'cmd', 'ps1', 'exe'],
  );
  final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
  return file?.path;
}
