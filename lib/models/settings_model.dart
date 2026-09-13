import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';

enum ThemeModeSetting { system, dark, light }

const List<String> _defaultCompilerPriority = <String>[
  'icx',
  'clang-cl',
  'msvc',
];

class SettingsModel {
  const SettingsModel({
    this.outputDirectory,
    this.themeMode = ThemeModeSetting.system,
    this.darkFlavor = 'mocha',
    this.accent = 'teal',
    this.compilerPriority = _defaultCompilerPriority,
    this.detectedCompilers = const <DetectedCompiler>[],
  });

  final String? outputDirectory;
  final ThemeModeSetting themeMode;
  final String darkFlavor;
  final String accent;

  /// 编译器优先级（`icx` / `clang-cl` / `msvc`，自高到低）。
  final List<String> compilerPriority;

  /// 上次编译器检测结果缓存；空表示无缓存（设置页与构建据此重检）。
  final List<DetectedCompiler> detectedCompilers;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (outputDirectory != null) 'outputDirectory': outputDirectory,
      'themeMode': themeMode.name,
      'darkFlavor': darkFlavor,
      'accent': accent,
      'compilerPriority': <String>[...compilerPriority],
      if (detectedCompilers.isNotEmpty)
        'detectedCompilers': <Map<String, Object?>>[
          for (final DetectedCompiler compiler in detectedCompilers)
            _detectedCompilerToMap(compiler),
        ],
    };
  }

  factory SettingsModel.fromMap(Map<String, Object?> map) {
    return SettingsModel(
      outputDirectory: _optionalString(map['outputDirectory']),
      themeMode: _themeModeFrom(map['themeMode']),
      darkFlavor: _allowedValue(map['darkFlavor'], darkFlavorNames, 'mocha'),
      accent: _allowedValue(map['accent'], accentColorNames, 'teal'),
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
    if (compiler.environmentScript != null &&
        compiler.environmentScript!.isNotEmpty)
      'environmentScript': compiler.environmentScript,
    if (compiler.extraPathEntries.isNotEmpty)
      'extraPathEntries': <String>[...compiler.extraPathEntries],
  };
}

/// 缓存列表容错：非列表或损坏条目视为无缓存/跳过，不抛异常。
List<DetectedCompiler> _detectedCompilersFrom(Object? value) {
  if (value is! List) {
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

DetectedCompiler? _detectedCompilerFrom(Object? value) {
  if (value is! Map) {
    return null;
  }
  final Object? kindValue = value['kind'];
  final CompilerKind? kind = kindValue is String
      ? compilerKindFromId(kindValue)
      : null;
  final String? version = _nonEmptyString(value['version']);
  final String? executablePath = _nonEmptyString(value['executablePath']);
  if (kind == null || version == null || executablePath == null) {
    return null;
  }
  return DetectedCompiler(
    kind: kind,
    version: version,
    executablePath: executablePath,
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
  final List<String> entries = <String>[
    for (final Object? item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
  return entries.isEmpty ? _defaultCompilerPriority : entries;
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

String _allowedValue(Object? value, List<String> allowed, String fallback) {
  if (value is String && allowed.contains(value)) {
    return value;
  }
  return fallback;
}
