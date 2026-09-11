import 'dart:io';

/// 将实体路径规范化为 explorer 可识别的绝对路径（分隔符统一为 `\`）。
///
/// explorer 对混合分隔符路径（如 `D:\a/b.txt`）不报错但会静默打开默认位置，
/// 因此传给 explorer 前必须先把路径转为绝对路径并统一分隔符。
String explorerPath(FileSystemEntity entity) =>
    entity.absolute.path.replaceAll('/', r'\');

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
    await Process.run('explorer', <String>[explorerPath(file)]);
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
    await Process.run('explorer', <String>['/select,', explorerPath(file)]);
    return true;
  } on ProcessException {
    return false;
  }
}

/// 用系统默认浏览器打开外部链接。
///
/// 返回 false 表示链接不是 http/https 或系统调用失败。
Future<bool> openExternalUrl(String url) async {
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return false;
  }
  try {
    // explorer 可打开 URL；成功时退出码也恒为 1，因此不检查退出码。
    await Process.run('explorer', <String>[url]);
    return true;
  } on ProcessException {
    return false;
  }
}
