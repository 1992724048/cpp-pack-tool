import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/repo_version.dart';
import 'package:cpp_nuget_pack/controls/build_options.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/catppuccin_icons.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/file_opener.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/repo_icon.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PackFiles extends StatefulWidget {
  const PackFiles({
    super.key,
    required this.pack,
    this.openFile = openWithDefaultApp,
    this.openUrl = openExternalUrl,
    this.onBuildPack,
    this.onSave,
    this.loadHeader = loadBuildScriptHeader,
    this.loadLatestVersion,
  });

  final PackModel pack;
  final Future<bool> Function(String path) openFile;

  /// 打开远程仓库网页；测试可注入。
  final Future<bool> Function(String url) openUrl;

  final Future<void> Function(PackModel pack)? onBuildPack;

  /// 保存选项变更；为 null 时不渲染选项控件（v1 行为）。
  final Future<bool> Function(PackModel pack)? onSave;

  /// 读取包内 build.py 头部；测试可注入。
  final Future<BuildScriptHeader?> Function(PackModel pack) loadHeader;

  /// 按仓库地址懒查询远端最新 tag；为 null 时不查询（最新版本显示 —）。
  final Future<String?> Function(String repoUrl)? loadLatestVersion;

  @override
  State<PackFiles> createState() => _PackFilesState();
}

class _PackFilesState extends State<PackFiles> {
  static const double _treeIconSize = 18;

  // TreeView 行内容原有效高度 18，按用户确认加高 8 后为 26（行容器另加 4）。
  static const double _treeRowContentMinHeight = 26;
  static const Set<FileType> _buildLabelTypes = <FileType>{
    FileType.lib,
    FileType.dll,
    FileType.pdb,
    FileType.executable,
    FileType.source
  };
  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  final Set<String> _expandedDirs = <String>{};

  BuildScriptHeader? _header;
  bool _savingOption = false;
  bool _optionsExpanded = true;
  int _headerLoadId = 0;
  String? _latestVersion;
  bool _latestLoaded = false;
  int _latestLoadId = 0;

  @override
  void initState() {
    super.initState();
    _refreshHeader();
  }

  @override
  void didUpdateWidget(covariant PackFiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pack.name != widget.pack.name) {
      _expandedDirs.clear();
    }
    if (_shouldReloadHeader(oldWidget.pack, widget.pack)) {
      _refreshHeader();
    }
  }

  static bool _shouldReloadHeader(PackModel before, PackModel after) {
    if (before.name != after.name || before.sourcePath != after.sourcePath) {
      return true;
    }
    return findBuildScript(before.files)?.path != findBuildScript(after.files)?.path;
  }

  Future<void> _refreshHeader() async {
    final int loadId = ++_headerLoadId;
    BuildScriptHeader? header;
    try {
      header = await widget.loadHeader(widget.pack);
    } catch (_) {
      // 头部读取失败按未声明处理：不渲染选项控件，也不影响构建入口
      header = null;
    }
    if (!mounted || loadId != _headerLoadId) {
      return;
    }
    setState(() => _header = header);
    _refreshLatestVersion();
  }

  Future<void> _refreshLatestVersion() async {
    final String? repo = _header?.repo;
    final Future<String?> Function(String repoUrl)? loader = widget.loadLatestVersion;
    final int loadId = ++_latestLoadId;
    if (repo == null) {
      setState(() {
        _latestVersion = null;
        _latestLoaded = false;
      });
      return;
    }
    if (loader == null) {
      setState(() {
        _latestVersion = null;
        _latestLoaded = true;
      });
      return;
    }
    setState(() {
      _latestVersion = null;
      _latestLoaded = false;
    });
    String? latest;
    try {
      latest = await loader(repo);
    } catch (_) {
      latest = null;
    }
    if (!mounted || loadId != _latestLoadId) {
      return;
    }
    setState(() {
      _latestVersion = latest;
      _latestLoaded = true;
    });
  }

  static List<String> _pathSegments(String path) =>
      path.split(_pathSeparator).where((String segment) => segment.isNotEmpty).toList();

  static int _compareNames(String first, String second) {
    final int insensitive = first.toLowerCase().compareTo(second.toLowerCase());
    if (insensitive != 0) {
      return insensitive;
    }
    return first.compareTo(second);
  }

  static _DirNode _buildTree(List<FileModel> files) {
    final _DirNode root = _DirNode(name: '', path: '');
    for (final FileModel file in files) {
      final List<String> segments = _pathSegments(file.path);
      if (segments.isEmpty) {
        root.files.add(file);
        continue;
      }
      _DirNode parent = root;
      for (final String segment in segments.take(segments.length - 1)) {
        final String childPath = parent.path.isEmpty ? segment : '${parent.path}/$segment';
        parent = parent.children.putIfAbsent(segment, () => _DirNode(name: segment, path: childPath));
        parent.size += file.size;
        parent.fileCount += 1;
      }
      parent.files.add(file);
    }
    return root;
  }

  List<TreeViewItem> _buildTreeItems(_DirNode node, Color sizeColor) {
    final List<TreeViewItem> items = <TreeViewItem>[];
    final List<_DirNode> dirs = node.children.values.toList()
      ..sort((_DirNode first, _DirNode second) => _compareNames(first.name, second.name));
    for (final _DirNode dir in dirs) {
      final bool expanded = _expandedDirs.contains(dir.path);
      items.add(
        TreeViewItem(
          value: dir.path,
          leading: _buildIcon(dir.name, isDirectory: true, isExpanded: expanded),
          expanded: expanded,
          content: _buildRow(
            dir.name,
            formatBytes(dir.size),
            sizeColor,
            label: Text('(${dir.fileCount} 个文件)', style: TextStyle(color: sizeColor)),
          ),
          children: _buildTreeItems(dir, sizeColor),
        ),
      );
    }
    final List<FileModel> files = node.files.toList()
      ..sort((FileModel first, FileModel second) => _compareNames(first.name, second.name));
    for (final FileModel file in files) {
      items.add(
        TreeViewItem(
          leading: _buildIcon(file.name),
          content: GestureDetector(
            onDoubleTap: () => _openFile(file),
            child: _buildRow(file.name, formatBytes(file.size), sizeColor, label: _buildBuildLabel(file)),
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildIcon(String name, {bool isDirectory = false, bool isExpanded = false}) {
    return SvgPicture.asset(
      iconAssetFor(brightness: FluentTheme
          .of(context)
          .brightness, name: name, isDirectory: isDirectory, isExpanded: isExpanded),
      width: _treeIconSize,
      height: _treeIconSize,
    );
  }

  static Widget _buildRow(String name, String size, Color sizeColor, {Widget? label}) {
    final Widget nameText = Text(name, overflow: TextOverflow.ellipsis);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _treeRowContentMinHeight),
      child: Row(
        children: <Widget>[
          if (label == null)
            Expanded(child: nameText)
          else
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(child: nameText),
                  const SizedBox(width: 5),
                  label,
                ],
              ),
            ),
          const SizedBox(width: 8),
          Text(size, style: TextStyle(color: sizeColor)),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  static Widget? _buildBuildLabel(FileModel file) {
    if (!_buildLabelTypes.contains(file.type)) {
      return null;
    }
    final String? label = inferBuildLabel(file.path);
    if (label == null) {
      return null;
    }
    return Tag(text: label, color: label == releaseBuildLabel ? MarkerColors.green : MarkerColors.orange, fontSize: 10);
  }

  Future<void> _openFile(FileModel file) async {
    final String? sourcePath = widget.pack.sourcePath;
    if (sourcePath == null) {
      showFloatingToast(context, '该包缺少源目录信息，无法打开文件', type: FloatingToastType.error,
          duration: const Duration(seconds: 5));
      return;
    }
    final bool opened = await widget.openFile(joinPath(sourcePath, file.path));
    if (!mounted) {
      return;
    }
    if (!opened) {
      showFloatingToast(
          context, '无法打开文件：${file.name}', type: FloatingToastType.error, duration: const Duration(seconds: 5));
    }
  }

  Future<void> _onItemInvoked(TreeViewItem item, TreeViewItemInvokeReason reason) async {
    if (reason != TreeViewItemInvokeReason.pressed) {
      return;
    }
    final Object? value = item.value;
    if (value is! String) {
      return;
    }
    setState(() {
      if (!_expandedDirs.remove(value)) {
        _expandedDirs.add(value);
      }
    });
  }

  Future<void> _onExpandToggle(TreeViewItem item, bool willExpand) async {
    final Object? value = item.value;
    if (value is! String) {
      return;
    }
    if (willExpand) {
      _expandedDirs.add(value);
    } else {
      _expandedDirs.remove(value);
    }
  }

  Widget _buildToolbar({required String? openRepoUrl, required bool canBuild, required bool showVersionChip}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
      child: Card(
        padding: EdgeInsetsGeometry.all(5),
        child: Row(
          children: [
            Wrap(
              spacing: 5,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (canBuild) FilledButton(key: const Key('buildPackButton'),
                    onPressed: () => widget.onBuildPack!(widget.pack),
                    child: const Text('构建')),
                if (openRepoUrl != null) _buildOpenRepoButton(openRepoUrl),
                if (canBuild) _buildRuntimeGroup(),
              ],
            ),
            Spacer(),
            if (showVersionChip) ...[_buildVersionChip()],
          ],
        ),
      ),
    );
  }

  Widget _buildOpenRepoButton(String url) {
    return Tooltip(
      message: url,
      child: Button(key: const Key('openRepoButton'), onPressed: () => _openRepo(url), child: Text('远程仓库')),
    );
  }

  Future<void> _openRepo(String url) async {
    final bool opened = await widget.openUrl(url);
    if (!mounted) {
      return;
    }
    if (!opened) {
      showFloatingToast(context, '无法打开链接', type: FloatingToastType.error, duration: const Duration(seconds: 5));
    }
  }

  Widget _buildRuntimeGroup() {
    final String? runtimeValue = _savedRuntimeLibrary();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RuntimeLibrarySelector(
          value: runtimeValue,
          enabled: widget.onSave != null && !_savingOption,
          onChanged: (String? value) {
            if (value != runtimeValue) {
              _changeBuildOption(runtimeOptionName, value);
            }
          },
        ),
      ],
    );
  }

  /// 运行库保存值（`MD` / `MT` 大写归一）；缺失或非法显示「默认（跟随配方）」。
  String? _savedRuntimeLibrary() {
    final String? normalized = normalizeRuntimeLibrary(widget.pack.buildOptions[runtimeOptionName]);
    return normalized?.toUpperCase();
  }

  /// 版本胶囊：纯展示（不可点击、不参与 Tab 序），四态见设计规格 §5.3。
  Widget _buildVersionChip() {
    final String current = widget.pack.sourceVersion ?? '不可用';
    final bool querying = !_latestLoaded;
    final String? latestVersion = _latestVersion;
    final String latestText = querying ? '查询中…' : (latestVersion ?? '不可用');
    final bool hasUpdate = !querying && latestVersion != null && compareTagVersions(latestVersion, current) > 0;
    final String latestTooltip;
    if (querying) {
      latestTooltip = '最新版本：查询中…';
    } else if (hasUpdate) {
      latestTooltip = '最新版本：$latestText（有新版本可用）';
    } else if (latestVersion != null) {
      latestTooltip = '最新版本：$latestText（已是最新）';
    } else {
      latestTooltip = '最新版本：不可用';
    }
    final FluentThemeData theme = FluentTheme.of(context);
    final Color valueColor = theme.resources.textFillColorPrimary;
    final Color placeholderColor = theme.resources.textFillColorTertiary;
    final TextStyle labelStyle = TextStyle(fontSize: 12, color: theme.resources.textFillColorSecondary);
    return Container(
      key: const Key('packRepoVersionLabel'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: theme.resources.solidBackgroundFillColorSecondary, borderRadius: BorderRadius.circular(999)),
      child: Tooltip(
        message: '当前版本：$current\n$latestTooltip',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (hasUpdate) ...<Widget>[
              const Icon(FluentIcons.update_restore, size: 12, color: MarkerColors.green),
              const SizedBox(width: 6)
            ],
            Text('当前', style: labelStyle),
            const SizedBox(width: 4),
            Text(current, style: TextStyle(
                fontSize: 12, color: widget.pack.sourceVersion == null ? placeholderColor : valueColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(FluentIcons.chevron_right, size: 12, color: placeholderColor),
            ),
            Text('最新', style: labelStyle),
            const SizedBox(width: 4),
            Text(latestText, style: TextStyle(
                fontSize: 12, color: querying || latestVersion == null ? placeholderColor : valueColor)),
          ],
        ),
      ),
    );
  }

  /// 保存选项变更：全字段拷贝 → onSave → 悬浮提示；保存挂起期间全控件禁用。
  ///
  /// [value] 为 null 表示移除保存键（如运行库选择「默认（跟随配方）」）。
  Future<void> _changeBuildOption(String name, String? value) async {
    final Future<bool> Function(PackModel pack)? onSave = widget.onSave;
    if (onSave == null || _savingOption) {
      return;
    }
    setState(() => _savingOption = true);
    bool saved = false;
    try {
      saved = await onSave(_withBuildOption(widget.pack, name, value));
    } catch (_) {
      saved = false;
    }
    if (!mounted) {
      return;
    }
    setState(() => _savingOption = false);
    if (saved) {
      showFloatingToast(context, '已保存');
    } else {
      showFloatingToast(context, '保存失败', type: FloatingToastType.error, duration: const Duration(seconds: 5));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canBuild = widget.onBuildPack != null && findBuildScript(widget.pack.files) != null;
    final String? openRepoUrl = openableRepoWebUrl(_header?.repo ?? '');
    final bool showVersionChip = _header?.repo != null;
    final List<BuildScriptOption> options = canBuild && widget.onSave != null ? (_header?.options ??
        const <BuildScriptOption>[]) : const <BuildScriptOption>[];
    final Color sizeColor = FluentTheme
        .of(context)
        .resources
        .textFillColorSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(),
        if (openRepoUrl != null || canBuild || showVersionChip) _buildToolbar(
            openRepoUrl: openRepoUrl, canBuild: canBuild, showVersionChip: showVersionChip),
        if (options.isNotEmpty)
          BuildOptionsPanel(
            options: options,
            values: widget.pack.buildOptions,
            expanded: _optionsExpanded,
            onToggleExpanded: () => setState(() => _optionsExpanded = !_optionsExpanded),
            saving: _savingOption,
            onChange: _changeBuildOption,
          ),
        Expanded(
          child: widget.pack.files.isEmpty
              ? const Center(child: Text('该包暂无文件'))
              : TreeView(items: _buildTreeItems(_buildTree(widget.pack.files), sizeColor),
              onItemInvoked: _onItemInvoked,
              onItemExpandToggle: _onExpandToggle,
              shrinkWrap: false,
              scrollPrimary: false),
        ),
      ],
    );
  }
}

class _DirNode {
  _DirNode({required this.name, required this.path});

  final String name;
  final String path;
  final Map<String, _DirNode> children = <String, _DirNode>{};
  final List<FileModel> files = <FileModel>[];
  int size = 0;
  int fileCount = 0;
}

/// 全字段拷贝并写入选项值；[value] 为 null 时移除该保存键。
PackModel _withBuildOption(PackModel pack, String name, String? value) {
  final Map<String, String> options = <String, String>{...pack.buildOptions};
  if (value == null) {
    options.remove(name);
  } else {
    options[name] = value;
  }
  return PackModel(
      name: pack.name,
      version: pack.version,
      author: pack.author,
      description: pack.description,
      license: pack.license,
      iconPath: pack.iconPath,
      sourcePath: pack.sourcePath,
      sourceVersion: pack.sourceVersion,
    )
    ..files = pack.files
    ..commands = pack.commands
    ..dependencies = pack.dependencies
    ..macros = pack.macros
    ..libDirectories = pack.libDirectories
    ..libraries = pack.libraries
    ..history = pack.history
    ..scripts = pack.scripts
    ..buildOptions = options
    ..enabledFormats = pack.enabledFormats;
}
