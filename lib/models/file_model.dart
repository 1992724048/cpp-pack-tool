import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

enum FileType {
  header,
  source,
  module,
  resource,
  lib,
  dll,
  pdb,
  asm,
  fortran,
  script,
  llvm,
  python,
  database,
  executable,
  other,
}

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
  'pdb': FileType.pdb,
  'asm': FileType.asm,
  's': FileType.asm,
  'nasm': FileType.asm,
  'f': FileType.fortran,
  'for': FileType.fortran,
  'f77': FileType.fortran,
  'f90': FileType.fortran,
  'f95': FileType.fortran,
  'f03': FileType.fortran,
  'f08': FileType.fortran,
  'bat': FileType.script,
  'cmd': FileType.script,
  'ps1': FileType.script,
  'vbs': FileType.script,
  'll': FileType.llvm,
  'bc': FileType.llvm,
  'py': FileType.python,
  'pyw': FileType.python,
  'pyi': FileType.python,
  'db': FileType.database,
  'exe': FileType.executable,
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

  Map<String, Object?> toMap() => <String, Object?>{'path': path, 'size': size};

  factory FileModel.fromMap(Map<String, Object?> map) {
    final Object? path = map['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('文件缺少 path 字段');
    }
    final Object? size = map['size'];
    if (size != null && size is! num) {
      throw const FormatException('文件 size 字段类型错误，应为整数');
    }
    return FileModel(
      name: baseName(path),
      path: path,
      size: (size as num?)?.toInt() ?? 0,
    );
  }

  FileType _determineFileType(String extension) {
    return _extensionTypes[extension] ?? FileType.other;
  }
}
