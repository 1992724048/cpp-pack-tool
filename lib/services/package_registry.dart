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

/// 一条已打包记录：完整的 [PackProject] 配置 + 最近打包时间。
class RegisteredPackage {
  RegisteredPackage({required this.project, this.lastPackedAt});

  /// 项目完整配置（含 packageId/version/sourceDirs/mappings 等）。
  final PackProject project;

  /// 最近一次一键打包的完成时间（可为空，表示尚未成功打包）。
  final DateTime? lastPackedAt;

  /// 返回副本；未提供的字段保持不变。
  RegisteredPackage copyWith({PackProject? project, DateTime? lastPackedAt}) {
    return RegisteredPackage(
      project: project ?? this.project.copy(),
      lastPackedAt: lastPackedAt ?? this.lastPackedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'project': project.toJson(),
    'lastPackedAt': lastPackedAt?.toIso8601String(),
  };

  factory RegisteredPackage.fromJson(Map<String, dynamic> json) {
    final projectJson = json['project'];
    final lastRaw = json['lastPackedAt'];
    return RegisteredPackage(
      project: projectJson is Map<String, dynamic>
          ? PackProject.fromJson(projectJson)
          : PackProject(),
      lastPackedAt: lastRaw is String ? DateTime.tryParse(lastRaw) : null,
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
bool upsertPackage(String outputDir, RegisteredPackage pkg) {
  if (outputDir.trim().isEmpty) return false;
  try {
    final current = loadRegistry(outputDir).packages;
    final updated = <RegisteredPackage>[];
    var replaced = false;
    for (final item in current) {
      if (item.project.packageId == pkg.project.packageId) {
        updated.add(pkg);
        replaced = true;
      } else {
        updated.add(item);
      }
    }
    if (!replaced) updated.add(pkg);
    saveRegistry(outputDir, updated);
    return true;
  } on Object catch (e) {
    developer.log('upsertPackage 失败', name: 'PackageRegistry', error: e);
    return false;
  }
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
