/// 应用设置存储：持久化 `nuget.exe` 路径、默认输出目录与最近打开的项目。
///
/// - 位置：Windows 下 `%APPDATA%\cpp_nuget_pack\settings.json`；其他平台兜底为
///   用户目录下 `.cpp_nuget_pack\settings.json`。
/// - 目录不存在时自动创建；读取失败（文件损坏/格式非法）时返回默认设置并记录
///   错误日志，不崩溃。
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'path_utils.dart';

/// 默认的 NuGet 全局包缓存目录（原始字符串，使用时展开环境变量）。
const String kDefaultNugetGlobalCacheDir = r'%USERPROFILE%\.nuget\packages';

/// 应用设置。
class AppSettings {
  AppSettings({
    this.nugetExePath,
    this.defaultOutputDir = '',
    this.nugetGlobalCacheDir = kDefaultNugetGlobalCacheDir,
    List<String>? recentProjects,
  }) : recentProjects = recentProjects ?? [];

  /// 用户指定的 `nuget.exe` 完整路径（可为空）。
  String? nugetExePath;

  /// 默认输出目录。
  String defaultOutputDir;

  /// 消费方 `nuget.config` 的全局包缓存目录（原始字符串，使用时展开环境变量）。
  String nugetGlobalCacheDir;

  /// 最近打开的项目文件路径列表（最近在前，最多保留 10 条）。
  List<String> recentProjects;

  /// 返回部分更新后的副本；未提供的字段保持不变。
  AppSettings copyWith({
    String? nugetExePath,
    String? defaultOutputDir,
    String? nugetGlobalCacheDir,
    List<String>? recentProjects,
  }) {
    return AppSettings(
      nugetExePath: nugetExePath ?? this.nugetExePath,
      defaultOutputDir: defaultOutputDir ?? this.defaultOutputDir,
      nugetGlobalCacheDir: nugetGlobalCacheDir ?? this.nugetGlobalCacheDir,
      recentProjects: recentProjects ?? List.of(this.recentProjects),
    );
  }

  /// 将 [projectPath] 加入最近列表（去重、置顶、截断到 10 条）。
  AppSettings addRecentProject(String projectPath) {
    final trimmed = projectPath.trim();
    if (trimmed.isEmpty) return this;
    final updated = <String>[
      trimmed,
      ...recentProjects.where((p) => p != trimmed),
    ];
    return copyWith(recentProjects: updated.take(10).toList());
  }

  Map<String, dynamic> toJson() => {
    'nugetExePath': nugetExePath,
    'defaultOutputDir': defaultOutputDir,
    'nugetGlobalCacheDir': nugetGlobalCacheDir,
    'recentProjects': List.of(recentProjects),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawRecent = json['recentProjects'];
    final recent = rawRecent is List
        ? rawRecent.whereType<String>().toList()
        : <String>[];
    return AppSettings(
      nugetExePath: json['nugetExePath'] is String
          ? json['nugetExePath'] as String
          : null,
      defaultOutputDir: json['defaultOutputDir'] is String
          ? json['defaultOutputDir'] as String
          : '',
      nugetGlobalCacheDir: json['nugetGlobalCacheDir'] is String
          ? json['nugetGlobalCacheDir'] as String
          : kDefaultNugetGlobalCacheDir,
      recentProjects: recent,
    );
  }

  @override
  String toString() =>
      'AppSettings(nugetExePath: $nugetExePath, defaultOutputDir: $defaultOutputDir, '
      'nugetGlobalCacheDir: $nugetGlobalCacheDir, '
      'recentProjects: ${recentProjects.length})';
}

/// 设置的读写入口。
class SettingsStore {
  SettingsStore({String? path}) : _path = path ?? defaultSettingsPath();

  final String _path;

  /// 计算默认设置文件路径（Windows 用 APPDATA；否则用户目录兜底）。
  static String defaultSettingsPath() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return joinPath([appData, 'cpp_nuget_pack', 'settings.json']);
    }
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return joinPath([home, '.cpp_nuget_pack', 'settings.json']);
  }

  /// 读取设置；文件不存在或损坏时返回默认 [AppSettings]。
  static AppSettings load({String? path}) {
    final store = SettingsStore(path: path);
    return store._read();
  }

  /// 保存设置，目录不存在时自动创建。
  static void save(AppSettings settings, {String? path}) {
    final store = SettingsStore(path: path);
    store._write(settings);
  }

  AppSettings _read() {
    final file = File(_path);
    if (!file.existsSync()) return AppSettings();
    try {
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return AppSettings();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return AppSettings();
      return AppSettings.fromJson(decoded);
    } on Object catch (e) {
      developer.log('读取设置失败，已回退到默认设置', name: 'SettingsStore', error: e);
      return AppSettings();
    }
  }

  void _write(AppSettings settings) {
    final directory = Directory(dirnameOf(_path));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final file = File(_path);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
