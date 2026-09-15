import 'package:cpp_nuget_pack/models/compiler_model.dart';

enum ThemeModeSetting { system, dark, light }

const List<String> _defaultCompilerPriority = <String>[
  'icx',
  'clang-cl',
  'msvc',
  'mingw',
];

class SettingsModel {
  const SettingsModel({
    this.outputDirectory,
    this.cmakeOutputDirectory,
    this.defaultAuthor = '',
    this.themeMode = ThemeModeSetting.system,
    this.compilerPriority = _defaultCompilerPriority,
    this.detectedCompilers = const <DetectedCompiler>[],
  });

  /// NuGet 打包输出目录。
  final String? outputDirectory;

  /// CMake 打包输出目录。
  final String? cmakeOutputDirectory;

  /// 全局默认作者：新包预填，占位作者在保存/加载时自动替换。
  final String defaultAuthor;

  final ThemeModeSetting themeMode;

  /// 编译器优先级（`icx` / `clang-cl` / `msvc` / `mingw`，自高到低）。
  final List<String> compilerPriority;

  /// 上次编译器检测结果缓存；空表示无缓存（设置页与构建据此重检）。
  final List<DetectedCompiler> detectedCompilers;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (outputDirectory != null) 'outputDirectory': outputDirectory,
      if (cmakeOutputDirectory != null)
        'cmakeOutputDirectory': cmakeOutputDirectory,
      if (defaultAuthor.isNotEmpty) 'defaultAuthor': defaultAuthor,
      'themeMode': themeMode.name,
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
      cmakeOutputDirectory: _optionalString(map['cmakeOutputDirectory']),
      defaultAuthor: _trimmedString(map['defaultAuthor']),
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
    if (compiler.cxxExecutablePath != null &&
        compiler.cxxExecutablePath!.isNotEmpty)
      'cxxExecutablePath': compiler.cxxExecutablePath,
    if (compiler.environmentScript != null &&
        compiler.environmentScript!.isNotEmpty)
      'environmentScript': compiler.environmentScript,
    if (compiler.extraPathEntries.isNotEmpty)
      'extraPathEntries': <String>[...compiler.extraPathEntries],
  };
}

/// 缓存列表容错：非列表或损坏条目视为无缓存/跳过，不抛异常。
///
/// R23 回退迁移：缓存含 GNU clang（`kind: clang`）条目时整表作废（返回空 = 无缓存），
/// 由设置页与构建触发一次重检。R23 条目指向 `clang.exe` GNU 驱动、与恢复后的
/// clang-cl 旗标体系不兼容，不能复用；若仅丢弃该条目而保留其余缓存，优先级中
/// `clang-cl` 将无条目可匹配而回落到 `msvc`——整表作废可保证首次选择仍按用户
/// 优先级重检。
List<DetectedCompiler> _detectedCompilersFrom(Object? value) {
  if (value is! List) {
    return const <DetectedCompiler>[];
  }
  if (value.any(_isLegacyGnuClangEntry)) {
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

bool _isLegacyGnuClangEntry(Object? value) {
  if (value is! Map) {
    return false;
  }
  final Object? kindValue = value['kind'];
  return kindValue is String && isLegacyCompilerKindId(kindValue);
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

/// 优先级读回：R23 回退迁移把 GNU clang 标识 `clang` 改写为 `clang-cl`（按首见
/// 顺序去重）；随后把「已支持但列表缺失」的种类按声明序补到末尾——新编译器
/// 种类（如 MinGW）随版本升级自动进入旧配置，且置末不改变既有选择；设置页只
/// 支持排序、不支持增删，补入是旧配置触达新种类的唯一路径。
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
    if (seen.add(id)) {
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

/// 容错字符串读取：非字符串视为空串，读回 trim。
String _trimmedString(Object? value) {
  if (value is! String) {
    return '';
  }
  return value.trim();
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
