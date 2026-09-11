import 'dart:io';

/// 用系统默认关联程序打开文件（等同资源管理器双击）。
///
/// 返回 false 表示文件不存在或系统调用失败。
Future<bool> openWithDefaultApp(String filePath) async {
  final File file = File(filePath);
  if (!file.existsSync()) {
    // explorer 对不存在的路径会静默打开「文档」窗口，必须先预检。
    return false;
  }
  try {
    // explorer 成功时退出码也恒为 1，因此不检查退出码。
    await Process.run('explorer', <String>[file.absolute.path]);
    return true;
  } on ProcessException {
    return false;
  }
}

/// 在资源管理器中定位文件（打开所在目录并选中该文件）。
///
/// 返回 false 表示文件不存在或系统调用失败。
Future<bool> revealInExplorer(String filePath) async {
  final File file = File(filePath);
  if (!file.existsSync()) {
    return false;
  }
  try {
    // `/select,` 与路径必须是两个独立参数；explorer 成功时退出码也恒为 1。
    await Process.run('explorer', <String>['/select,', file.absolute.path]);
    return true;
  } on ProcessException {
    return false;
  }
}
