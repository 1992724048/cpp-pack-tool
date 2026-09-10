import 'package:cpp_nuget_pack/models/build_model.dart';

enum FileType { header, source, resource, lib, dll, other }

class FileModel {
  final String name;
  final String path;
  final int size;
  String extension = '';
  FileType type = FileType.other;
  BuildModel buildModel = BuildModel.all;

  bool copyOutput = false;

  FileModel({required this.name, required this.path, this.size = 0}) {
    extension = name.split('.').last.toLowerCase();
    type = _determineFileType(extension);
  }

  FileType _determineFileType(String extension) {
    switch (extension) {
      case 'h':
      case 'hpp':
        return FileType.header;
      case 'c':
      case 'cpp':
        return FileType.source;
      case 'rc':
        return FileType.resource;
      case 'lib':
        return FileType.lib;
      case 'dll':
        return FileType.dll;
      default:
        return FileType.other;
    }
  }
}
