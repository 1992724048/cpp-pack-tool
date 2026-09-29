import 'package:cpp_nuget_pack/build/compiler_model.dart';

enum ThemeModeSetting { system, dark, light }

const List<String> _defaultCompilerPriority = <String>['icx', 'clang-cl', 'msvc'];

const Object _unset = Object();

class SettingsModel {
  const SettingsModel({
    this.outputDirectory,
    this.themeMode = ThemeModeSetting.system,
    this.compilerPriority = _defaultCompilerPriority,
    this.detectedCompilers = const <DetectedCompiler>[],
  });

  final String? outputDirectory;
  final ThemeModeSetting themeMode;
  final List<String> compilerPriority;
  final List<DetectedCompiler> detectedCompilers;

  SettingsModel copyWith({
    Object? outputDirectory = _unset,
    ThemeModeSetting? themeMode,
    List<String>? compilerPriority,
    List<DetectedCompiler>? detectedCompilers,
  }) {
    return SettingsModel(
      outputDirectory: identical(outputDirectory, _unset) ? this.outputDirectory : outputDirectory as String?,
      themeMode: themeMode ?? this.themeMode,
      compilerPriority: compilerPriority ?? this.compilerPriority,
      detectedCompilers: detectedCompilers ?? this.detectedCompilers,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (outputDirectory != null) 'outputDirectory': outputDirectory,
      'themeMode': themeMode.name,
      'compilerPriority': <String>[...compilerPriority],
      if (detectedCompilers.isNotEmpty)
        'detectedCompilers': <Map<String, Object?>>[
          for (final DetectedCompiler compiler in detectedCompilers) _detectedCompilerToMap(compiler),
        ],
    };
  }

  factory SettingsModel.fromMap(Map<String, Object?> map) {
    return SettingsModel(
      outputDirectory: _optionalString(map['outputDirectory']),
      themeMode: _themeModeFrom(map['themeMode']),
      compilerPriority: _compilerPriorityFrom(map['compilerPriority']),
      detectedCompilers: _detectedCompilersFrom(map['detectedCompilers']),
    );
  }
}

Map<String, Object?> _detectedCompilerToMap(DetectedCompiler compiler) {
  return <String, Object?>{
    'kind': compilerKindId(compiler.kind),
    'version': compiler.version,
    'executablePath': compiler.executablePath,
    if (compiler.cxxExecutablePath != null && compiler.cxxExecutablePath!.isNotEmpty)
      'cxxExecutablePath': compiler.cxxExecutablePath,
    if (compiler.environmentScript != null && compiler.environmentScript!.isNotEmpty)
      'environmentScript': compiler.environmentScript,
    if (compiler.extraPathEntries.isNotEmpty) 'extraPathEntries': <String>[...compiler.extraPathEntries],
  };
}

List<DetectedCompiler> _detectedCompilersFrom(Object? value) {
  if (value is! List) {
    return const <DetectedCompiler>[];
  }
  if (value.any(_hasUnrecognizedCompilerKind)) {
    return const <DetectedCompiler>[];
  }
  final List<DetectedCompiler> compilers = <DetectedCompiler>[];
  for (final Object? item in value) {
    final DetectedCompiler? compiler = _detectedCompilerFrom(item);
    if (compiler != null) {
      compilers.add(compiler);
    }
  }
  return compilers;
}

bool _hasUnrecognizedCompilerKind(Object? value) {
  if (value is! Map) {
    return false;
  }
  final Object? kindValue = value['kind'];
  return kindValue is String && compilerKindFromId(kindValue) == null;
}

DetectedCompiler? _detectedCompilerFrom(Object? value) {
  if (value is! Map) {
    return null;
  }
  final Object? kindValue = value['kind'];
  final CompilerKind? kind = kindValue is String ? compilerKindFromId(kindValue) : null;
  final String? version = _nonEmptyString(value['version']);
  final String? executablePath = _nonEmptyString(value['executablePath']);
  if (kind == null || version == null || executablePath == null) {
    return null;
  }
  return DetectedCompiler(
    kind: kind,
    version: version,
    executablePath: executablePath,
    cxxExecutablePath: _nonEmptyString(value['cxxExecutablePath']),
    environmentScript: _nonEmptyString(value['environmentScript']),
    extraPathEntries: _stringList(value['extraPathEntries']),
  );
}

String? _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return <String>[
    for (final Object? item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

List<String> _compilerPriorityFrom(Object? value) {
  if (value is! List) {
    return _defaultCompilerPriority;
  }
  final List<String> entries = <String>[];
  final Set<String> seen = <String>{};
  for (final Object? item in value) {
    if (item is! String || item.trim().isEmpty) {
      continue;
    }
    final String id = isLegacyCompilerKindId(item) ? 'clang-cl' : item.trim();
    if (compilerKindFromId(id) != null && seen.add(id)) {
      entries.add(id);
    }
  }
  for (final CompilerKind kind in CompilerKind.values) {
    final String id = compilerKindId(kind);
    if (seen.add(id)) {
      entries.add(id);
    }
  }
  return entries;
}

String? _optionalString(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return value;
}

ThemeModeSetting _themeModeFrom(Object? value) {
  if (value is String) {
    for (final ThemeModeSetting mode in ThemeModeSetting.values) {
      if (mode.name == value) {
        return mode;
      }
    }
  }
  return ThemeModeSetting.system;
}
