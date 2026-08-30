/// 输出目录包注册表：记录「已打包到该输出目录的包」及其最近打包时间。
///
/// 配置文件：`<全局输出目录>\packages.json`，结构：
/// ```json
/// { "packages": [ { "project": { ...PackProject JSON... }, "lastPackedAt": "2026-08-27T12:00:00" } ] }
/// ```
///
/// 本模块为纯 Dart + dart:io，可单测；不依赖 UI 层。读取失败（文件缺失/损坏）
/// 不抛异常、不崩溃——返回空列表并记录警告（经由 [developer.log]，结果类型
/// 亦携带解析错误信息供调用方日志）。写入采用「临时文件 + 改名」的原子写。
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../models/pack_project.dart';
import 'path_utils.dart';

/// 注册表文件名。
const String kRegistryFileName = 'packages.json';

/// 一条打包历史记录：版本 + 打包完成时间 + 可选摘要。
///
/// 由 [upsertPackage] 在打包时追加；[RegisteredPackage.history] 按打包时间升序
/// 维护，时间线查询（[packageHistory]）会按时间倒序返回。
class PackHistoryEntry {
  PackHistoryEntry({
    required this.version,
    required this.packedAt,
    this.summary,
  });

  /// 该次打包的版本号。
  final String version;

  /// 该次打包的完成时间。
  final DateTime packedAt;

  /// 可选摘要（如打包模式/备注），暂未使用。
  final String? summary;

  /// 返回副本；未提供的字段保持不变。
  PackHistoryEntry copyWith({
    String? version,
    DateTime? packedAt,
    String? summary,
  }) {
    return PackHistoryEntry(
      version: version ?? this.version,
      packedAt: packedAt ?? this.packedAt,
      summary: summary ?? this.summary,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'packedAt': packedAt.toIso8601String(),
    if (summary != null) 'summary': summary,
  };

  factory PackHistoryEntry.fromJson(Map<String, dynamic> json) {
    final versionRaw = json['version'];
    final packedRaw = json['packedAt'];
    final summaryRaw = json['summary'];
    final packed = packedRaw is String ? DateTime.tryParse(packedRaw) : null;
    return PackHistoryEntry(
      version: versionRaw is String ? versionRaw : '',
      packedAt: packed ?? DateTime.now(),
      summary: summaryRaw is String ? summaryRaw : null,
    );
  }

  @override
  String toString() =>
      'PackHistoryEntry(version: $version, packedAt: $packedAt)';
}

/// 一条已打包记录：完整的 [PackProject] 配置 + 最近打包时间 + 打包历史。
class RegisteredPackage {
  RegisteredPackage({
    required this.project,
    this.lastPackedAt,
    List<PackHistoryEntry>? history,
  }) : history = history ?? [];

  /// 项目完整配置（含 packageId/version/sourceDirs/mappings 等）。
  final PackProject project;

  /// 最近一次一键打包的完成时间（可为空，表示尚未成功打包）。
  final DateTime? lastPackedAt;

  /// 打包历史（按打包时间升序）；旧数据无 history 时为空列表，时间线在首次
  /// 打包后开始记录，[lastPackedAt] 保留兼容。
  final List<PackHistoryEntry> history;

  /// 返回副本；未提供的字段保持不变。
  RegisteredPackage copyWith({
    PackProject? project,
    DateTime? lastPackedAt,
    List<PackHistoryEntry>? history,
  }) {
    return RegisteredPackage(
      project: project ?? this.project.copy(),
      lastPackedAt: lastPackedAt ?? this.lastPackedAt,
      history: history != null ? List.of(history) : List.of(this.history),
    );
  }

  Map<String, dynamic> toJson() => {
    'project': project.toJson(),
    'lastPackedAt': lastPackedAt?.toIso8601String(),
    'history': [for (final entry in history) entry.toJson()],
  };

  factory RegisteredPackage.fromJson(Map<String, dynamic> json) {
    final projectJson = json['project'];
    final lastRaw = json['lastPackedAt'];
    final historyRaw = json['history'];
    final history = <PackHistoryEntry>[];
    if (historyRaw is List) {
      for (final item in historyRaw) {
        if (item is Map<String, dynamic>) {
          history.add(PackHistoryEntry.fromJson(item));
        }
      }
    }
    return RegisteredPackage(
      project: projectJson is Map<String, dynamic>
          ? PackProject.fromJson(projectJson)
          : PackProject(),
      lastPackedAt: lastRaw is String ? DateTime.tryParse(lastRaw) : null,
      history: history,
    );
  }
}

/// [loadRegistry] 的返回结果：包列表 + 可选解析错误。
///
/// 文件不存在时 `packages` 为空且 `error` 为 null；文件损坏/格式非法时
/// `packages` 为空且 `error` 携带失败说明。
class RegistryLoadResult {
  const RegistryLoadResult({required this.packages, this.error});

  /// 已解析的包列表（按注册表顺序）。
  final List<RegisteredPackage> packages;

  /// 解析失败说明；null 表示成功或文件不存在。
  final String? error;

  /// 是否出现解析错误。
  bool get hasError => error != null;
}

/// 读取注册表。文件不存在返回空列表；解析失败/损坏返回空列表并记录警告。
///
/// [outputDir] 为空或未设置时返回空结果（无错误）。
RegistryLoadResult loadRegistry(String outputDir) {
  if (outputDir.trim().isEmpty) {
    return const RegistryLoadResult(packages: <RegisteredPackage>[]);
  }
  final file = File(joinPath([outputDir.trim(), kRegistryFileName]));
  if (!file.existsSync()) {
    return const RegistryLoadResult(packages: <RegisteredPackage>[]);
  }
  try {
    final content = file.readAsStringSync();
    if (content.trim().isEmpty) {
      return const RegistryLoadResult(packages: <RegisteredPackage>[]);
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      return _corruptResult('注册表根节点必须是对象');
    }
    final rawPackages = decoded['packages'];
    if (rawPackages is! List) {
      return _corruptResult('注册表缺少 packages 列表');
    }
    final packages = <RegisteredPackage>[];
    for (final item in rawPackages) {
      if (item is Map<String, dynamic>) {
        packages.add(RegisteredPackage.fromJson(item));
      }
    }
    return RegistryLoadResult(packages: packages);
  } on Object catch (e) {
    return _corruptResult('解析注册表失败：$e');
  }
}

/// 构造损坏结果并记日志。
RegistryLoadResult _corruptResult(String message) {
  developer.log(message, name: 'PackageRegistry');
  return RegistryLoadResult(packages: <RegisteredPackage>[], error: message);
}

/// 写入注册表（目录不存在则创建；原子写：先写临时文件再改名）。
///
/// 写入失败时抛出异常，由调用方处理（不 silent ignore）。
void saveRegistry(String outputDir, List<RegisteredPackage> packages) {
  final dir = Directory(outputDir.trim());
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final target = File(joinPath([outputDir.trim(), kRegistryFileName]));
  final temp = File('${target.path}.tmp');
  try {
    temp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'packages': [for (final pkg in packages) pkg.toJson()],
      }),
    );
    _replaceFile(temp, target);
  } on Object {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } on Object {
      // 清理临时文件失败不掩盖原始错误。
    }
    rethrow;
  }
}

/// 将 [temp] 原子替换到 [target]：优先 rename（覆盖目标），平台 rename 不支持
/// 覆盖时移除目标后再改名，保证不留下半成品文件。
void _replaceFile(File temp, File target) {
  try {
    temp.renameSync(target.path);
  } on FileSystemException {
    if (target.existsSync()) target.deleteSync();
    temp.renameSync(target.path);
  }
}

/// 按 packageId 更新或追加一条记录并落盘；返回是否成功。
///
/// [outputDir] 为空时不写入并返回 false。
///
/// 当 [pkg.lastPackedAt] 非空（即一次打包调用）时，向历史追加一条
/// [PackHistoryEntry]（`version` 取 `pkg.project.version`）；若最新历史条目版本
/// 相同则仅更新其 [PackHistoryEntry.packedAt]，否则新增一条。
bool upsertPackage(String outputDir, RegisteredPackage pkg) {
  if (outputDir.trim().isEmpty) return false;
  try {
    final current = loadRegistry(outputDir).packages;
    final updated = <RegisteredPackage>[];
    var replaced = false;
    for (final item in current) {
      if (item.project.packageId == pkg.project.packageId) {
        updated.add(_mergeRegistryRecord(item, pkg));
        replaced = true;
      } else {
        updated.add(item);
      }
    }
    if (!replaced) updated.add(_seedRegistryRecord(pkg));
    saveRegistry(outputDir, updated);
    return true;
  } on Object catch (e) {
    developer.log('upsertPackage 失败', name: 'PackageRegistry', error: e);
    return false;
  }
}

/// 合并既有记录与本次传入记录：项目与 lastPackedAt 以本次为准，历史取两者并集
/// 后追加/更新本次打包条目。
RegisteredPackage _mergeRegistryRecord(
  RegisteredPackage existing,
  RegisteredPackage incoming,
) {
  final merged = RegisteredPackage(
    project: incoming.project.copy(),
    lastPackedAt: incoming.lastPackedAt,
    history: [...existing.history, ...incoming.history],
  );
  if (incoming.lastPackedAt != null) {
    _appendHistory(merged, incoming.project.version, incoming.lastPackedAt!);
  }
  return merged;
}

/// 构造新 packageId 的记录（继承传入历史），并追加本次打包条目（若有）。
RegisteredPackage _seedRegistryRecord(RegisteredPackage incoming) {
  final seeded = RegisteredPackage(
    project: incoming.project.copy(),
    lastPackedAt: incoming.lastPackedAt,
    history: [...incoming.history],
  );
  if (incoming.lastPackedAt != null) {
    _appendHistory(seeded, incoming.project.version, incoming.lastPackedAt!);
  }
  return seeded;
}

/// 向 [pkg].history 追加或更新一条打包历史。
///
/// 若最新一条的版本与 [version] 相同，仅更新其 [PackHistoryEntry.packedAt]；
/// 否则追加新条目。
void _appendHistory(RegisteredPackage pkg, String version, DateTime packedAt) {
  if (pkg.history.isEmpty) {
    pkg.history.add(PackHistoryEntry(version: version, packedAt: packedAt));
    return;
  }
  final lastIndex = pkg.history.length - 1;
  final last = pkg.history[lastIndex];
  if (last.version == version) {
    pkg.history[lastIndex] = last.copyWith(packedAt: packedAt);
  } else {
    pkg.history.add(PackHistoryEntry(version: version, packedAt: packedAt));
  }
}

/// 查询指定包 id 的打包历史（按打包时间倒序）。
///
/// [] 供 UI 时间线展示；包不存在或历史为空时返回空列表。
List<PackHistoryEntry> packageHistory(String outputDir, String packageId) {
  final result = loadRegistry(outputDir);
  for (final pkg in result.packages) {
    if (pkg.project.packageId == packageId) {
      final sorted = [...pkg.history]
        ..sort((a, b) => b.packedAt.compareTo(a.packedAt));
      return sorted;
    }
  }
  return const [];
}

/// 指定包 id 是否已在输出目录注册表中登记。
///
/// 供依赖丢失检查与自我排除使用；[outputDir] 为空时返回 false。
bool isPackagePresent(String outputDir, String packageId) {
  if (outputDir.trim().isEmpty) return false;
  return loadRegistry(outputDir).packages
      .any((pkg) => pkg.project.packageId == packageId);
}

/// 建议版本策略：根据 [strategy] 为 [currentVersion] 推导新版本号。
///
/// 返回 `String?`；解析失败（无法识别为语义化版本）返回 null。
/// - `manual`：返回输入版本原值（不强制语义化）。
/// - `timestamp`：以输入版本为 SemVer 主干，生成 prerelease 版本
///   `{major}.{minor}.{patch}-{yyyyMMddHHmm}`（如 `1.2.3-202608271230`）。
/// - `bump`：以输入版本为基线取其 patch+1；若 [registeredVersions] 中存在与输入
///   同 `major.minor` 的更高 patch，则取历史最高 patch+1（如 `1.2.3` + 历史
///   `1.2.7` → `1.2.8`）。
///
/// [registeredVersions] 为包历史中的版本列表（用于 bump）。其它策略忽略之。
String? suggestVersion({
  required String currentVersion,
  required List<String> registeredVersions,
  required String strategy,
}) {
  final input = currentVersion.trim();
  if (strategy == 'manual') {
    return input.isEmpty ? null : input;
  }
  final base = _parseSemVer(input);
  if (base == null) return null;

  if (strategy == 'timestamp') {
    final now = DateTime.now();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${pad2(now.month)}${pad2(now.day)}'
        '${pad2(now.hour)}${pad2(now.minute)}';
    return '${base.major}.${base.minor}.${base.patch}-$stamp';
  }

  if (strategy == 'bump') {
    var maxPatch = base.patch;
    for (final version in registeredVersions) {
      final other = _parseSemVer(version);
      if (other == null) continue;
      if (other.major == base.major &&
          other.minor == base.minor &&
          other.patch > maxPatch) {
        maxPatch = other.patch;
      }
    }
    return '${base.major}.${base.minor}.${maxPatch + 1}';
  }

  return null;
}

/// 解析语义化版本的主段（`major.minor.patch`），忽略 prerelease 与 build 元数据。
///
/// 仅保留数字主段；缺失的 minor/patch 按 0 处理；无法解析 major 返回 null。
({int major, int minor, int patch})? _parseSemVer(String version) {
  final trimmed = version.trim();
  if (trimmed.isEmpty) return null;
  final core = trimmed.split('+').first;
  final coreNoPre = core.split('-').first;
  final parts = coreNoPre.split('.');
  final major = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  if (major == null) return null;
  final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final patch = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
  return (major: major, minor: minor, patch: patch);
}

/// 移除指定 packageId 的记录并落盘；返回是否成功。
///
/// 文件不存在时静默返回 true（无可操作项）。
bool removePackage(String outputDir, String packageId) {
  if (outputDir.trim().isEmpty) return true;
  final file = File(joinPath([outputDir.trim(), kRegistryFileName]));
  if (!file.existsSync()) return true;
  try {
    final current = loadRegistry(outputDir).packages;
    final updated = current
        .where((item) => item.project.packageId != packageId)
        .toList();
    saveRegistry(outputDir, updated);
    return true;
  } on Object catch (e) {
    developer.log('removePackage 失败', name: 'PackageRegistry', error: e);
    return false;
  }
}

/// 源目录配置文件名（保存在源目录下，为该库的完整 [PackProject] 配置）。
const String kSourceDirConfigFileName = '.cpp_nuget_pack.json';

/// [readSourceDirConfig] 的返回结果：项目配置 + 可选解析错误。
///
/// 文件不存在时 `project` 为 null 且 `error` 为 null；损坏/格式非法时 `project`
/// 为 null 且 `error` 携带失败说明。
class SourceDirConfigResult {
  const SourceDirConfigResult({this.project, this.error});

  /// 解析成功时的项目配置（可为 null，表示无配置或读取失败）。
  final PackProject? project;

  /// 解析失败说明；null 表示成功或文件不存在。
  final String? error;

  /// 是否出现解析错误。
  bool get hasError => error != null;
}

/// 将 [project] 的完整配置写入源目录下的 `.cpp_nuget_pack.json`。
///
/// 源目录不存在时跳过并返回 false；写入成功返回 true（临时文件 + 改名的原子写）。
bool writeSourceDirConfig(String sourceDir, PackProject project) {
  final dir = Directory(sourceDir.trim());
  if (!dir.existsSync()) return false;
  final target = File(joinPath([sourceDir.trim(), kSourceDirConfigFileName]));
  final temp = File('${target.path}.tmp');
  try {
    temp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
    );
    _replaceFile(temp, target);
    return true;
  } on Object catch (e) {
    developer.log('writeSourceDirConfig 失败', name: 'PackageRegistry', error: e);
    try {
      if (temp.existsSync()) temp.deleteSync();
    } on Object {
      // 清理临时文件失败不掩盖原始错误。
    }
    return false;
  }
}

/// 从源目录读取项目配置（`.cpp_nuget_pack.json`）。
///
/// 文件不存在返回空结果（无错误）；解析失败/损坏返回空结果并携带错误说明。
SourceDirConfigResult readSourceDirConfig(String sourceDir) {
  final source = sourceDir.trim();
  if (source.isEmpty) {
    return const SourceDirConfigResult();
  }
  final file = File(joinPath([source, kSourceDirConfigFileName]));
  if (!file.existsSync()) {
    return const SourceDirConfigResult();
  }
  try {
    final content = file.readAsStringSync();
    if (content.trim().isEmpty) {
      return const SourceDirConfigResult(error: '源目录配置文件为空');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      return const SourceDirConfigResult(error: '源目录配置根节点必须是对象');
    }
    return SourceDirConfigResult(project: PackProject.fromJson(decoded));
  } on Object catch (e) {
    return SourceDirConfigResult(error: '解析源目录配置失败：$e');
  }
}
