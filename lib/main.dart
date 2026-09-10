import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/scanner/file_scan.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'controls/add_directory_dialog.dart';
import 'controls/pack_list.dart';

void main() {
  runApp(const PackTool());
}

class PackTool extends StatelessWidget {
  const PackTool({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'C++ Pack Tool',
      themeMode: ThemeMode.system,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({
    super.key,
    this.pickDirectory = getDirectoryPath,
    this.scanFiles = FileScan.scan,
    this.store = const PackStore(),
  });

  final Future<String?> Function() pickDirectory;
  final Future<List<FileModel>> Function(String directoryPath) scanFiles;
  final PackStore store;

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  List<PackModel> _packs = [];
  List<PackLoadError> _loadErrors = [];
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
      _loadErrors = errors;
      _sortPacks();
      _selected = _packs.isEmpty ? null : 0;
    });
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
    return true;
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
    final Widget content = body ?? _buildEmptyGuide();
    if (_loadErrors.isEmpty) {
      return content;
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: InfoBar(
            title: Text('${_loadErrors.length} 个配置加载失败'),
            content: Text(
              _loadErrors
                  .map((PackLoadError error) => error.toString())
                  .join('\n'),
            ),
            severity: InfoBarSeverity.warning,
          ),
        ),
        Expanded(child: content),
      ],
    );
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
              child: IconButton(icon: Svgs.deleteFolder, onPressed: () {}),
            ),
            Tooltip(
              message: '重新映射',
              child: IconButton(icon: Svgs.mapAsDrive, onPressed: () {}),
            ),
            Tooltip(
              message: '打包文件夹',
              child: IconButton(icon: Svgs.moveToFolder, onPressed: () {}),
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
        items: PackList.buildCards(_packs, onSave: _savePack),
        footerItems: [
          PaneItemSeparator(),
          LibraryItem(
            icon: Svgs.settings,
            title: '设置',
            body: const Center(child: Text('设置内容')),
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
