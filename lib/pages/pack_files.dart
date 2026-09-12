import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/catppuccin_icons.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/file_opener.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PackFiles extends StatefulWidget {
  const PackFiles({
    super.key,
    required this.pack,
    this.openFile = openWithDefaultApp,
    this.onBuildPack,
    this.onSave,
    this.loadHeader = loadBuildScriptHeader,
    this.loadLatestVersion,
  });

  final PackModel pack;
  final Future<bool> Function(String path) openFile;
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
  static const double _optionFieldWidth = 120;
  static const Set<FileType> _buildLabelTypes = <FileType>{
    FileType.lib,
    FileType.dll,
    FileType.pdb,
    FileType.executable,
  };
  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  final Set<String> _expandedDirs = <String>{};

  BuildScriptHeader? _header;
  bool _savingOption = false;
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
    return findBuildScript(before.files)?.path !=
        findBuildScript(after.files)?.path;
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
    final Future<String?> Function(String repoUrl)? loader =
        widget.loadLatestVersion;
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

  static List<String> _pathSegments(String path) => path
      .split(_pathSeparator)
      .where((String segment) => segment.isNotEmpty)
      .toList();

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
        final String childPath = parent.path.isEmpty
            ? segment
            : '${parent.path}/$segment';
        parent = parent.children.putIfAbsent(
          segment,
          () => _DirNode(name: segment, path: childPath),
        );
        parent.size += file.size;
      }
      parent.files.add(file);
    }
    return root;
  }

  List<TreeViewItem> _buildTreeItems(_DirNode node, Color sizeColor) {
    final List<TreeViewItem> items = <TreeViewItem>[];
    final List<_DirNode> dirs = node.children.values.toList()
      ..sort(
        (_DirNode first, _DirNode second) =>
            _compareNames(first.name, second.name),
      );
    for (final _DirNode dir in dirs) {
      final bool expanded = _expandedDirs.contains(dir.path);
      items.add(
        TreeViewItem(
          value: dir.path,
          leading: _buildIcon(
            dir.name,
            isDirectory: true,
            isExpanded: expanded,
          ),
          expanded: expanded,
          content: _buildRow(dir.name, formatBytes(dir.size), sizeColor),
          children: _buildTreeItems(dir, sizeColor),
        ),
      );
    }
    final List<FileModel> files = node.files.toList()
      ..sort(
        (FileModel first, FileModel second) =>
            _compareNames(first.name, second.name),
      );
    for (final FileModel file in files) {
      items.add(
        TreeViewItem(
          leading: _buildIcon(file.name),
          content: GestureDetector(
            onDoubleTap: () => _openFile(file),
            child: _buildRow(
              file.name,
              formatBytes(file.size),
              sizeColor,
              label: _buildBuildLabel(file),
            ),
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildIcon(
    String name, {
    bool isDirectory = false,
    bool isExpanded = false,
  }) {
    return SvgPicture.asset(
      iconAssetFor(
        brightness: FluentTheme.of(context).brightness,
        name: name,
        isDirectory: isDirectory,
        isExpanded: isExpanded,
      ),
      width: _treeIconSize,
      height: _treeIconSize,
    );
  }

  static Widget _buildRow(
    String name,
    String size,
    Color sizeColor, {
    Widget? label,
  }) {
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
    return Tag(
      text: label,
      color: label == releaseBuildLabel
          ? UCColors.flavor.green
          : UCColors.flavor.peach,
      fontSize: 10,
    );
  }

  Future<void> _openFile(FileModel file) async {
    final String? sourcePath = widget.pack.sourcePath;
    if (sourcePath == null) {
      showFloatingToast(
        context,
        '该包缺少源目录信息，无法打开文件',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    final bool opened = await widget.openFile(joinPath(sourcePath, file.path));
    if (!mounted) {
      return;
    }
    if (!opened) {
      showFloatingToast(
        context,
        '无法打开文件：${file.name}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _onItemInvoked(
    TreeViewItem item,
    TreeViewItemInvokeReason reason,
  ) async {
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

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: <Widget>[
          FilledButton(
            key: const Key('buildPackButton'),
            onPressed: () => widget.onBuildPack!(widget.pack),
            child: const Text('构建'),
          ),
          if (widget.onSave != null)
            for (final BuildScriptOption option
                in _header?.options ?? const <BuildScriptOption>[])
              _buildOptionField(option),
        ],
      ),
    );
  }

  Widget _buildRepoVersionRow() {
    final String current = widget.pack.sourceVersion ?? '—';
    final String latest = _latestLoaded ? (_latestVersion ?? '—') : '查询中…';
    return Padding(
      key: const Key('packRepoVersionLabel'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: <Widget>[
          Text('当前版本：$current'),
          const SizedBox(width: 24),
          Text('最新版本：$latest'),
        ],
      ),
    );
  }

  Widget _buildOptionField(BuildScriptOption option) {
    final String value =
        widget.pack.buildOptions[option.name] ?? option.defaultValue;
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(option.name),
          const SizedBox(width: 6),
          SizedBox(
            width: _optionFieldWidth,
            child: ComboBox<String>(
              key: Key('buildOption_${option.name}'),
              value: value,
              onChanged: _savingOption
                  ? null
                  : (String? selected) {
                      if (selected != null && selected != value) {
                        _selectOption(option.name, selected);
                      }
                    },
              items: <ComboBoxItem<String>>[
                for (final String item in option.values)
                  ComboBoxItem<String>(value: item, child: Text(item)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectOption(String name, String value) async {
    final Future<bool> Function(PackModel pack)? onSave = widget.onSave;
    if (onSave == null || _savingOption) {
      return;
    }
    _savingOption = true;
    bool saved = false;
    try {
      saved = await onSave(_withBuildOption(widget.pack, name, value));
    } catch (_) {
      saved = false;
    } finally {
      _savingOption = false;
    }
    if (!mounted) {
      return;
    }
    if (saved) {
      showFloatingToast(context, '已保存');
    } else {
      showFloatingToast(
        context,
        '保存失败',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canBuild =
        widget.onBuildPack != null &&
        findBuildScript(widget.pack.files) != null;
    final Color sizeColor = FluentTheme.of(context)
        .resources
        .textFillColorSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canBuild) _buildToolbar(),
        if (_header?.repo != null) _buildRepoVersionRow(),
        Expanded(
          child: widget.pack.files.isEmpty
              ? const Center(child: Text('该包暂无文件'))
              : TreeView(
                  items: _buildTreeItems(
                    _buildTree(widget.pack.files),
                    sizeColor,
                  ),
                  onItemInvoked: _onItemInvoked,
                  onItemExpandToggle: _onExpandToggle,
                  shrinkWrap: false,
                  scrollPrimary: false,
                ),
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
}

PackModel _withBuildOption(PackModel pack, String name, String value) {
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
    ..buildOptions = <String, String>{...pack.buildOptions, name: value};
}
