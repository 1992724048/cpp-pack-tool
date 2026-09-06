import 'dart:io';

class FileScan {
  List<String> files = [];

  FileScan();

  void scanFiles(String directoryPath) {
    Directory directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw Exception('Directory does not exist: $directoryPath');
    }

    List<FileSystemEntity> entities = directory.listSync(recursive: true);
    for (var entity in entities) {
      if (entity is File) {
        files.add(entity.path);
      }
      if (entity is Directory) {
        scanFiles(entity.path);
      }
    }
  }
}
