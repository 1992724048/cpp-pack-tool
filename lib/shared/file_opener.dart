import 'dart:io';

String explorerPath(FileSystemEntity entity) => entity.absolute.path.replaceAll('/', r'\');

Future<bool> openWithDefaultApp(String filePath) async {
  final File file = File(filePath);
  if (!file.existsSync()) {
    return false;
  }
  try {
    await Process.run('explorer', <String>[explorerPath(file)]);
    return true;
  } on ProcessException {
    return false;
  }
}

Future<bool> revealInExplorer(String filePath) async {
  final File file = File(filePath);
  if (!file.existsSync()) {
    return false;
  }
  try {
    await Process.run('explorer', <String>['/select,', explorerPath(file)]);
    return true;
  } on ProcessException {
    return false;
  }
}

Future<bool> openExternalUrl(String url) async {
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return false;
  }
  try {
    await Process.run('explorer', <String>[url]);
    return true;
  } on ProcessException {
    return false;
  }
}
