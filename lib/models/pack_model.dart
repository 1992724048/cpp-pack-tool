import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

class PackModel {
  final String name;
  final String version;
  final String author;
  final String? description;
  final String? license;
  final String? iconPath;
  final String? sourcePath;

  List<FileModel> files = [];
  List<CmdModel> commands = [];
  List<DependencyModel> dependencies = [];
  List<MacroModel> macros = [];
  List<LibDirModel> libDirectories = [];
  List<LibraryModel> libraries = [];
  List<HistoryModel> history = [];
  List<ScriptProjectModel> scripts = [];

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
      'commands': <Map<String, Object?>>[
        for (final CmdModel command in commands) command.toMap(),
      ],
      'macros': <Map<String, Object?>>[
        for (final MacroModel macro in macros) macro.toMap(),
      ],
      'libDirectories': <Map<String, Object?>>[
        for (final LibDirModel libDirectory in libDirectories)
          libDirectory.toMap(),
      ],
      'libraries': <Map<String, Object?>>[
        for (final LibraryModel library in libraries) library.toMap(),
      ],
      'history': <Map<String, Object?>>[
        for (final HistoryModel entry in history) entry.toMap(),
      ],
      'scripts': <Map<String, Object?>>[
        for (final ScriptProjectModel script in scripts) script.toMap(),
      ],
    };
  }

  factory PackModel.fromMap(
    Map<String, Object?> map, {
    List<String>? warnings,
  }) {
    final PackModel pack = PackModel(
      name: _requiredString(map, 'name'),
      version: _requiredString(map, 'version'),
      author: _requiredString(map, 'author'),
      description: _optionalString(map, 'description'),
      license: _optionalString(map, 'license'),
      iconPath: _optionalString(map, 'iconPath'),
      sourcePath: _optionalString(map, 'sourcePath'),
    );

    pack.files.addAll(<FileModel>[
      for (final Map<String, Object?> item in _mapList(map, 'files'))
        FileModel.fromMap(item),
    ]);
    pack.dependencies.addAll(<DependencyModel>[
      for (final Map<String, Object?> item in _mapList(map, 'dependencies'))
        DependencyModel.fromMap(item),
    ]);
    pack.commands.addAll(<CmdModel>[
      for (final Map<String, Object?> item in _mapList(map, 'commands'))
        CmdModel.fromMap(item),
    ]);
    pack.macros.addAll(<MacroModel>[
      for (final Map<String, Object?> item in _mapList(map, 'macros'))
        MacroModel.fromMap(item),
    ]);
    pack.libDirectories.addAll(<LibDirModel>[
      for (final Map<String, Object?> item in _mapList(map, 'libDirectories'))
        LibDirModel.fromMap(item),
    ]);
    pack.libraries.addAll(<LibraryModel>[
      for (final Map<String, Object?> item in _mapList(map, 'libraries'))
        LibraryModel.fromMap(item),
    ]);
    pack.history.addAll(<HistoryModel>[
      for (final Map<String, Object?> item in _mapList(map, 'history'))
        HistoryModel.fromMap(item),
    ]);

    final Set<String> scriptIds = <String>{};
    for (final Map<String, Object?> item in _mapList(map, 'scripts')) {
      try {
        final ScriptProjectModel script = ScriptProjectModel.fromMap(
          item,
          warnings: warnings,
        );
        if (!scriptIds.add(script.id)) {
          warnings?.add('脚本 id 重复，已丢弃：${script.id}');
          continue;
        }
        pack.scripts.add(script);
      } catch (error) {
        warnings?.add(_describeScriptError(item, error));
      }
    }
    return pack;
  }
}

List<Map<String, Object?>> _mapList(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value == null) {
    return const <Map<String, Object?>>[];
  }
  if (value is! List) {
    throw FormatException('$key 字段类型错误，应为列表');
  }
  final List<Map<String, Object?>> items = <Map<String, Object?>>[];
  for (final Object? item in value) {
    if (item is! Map) {
      throw FormatException('$key 项类型错误，应为映射');
    }
    items.add(_stringKeyMap(item));
  }
  return items;
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

String _describeScriptError(Map<String, Object?> item, Object error) {
  final Object? id = item['id'];
  final String label = id is String && id.isNotEmpty ? id : '未知 id';
  return '脚本「$label」解析失败，已丢弃：${formatError(error)}';
}
