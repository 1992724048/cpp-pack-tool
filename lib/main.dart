import 'package:catppuccin_flutter/catppuccin_flutter.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/packaging/cmake_exporter.dart' as cmake_exporter;
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/packaging/script_packaging.dart';
import 'package:cpp_nuget_pack/scanner/file_scan.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'app_info.dart';
import 'controls/add_directory_dialog.dart';
import 'controls/build_pack_dialog.dart';
import 'controls/delete_pack_dialog.dart';
import 'controls/dependency_graph_dialog.dart';
import 'controls/missing_dependencies_dialog.dart';
import 'controls/pack_export_dialog.dart';
import 'controls/pack_history_dialog.dart';
import 'controls/pack_list.dart';
import 'controls/packaging_issues_dialog.dart';
import 'controls/remap_pack_dialog.dart';
import 'pages/about.dart';
import 'pages/setting.dart';

void main() {
  runApp(const PackTool());
}

class PackTool extends StatefulWidget {
  const PackTool({super.key, this.store = const PackStore()});

  final PackStore store;

  @override
  State<PackTool> createState() => _PackToolState();
}

class _PackToolState extends State<PackTool> {
  SettingsModel _settings = const SettingsModel();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SettingsModel settings;
    try {
      settings = await widget.store.loadSettings();
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
  }

  Future<void> _saveSettings(SettingsModel next) async {
    setState(() => _settings = next);
    await widget.store.saveSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'C++ Pack Tool',
      themeMode: switch (_settings.themeMode) {
        ThemeModeSetting.system => ThemeMode.system,
        ThemeModeSetting.dark => ThemeMode.dark,
        ThemeModeSetting.light => ThemeMode.light,
      },
      theme: buildTheme(Brightness.light, catppuccin.latte, _settings.accent),
      darkTheme: buildTheme(
        Brightness.dark,
        flavorByName(_settings.darkFlavor),
        _settings.accent,
      ),
      home: MainLayout(
        store: widget.store,
        settings: _settings,
        onSaveSettings: _saveSettings,
      ),
    );
  }
}

Future<void> _noopSaveSettings(SettingsModel settings) async {}

class MainLayout extends StatefulWidget {
  const MainLayout({
    super.key,
    this.pickDirectory = getDirectoryPath,
    this.scanFiles = FileScan.scan,
    this.store = const PackStore(),
    this.settings = const SettingsModel(),
    this.onSaveSettings = _noopSaveSettings,
    this.exportPackage = exportNuGetPackage,
    this.exportCmakePackage = cmake_exporter.exportCmakePackage,
    this.buildPack = runPackBuild,
    this.now = DateTime.now,
  });

  final Future<String?> Function() pickDirectory;
  final Future<List<FileModel>> Function(String directoryPath) scanFiles;
  final PackStore store;
  final SettingsModel settings;
  final Future<void> Function(SettingsModel settings) onSaveSettings;
  final Future<PackageExportResult> Function(
    PackModel pack,
    String outputDirectory,
  )
  exportPackage;
  final Future<PackageExportResult> Function(
    PackModel pack,
    String outputDirectory,
  )
  exportCmakePackage;
  final PackBuildRunner buildPack;
  final DateTime Function() now;

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  static const String _nugetBuilderId = 'nuget';
  static const String _cmakeBuilderId = 'cmake';

  List<PackModel> _packs = [];
  int? _selected;
  PackageBuilder _packagingBuilder = PackageBuilderRegistry.all.first;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final List<PackLoadError> errors = <PackLoadError>[];
    List<PackModel> packs = <PackModel>[];
    try {
      await widget.store.ensureConfigExist();
      final PackLoadResult result = await widget.store.loadPacks();
      packs = result.packs;
      errors.addAll(result.errors);
    } catch (error) {
      errors.add(
        PackLoadError(
          fileName: widget.store.rootPath,
          message: error.toString(),
        ),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _packs = packs;
      _sortPacks();
      _selected = _packs.isEmpty ? null : 0;
    });
    if (errors.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showLoadErrorsToast(errors),
      );
    }
  }

  void _showLoadErrorsToast(List<PackLoadError> errors) {
    if (!mounted) {
      return;
    }
    final String details = errors
        .map((PackLoadError error) => error.toString())
        .join('\n');
    showFloatingToast(
      context,
      '${errors.length} 个配置加载失败\n$details',
      type: FloatingToastType.error,
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _addFolder() async {
    final String? path = await widget.pickDirectory();
    if (path == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final Future<List<FileModel>> scanFuture = widget.scanFiles(path);
    final PackModel? pack = await showDialog<PackModel>(
      context: context,
      builder: (_) =>
          AddDirectoryDialog(directoryPath: path, scanFuture: scanFuture),
    );
    if (pack == null || !mounted) {
      return;
    }
    final int totalSize = pack.files.fold<int>(
      0,
      (int sum, FileModel file) => sum + file.size,
    );
    pack.history = appendHistoryEntry(
      pack.history,
      HistoryModel(
        time: widget.now(),
        type: HistoryType.created,
        message: '创建包：${pack.files.length} 个文件，总大小 ${formatBytes(totalSize)}',
      ),
    );
    await _savePack(pack);
  }

  Future<bool> _savePack(PackModel pack) async {
    final PackModel? previous = _findPack(pack.name);
    if (previous != null && previous.version != pack.version) {
      pack.history = appendHistoryEntry(
        pack.history,
        HistoryModel(
          time: widget.now(),
          type: HistoryType.versionChanged,
          message: '版本变更：${previous.version} → ${pack.version}',
        ),
      );
    }
    try {
      await widget.store.savePack(pack);
    } catch (error) {
      if (!mounted) {
        return false;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => ContentDialog(
          title: const Text('保存失败'),
          content: Text('包「${pack.name}」保存失败：$error'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return false;
    }
    if (!mounted) {
      return false;
    }
    _upsertPack(pack);
    return true;
  }

  void _upsertPack(PackModel pack) {
    setState(() {
      final int existing = _packs.indexWhere(
        (PackModel item) => item.name.toLowerCase() == pack.name.toLowerCase(),
      );
      if (existing >= 0) {
        _packs[existing] = pack;
      } else {
        _packs.add(pack);
      }
      _sortPacks();
      final int selected = _packs.indexOf(pack);
      if (selected >= 0) {
        _selected = selected;
      }
    });
  }

  bool get _hasSelectedPack {
    final int? selected = _selected;
    return selected != null && selected >= 0 && selected < _packs.length;
  }

  PackModel? _findPack(String name) {
    final String lower = name.toLowerCase();
    for (final PackModel pack in _packs) {
      if (pack.name.toLowerCase() == lower) {
        return pack;
      }
    }
    return null;
  }

  Future<void> _deleteSelectedPack() async {
    final int? selected = _selected;
    if (selected == null || selected < 0 || selected >= _packs.length) {
      return;
    }
    final PackModel pack = _packs[selected];
    final List<PackDependent> dependents = <PackDependent>[
      for (final PackModel item in _packs)
        if (item.name.toLowerCase() != pack.name.toLowerCase())
          for (final DependencyModel dependency in item.dependencies)
            if (dependency.name.toLowerCase() == pack.name.toLowerCase())
              (name: item.name, version: dependency.version),
    ];
    final bool confirmed = await showDeletePackDialog(
      context,
      packName: pack.name,
      dependents: dependents,
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await widget.store.deletePack(pack.name);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showFloatingToast(
        context,
        '删除失败：$error',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _packs.removeAt(selected);
      if (_packs.isEmpty) {
        _selected = null;
      } else if (selected >= _packs.length) {
        _selected = _packs.length - 1;
      }
    });
    showFloatingToast(context, '已删除');
  }

  Future<void> _remapSelectedPack() async {
    final int? selected = _selected;
    if (selected == null || selected < 0 || selected >= _packs.length) {
      return;
    }
    final PackModel pack = _packs[selected];
    final String? sourcePath = pack.sourcePath;
    if (sourcePath == null) {
      showFloatingToast(
        context,
        '该包缺少源目录信息，无法重新映射',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    final Future<List<FileModel>> scanFuture = widget.scanFiles(sourcePath);
    await showDialog<void>(
      context: context,
      builder: (_) => RemapPackDialog(
        pack: pack,
        scanFuture: scanFuture,
        onApply: _applyRemap,
      ),
    );
  }

  Future<void> _applyRemap(PackModel pack) async {
    final PackModel? previous = _findPack(pack.name);
    if (previous != null) {
      final Set<String> oldPaths = <String>{
        for (final FileModel file in previous.files) file.path.toLowerCase(),
      };
      final Set<String> newPaths = <String>{
        for (final FileModel file in pack.files) file.path.toLowerCase(),
      };
      final int added = newPaths.difference(oldPaths).length;
      final int removed = oldPaths.difference(newPaths).length;
      final int oldSize = previous.files.fold<int>(
        0,
        (int sum, FileModel file) => sum + file.size,
      );
      final int newSize = pack.files.fold<int>(
        0,
        (int sum, FileModel file) => sum + file.size,
      );
      if (added != 0 || removed != 0 || oldSize != newSize) {
        pack.history = appendHistoryEntry(
          pack.history,
          HistoryModel(
            time: widget.now(),
            type: HistoryType.filesChanged,
            message:
                '重新映射：新增 $added 个文件、移除 $removed 个；'
                '总大小 ${formatBytes(oldSize)} → ${formatBytes(newSize)}',
          ),
        );
      }
    }
    await widget.store.savePack(pack);
    if (!mounted) {
      return;
    }
    _upsertPack(pack);
  }

  void _selectPackagingBuilder(PackageBuilder builder) {
    setState(() => _packagingBuilder = builder);
  }

  Future<void> _buildPack(PackModel pack) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BuildPackDialog(
        pack: pack,
        build: widget.buildPack,
        scanFiles: widget.scanFiles,
        onApply: _applyRemap,
      ),
    );
  }

  Future<void> _packSelectedPack() async {
    final int? selected = _selected;
    if (selected == null || selected < 0 || selected >= _packs.length) {
      return;
    }
    final PackModel pack = _packs[selected];
    final String? outputDirectory = widget.settings.outputDirectory;
    if (outputDirectory == null || outputDirectory.isEmpty) {
      showFloatingToast(
        context,
        '请先在设置页配置打包输出目录',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (pack.sourcePath == null) {
      showFloatingToast(
        context,
        '该包缺少源目录信息，无法打包',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    final List<PackDependent> missing = _missingDependencies(pack);
    if (missing.isNotEmpty) {
      final bool proceed = await showMissingDependenciesDialog(
        context,
        missing: missing,
      );
      if (!proceed || !mounted) {
        return;
      }
    }
    final PackagePlan? plan = await _buildPackagingPlan(pack);
    if (!mounted) {
      return;
    }
    final List<PackagingIssue> executableWarnings = plan == null
        ? const <PackagingIssue>[]
        : collectExecutableWarnings(plan);
    final List<PackagingIssue> issues = <PackagingIssue>[
      if (plan != null && _packagingBuilder.id == _nugetBuilderId)
        ...collectPackagingIssues(pack, plan),
      ...executableWarnings,
    ];
    if (issues.isNotEmpty) {
      final bool proceed = await showPackagingIssuesDialog(
        context,
        issues: issues,
        showSupplyChainNotice: executableWarnings.isNotEmpty,
      );
      if (!proceed || !mounted) {
        return;
      }
    }
    final Future<PackageExportResult> Function(
      PackModel pack,
      String outputDirectory,
    )
    exportPackage = _packagingBuilder.id == _cmakeBuilderId
        ? widget.exportCmakePackage
        : widget.exportPackage;
    await showDialog<void>(
      context: context,
      builder: (_) => PackExportDialog(
        pack: pack,
        outputDirectory: outputDirectory,
        exportPackage: exportPackage,
        onExported: (PackageExportResult result) => _recordExport(pack, result),
      ),
    );
  }

  Future<PackagePlan?> _buildPackagingPlan(PackModel pack) async {
    try {
      return await _packagingBuilder.buildPlan(pack);
    } catch (_) {
      // 校验期构建计划失败不阻断导出：导出对话框会以实际错误提示用户
      return null;
    }
  }

  List<PackDependent> _missingDependencies(PackModel pack) {
    final List<PackDependent> missing = <PackDependent>[];
    final Set<String> seen = <String>{};
    for (final DependencyModel dependency in pack.dependencies) {
      if (!seen.add(dependency.name.toLowerCase())) {
        continue;
      }
      if (_findPack(dependency.name) == null) {
        missing.add((name: dependency.name, version: dependency.version));
      }
    }
    return missing;
  }

  Future<void> _recordExport(PackModel pack, PackageExportResult result) async {
    pack.history = appendHistoryEntry(
      pack.history,
      HistoryModel(
        time: widget.now(),
        type: HistoryType.exported,
        message: '打包导出：${result.outputPath}',
      ),
    );
    try {
      await widget.store.savePack(pack);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showFloatingToast(
        context,
        '保存历史记录失败：${formatError(error)}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    _upsertPack(pack);
  }

  Future<void> _historySelectedPack() async {
    final int? selected = _selected;
    if (selected == null || selected < 0 || selected >= _packs.length) {
      return;
    }
    await showPackHistoryDialog(
      context,
      pack: _packs[selected],
      onSave: _savePack,
    );
  }

  Future<void> _openDependencyGraph() async {
    await showDependencyGraphDialog(
      context,
      packs: _packs,
      selectedPackName: _hasSelectedPack ? _packs[_selected!].name : null,
    );
  }

  void _sortPacks() {
    _packs.sort((PackModel first, PackModel second) {
      final int insensitive = first.name.toLowerCase().compareTo(
        second.name.toLowerCase(),
      );
      if (insensitive != 0) {
        return insensitive;
      }
      return first.name.compareTo(second.name);
    });
  }

  Widget _buildPaneBody(PaneItem? item, Widget? body) {
    return body ?? _buildEmptyGuide();
  }

  Widget _buildEmptyGuide() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Svgs.cardboardBox,
          const SizedBox(height: 12),
          const Text('尚未添加包'),
          const SizedBox(height: 6),
          const Text('点击工具栏「添加文件夹」开始'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      titleBar: TitleBar(
        isBackButtonVisible: false,
        title: const Center(widthFactor: 1.0, child: Text('C++ NuGet 打包工具')),
      ),
      paneBodyBuilder: _buildPaneBody,
      pane: NavigationPane(
        selected: _selected,
        onChanged: (int newIndex) => setState(() => _selected = newIndex),
        header: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Tooltip(
              message: '添加文件夹',
              child: IconButton(icon: Svgs.addFolder, onPressed: _addFolder),
            ),
            Tooltip(
              message: '删除文件夹',
              child: IconButton(
                icon: Svgs.deleteFolder,
                onPressed: _hasSelectedPack ? _deleteSelectedPack : null,
              ),
            ),
            Tooltip(
              message: '重新映射',
              child: IconButton(
                icon: Svgs.mapAsDrive,
                onPressed: _hasSelectedPack ? _remapSelectedPack : null,
              ),
            ),
            Tooltip(
              message: '打包文件夹',
              child: IconButton(
                icon: Svgs.moveToFolder,
                onPressed: _hasSelectedPack ? _packSelectedPack : null,
              ),
            ),
            Tooltip(
              message: '历史记录',
              child: IconButton(
                icon: Svgs.historyFolder,
                onPressed: _hasSelectedPack ? _historySelectedPack : null,
              ),
            ),
            Tooltip(
              message: '依赖关系图',
              child: IconButton(
                icon: Svgs.internetConnection,
                onPressed: _hasSelectedPack ? _openDependencyGraph : null,
              ),
            ),
          ],
        ),
        displayMode: PaneDisplayMode.expanded,
        size: NavigationPaneSize(
          openMaxWidth: 260,
          openMinWidth: 260,
          compactWidth: 50,
        ),
        items: PackList.buildCards(
          _packs,
          onSave: _savePack,
          pickDirectory: widget.pickDirectory,
          onBuildPack: _buildPack,
          packagingBuilder: _packagingBuilder,
          onPackagingBuilderChanged: _selectPackagingBuilder,
        ),
        footerItems: [
          PaneItemSeparator(),
          LibraryItem(
            icon: Svgs.settings,
            title: '设置',
            body: Setting(
              settings: widget.settings,
              onSave: widget.onSaveSettings,
              pickDirectory: widget.pickDirectory,
            ),
          ),
          LibraryItem(
            icon: Svgs.info,
            title: '关于',
            version: appVersion,
            body: const About(),
          ),
        ],
      ),
    );
  }
}
