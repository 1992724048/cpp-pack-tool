/// 主工作台：顶部工具栏 + 左栏库列表 + 右栏 TabBar/TabBarView + 底部日志面板。
///
/// 对照 `docs/ui-spec.md` §四（页面布局）与 §3.7。数据状态用 setState 驱动，
/// 不引入状态管理库；初始化 AppSettings 与最近项目列表。
library;

import 'package:flutter/material.dart';

import '../models/pack_project.dart';
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
import 'widgets/top_toolbar.dart';

/// 主工作台。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _log = LogController();
    _settings = SettingsStore.load();
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
          TopToolbar(onOpenSettings: _openSettings),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LibraryList(
                  projects: _projects,
                  selectedIndex: _selectedIndex,
                  onSelect: _selectProject,
                  onAdd: _openAddSourceDir,
                  onRename: _renameProject,
                  onDelete: _deleteProject,
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
                log: _log,
                onNotify: _notify,
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

  Future<void> _openAddSourceDir() async {
    final initialDir = _selectedProject?.outputDirectory;
    final sourceDir = await showDialog<SourceDir>(
      context: context,
      builder: (_) => AddSourceDirDialog(initialDirectory: initialDir),
    );
    if (sourceDir == null || !mounted) return;
    setState(() {
      if (_selectedIndex == null) {
        _projects.add(
          PackProject(
            packageId: _derivePackageId(sourceDir.name),
            sourceDirs: <SourceDir>[sourceDir],
          ),
        );
        _selectedIndex = _projects.length - 1;
      } else {
        final index = _selectedIndex!;
        final current = _projects[index];
        _projects[index] = current.copyWith(
          sourceDirs: <SourceDir>[...current.sourceDirs, sourceDir],
        );
      }
    });
    _tabController.animateTo(0);
    _log.info('已添加源目录：${sourceDir.path}，映射 ${sourceDir.mappings.length} 条');
    _notify('已添加源目录：${sourceDir.path}');
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
    setState(() => _projects[index] = project.copyWith(packageId: newId));
    _log.info('已将库项目重命名为 $newId');
  }

  Future<void> _deleteProject(int index) async {
    final project = _projects[index];
    final confirmed = await confirmDelete(
      context,
      title: '删除确认',
      message: '确定删除库项目「${project.packageId}」吗？该项目的包元数据与映射将一并移除。',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _projects.removeAt(index);
      final selected = _selectedIndex;
      if (selected == null || selected == index) {
        _selectedIndex = _projects.isEmpty ? null : 0;
      } else if (selected > index) {
        _selectedIndex = selected - 1;
      }
    });
    _log.info('已删除库项目：${project.packageId}');
  }

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
