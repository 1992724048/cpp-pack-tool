import 'package:cpp_nuget_pack/shared/format.dart';

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
  'ico': FileType.resource,
  'lib': FileType.lib,
  'a': FileType.lib,
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

const Set<String> _binaryExtensions = <String>{
  // 图片
  'ico', 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'tiff', 'cur',
  // 压缩包
  'zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz',
  // 字体
  'ttf', 'otf', 'woff', 'woff2',
  // 模型
  'onnx', 'pt', 'pth', 'safetensors', 'npy',
  // 二进制数据 / 符号
  'bin', 'dat', 'ilk', 'dbg', 'idb', 'obj',
};

/// 明确排除的文本类扩展名在此不列：map（链接器 map 文件）、exp（导出表）、
/// txt / md / json / xml / html / rc 均按文本处理。
/// [extension] 须为已小写归一的扩展名（[FileModel.extension] 即是）。
bool isBinaryFileType(FileType type, String extension) => switch (type) {
      FileType.lib || FileType.dll || FileType.pdb || FileType.executable => true,
      _ => _binaryExtensions.contains(extension),
    };

/// 包内 files/ 下的子目录名，取值须与 package_plan.dart 的 filesSubdirectories 对齐。
const Map<FileType, String> _filesSubdirectories = <FileType, String>{
  FileType.source: 'source',
  FileType.lib: 'library',
  FileType.dll: 'library',
  FileType.pdb: 'library',
  FileType.asm: 'assembly',
  FileType.resource: 'resource',
  FileType.script: 'script',
  FileType.fortran: 'fortran',
  FileType.llvm: 'llvm',
  FileType.python: 'python',
  FileType.database: 'data',
  FileType.executable: 'executable',
  FileType.other: 'other',
};

/// header / module 返回 null —— 它们落 include/ 而非 files/ 下。
String? filesSubdirectoryOf(FileType type) => _filesSubdirectories[type];

class FileModel {
  final String name;
  final String path;
  final int size;
  String extension = '';
  FileType type = FileType.other;

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
    return FileModel(name: baseName(path), path: path, size: (size as num?)?.toInt() ?? 0);
  }

  FileType _determineFileType(String extension) {
    return _extensionTypes[extension] ?? FileType.other;
  }
}
