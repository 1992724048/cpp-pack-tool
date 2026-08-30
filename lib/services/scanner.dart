/// 目录扫描服务：递归扫描源码目录，按扩展名分类文件并生成建议映射。
///
/// 纯 `dart:io` 实现，不依赖 Flutter。扫描遵循以下约束：
/// - 递归深度上限（默认 4 层），防止深入项目生成目录。
/// - 单目录条目数上限（默认 5000），防止超大目录拖垮扫描。
/// - 忽略常见生成/源外目录（`build`、`out`、`.git` 等）。
/// - 通过规范路径 visited 集合 + 不跟随符号链接，避免符号链接循环。
library;

import 'dart:io';

import '../models/pack_project.dart';
import 'path_utils.dart';

/// 文件分类扩展名集合（头文件/源码/库/数据）统一定义在 `pack_project.dart`，
/// 扫描器与 `FileMapping.fileKind` 共享同一套分类，避免语义漂移。

/// 扫描时忽略的目录名（小写），通常为生成/源外目录。
const Set<String> kIgnoredDirectoryNames = {
  'build',
  'out',
  '.git',
  '.dart_tool',
  '.temp',
  '.vs',
  '.idea',
  'node_modules',
  'cmakefiles',
};

const Set<String> kIgnoredFileNames = {
  '.cpp_nuget_pack.json',
};

/// 扫描结果：分类后的相对路径列表与建议映射。
class ScanResult {
  ScanResult({
    required this.headers,
    required this.sources,
    required this.libraries,
    required this.dataFiles,
    this.dynamicLibraries = const [],
    this.executables = const [],
    required this.suggestedMappings,
    this.truncated = false,
    this.warnings = const [],
  });

  /// 头文件相对路径列表（含 `**` 的子目录结构，以 `\` 分隔）。
  final List<String> headers;

  /// 源码文件相对路径列表（自动注入消费者编译目标）。
  final List<String> sources;

  /// 静态库文件相对路径列表（参与链接依赖）。
  final List<String> libraries;

  /// 数据文件相对路径列表（建议硬链接到 OutDir 或随包）。
  final List<String> dataFiles;

  /// 动态库（.dll/.so/.dylib）相对路径列表（建议硬链接到 OutDir）。
  final List<String> dynamicLibraries;

  /// 可执行文件（.exe）相对路径列表（建议硬链接到 OutDir）。
  final List<String> executables;

  /// 建议的文件映射（供用户确认/修改后写入包配置）。
  final List<FileMapping> suggestedMappings;

  /// 是否因深度或数量限制而被截断（[warnings] 中给出具体原因）。
  final bool truncated;

  /// 扫描过程中记录的告警信息（如截断提醒）。
  final List<String> warnings;
}

/// 扫描 [dirPath] 目录树，返回分类结果与建议映射。
///
/// - [maxDepth]：递归最大目录深度（0 表示只扫描根目录直接文件）。
/// - [maxFilesPerDir]：单目录处理的条目数上限。
///
/// 当 [dirPath] 不存在或不是目录时抛出 [FileSystemException]。
ScanResult scanSourceDir(
  String dirPath, {
  int maxDepth = 8,
  int maxFilesPerDir = 5000,
}) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    throw FileSystemException('扫描目录不存在', dirPath);
  }
  if (!FileSystemEntity.isDirectorySync(dirPath)) {
    throw FileSystemException('扫描目标不是目录', dirPath);
  }

  final headers = <String>[];
  final sources = <String>[];
  final libraries = <String>[];
  final dataFiles = <String>[];
  final dynamicLibraries = <String>[];
  final executables = <String>[];
  final warnings = <String>[];
  var truncated = false;

  final visitedDirs = <String>{};
  _walk(
    dir: dir,
    relRoot: '',
    depth: 0,
    maxDepth: maxDepth,
    maxFilesPerDir: maxFilesPerDir,
    headers: headers,
    sources: sources,
    libraries: libraries,
    dataFiles: dataFiles,
    dynamicLibraries: dynamicLibraries,
    executables: executables,
    visitedDirs: visitedDirs,
    warnings: warnings,
    onTruncate: (reason) {
      truncated = true;
      warnings.add(reason);
    },
  );

  final suggested = <FileMapping>[];
  suggested.addAll(_buildHeaderMappings(dirPath, headers));
  suggested.addAll(_buildSourceMappings(dirPath, sources));
  suggested.addAll(
    _buildLibraryAndDataMappings(
      libraries,
      dataFiles,
      dynamicLibraries,
      executables,
    ),
  );

  return ScanResult(
    headers: headers,
    sources: sources,
    libraries: libraries,
    dataFiles: dataFiles,
    dynamicLibraries: dynamicLibraries,
    executables: executables,
    suggestedMappings: suggested,
    truncated: truncated,
    warnings: warnings,
  );
}

/// 深度优先遍历单个目录，填充分类列表。
void _walk({
  required Directory dir,
  required String relRoot,
  required int depth,
  required int maxDepth,
  required int maxFilesPerDir,
  required List<String> headers,
  required List<String> sources,
  required List<String> libraries,
  required List<String> dataFiles,
  required List<String> dynamicLibraries,
  required List<String> executables,
  required Set<String> visitedDirs,
  required List<String> warnings,
  required void Function(String reason) onTruncate,
}) {
  // 规范路径去重，防止符号链接循环。
  final canonical = _canonicalPath(dir.path);
  if (visitedDirs.contains(canonical)) {
    warnings.add('跳过循环目录: ${dir.path}');
    return;
  }
  visitedDirs.add(canonical);

  List<FileSystemEntity> entries;
  try {
    // followLinks: false → 符号链接以 link 类型出现，后续不会被当作目录递归。
    entries = dir.listSync(followLinks: false);
  } on FileSystemException catch (e) {
    warnings.add('无法读取目录 ${dir.path}: ${e.message}');
    return;
  }

  if (entries.length > maxFilesPerDir) {
    onTruncate(
      '目录 ${dir.path} 条目数 ${entries.length} 超过上限 $maxFilesPerDir，'
      '仅处理前 $maxFilesPerDir 个',
    );
    entries = entries.sublist(0, maxFilesPerDir);
  }

  for (final entry in entries) {
    final name = basenameOf(entry.path);
    final rel = relRoot.isEmpty ? name : '$relRoot$pathSeparator$name';

    final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      // 不跟随符号链接，避免循环。
      warnings.add('跳过符号链接: ${entry.path}');
      continue;
    }

    if (type == FileSystemEntityType.directory) {
      if (kIgnoredDirectoryNames.contains(name.toLowerCase())) {
        warnings.add('忽略生成目录: ${entry.path}');
        continue;
      }
      if (depth >= maxDepth) {
        onTruncate('达到最大深度 $maxDepth，跳过目录: ${entry.path}');
        continue;
      }
      _walk(
        dir: Directory(entry.path),
        relRoot: rel,
        depth: depth + 1,
        maxDepth: maxDepth,
        maxFilesPerDir: maxFilesPerDir,
        headers: headers,
        sources: sources,
        libraries: libraries,
        dataFiles: dataFiles,
        dynamicLibraries: dynamicLibraries,
        executables: executables,
        visitedDirs: visitedDirs,
        warnings: warnings,
        onTruncate: onTruncate,
      );
      continue;
    }

    if (type == FileSystemEntityType.file) {
      if (kIgnoredFileNames.contains(name.toLowerCase())) {
        warnings.add('忽略文件: ${entry.path}');
        continue;
      }
      final ext = _extensionOf(name);
      if (kHeaderExtensions.contains(ext)) {
        headers.add(rel);
      } else if (kSourceExtensions.contains(ext) ||
          kModuleExtensions.contains(ext)) {
        // C++ Module（.cppm/.ixx/.mpp）与源码同策略：并入 sources，统一生成
        // `build\native\src\...` 建议映射并注入 ClCompile（由语言标准解析模块语义）。
        sources.add(rel);
      } else if (kStaticLibraryExtensions.contains(ext)) {
        libraries.add(rel);
      } else if (kDynamicLibraryExtensions.contains(ext)) {
        dynamicLibraries.add(rel);
      } else if (kExecutableExtensions.contains(ext)) {
        executables.add(rel);
      } else if (kDataExtensions.contains(ext)) {
        dataFiles.add(rel);
      }
    }
    // 其余类型（socket 等）忽略。
  }
}

/// 根据头文件相对路径按父目录分组，生成建议映射。
///
/// 每个直接包含头文件的父目录，按实际存在的扩展名各产生一条映射：
/// glob 为该目录下的 `*.ext`，目标为「最终 `#include` 路径」——即消费者
/// 代码中 `#include <{target}/xxx.h>` 的路径前缀（不含 `build\native\include\`
/// 前缀），如 `v8`、`v8\cppgc`。非递归、不重叠，可完整保留包内相对结构。
List<FileMapping> _buildHeaderMappings(String dirPath, List<String> headers) {
  if (headers.isEmpty) return const [];
  final clusterName = basenameOf(dirPath);
  final byDir = <String, Set<String>>{};
  for (final rel in headers) {
    final parent = dirnameOf(rel);
    final ext = _extensionOf(basenameOf(rel));
    byDir.putIfAbsent(parent, () => <String>{}).add(ext);
  }

  final mappings = <FileMapping>[];
  for (final parent in byDir.keys) {
    final targetSegments = <String>[
      clusterName,
      ...(parent.isEmpty ? const <String>[] : parent.split(pathSeparator)),
    ];
    final target = joinPath(targetSegments);
    for (final ext in byDir[parent]!) {
      final srcGlob = parent.isEmpty ? '*$ext' : '$parent$pathSeparator*$ext';
      mappings.add(FileMapping(srcGlob: srcGlob, target: target));
    }
  }
  return mappings;
}

/// 根据源码文件按父目录分组，生成建议映射。
///
/// 每条映射的 target 为包内 `build\native\src\...` 绝对段（按源目录名/父目录
/// 保留结构）；消费者侧由 `msbuild_generator` 生成 ClCompile 注入 Target。
List<FileMapping> _buildSourceMappings(String dirPath, List<String> sources) {
  if (sources.isEmpty) return const [];
  final clusterName = basenameOf(dirPath);
  final byDir = <String, Set<String>>{};
  for (final rel in sources) {
    final parent = dirnameOf(rel);
    final ext = _extensionOf(basenameOf(rel));
    byDir.putIfAbsent(parent, () => <String>{}).add(ext);
  }

  final mappings = <FileMapping>[];
  for (final parent in byDir.keys) {
    final target = joinPath([
      'build',
      'native',
      'src',
      clusterName,
      ...(parent.isEmpty ? const <String>[] : parent.split(pathSeparator)),
    ]);
    for (final ext in byDir[parent]!) {
      final srcGlob = parent.isEmpty ? '*$ext' : '$parent$pathSeparator*$ext';
      mappings.add(FileMapping(srcGlob: srcGlob, target: target));
    }
  }
  return mappings;
}

/// 根据库/数据/动态库/可执行文件按父目录分组（识别配置与平台），生成建议映射。
///
/// 目标路径按文件类别派生：
/// - `staticLibrary`/`dynamicLibrary`/`data`：位于配置目录时映射到 `build\native\lib\{平台}\{配置}`；
///   否则（无配置目录，如源目录根）映射到默认 `build\native\lib`。
/// - `executable`：建议映射到 `build\native\tools`；位于配置目录时追加 `\{配置}`（如
///   `build\native\tools\Debug`），便于 exe 注入引用其同级运行库。
List<FileMapping> _buildLibraryAndDataMappings(
  List<String> libraries,
  List<String> dataFiles,
  List<String> dynamicLibraries,
  List<String> executables,
) {
  // 父目录 -> 扩展名 -> 文件类别（仅统计真实出现的扩展名）。
  final byDir = <String, Map<String, String>>{};
  void add(String rel, String kind) {
    final parent = dirnameOf(rel);
    final ext = _extensionOf(basenameOf(rel));
    if (ext.isEmpty) return;
    byDir
        .putIfAbsent(parent, () => <String, String>{})
        .putIfAbsent(ext, () => kind);
  }

  for (final rel in libraries) {
    add(rel, 'staticLibrary');
  }
  for (final rel in dynamicLibraries) {
    add(rel, 'dynamicLibrary');
  }
  for (final rel in executables) {
    add(rel, 'executable');
  }
  // 数据文件：位于配置目录时随库映射到平台×配置；独立数据文件（如源目录根
  // icudtl.dat）映射到默认 `build\native\lib`（无配置目录）。
  for (final rel in dataFiles) {
    add(rel, 'data');
  }

  final mappings = <FileMapping>[];
  for (final parent in byDir.keys) {
    final config = _detectConfig(parent);
    final platform = _detectPlatform(parent);
    final byExt = byDir[parent]!;
    for (final entry in byExt.entries) {
      final ext = entry.key;
      final kind = entry.value;
      final target = kind == 'executable'
          ? (config != null
                ? joinPath(['build', 'native', 'tools', config])
                : joinPath(['build', 'native', 'tools']))
          : (config != null
                ? joinPath(['build', 'native', 'lib', platform, config])
                : joinPath(['build', 'native', 'lib']));
      mappings.add(
        FileMapping(
          srcGlob: parent.isEmpty ? '*$ext' : '$parent$pathSeparator*$ext',
          target: target,
          platforms: config != null ? [platform] : const <String>[],
          configurations: config != null ? [config] : const <String>[],
        ),
      );
    }
  }
  return mappings;
}

/// 从路径段探测配置名（`Debug`/`Release`），无法识别返回 null。
String? _detectConfig(String parentRelPath) {
  if (parentRelPath.isEmpty) return null;
  for (final segment in parentRelPath.split(pathSeparator)) {
    final s = segment.toLowerCase();
    if (s == 'debug') return 'Debug';
    if (s == 'release' ||
        s == 'reldebug' ||
        s == 'relwithdebinfo' ||
        s == 'minsizerel' ||
        s == 'profile') {
      return 'Release';
    }
  }
  return null;
}

/// 从路径段探测平台名（`x64`/`x86`/`arm64`），未识别时默认 `x64`。
String _detectPlatform(String parentRelPath) {
  if (parentRelPath.isEmpty) return 'x64';
  for (final segment in parentRelPath.split(pathSeparator)) {
    final s = segment.toLowerCase();
    if (s == 'x64' || s == 'amd64' || s == 'win64') return 'x64';
    if (s == 'x86' || s == 'win32') return 'x86';
    if (s == 'arm64') return 'arm64';
  }
  return 'x64';
}

/// 提取小写扩展名（含点），无扩展名返回空串。
String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  return name.substring(dot).toLowerCase();
}

/// 解析路径的规范（含符号链接）形式；失败时回退到原路径。
String _canonicalPath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return path;
  }
}

/// 归一化 `srcGlob` 用作变化检测/条件合并的键：统一分隔符、去首尾空白、转小写。
///
/// 扫描器生成的 glob 与用户手输的 glob 可能分隔符/大小写不同（如 `src\A.H` 与
/// `src/a.h`），归一化后视为同一文件类条目。
String normalizeMappingGlob(String srcGlob) =>
    normalizeSeparators(srcGlob.trim()).toLowerCase();

/// 映射的归一化键：`srcGlob + fileKind`（fileKind 派生自扩展名，随 srcGlob 确定）。
String _mappingKey(FileMapping mapping) =>
    '${normalizeMappingGlob(mapping.srcGlob)}|${mapping.fileKind}';

/// 判断扫描结果与现有映射是否存在「文件类条目」差异（新增/删除）。
///
/// 对比 [current] 与 [scan].suggestedMappings 的归一化键集合（srcGlob+fileKind）。
/// 仅当文件集合发生变化（新增或移除 glob）时返回 true；纯条件/目标路径调整不算
/// 变化（不触发重生成，由用户自行编辑）。
bool hasMappingChanged(List<FileMapping> current, ScanResult scan) {
  final currentKeys = current.map(_mappingKey).toSet();
  final scanKeys = scan.suggestedMappings.map(_mappingKey).toSet();
  return currentKeys.length != scanKeys.length ||
      !currentKeys.containsAll(scanKeys);
}

/// 合并旧字段条件（platforms/configurations）到新的建议映射。
///
/// 对 [newMappings] 中「归一化 srcGlob 与 [oldMappings] 相同」的条目，沿用旧映射的
/// platforms/configurations 条件；其余条目保持扫描建议默认（空 = 全部）。
List<FileMapping> mergeMappingConditions(
  List<FileMapping> oldMappings,
  List<FileMapping> newMappings,
) {
  final oldByGlob = <String, FileMapping>{};
  for (final mapping in oldMappings) {
    oldByGlob[normalizeMappingGlob(mapping.srcGlob)] = mapping;
  }
  return [
    for (final mapping in newMappings)
      mapping.copyWith(
        platforms:
            oldByGlob[normalizeMappingGlob(mapping.srcGlob)]?.platforms ??
            const <String>[],
        configurations:
            oldByGlob[normalizeMappingGlob(mapping.srcGlob)]?.configurations ??
            const <String>[],
      ),
  ];
}

/// 库图标候选文件名（按优先级排序；匹配时大小写不敏感）。
const List<String> kIconCandidateNames = <String>[
  'icon.png',
  'icon.jpg',
  'icon.jpeg',
  'icon.ico',
];

/// 在 [sourceDir] 顶层查找库图标文件。
///
/// 按 `icon.png` > `icon.jpg` > `icon.jpeg` > `icon.ico`（大小写不敏感）返回
/// 第一个存在的完整路径；[sourceDir] 不存在或未找到时返回 null。仅查顶层
/// （不递归），与 [scanSourceDir] 的递归行为不同。
String? findIconFile(String sourceDir) {
  final dir = sourceDir.trim();
  if (dir.isEmpty) return null;
  final directory = Directory(dir);
  if (!directory.existsSync()) return null;

  final lowerToPath = <String, String>{};
  List<FileSystemEntity> entries;
  try {
    entries = directory.listSync(followLinks: false);
  } on FileSystemException {
    return null;
  }
  for (final entry in entries) {
    if (entry is File) {
      lowerToPath[basenameOf(entry.path).toLowerCase()] = entry.path;
    }
  }
  for (final name in kIconCandidateNames) {
    final found = lowerToPath[name];
    if (found != null) return found;
  }
  return null;
}
