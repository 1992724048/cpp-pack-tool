import 'package:catppuccin_flutter/catppuccin_flutter.dart';
import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/scanner/file_scan.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'controls/add_directory_dialog.dart';
import 'controls/delete_pack_dialog.dart';
import 'controls/pack_export_dialog.dart';
import 'controls/pack_list.dart';
import 'controls/remap_pack_dialog.dart';
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

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
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
    await _savePack(pack);
  }

  Future<bool> _savePack(PackModel pack) async {
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

  Future<void> _deleteSelectedPack() async {
    final int? selected = _selected;
    if (selected == null || selected < 0 || selected >= _packs.length) {
      return;
    }
    final PackModel pack = _packs[selected];
    final List<String> dependents = <String>[
      for (final PackModel item in _packs)
        if (item.name.toLowerCase() != pack.name.toLowerCase() &&
            item.dependencies.any(
              (DependencyModel dependency) =>
                  dependency.name.toLowerCase() == pack.name.toLowerCase(),
            ))
          item.name,
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
    await widget.store.savePack(pack);
    if (!mounted) {
      return;
    }
    _upsertPack(pack);
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
    await showDialog<void>(
      context: context,
      builder: (_) => PackExportDialog(
        pack: pack,
        outputDirectory: outputDirectory,
        exportPackage: widget.exportPackage,
      ),
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
              child: IconButton(icon: Svgs.historyFolder, onPressed: () {}),
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
            version: '26.0.0',
            body: const Center(child: Text('关于内容')),
          ),
        ],
      ),
    );
  }
}
