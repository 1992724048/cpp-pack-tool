import 'dart:io';

import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

class PackLoadError {
  const PackLoadError({required this.fileName, required this.message});

  final String fileName;
  final String message;

  @override
  String toString() => '$fileName：$message';
}

typedef PackLoadResult = ({List<PackModel> packs, List<PackLoadError> errors});

class PackStore {
  const PackStore({this.rootPath = 'config'});

  final String rootPath;

  Directory get root => Directory(rootPath);

  Directory get packsDirectory => Directory('$rootPath/packs');

  File get configFile => File('$rootPath/config.yaml');

  Future<void> ensureConfigExist() async {
    await packsDirectory.create(recursive: true);
    if (!await configFile.exists()) {
      await configFile.writeAsString('version: 1\n', flush: true);
    }
  }

  Future<PackLoadResult> loadPacks() async {
    final List<PackModel> packs = <PackModel>[];
    final List<PackLoadError> errors = <PackLoadError>[];
    if (!await packsDirectory.exists()) {
      return (packs: packs, errors: errors);
    }

    final List<File> files = <File>[];
    await for (final FileSystemEntity entity in packsDirectory.list(
      followLinks: false,
    )) {
      if (entity is File && entity.path.toLowerCase().endsWith('.yaml')) {
        files.add(entity);
      }
    }
    files.sort(
      (File first, File second) =>
          _compareNames(baseName(first.path), baseName(second.path)),
    );

    for (final File file in files) {
      try {
        final String content = await file.readAsString();
        final Object? document = loadYaml(content);
        if (document is! Map) {
          throw const FormatException('文件内容为空或不是 YAML 映射');
        }
        final List<String> warnings = <String>[];
        packs.add(
          PackModel.fromMap(_stringKeyMap(document), warnings: warnings),
        );
        for (final String warning in warnings) {
          errors.add(
            PackLoadError(fileName: baseName(file.path), message: warning),
          );
        }
      } catch (error) {
        errors.add(
          PackLoadError(
            fileName: baseName(file.path),
            message: formatError(error),
          ),
        );
      }
    }

    packs.sort(
      (PackModel first, PackModel second) =>
          _compareNames(first.name, second.name),
    );
    return (packs: packs, errors: errors);
  }

  Future<void> savePack(PackModel pack) async {
    await ensureConfigExist();
    final File file = File(
      '${packsDirectory.path}/${sanitizeFileName(pack.name)}.yaml',
    );

    final Map<String, Object?> payload = pack.toMap();
    final String? description = pack.description;
    if (description != null && description.contains('\n')) {
      payload['description'] = wrapAsYamlNode(
        description,
        scalarStyle: ScalarStyle.LITERAL,
      );
    }

    final YamlEditor editor = YamlEditor('');
    editor.update(<Object?>[], payload);
    final String yaml = editor.toString();
    await file.writeAsString(
      yaml.endsWith('\n') ? yaml : '$yaml\n',
      flush: true,
    );
  }

  Future<void> deletePack(String name) async {
    final File file = File(
      '${packsDirectory.path}/${sanitizeFileName(name)}.yaml',
    );
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<SettingsModel> loadSettings() async {
    final File file = configFile;
    if (!await file.exists()) {
      return const SettingsModel();
    }
    try {
      final String content = await file.readAsString();
      final Object? document = loadYaml(content);
      if (document is! Map) {
        return const SettingsModel();
      }
      return SettingsModel.fromMap(_stringKeyMap(document));
    } catch (_) {
      return const SettingsModel();
    }
  }

  Future<void> saveSettings(SettingsModel settings) async {
    await ensureConfigExist();
    final Map<String, Object?> payload = <String, Object?>{
      'version': 1,
      ...settings.toMap(),
    };

    final YamlEditor editor = YamlEditor('');
    editor.update(<Object?>[], payload);
    final String yaml = editor.toString();
    await configFile.writeAsString(
      yaml.endsWith('\n') ? yaml : '$yaml\n',
      flush: true,
    );
  }

  static String sanitizeFileName(String name) {
    final String sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final String capped = String.fromCharCodes(sanitized.runes.take(100));
    return capped.isEmpty ? 'pack' : capped;
  }
}

Map<String, Object?> _stringKeyMap(Map<Object?, Object?> map) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in map.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

int _compareNames(String first, String second) {
  final int insensitive = first.toLowerCase().compareTo(second.toLowerCase());
  if (insensitive != 0) {
    return insensitive;
  }
  return first.compareTo(second);
}
