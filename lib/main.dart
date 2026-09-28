import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_cache.dart';
import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart' as toolchain;
import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/packaging/script_packaging.dart';
import 'package:cpp_nuget_pack/scanner/file_scan.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/util/system_entries.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'app_info.dart';
import 'controls/add_directory_dialog.dart';
import 'controls/build_pack_dialog.dart';
import 'controls/delete_pack_dialog.dart';
import 'controls/dependency_graph_dialog.dart';
import 'controls/header_include_issues_dialog.dart';
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
      title: 'C++ Pack',
      themeMode: switch (_settings.themeMode) {
        ThemeModeSetting.system => ThemeMode.system,
        ThemeModeSetting.dark => ThemeMode.dark,
        ThemeModeSetting.light => ThemeMode.light,
      },
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: MainLayout(store: widget.store, settings: _settings, onSaveSettings: _saveSettings),
    );
  }
}

Future<void> _noopSaveSettings(SettingsModel settings) async {}

/// 构建环境准备函数：由 MainLayout 注入设置中的编译器优先级与检测缓存，
/// 缓存缺失/失效并完成重检时经 [onCompilersDetected] 回调新检测结果
/// （MainLayout 把它写回配置）；测试注入以绕过真实检测。
typedef PackBuildEnvironmentPreparer = Future<BuildEnvironment> Function(
  PackModel pack, {
  required List<String> compilerPriority,
  required List<toolchain.DetectedCompiler> cachedCompilers,
  required CompilerDetectionCallback onCompilersDetected,
});

/// 默认构建环境准备：读取包内 build.py 头部并解析选项。
Future<BuildEnvironment> _preparePackBuildEnvironment(
  PackModel pack, {
  required List<String> compilerPriority,
  required List<toolchain.DetectedCompiler> cachedCompilers,
  required CompilerDetectionCallback onCompilersDetected,
}) {
  return preparePackBuildEnvironment(
    pack,
    priority: compilerPriority,
    cachedCompilers: cachedCompilers,
    onCompilersDetected: onCompilersDetected,
  );
}

/// 包构建缓存探测（删除对话框用）；测试注入。
typedef PackBuildCacheProbe = Future<bool> Function(String packName);

/// 包构建缓存删除；测试注入。
typedef PackBuildCacheDeleter = Future<void> Function(String packName);

/// 包内预置源码缺席探测（构建对话框 `sourceNone` 判据）；测试注入。
///
/// 返回 `true` 表示**包内无预置源码**（`SRC_PATH` 为脚本自行下载的工作区），
/// 与消费方 `sourceNone` 同极性。
typedef PackSourceAbsentProbe = Future<bool> Function(String sourcePath);

/// 生产默认的预置源码缺席探测：全仓唯一把 [hasPresetSource] 取反成 `sourceNone`
/// 极性的地方，提取为具名函数是因为 const 默认值不接受 `async` 闭包。
Future<bool> absentByPresetSourceProbe(String sourcePath) async =>
    !await hasPresetSource(sourcePath);

class MainLayout extends StatefulWidget {
  const MainLayout({
    super.key,
    this.pickDirectory = getDirectoryPath,
    this.scanFiles = FileScan.scan,
    this.store = const PackStore(),
    this.settings = const SettingsModel(),
    this.onSaveSettings = _noopSaveSettings,
    this.exportPackage = exportNuGetPackage,
    this.buildPack = runPackBuildStreaming,
    this.prepareBuildEnv,
    this.detectCompilers = detectCompilersReadOnly,
    this.loadBuildHeader = loadBuildScriptHeader,
    this.probeSourceAbsent = absentByPresetSourceProbe,
    this.fixIncludes = fixHeaderIncludes,
    this.now = DateTime.now,
    this.hasBuildCache = hasPackBuildCache,
    this.deleteBuildCache = deletePackBuildCache,
  });

  final Future<String?> Function() pickDirectory;
  final Future<List<FileModel>> Function(String directoryPath) scanFiles;
  final PackStore store;
  final SettingsModel settings;
  final Future<void> Function(SettingsModel settings) onSaveSettings;
  final Future<PackageExportResult> Function(PackModel pack, String outputDirectory) exportPackage;
  final PackBuildRunner buildPack;
  final PackBuildEnvironmentPreparer? prepareBuildEnv;

  final Future<List<toolchain.DetectedCompiler>> Function() detectCompilers;

  /// 读取包内 build.py 头部；重映射/构建后据此注册系统条目，仅测试注入替代实现。
  final Future<BuildScriptHeader?> Function(PackModel pack) loadBuildHeader;

  /// 探测包内**无**预置源码（缺省 [absentByPresetSourceProbe]）；构建对话框的
  /// `sourceNone` 标记据此展示下载/准备源码时间线，仅测试注入替代实现。
  ///
  /// 极性见 [PackSourceAbsentProbe]：`true` = 无预置源码。取反只写在默认值指向的
  /// 那一个函数里，调用点原样透传，从命名上即排除再次接反。
  final PackSourceAbsentProbe probeSourceAbsent;

  /// 构建成功后、重新映射前的 include 引用检查与自动修复；测试注入替代实现。
  final PackHeaderIncludeFixer fixIncludes;

  final DateTime Function() now;

  /// 删除包时探测其构建缓存是否存在；测试注入。
  final PackBuildCacheProbe hasBuildCache;

  /// 删除包时按需删除其构建缓存；测试注入。
  final PackBuildCacheDeleter deleteBuildCache;

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  static const NuGetPackageBuilder _packagingBuilder = NuGetPackageBuilder();

  List<PackModel> _packs = [];
  int? _selected;

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
      errors.add(PackLoadError(fileName: widget.store.rootPath, message: error.toString()));
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLoadErrorsToast(errors));
    }
  }

  void _showLoadErrorsToast(List<PackLoadError> errors) {
    if (!mounted) {
      return;
    }
    final String details = errors.map((PackLoadError error) => error.toString()).join('\n');
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
      builder: (_) => AddDirectoryDialog(directoryPath: path, scanFuture: scanFuture),
    );
    if (pack == null || !mounted) {
      return;
    }
    final int totalSize = pack.files.fold<int>(0, (int sum, FileModel file) => sum + file.size);
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
          actions: [Button(onPressed: () => Navigator.pop(dialogContext), child: const Text('确定'))],
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
      final int existing = _packs.indexWhere((PackModel item) => item.name.toLowerCase() == pack.name.toLowerCase());
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
    final bool hasCache = await _probeBuildCache(pack.name);
    if (!mounted) {
      return;
    }
    final DeletePackResult result = await showDeletePackDialog(
      context,
      packName: pack.name,
      dependents: dependents,
      hasBuildCache: hasCache,
    );
    if (!result.confirmed || !mounted) {
      return;
    }
    try {
      await widget.store.deletePack(pack.name);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showFloatingToast(context, '删除失败：$error', type: FloatingToastType.error, duration: const Duration(seconds: 5));
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
    if (result.deleteCache) {
      try {
        await widget.deleteBuildCache(pack.name);
      } catch (error) {
        if (!mounted) {
          return;
        }
        showFloatingToast(
          context,
          '已删除包，但构建缓存删除失败：${formatError(error)}',
          type: FloatingToastType.error,
          duration: const Duration(seconds: 5),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      showFloatingToast(context, '已删除（含构建缓存）');
      return;
    }
    showFloatingToast(context, '已删除');
  }

  /// 构建缓存探测：异常按无缓存处理（不阻断删除）。
  Future<bool> _probeBuildCache(String packName) async {
    try {
      return await widget.hasBuildCache(packName);
    } catch (_) {
      return false;
    }
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
      builder: (_) => RemapPackDialog(pack: pack, scanFuture: scanFuture, onApply: _applyRemap),
    );
  }

  Future<void> _applyRemap(PackModel pack) async {
    final PackModel? previous = _findPack(pack.name);
    if (previous != null) {
      final Set<String> oldPaths = <String>{for (final FileModel file in previous.files) file.path.toLowerCase()};
      final Set<String> newPaths = <String>{for (final FileModel file in pack.files) file.path.toLowerCase()};
      final int added = newPaths.difference(oldPaths).length;
      final int removed = oldPaths.difference(newPaths).length;
      final int oldSize = previous.files.fold<int>(0, (int sum, FileModel file) => sum + file.size);
      final int newSize = pack.files.fold<int>(0, (int sum, FileModel file) => sum + file.size);
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
    final PackModel updated = await _syncSystemEntries(pack);
    await widget.store.savePack(updated);
    if (!mounted) {
      return;
    }
    _upsertPack(updated);
  }

  /// 注册构建管线系统条目（根级 pre/post.bat 命令与 `# depends:` 依赖）。
  ///
  /// build.py 缺失或不可读时仍同步脚本命令，不阻断重映射。
  Future<PackModel> _syncSystemEntries(PackModel pack) async {
    BuildScriptHeader? header;
    try {
      header = await widget.loadBuildHeader(pack);
    } catch (_) {
      header = null;
    }
    return applySystemEntries(pack, header: header, resolvePackVersion: (String name) => _findPack(name)?.version).pack;
  }

  Future<void> _buildPack(PackModel pack) async {
    if (!mounted) {
      return;
    }
    final PackBuildEnvironmentPreparer prepare =
        widget.prepareBuildEnv ??
        (
          PackModel pack, {
          required List<String> compilerPriority,
          required List<toolchain.DetectedCompiler> cachedCompilers,
          required CompilerDetectionCallback onCompilersDetected,
        }) => _preparePackBuildEnvironment(
          pack,
          compilerPriority: compilerPriority,
          cachedCompilers: cachedCompilers,
          onCompilersDetected: onCompilersDetected,
        );
    final bool sourceNone = await _probeSourceNone(pack);
    if (!mounted) {
      return;
    }
    final BuildDialogResult? result = await showDialog<BuildDialogResult>(
      context: context,
      // 关闭必须经对话框内「关闭」按钮回传失败条目/修复报告：Esc 撤走会丢构建历史
      dismissWithEsc: false,
      builder: (_) => BuildPackDialog(
        pack: pack,
        sourceNone: sourceNone,
        build:
            (
              PackModel pack,
              void Function(PackBuildStage) onStage, {
              Map<String, String>? environment,
              void Function(String line)? onOutput,
            }) => widget.buildPack(
              pack,
              onStage,
              environment: environment,
              onOutput: onOutput,
            ),
        prepare: (PackModel pack) => prepare(
          pack,
          compilerPriority: widget.settings.compilerPriority,
          cachedCompilers: widget.settings.detectedCompilers,
          onCompilersDetected: _persistDetectedCompilers,
        ),
        scanFiles: widget.scanFiles,
        onApply: _applyRemap,
        fixIncludes: widget.fixIncludes,
        now: widget.now,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final HistoryModel? failureEntry = result.failureEntry;
    if (failureEntry != null) {
      await _recordBuildFailure(pack, failureEntry);
      if (!mounted) {
        return;
      }
    }
    final HeaderIncludeFixReport? report = result.fixReport;
    if (report == null) {
      return;
    }
    if (report.fixedCount > 0) {
      showFloatingToast(context, '已自动修复 ${report.fixedCount} 处头文件引用');
    }
    if (report.hasIssues) {
      await showHeaderIncludeIssuesDialog(context, report: report);
    }
  }

  /// 记录构建失败条目（失败会话关闭时落盘一次）；保存失败仅提示、不阻断。
  Future<void> _recordBuildFailure(PackModel pack, HistoryModel entry) async {
    final PackModel? current = _findPack(pack.name);
    if (current == null) {
      return;
    }
    current.history = appendHistoryEntry(current.history, entry);
    try {
      await widget.store.savePack(current);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showFloatingToast(
        context,
        '构建记录保存失败：${formatError(error)}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    _upsertPack(current);
  }

  /// 取构建对话框的 `sourceNone` 标记：**包内无预置源码时为 true**（此时
  /// `SRC_PATH` 是脚本自行下载的工作区，时间线走下载/分类）。
  ///
  /// 极性由 [MainLayout.probeSourceAbsent] 自身定义，本方法只做缺省与异常兜底，
  /// 取值原样透传，不再取反。探测失败按「有预置源码」（false）兜底。
  Future<bool> _probeSourceNone(PackModel pack) async {
    final String? sourcePath = pack.sourcePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      return false;
    }
    try {
      return await widget.probeSourceAbsent(sourcePath);
    } catch (_) {
      return false;
    }
  }

  /// 把构建准备阶段的新检测结果写回配置（经 [MainLayout.onSaveSettings]）。
  void _persistDetectedCompilers(List<toolchain.DetectedCompiler> compilers) {
    final SettingsModel next = widget.settings.copyWith(detectedCompilers: compilers);
    unawaited(_saveDetectedCompilers(next));
  }

  Future<void> _saveDetectedCompilers(SettingsModel settings) async {
    try {
      await widget.onSaveSettings(settings);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showFloatingToast(
        context,
        '保存编译器检测结果失败：${formatError(error)}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
    }
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
        '请先在设置页配置 NuGet 打包输出目录',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (pack.sourcePath == null) {
      showFloatingToast(context, '该包缺少源目录信息，无法打包', type: FloatingToastType.error, duration: const Duration(seconds: 5));
      return;
    }
    final List<PackDependent> missing = _missingDependencies(pack);
    if (missing.isNotEmpty) {
      final bool proceed = await showMissingDependenciesDialog(context, missing: missing);
      if (!proceed || !mounted) {
        return;
      }
    }
    final PackModel fixed = await _fixIncludesBeforeExport(pack);
    if (!mounted) {
      return;
    }
    final PackagePlan? plan = await _buildPackagingPlan(fixed);
    if (!mounted) {
      return;
    }
    final List<PackagingIssue> executableWarnings = plan == null
        ? const <PackagingIssue>[]
        : collectExecutableWarnings(plan);
    final List<PackagingIssue> issues = <PackagingIssue>[
      if (plan != null) ...collectPackagingIssues(fixed, plan),
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
    await showDialog<void>(
      context: context,
      builder: (_) => PackExportDialog(
        pack: fixed,
        outputDirectory: outputDirectory,
        exportPackage: widget.exportPackage,
        onExported: (PackageExportResult result) => _recordExport(fixed, result),
      ),
    );
  }

  /// 导出前的 include 引用检查与自动修复，返回大小快照已刷新的包。
  ///
  /// 与构建后那次同用 [MainLayout.fixIncludes]，但位置不同：构建后的修复覆盖不到
  /// 没有 build.py 因而不触发构建的目录，导出前这一次兜住它。检查失败不阻断导出，
  /// 原包返回。
  Future<PackModel> _fixIncludesBeforeExport(PackModel pack) async {
    final String sourcePath = pack.sourcePath!;
    final HeaderIncludeFixReport report;
    try {
      report = await widget.fixIncludes(sourcePath, packageName: pack.name);
    } catch (error) {
      if (!mounted) {
        return pack;
      }
      showFloatingToast(
        context,
        '头文件引用检查失败：${formatError(error)}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return pack;
    }
    if (!mounted) {
      return pack;
    }
    final PackModel refreshed = report.fixedCount == 0
        ? pack
        : await _refreshFixedFileSizes(pack, sourcePath, report);
    if (!mounted) {
      return refreshed;
    }
    if (report.fixedCount > 0) {
      showFloatingToast(
        context,
        '打包前自动修复 ${report.fixedCount} 处失效引用',
      );
    }
    if (report.hasIssues) {
      await showHeaderIncludeIssuesDialog(context, report: report);
    }
    return refreshed;
  }

  /// 修复改写了文件内容、字节数随之变化，而 `pack.files` 是构建后 [FileScan] 的
  /// 快照：重新 stat 被改写文件并只替换这些条目，其余条目（含顺序）原样保留。
  ///
  /// 必要的依据是 [FileModel.size] 会进入打包计划（`PackageFileSource.size`）、
  /// 文件管理页与导出预览对话框的总大小，不刷新即按旧字节数展示。
  Future<PackModel> _refreshFixedFileSizes(
    PackModel pack,
    String sourcePath,
    HeaderIncludeFixReport report,
  ) async {
    final Set<String> fixedPaths = <String>{
      for (final HeaderIncludeFix fix in report.fixed)
        fix.filePath.toLowerCase(),
    };
    final List<FileModel> files = <FileModel>[];
    for (final FileModel file in pack.files) {
      if (!fixedPaths.contains(file.path.toLowerCase())) {
        files.add(file);
        continue;
      }
      try {
        final int size = await File(joinPath(sourcePath, file.path)).length();
        files.add(
          FileModel(name: file.name, path: file.path, size: size)
            ..buildModel = file.buildModel,
        );
      } catch (_) {
        // stat 失败保留原字节数并放过：只为刷新展示，不阻断导出
        files.add(file);
      }
    }
    final PackModel refreshed = pack.copyWith(files: files);
    if (mounted) {
      _upsertPack(refreshed);
    }
    return refreshed;
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
      HistoryModel(time: widget.now(), type: HistoryType.exported, message: '打包导出：${result.outputPath}'),
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
    await showPackHistoryDialog(context, pack: _packs[selected], onSave: _savePack);
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
      final int insensitive = first.name.toLowerCase().compareTo(second.name.toLowerCase());
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
      paneBodyBuilder: _buildPaneBody,
      titleBar: SizedBox.shrink(),
      pane: NavigationPane(
        selected: _selected,
        onChanged: (int newIndex) => setState(() => _selected = newIndex),
        header: Column(
          mainAxisSize: .min,
          spacing: 0,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Tooltip(
                  message: '添加文件夹',
                  child: IconButton(icon: Svgs.addFolder, onPressed: _addFolder),
                ),
                Tooltip(
                  message: '删除文件夹',
                  child: IconButton(icon: Svgs.deleteFolder, onPressed: _hasSelectedPack ? _deleteSelectedPack : null),
                ),
                Tooltip(
                  message: '重新映射',
                  child: IconButton(icon: Svgs.mapAsDrive, onPressed: _hasSelectedPack ? _remapSelectedPack : null),
                ),
                Tooltip(
                  message: '打包文件夹',
                  child: IconButton(icon: Svgs.moveToFolder, onPressed: _hasSelectedPack ? _packSelectedPack : null),
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
            Divider(style: DividerThemeData(horizontalMargin: .fromLTRB(0, 3, 8, 0)),),
          ],
        ),
        displayMode: PaneDisplayMode.expanded,
        size: NavigationPaneSize(openMaxWidth: 260, openMinWidth: 260, compactWidth: 50),
        items: PackList.buildCards(
          _packs,
          onSave: _savePack,
          pickDirectory: widget.pickDirectory,
          onBuildPack: _buildPack,
          loadHeader: widget.loadBuildHeader,
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
              detectCompilers: widget.detectCompilers,
            ),
          ),
          LibraryItem(icon: Svgs.info, title: '关于', version: appVersion, body: const About()),
        ],
      ),
    );
  }
}
