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

/// 头文件扩展名。
const Set<String> kHeaderExtensions = {'.h', '.hpp', '.hh', '.hxx'};

/// 库文件扩展名。
const Set<String> kLibraryExtensions = {'.lib', '.a', '.dll', '.so', '.dylib'};

/// 数据文件扩展名（建议拷贝到 OutDir 或随包）。
const Set<String> kDataExtensions = {'.dat', '.bin', '.json', '.txt'};

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

/// 扫描结果：分类后的相对路径列表与建议映射。
class ScanResult {
  ScanResult({
    required this.headers,
    required this.libraries,
    required this.dataFiles,
    required this.suggestedMappings,
    this.truncated = false,
    this.warnings = const [],
  });

  /// 头文件相对路径列表（含 `**` 的子目录结构，以 `\` 分隔）。
  final List<String> headers;

  /// 库文件相对路径列表。
  final List<String> libraries;

  /// 数据文件相对路径列表（建议拷贝到 OutDir 或随包）。
  final List<String> dataFiles;

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
  int maxDepth = 4,
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
  final libraries = <String>[];
  final dataFiles = <String>[];
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
    libraries: libraries,
    dataFiles: dataFiles,
    visitedDirs: visitedDirs,
    warnings: warnings,
    onTruncate: (reason) {
      truncated = true;
      warnings.add(reason);
    },
  );

  final suggested = <FileMapping>[];
  suggested.addAll(_buildHeaderMappings(dirPath, headers));
  suggested.addAll(_buildLibraryAndDataMappings(libraries, dataFiles));

  return ScanResult(
    headers: headers,
    libraries: libraries,
    dataFiles: dataFiles,
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
  required List<String> libraries,
  required List<String> dataFiles,
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
        libraries: libraries,
        dataFiles: dataFiles,
        visitedDirs: visitedDirs,
        warnings: warnings,
        onTruncate: onTruncate,
      );
      continue;
    }

    if (type == FileSystemEntityType.file) {
      final ext = _extensionOf(name);
      if (kHeaderExtensions.contains(ext)) {
        headers.add(rel);
      } else if (kLibraryExtensions.contains(ext)) {
        libraries.add(rel);
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
/// glob 为该目录下的 `*.ext`，目标为 `build\native\include\<源目录名>\<子目录>`。
/// 非递归、不重叠，可完整保留包内相对结构。
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
      'build',
      'native',
      'include',
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

/// 根据库/数据文件按父目录分组（识别配置与平台），生成建议映射。
List<FileMapping> _buildLibraryAndDataMappings(
  List<String> libraries,
  List<String> dataFiles,
) {
  // 父目录 -> 实际存在的扩展名集合（库 + 数据，仅统计真实出现的扩展名）。
  final byDir = <String, Set<String>>{};
  void add(String rel) {
    final parent = dirnameOf(rel);
    final ext = _extensionOf(basenameOf(rel));
    if (ext.isEmpty) return;
    byDir.putIfAbsent(parent, () => <String>{}).add(ext);
  }

  for (final rel in libraries) {
    add(rel);
  }
  // 仅当父目录能识别出配置时，数据文件才随库一起映射到 lib 目标。
  for (final rel in dataFiles) {
    final parent = dirnameOf(rel);
    if (_detectConfig(parent) != null) {
      add(rel);
    }
  }

  final mappings = <FileMapping>[];
  for (final parent in byDir.keys) {
    final config = _detectConfig(parent);
    final platform = _detectPlatform(parent);
    final target = config != null
        ? joinPath(['build', 'native', 'lib', platform, config])
        : joinPath(['build', 'native', 'lib']);

    for (final ext in byDir[parent]!) {
      mappings.add(
        FileMapping(
          srcGlob: parent.isEmpty ? '*$ext' : '$parent$pathSeparator*$ext',
          target: target,
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
