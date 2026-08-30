/// 核心数据模型：C++ NuGet 打包工具的项目元数据与配置。
///
/// 整个包由 [PackProject] 描述：包元数据（id/version/描述等）、源码目录
/// （[SourceDir]）以及每个目录下的文件映射（[FileMapping]），外加编译配置
/// （[CompileConfig]）。所有模型均提供 `toJson`/`fromJson`/`copyWith` 以便
/// 序列化与不可变更新。
library;

/// 合法 NuGet 包 id 的正则，与 NuGet 官方 PackageIdValidator 一致：
/// 以字母/数字/下划线开头（`\w`），段之间用 `.`/`_`/`-` 分隔，段内为 `\w`。
/// 不允许连续分隔符，也不允许以分隔符开头或结尾。
final RegExp _nugetIdPattern = RegExp(r'^\w+([._-]\w+)*$');

/// 头文件扩展名（[FileMapping.fileKind] == 'header'）。
const Set<String> kHeaderExtensions = {'.h', '.hpp', '.hh', '.hxx'};

/// 源码文件扩展名（[FileMapping.fileKind] == 'source'）。
///
/// 源码映射自动注入消费者编译目标（见 `msbuild_generator` 的 ClCompile 注入）。
const Set<String> kSourceExtensions = {'.cpp', '.cc', '.cxx', '.c'};

/// 库文件扩展名（[FileMapping.fileKind] == 'library'）。
///
/// 注意：`.dll` 属动态链接库，装入 [kDataExtensions]（打包后硬链接到消费方
/// `$(OutDir)`），而非作为链接依赖参与 `AdditionalDependencies`。
const Set<String> kLibraryExtensions = {'.lib', '.a', '.so', '.dylib'};

/// 数据文件扩展名（[FileMapping.fileKind] == 'data'）。
///
/// 数据映射打包后自动硬链接到消费者 `$(OutDir)`（见 `msbuild_generator` 的拷贝 Target）。
/// `.dll` 动态库按数据文件处理：打包后自动落盘到消费方输出目录。
const Set<String> kDataExtensions = {
  '.dat',
  '.json',
  '.bin',
  '.txt',
  '.xml',
  '.dll',
};

/// C++ Module 文件扩展名（[FileMapping.fileKind] == 'module'）。
///
/// `.ixx` 为模块接口单元；模块映射与源码映射同策略，打包后自动注入消费方
/// ClCompile（由编译器语言标准 `/std:c++20` 或 `/std:c++latest` 解析模块语义）。
const Set<String> kModuleExtensions = {'.cppm', '.ixx', '.mpp'};

/// 从路径串提取目录/文件名（兼容 `\` 与 `/`）。
String _basenameOf(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  final normalized = trimmed.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.last;
}

/// 提取小写扩展名（含点），无扩展名返回空串。
String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot <= 0) return '';
  return path.substring(dot).toLowerCase();
}

/// 将 JSON 中的字符串字段归一化（null -> 空串）。
String _jsonString(dynamic value) => value is String ? value : '';

/// 将 JSON 中的字符串列表归一化。
List<String> _jsonStringList(dynamic value) {
  if (value is! List) return [];
  return value.whereType<String>().toList();
}

/// 项目配置：包元数据、源码目录、平台/配置列表与编译配置。
class PackProject {
  /// 创建项目模型。默认平台为 `x64`、配置为 `Debug`/`Release`。
  PackProject({
    this.packageId = '',
    this.version = '1.0.0',
    this.description = '',
    this.authors = '',
    this.owners = '',
    this.tags = '',
    this.license = '',
    this.repository = '',
    this.preBuildCommand = '',
    this.postBuildCommand = '',
    List<SourceDir>? sourceDirs,
    List<String>? platforms,
    List<String>? configurations,
    CompileConfig? compileConfig,
  }) : sourceDirs = sourceDirs ?? [],
       platforms = platforms ?? const ['x64'],
       configurations = configurations ?? const ['Debug', 'Release'],
       compileConfig = compileConfig ?? CompileConfig();

  /// NuGet 包 id（唯一标识，需符合 NuGet id 规则）。
  String packageId;

  /// 包版本号。
  String version;

  /// 包描述。
  String description;

  /// 作者（逗号或多值字符串）。
  String authors;

  /// 拥有者（逗号或多值字符串）。
  String owners;

  /// 标签（逗号分隔字符串）。
  String tags;

  /// 许可证（可为空，空则不写入 nuspec）。
  String license;

  /// 仓库地址（可为空，空则不写入 nuspec）。
  String repository;

  /// 打包前执行的构建脚本（如 `clean.bat` 或 `.\sign.ps1`）；空表示跳过。
  String preBuildCommand;

  /// 打包成功后执行的构建脚本；空表示跳过，失败仅记录警告。
  String postBuildCommand;

  /// 需要打包的源码目录列表。
  List<SourceDir> sourceDirs;

  /// 支持的目标平台，默认 `['x64']`。
  List<String> platforms;

  /// 支持的配置列表，默认 `['Debug', 'Release']`。
  List<String> configurations;

  /// 编译配置（宏、头文件/库路径、链接依赖、拷贝文件、注入源码）。
  CompileConfig compileConfig;

  /// 校验包 id 是否合法（非空且符合 NuGet id 规则）。
  static bool isValidPackageId(String id) =>
      id.trim().isNotEmpty && _nugetIdPattern.hasMatch(id);

  /// 校验包 id。非法时抛出 [FormatException]。
  ///
  /// Throw 的 [FormatException] 携带人类可读的失败原因。
  void validate() {
    final trimmed = packageId.trim();
    if (trimmed.isEmpty) {
      throw FormatException('packageId 不能为空');
    }
    if (!isValidPackageId(trimmed)) {
      throw FormatException(
        'packageId "$trimmed" 不是合法的 NuGet 包 id（必须以字母或数字开头，'
        '仅含字母、数字、下划线、连字符、点号；段之间用 . _ - 分隔）。',
      );
    }
  }

  /// 深拷贝（等价于 JSON 往返的结果）。
  PackProject copy() => PackProject.fromJson(toJson());

  /// 返回部分更新后的副本；未提供的字段保持不变。
  PackProject copyWith({
    String? packageId,
    String? version,
    String? description,
    String? authors,
    String? owners,
    String? tags,
    String? license,
    String? repository,
    String? preBuildCommand,
    String? postBuildCommand,
    List<SourceDir>? sourceDirs,
    List<String>? platforms,
    List<String>? configurations,
    CompileConfig? compileConfig,
  }) {
    return PackProject(
      packageId: packageId ?? this.packageId,
      version: version ?? this.version,
      description: description ?? this.description,
      authors: authors ?? this.authors,
      owners: owners ?? this.owners,
      tags: tags ?? this.tags,
      license: license ?? this.license,
      repository: repository ?? this.repository,
      preBuildCommand: preBuildCommand ?? this.preBuildCommand,
      postBuildCommand: postBuildCommand ?? this.postBuildCommand,
      sourceDirs: sourceDirs != null
          ? sourceDirs.map((e) => e.copyWith()).toList()
          : List.of(this.sourceDirs),
      platforms: platforms ?? List.of(this.platforms),
      configurations: configurations ?? List.of(this.configurations),
      compileConfig: compileConfig ?? this.compileConfig.copyWith(),
    );
  }

  /// 序列化为 JSON 可编码的 Map。
  Map<String, dynamic> toJson() => {
    'packageId': packageId,
    'version': version,
    'description': description,
    'authors': authors,
    'owners': owners,
    'tags': tags,
    'license': license,
    'repository': repository,
    'preBuildCommand': preBuildCommand,
    'postBuildCommand': postBuildCommand,
    'sourceDirs': sourceDirs.map((e) => e.toJson()).toList(),
    'platforms': List.of(platforms),
    'configurations': List.of(configurations),
    'compileConfig': compileConfig.toJson(),
  };

  /// 从 JSON Map 反序列化；缺失或非法字段回退到默认值。
  factory PackProject.fromJson(Map<String, dynamic> json) {
    return PackProject(
      packageId: _jsonString(json['packageId']),
      version: _jsonString(json['version']),
      description: _jsonString(json['description']),
      authors: _jsonString(json['authors']),
      owners: _jsonString(json['owners']),
      tags: _jsonString(json['tags']),
      license: _jsonString(json['license']),
      repository: _jsonString(json['repository']),
      preBuildCommand: _jsonString(json['preBuildCommand']),
      postBuildCommand: _jsonString(json['postBuildCommand']),
      sourceDirs: _jsonList(json['sourceDirs'], SourceDir.fromJson),
      platforms: _jsonStringList(json['platforms']),
      configurations: _jsonStringList(json['configurations']),
      compileConfig: json['compileConfig'] is Map<String, dynamic>
          ? CompileConfig.fromJson(
              json['compileConfig'] as Map<String, dynamic>,
            )
          : CompileConfig(),
    );
  }

  @override
  String toString() {
    return 'PackProject(packageId: $packageId, version: $version, '
        'sourceDirs: ${sourceDirs.length}, platforms: $platforms, '
        'configurations: $configurations)';
  }
}

/// 将 JSON 列表按 [fromJson] 逐项反序列化。
List<T> _jsonList<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  if (value is! List) return [];
  final result = <T>[];
  for (final item in value) {
    if (item is Map<String, dynamic>) {
      result.add(fromJson(item));
    }
  }
  return result;
}

/// 一个待打包的源码目录及其文件映射。
class SourceDir {
  /// 创建源码目录。若 [name] 为空则自动从 [path] 提取目录名。
  SourceDir({required this.path, String? name, List<FileMapping>? mappings})
    : name = (name != null && name.isNotEmpty) ? name : _basenameOf(path),
      mappings = mappings ?? [];

  /// 源码目录路径。
  String path;

  /// 目录名（自动从 [path] 提取，也可显式指定）。
  String name;

  /// 该目录下的文件映射列表。
  List<FileMapping> mappings;

  /// 返回部分更新后的副本；未提供的字段保持不变。
  ///
  /// 显式传入 [name] 时使用之；否则若 [path] 发生了变更则从新路径派生目录名；
  /// 两者都未变化时保留原目录名。
  SourceDir copyWith({
    String? path,
    String? name,
    List<FileMapping>? mappings,
  }) {
    final nextPath = path ?? this.path;
    final nextName =
        name ??
        (path != null && path != this.path ? _basenameOf(nextPath) : this.name);
    return SourceDir(
      path: nextPath,
      name: nextName,
      mappings: mappings != null
          ? mappings.map((e) => e.copyWith()).toList()
          : List.of(this.mappings),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'mappings': mappings.map((e) => e.toJson()).toList(),
  };

  factory SourceDir.fromJson(Map<String, dynamic> json) {
    return SourceDir(
      path: _jsonString(json['path']),
      name: _jsonString(json['name']),
      mappings: _jsonList(json['mappings'], FileMapping.fromJson),
    );
  }

  @override
  String toString() =>
      'SourceDir(path: $path, name: $name, mappings: ${mappings.length})';
}

/// 单个文件 glob 到包内目标路径的映射。
class FileMapping {
  /// 创建文件映射。`platforms`/`configurations` 为空表示适用于全部。
  FileMapping({
    this.srcGlob = '',
    this.target = '',
    List<String>? platforms,
    List<String>? configurations,
  }) : platforms = platforms ?? [],
       configurations = configurations ?? [];

  /// 源 glob（相对 [SourceDir.path] 或包工作目录）。
  String srcGlob;

  /// 包内目标路径。
  String target;

  /// 适用平台；空表示全部。
  List<String> platforms;

  /// 适用配置；空表示全部。
  List<String> configurations;

  /// 按 `srcGlob` 扩展名命分类，返回
  /// 'header'/'source'/'module'/'data'/'library'/'other' 之一。
  ///
  /// 分类决定了该映射在 nuspec/targets 中的处理方式：
  /// - `header`：target 为「最终 `#include` 路径」（不含 `build\native\include\` 前缀），
  ///   nuspec 自动拼 `build\native\include\`，msbuild 派生 include 子目录。
  /// - `source`：target 为包内 `build\native\src\...` 相对段，nuspec 自动拼前缀，
  ///   msbuild 生成 ClCompile 注入 Target。
  /// - `module`：与 `source` 同策略（target 前缀 `build\native\src\` 并注入 ClCompile），
  ///   由编译器语言标准解析模块语义。
  /// - `library`：target 为包内路径（如 `build\native\lib\x64\Debug`），生成链接依赖。
  /// - `data`：target 为包内目录，msbuild 生成硬链接到 `$(OutDir)` 的 Target。
  /// - `other`：未识别扩展名，target 原样输出为包内路径。
  String get fileKind {
    final glob = srcGlob.trim().toLowerCase();
    if (glob.isEmpty) return 'other';
    final ext = _extensionOf(glob);
    if (kHeaderExtensions.contains(ext)) return 'header';
    if (kSourceExtensions.contains(ext)) return 'source';
    if (kModuleExtensions.contains(ext)) return 'module';
    if (kLibraryExtensions.contains(ext)) return 'library';
    if (kDataExtensions.contains(ext)) return 'data';
    return 'other';
  }

  /// 是否为头文件映射（`fileKind == 'header'`）。
  bool get isHeaderMapping => fileKind == 'header';

  /// 是否为会自动注入消费方编译的映射（源文件或 C++ Module，`fileKind == 'source' || 'module'`）。
  ///
  /// 生成器（`msbuild_generator`）据此生成 ClCompile 注入 Target；两种类型共用
  /// `build\native\src\` 目标前缀与同一注入逻辑。
  bool get isSourceMapping => fileKind == 'source' || fileKind == 'module';

  /// 返回部分更新后的副本；未提供的字段保持不变。
  FileMapping copyWith({
    String? srcGlob,
    String? target,
    List<String>? platforms,
    List<String>? configurations,
  }) {
    return FileMapping(
      srcGlob: srcGlob ?? this.srcGlob,
      target: target ?? this.target,
      platforms: platforms ?? List.of(this.platforms),
      configurations: configurations ?? List.of(this.configurations),
    );
  }

  Map<String, dynamic> toJson() => {
    'srcGlob': srcGlob,
    'target': target,
    'platforms': List.of(platforms),
    'configurations': List.of(configurations),
  };

  factory FileMapping.fromJson(Map<String, dynamic> json) {
    return FileMapping(
      srcGlob: _jsonString(json['srcGlob']),
      target: _jsonString(json['target']),
      platforms: _jsonStringList(json['platforms']),
      configurations: _jsonStringList(json['configurations']),
    );
  }

  @override
  String toString() => 'FileMapping(srcGlob: $srcGlob, target: $target)';
}

/// 编译配置：语言标准、预处理宏、包含/库路径与链接依赖。
///
/// 数据文件与源码文件不再由编译配置维护——统一在「文件映射」中通过
/// [FileMapping.fileKind]（data/source）自动处理（见 `msbuild_generator`）。
class CompileConfig {
  /// 创建编译配置，采用默认语言标准 `stdcpp23`。
  CompileConfig({
    this.languageStandard = 'stdcpp23',
    this.clanguageStandard = '',
    this.preprocessorDefines = '',
    Map<String, String>? configDefines,
    this.additionalIncludeDirectories = '',
    this.additionalLibraryDirectories = '',
    this.additionalDependencies = '',
  }) : configDefines = configDefines ?? {};

  /// 语言标准，如 `stdcpp23`、`stdcpp20`。
  String languageStandard;

  /// C 语言标准，如 `c11`、`c17`；空表示不设置（不写入 MSBuild）。
  String clanguageStandard;

  /// 全局预处理宏，分号分隔（如 `NOMINMAX;V8_ENABLE_WEBASSEMBLY`）。
  String preprocessorDefines;

  /// 配置名 -> 该配置追加的宏，如 `{'Debug': 'V8_ENABLE_CHECKS'}`。
  Map<String, String> configDefines;

  /// 额外的头文件搜索目录，分号分隔，可为空。
  String additionalIncludeDirectories;

  /// 额外的库搜索目录，分号分隔，可为空。
  String additionalLibraryDirectories;

  /// 额外的链接依赖，分号分隔，如 `ws2_32.lib;ntdll.lib`。
  String additionalDependencies;

  /// 返回部分更新后的副本；未提供的字段保持不变。
  CompileConfig copyWith({
    String? languageStandard,
    String? clanguageStandard,
    String? preprocessorDefines,
    Map<String, String>? configDefines,
    String? additionalIncludeDirectories,
    String? additionalLibraryDirectories,
    String? additionalDependencies,
  }) {
    return CompileConfig(
      languageStandard: languageStandard ?? this.languageStandard,
      clanguageStandard: clanguageStandard ?? this.clanguageStandard,
      preprocessorDefines: preprocessorDefines ?? this.preprocessorDefines,
      configDefines: configDefines != null
          ? Map<String, String>.from(configDefines)
          : Map<String, String>.from(this.configDefines),
      additionalIncludeDirectories:
          additionalIncludeDirectories ?? this.additionalIncludeDirectories,
      additionalLibraryDirectories:
          additionalLibraryDirectories ?? this.additionalLibraryDirectories,
      additionalDependencies:
          additionalDependencies ?? this.additionalDependencies,
    );
  }

  Map<String, dynamic> toJson() => {
    'languageStandard': languageStandard,
    'clanguageStandard': clanguageStandard,
    'preprocessorDefines': preprocessorDefines,
    'configDefines': Map<String, String>.from(configDefines),
    'additionalIncludeDirectories': additionalIncludeDirectories,
    'additionalLibraryDirectories': additionalLibraryDirectories,
    'additionalDependencies': additionalDependencies,
  };

  factory CompileConfig.fromJson(Map<String, dynamic> json) {
    final configDefinesRaw = json['configDefines'];
    final configDefinesMap = <String, String>{};
    if (configDefinesRaw is Map) {
      configDefinesRaw.forEach((key, value) {
        if (key is String && value is String) {
          configDefinesMap[key] = value;
        }
      });
    }
    // 旧 JSON 可能含 dataFilesToCopy/injectedSources 键，已迁移至文件映射；
    // 此处直接忽略（不读取），保证旧配置加载不报错。
    return CompileConfig(
      languageStandard: _jsonString(json['languageStandard']),
      clanguageStandard: _jsonString(json['clanguageStandard']),
      preprocessorDefines: _jsonString(json['preprocessorDefines']),
      configDefines: configDefinesMap,
      additionalIncludeDirectories: _jsonString(
        json['additionalIncludeDirectories'],
      ),
      additionalLibraryDirectories: _jsonString(
        json['additionalLibraryDirectories'],
      ),
      additionalDependencies: _jsonString(json['additionalDependencies']),
    );
  }

  @override
  String toString() {
    return 'CompileConfig(languageStandard: $languageStandard, '
        'clanguageStandard: $clanguageStandard, '
        'configDefines: $configDefines)';
  }
}
