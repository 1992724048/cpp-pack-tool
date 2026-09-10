import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';

class PackModel {
  final String name;
  final String version;
  final String author;
  final String? description;
  final String? license;
  final String? iconPath;
  final String? sourcePath;

  List<FileModel> files = [];
  List<CmdModel> cmds = [];
  List<DependencyModel> dependencies = [];

  static List<PackModel> packs = [];

  PackModel({
    required this.name,
    required this.version,
    required this.author,
    this.description,
    this.license,
    this.iconPath,
    this.sourcePath,
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'version': version,
      'author': author,
      if (description != null) 'description': description,
      if (license != null) 'license': license,
      if (iconPath != null) 'iconPath': iconPath,
      if (sourcePath != null) 'sourcePath': sourcePath,
      'files': <Map<String, Object?>>[
        for (final FileModel file in files) file.toMap(),
      ],
      'dependencies': <Map<String, Object?>>[
        for (final DependencyModel dependency in dependencies)
          dependency.toMap(),
      ],
    };
  }

  factory PackModel.fromMap(Map<String, Object?> map) {
    final PackModel pack = PackModel(
      name: _requiredString(map, 'name'),
      version: _requiredString(map, 'version'),
      author: _requiredString(map, 'author'),
      description: _optionalString(map, 'description'),
      license: _optionalString(map, 'license'),
      iconPath: _optionalString(map, 'iconPath'),
      sourcePath: _optionalString(map, 'sourcePath'),
    );

    final Object? files = map['files'];
    if (files != null) {
      if (files is! List) {
        throw const FormatException('files 字段类型错误，应为列表');
      }
      for (final Object? item in files) {
        if (item is! Map) {
          throw const FormatException('files 项类型错误，应为映射');
        }
        pack.files.add(FileModel.fromMap(_stringKeyMap(item)));
      }
    }

    final Object? dependencies = map['dependencies'];
    if (dependencies != null) {
      if (dependencies is! List) {
        throw const FormatException('dependencies 字段类型错误，应为列表');
      }
      for (final Object? item in dependencies) {
        if (item is! Map) {
          throw const FormatException('dependencies 项类型错误，应为映射');
        }
        pack.dependencies.add(DependencyModel.fromMap(_stringKeyMap(item)));
      }
    }
    return pack;
  }
}

Map<String, Object?> _stringKeyMap(Map<Object?, Object?> map) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in map.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String _requiredString(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value == null || (value is String && value.isEmpty)) {
    throw FormatException('缺少必填字段：$key');
  }
  if (value is! String) {
    throw FormatException('字段 $key 类型错误，应为字符串');
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('字段 $key 类型错误，应为字符串');
  }
  return value.isEmpty ? null : value;
}
