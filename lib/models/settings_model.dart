import 'package:cpp_nuget_pack/models/compiler_model.dart';

enum ThemeModeSetting { system, dark, light }

const List<String> _defaultCompilerPriority = <String>[
  'icx',
  'clang-cl',
  'msvc',
];

/// `copyWith` 的可空字段哨兵：区分「未传」（保持原值）与「传 null」（清空）。
const Object _unset = Object();

class SettingsModel {
  const SettingsModel({
    this.outputDirectory,
    this.defaultAuthor = '',
    this.themeMode = ThemeModeSetting.system,
    this.compilerPriority = _defaultCompilerPriority,
    this.detectedCompilers = const <DetectedCompiler>[],
  });

  /// NuGet 打包输出目录。
  final String? outputDirectory;

  /// 全局默认作者：新包预填，占位作者在保存/加载时自动替换。
  final String defaultAuthor;

  final ThemeModeSetting themeMode;

  /// 编译器优先级（`icx` / `clang-cl` / `msvc`，自高到低）。
  final List<String> compilerPriority;

  /// 上次编译器检测结果缓存；空表示无缓存（设置页与构建据此重检）。
  final List<DetectedCompiler> detectedCompilers;

  /// 复制并覆盖字段；可空字段（输出目录）用哨兵区分「未传」与
  /// 「传 null（清空）」。
  SettingsModel copyWith({
    Object? outputDirectory = _unset,
    String? defaultAuthor,
    ThemeModeSetting? themeMode,
    List<String>? compilerPriority,
    List<DetectedCompiler>? detectedCompilers,
  }) {
    return SettingsModel(
      outputDirectory: identical(outputDirectory, _unset)
          ? this.outputDirectory
          : outputDirectory as String?,
      defaultAuthor: defaultAuthor ?? this.defaultAuthor,
      themeMode: themeMode ?? this.themeMode,
      compilerPriority: compilerPriority ?? this.compilerPriority,
      detectedCompilers: detectedCompilers ?? this.detectedCompilers,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (outputDirectory != null) 'outputDirectory': outputDirectory,
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
/// 已删除编译器种类与 R23 回退迁移的整表作废：缓存含 MinGW（`kind: mingw`）或 GNU
/// clang（`kind: clang`）条目时整表作废（返回空 = 无缓存），由设置页与构建触发一次
/// 重检。这两类条目指向的工具链驱动与已删除/已恢复的旗标体系均不兼容，不能复用；
/// 若仅丢弃该条目而保留其余缓存，优先级中对应种类将无条目可匹配而回落到其它编译器
/// ——整表作废可保证首次选择仍按用户优先级重检。
List<DetectedCompiler> _detectedCompilersFrom(Object? value) {
  if (value is! List) {
    return const <DetectedCompiler>[];
  }
  if (value.any(_isLegacyMingwEntry) || value.any(_isLegacyGnuClangEntry)) {
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

/// 历史 MinGW 稳定标识（大小写不敏感、容忍首尾空白）；只为配置迁移识别，
/// 不对应任何 [CompilerKind]（[compilerKindFromId] 对其返回 null）。
bool _isLegacyMingwEntry(Object? value) {
  if (value is! Map) {
    return false;
  }
  final Object? kindValue = value['kind'];
  return kindValue is String && kindValue.trim().toLowerCase() == 'mingw';
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

/// 优先级读回：先按有效标识过滤（已删除的编译器种类如 MinGW 及其历史遗留值一律
/// 丢弃），R23 回退迁移把 GNU clang 标识 `clang` 改写为 `clang-cl`（按首见顺序
/// 去重）；随后把「已支持但列表缺失」的种类按声明序补到末尾——新编译器种类随版本
/// 升级自动进入旧配置，且置末不改变既有选择；设置页只支持排序、不支持增删，补入
/// 是旧配置触达新种类的唯一路径。
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
