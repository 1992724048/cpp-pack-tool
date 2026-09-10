import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PackFiles extends StatefulWidget {
  const PackFiles({super.key, required this.pack});

  final PackModel pack;

  @override
  State<PackFiles> createState() => _PackFilesState();
}

class _PackFilesState extends State<PackFiles> {
  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  final Set<String> _expandedDirs = <String>{};

  @override
  void initState() {
    super.initState();
    _expandedDirs.addAll(_topLevelDirs(widget.pack.files));
  }

  @override
  void didUpdateWidget(covariant PackFiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pack.name != widget.pack.name) {
      _expandedDirs
        ..clear()
        ..addAll(_topLevelDirs(widget.pack.files));
    }
  }

  static Set<String> _topLevelDirs(List<FileModel> files) {
    final Set<String> dirs = <String>{};
    for (final FileModel file in files) {
      final List<String> segments = _pathSegments(file.path);
      if (segments.length > 1) {
        dirs.add(segments.first);
      }
    }
    return dirs;
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
      items.add(
        TreeViewItem(
          value: dir.path,
          leading: const Icon(FluentIcons.folder),
          expanded: _expandedDirs.contains(dir.path),
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
          leading: const Icon(FluentIcons.document),
          content: _buildRow(file.name, formatBytes(file.size), sizeColor),
        ),
      );
    }
    return items;
  }

  static Widget _buildRow(String name, String size, Color sizeColor) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(size, style: TextStyle(color: sizeColor)),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
    if (widget.pack.files.isEmpty) {
      return const Center(child: Text('该包暂无文件'));
    }
    final Color sizeColor = FluentTheme.of(context)
        .resources
        .textFillColorSecondary;
    return TreeView(
      items: _buildTreeItems(_buildTree(widget.pack.files), sizeColor),
      onItemInvoked: _onItemInvoked,
      onItemExpandToggle: _onExpandToggle,
      shrinkWrap: false,
      scrollPrimary: false,
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
