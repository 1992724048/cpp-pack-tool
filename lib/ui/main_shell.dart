/// 主工作台：左栏库列表 + 右栏 TabBar/TabBarView + 底部日志面板。
///
/// 数据状态用 setState 驱动，不引入状态管理库；初始化 AppSettings，并从
/// 输出目录注册表恢复已打包的库项目（见 `package_registry.dart`）。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../models/pack_project.dart';
import '../services/package_registry.dart';
import '../services/path_utils.dart';
import '../services/scanner.dart';
import '../services/settings.dart';
import 'log_controller.dart';
import 'pages/build_config_page.dart';
import 'pages/file_mapping_page.dart';
import 'pages/pack_info_page.dart';
import 'pages/pack_page.dart';
import 'tokens.dart';
import 'widgets/app_dialogs.dart';
import 'widgets/library_list.dart';
import 'widgets/log_panel.dart';
import 'widgets/settings_dialog.dart';

/// 主工作台：左栏库列表 + 右栏 TabBar/TabBarView + 底部日志面板。
///
/// 数据状态用 setState 驱动，不引入状态管理库。启动时读取 AppSettings（默认
/// 输出目录）并从输出目录注册表恢复已打包的库项目；[settings]/[initialPackages]/
/// [registryOutputDir] 为可注入构造参数，便于测试不依赖真实 `%APPDATA%`。
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.settings,
    this.initialPackages,
    this.registryOutputDir,
  });

  /// 注入的设置；为 null 时从 SettingsStore 读取。
  final AppSettings? settings;

  /// 注入的初始库项目列表；非 null 时跳过注册表加载（用于测试）。
  final List<PackProject>? initialPackages;

  /// 覆盖注册表输出目录（缺省取设置的默认输出目录）；用于测试写入隔离目录。
  final String? registryOutputDir;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final LogController _log;
  late AppSettings _settings;

  final List<PackProject> _projects = <PackProject>[];
  int? _selectedIndex;

  /// 已注册到输出目录注册表的 packageId 集合（用于删除时同步移除注册表条目）。
  final Set<String> _registeredIds = <String>{};

  /// 按 packageId 索引的库图标路径（来源：每个项目首个源目录顶层的 icon.*）。
  Map<String, String?> _iconPaths = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _log = LogController();
    _settings = widget.settings ?? SettingsStore.load();
    final initial = widget.initialPackages;
    if (initial != null) {
      _projects.addAll(initial);
      if (initial.isNotEmpty) _selectedIndex = 0;
    } else {
      _loadRegistryProjects();
    }
    _refreshIconPaths();
    _log.info('应用已启动，加载设置：$_settings');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _log.dispose();
    super.dispose();
  }

  PackProject? get _selectedProject {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _projects.length) return null;
    return _projects[index];
  }

  @override
  Widget build(BuildContext context) {
    final project = _selectedProject;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LibraryList(
                  projects: _projects,
                  selectedIndex: _selectedIndex,
                  iconPaths: _iconPaths,
                  onSelect: _selectProject,
                  onAdd: _addNewProject,
                  onRename: _renameProject,
                  onDelete: _deleteProject,
                  onSettings: _openSettings,
                ),
                Container(width: 1, color: AppColors.borderStrong),
                Expanded(child: _workspace(project)),
              ],
            ),
          ),
          LogPanel(controller: _log),
        ],
      ),
    );
  }

  Widget _workspace(PackProject? project) {
    return Column(
      children: [
        Container(
          height: AppDims.tabBarHeight,
          decoration: const BoxDecoration(
            color: AppColors.bgPanel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '包信息'),
              Tab(text: '文件映射'),
              Tab(text: '编译配置'),
              Tab(text: '打包'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              PackInfoPage(
                key: ValueKey('packinfo-$_selectedIndex'),
                project: project,
                onChanged: _updateProject,
              ),
              FileMappingPage(
                key: ValueKey('mapping-$_selectedIndex'),
                project: project,
                onChanged: _updateProject,
                onAddSourceDir: _addSourceDirToCurrent,
              ),
              BuildConfigPage(
                key: ValueKey('build-$_selectedIndex'),
                project: project,
                onChanged: _updateProject,
              ),
              PackPage(
                key: ValueKey('packpage-$_selectedIndex'),
                project: project,
                onChanged: _updateProject,
                settings: _settings,
                onSettingsChanged: _updateSettings,
                onOpenSettings: _openSettings,
                log: _log,
                onNotify: _notify,
                onPacked: _onPackSuccess,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _selectProject(int index) {
    setState(() => _selectedIndex = index);
  }

  void _updateProject(PackProject updated) {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _projects.length) return;
    setState(() => _projects[index] = updated);
  }

  void _updateSettings(AppSettings settings) {
    setState(() => _settings = settings);
    try {
      SettingsStore.save(settings);
      _log.info('设置已保存');
    } on Object catch (e) {
      _log.error('保存设置失败：$e');
      _notify('保存设置失败：$e', isError: true);
    }
  }

  Future<void> _openSettings() async {
    final updated = await showDialog<AppSettings>(
      context: context,
      builder: (_) => SettingsDialog(settings: _settings),
    );
    if (updated != null && mounted) {
      _updateSettings(updated);
    }
  }

  /// 左栏「＋ 添加」：始终新建一个库项目（无论当前是否有选中项目）。
  ///
  /// 流程：选择源目录 → 扫描 → 映射建议确认 → 新建库项目加入列表，并自动选中、
  /// 切回「包信息」Tab 提供视觉反馈。选中态不影响 ＋ 的「新建库项目」语义。
  Future<void> _addNewProject() async {
    final sourceDir = await showDialog<SourceDir>(
      context: context,
      builder: (_) => const AddSourceDirDialog(),
    );
    if (sourceDir == null || !mounted) return;
    final id = _derivePackageId(sourceDir.name);
    setState(() {
      _projects.add(
        PackProject(packageId: id, sourceDirs: <SourceDir>[sourceDir]),
      );
      _selectedIndex = _projects.length - 1;
      _refreshIconPaths();
    });
    _tabController.animateTo(0);
    _log.info(
      '已新建库项目：$id，源目录 ${sourceDir.path}，'
      '映射 ${sourceDir.mappings.length} 条',
    );
    _notify('已新建库项目：$id');
  }

  /// 向当前选中的库项目追加源目录（文件映射页「添加源目录」入口）。
  ///
  /// 复用 [AddSourceDirDialog] 流程，将新目录加入当前项目的 sourceDirs 并刷新；
  /// 返回新源目录在项目中的下标（无选中项目或用户取消时返回 null，供页面切换）。
  Future<int?> _addSourceDirToCurrent() async {
    final selectedIndex = _selectedIndex;
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= _projects.length) {
      return null;
    }
    final current = _projects[selectedIndex];
    final sourceDir = await showDialog<SourceDir>(
      context: context,
      builder: (_) => const AddSourceDirDialog(),
    );
    if (sourceDir == null || !mounted) return null;
    final updated = current.copyWith(
      sourceDirs: <SourceDir>[...current.sourceDirs, sourceDir],
    );
    setState(() {
      _projects[selectedIndex] = updated;
      _refreshIconPaths();
    });
    _log.info('已添加源目录：${sourceDir.path}，映射 ${sourceDir.mappings.length} 条');
    _notify('已添加源目录：${sourceDir.path}');
    return updated.sourceDirs.length - 1;
  }

  Future<void> _renameProject(int index) async {
    final project = _projects[index];
    final newId = await promptTextInput(
      context,
      title: '重命名库项目',
      hint: '新的包 ID',
      initial: project.packageId,
    );
    if (newId == null) return;
    setState(() {
      _projects[index] = project.copyWith(packageId: newId);
      if (_registeredIds.remove(project.packageId)) {
        _registeredIds.add(newId);
      }
      _refreshIconPaths();
    });
    _log.info('已将库项目重命名为 $newId');
  }

  Future<void> _deleteProject(int index) async {
    if (index < 0 || index >= _projects.length) return;
    final project = _projects[index];
    final options = await confirmDeleteProject(
      context,
      packageId: project.packageId,
      inRegistry: _registeredIds.contains(project.packageId),
    );
    if (options == null || !mounted) return;
    _performDelete(index, project, options);
  }

  /// 按勾选项执行删除：注册表移除、源目录包配置删除、当前版本 nupkg 删除。
  ///
  /// 单项失败仅记录 warn 日志（不中断其余删除）；成功后记录 info 日志。
  void _performDelete(
    int index,
    PackProject project,
    DeleteProjectOptions options,
  ) {
    if (options.removeFromRegistry &&
        _registeredIds.contains(project.packageId)) {
      _removeFromRegistry(project.packageId);
    }
    if (options.deleteSourceDirConfig) {
      _deleteSourceDirConfigs(project);
    }
    if (options.deleteNupkg) {
      _deleteNupkg(project);
    }
    setState(() {
      _registeredIds.remove(project.packageId);
      _projects.removeAt(index);
      final selected = _selectedIndex;
      if (selected == null || selected == index) {
        _selectedIndex = _projects.isEmpty ? null : 0;
      } else if (selected > index) {
        _selectedIndex = selected - 1;
      }
      _refreshIconPaths();
    });
    _log.info('已删除库项目：${project.packageId}');
  }

  /// 删除该项目所有源目录下的 `.cpp_nuget_pack.json`（存在才删）。
  void _deleteSourceDirConfigs(PackProject project) {
    for (final sourceDir in project.sourceDirs) {
      final path = sourceDir.path.trim();
      if (path.isEmpty) continue;
      final file = File(joinPath([path, kSourceDirConfigFileName]));
      if (!file.existsSync()) continue;
      try {
        file.deleteSync();
        _log.info('已删除源目录包配置文件：${file.path}');
      } on FileSystemException catch (e) {
        _log.warn('删除源目录包配置文件失败：${file.path}（${e.message}）');
      }
    }
  }

  /// 删除输出目录下当前版本 `.nupkg`（仅精确匹配当前版本，避免误删历史版本）。
  void _deleteNupkg(PackProject project) {
    final outputDir = _registryOutputDir;
    if (outputDir.isEmpty) return;
    final id = project.packageId.trim();
    if (id.isEmpty) return;
    final file = File(joinPath([outputDir, '$id.${project.version}.nupkg']));
    if (!file.existsSync()) return;
    try {
      file.deleteSync();
      _log.info('已删除已输出的 NuGet 包：${file.path}');
    } on FileSystemException catch (e) {
      _log.warn('删除 NuGet 包失败：${file.path}（${e.message}）');
    }
  }

  /// 为当前全部项目重建图标路径缓存（每个项目首个源目录顶层的 icon.*）。
  void _refreshIconPaths() {
    final map = <String, String?>{};
    for (final project in _projects) {
      final sourceDirs = project.sourceDirs;
      String? icon;
      if (sourceDirs.isNotEmpty) {
        final firstDir = sourceDirs.first.path.trim();
        if (firstDir.isNotEmpty) {
          icon = findIconFile(firstDir);
        }
      }
      map[project.packageId] = icon;
    }
    _iconPaths = map;
  }

  /// 从输出目录注册表移除 packageId；失败时记录日志并提示。
  void _removeFromRegistry(String packageId) {
    final outputDir = _registryOutputDir;
    if (outputDir.isEmpty) return;
    final ok = removePackage(outputDir, packageId);
    if (ok) {
      _log.info('已从输出目录注册表移除：$packageId');
    } else {
      _log.error('从输出目录注册表移除 $packageId 失败');
      _notify('移除输出目录注册表条目失败', isError: true);
    }
  }

  /// 启动时从输出目录注册表恢复已打包的库项目。
  void _loadRegistryProjects() {
    final outputDir = _registryOutputDir;
    if (outputDir.isEmpty) return;
    final result = loadRegistry(outputDir);
    if (result.hasError) {
      _log.warn('读取输出目录注册表失败：${result.error}');
    }
    if (result.packages.isEmpty) return;
    for (final pkg in result.packages) {
      final restored = _applySourceDirConfig(pkg.project.copy());
      _projects.add(restored);
      _registeredIds.add(restored.packageId);
    }
    _selectedIndex = 0;
    _log.info('已从输出目录注册表恢复 ${result.packages.length} 个库项目');
  }

  /// 用源目录配置覆盖注册表项目（源目录配置为事实源）；读取失败仅警告继续。
  PackProject _applySourceDirConfig(PackProject project) {
    for (final sourceDir in project.sourceDirs) {
      if (sourceDir.path.trim().isEmpty) continue;
      final result = readSourceDirConfig(sourceDir.path);
      if (result.error != null) {
        _log.warn('读取源目录配置 ${sourceDir.path} 失败：${result.error}');
        continue;
      }
      final config = result.project;
      if (config != null) {
        _log.info('已用源目录配置覆盖 ${config.packageId}（${sourceDir.path}）');
        return config;
      }
    }
    return project;
  }

  /// 一键打包成功后登记到输出目录注册表，并将配置写入主源目录。
  void _onPackSuccess(PackProject project) {
    _writeSourceDirConfig(project);
    final outputDir = _registryOutputDir;
    if (outputDir.isEmpty) return;
    final pkg = RegisteredPackage(
      project: project.copy(),
      lastPackedAt: DateTime.now(),
    );
    final ok = upsertPackage(outputDir, pkg);
    if (ok) {
      setState(() => _registeredIds.add(project.packageId));
      _log.info('已登记到输出目录注册表：${project.packageId}');
    } else {
      _log.error('写入输出目录注册表失败：${project.packageId}');
      _notify('写入输出目录注册表失败', isError: true);
    }
  }

  /// 将包配置写入主源目录（`{sourceDir}\.cpp_nuget_pack.json`），供下次加载优先读取。
  void _writeSourceDirConfig(PackProject project) {
    final sourceDirs = project.sourceDirs;
    if (sourceDirs.isEmpty) return;
    final sourceDir = sourceDirs.first.path.trim();
    if (sourceDir.isEmpty) return;
    final ok = writeSourceDirConfig(sourceDir, project);
    if (ok) {
      _log.info('已保存源目录配置：$sourceDir');
    } else {
      _log.error('写入源目录配置失败：$sourceDir');
      _notify('写入源目录配置失败', isError: true);
    }
  }

  /// 用于读写的输出目录：优先注入值，否则取设置的默认输出目录。
  String get _registryOutputDir =>
      widget.registryOutputDir?.trim() ?? _settings.defaultOutputDir.trim();

  void _notify(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.bgSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 从目录名派生合法的 NuGet 包 id。
  static String _derivePackageId(String name) {
    var id = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    // 去掉开头分隔符，确保以字母/数字/下划线开头（NuGet id 规则）。
    id = id.replaceFirst(RegExp(r'^[._-]+'), '');
    if (id.isEmpty || id.replaceAll('_', '').isEmpty) return 'Pkg';
    return id;
  }
}
