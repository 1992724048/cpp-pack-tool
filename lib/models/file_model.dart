import 'package:cpp_nuget_pack/models/build_model.dart';

enum FileType { header, source, module, resource, lib, dll, other }

const Map<String, FileType> _extensionTypes = {
  'h': FileType.header,
  'hpp': FileType.header,
  'hh': FileType.header,
  'hxx': FileType.header,
  'h++': FileType.header,
  'inl': FileType.header,
  'ipp': FileType.header,
  'tcc': FileType.header,
  'c': FileType.source,
  'cpp': FileType.source,
  'cc': FileType.source,
  'cxx': FileType.source,
  'c++': FileType.source,
  'ixx': FileType.module,
  'cppm': FileType.module,
  'ccm': FileType.module,
  'cxxm': FileType.module,
  'c++m': FileType.module,
  'mxx': FileType.module,
  'mpp': FileType.module,
  'rc': FileType.resource,
  'lib': FileType.lib,
  'dll': FileType.dll,
};

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
    return _extensionTypes[extension] ?? FileType.other;
  }
}
