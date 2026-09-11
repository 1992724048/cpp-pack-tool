import 'dart:io';

import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/catppuccin_icons.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

Future<String> _readFileAsString(String path) => File(path).readAsString();

Future<void> showPackPreviewDialog(
  BuildContext context, {
  required PackModel pack,
  required PackagePlan plan,
  Future<String> Function(String path) readFile = _readFileAsString,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) =>
        PackPreviewDialog(pack: pack, plan: plan, readFile: readFile),
  );
}

class PackPreviewDialog extends StatefulWidget {
  const PackPreviewDialog({
    super.key,
    required this.pack,
    required this.plan,
    this.readFile = _readFileAsString,
  });

  final PackModel pack;
  final PackagePlan plan;
  final Future<String> Function(String path) readFile;

  @override
  State<PackPreviewDialog> createState() => _PackPreviewDialogState();
}

class _PackPreviewDialogState extends State<PackPreviewDialog> {
  static const double _treeWidth = 300;
  static const double _contentWidth = 880;
  static const double _contentHeight = 560;
  static const double _treeIconSize = 18;
  static const double _rowHeight = 26;
  static const double _indentWidth = 16;
  static const TextStyle _monoTextStyle = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: <String>['Courier New', 'monospace'],
    fontSize: 13,
  );

  final Set<String> _expandedDirs = <String>{};
  final ScrollController _previewScrollController = ScrollController();
  late final _PreviewNode _tree;
  PackageEntry? _selected;
  String? _previewText;
  Object? _previewError;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _tree = _buildTree(widget.plan.entries);
  }

  @override
  void dispose() {
    _previewScrollController.dispose();
    super.dispose();
  }

  static _PreviewNode _buildTree(List<PackageEntry> entries) {
    final _PreviewNode root = _PreviewNode(name: '', path: '');
    for (final PackageEntry entry in entries) {
      final List<String> segments = entry.packagePath
          .split('/')
          .where((String segment) => segment.isNotEmpty)
          .toList();
      if (segments.isEmpty) {
        continue;
      }
      _PreviewNode parent = root;
      for (final String segment in segments.take(segments.length - 1)) {
        final String childPath = parent.path.isEmpty
            ? segment
            : '${parent.path}/$segment';
        parent = parent.children.putIfAbsent(
          segment,
          () => _PreviewNode(name: segment, path: childPath),
        );
      }
      parent.files.add(_PreviewFile(name: segments.last, entry: entry));
    }
    return root;
  }

  void _toggleDirectory(String path) {
    setState(() {
      if (!_expandedDirs.remove(path)) {
        _expandedDirs.add(path);
      }
    });
  }

  Future<void> _selectEntry(PackageEntry entry) async {
    final int generation = ++_generation;
    final PackageEntrySource source = entry.source;
    final bool loadFile = source is PackageFileSource && !source.isBinary;
    setState(() {
      _selected = entry;
      _previewText = null;
      _previewError = null;
      _loading = loadFile;
    });
    if (!loadFile) {
      return;
    }
    final String? sourcePath = widget.pack.sourcePath;
    if (sourcePath == null) {
      setState(() {
        _loading = false;
        _previewError = ArgumentError('该包缺少源目录信息');
      });
      return;
    }
    try {
      final String content = await widget.readFile(
        joinPath(sourcePath, source.path),
      );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _previewText = content;
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _previewError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('packPreviewDialog'),
      title: const Text('打包预览'),
      constraints: const BoxConstraints(maxWidth: 960),
      content: SizedBox(
        width: _contentWidth,
        height: _contentHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: _treeWidth, child: _buildTreePanel()),
            const SizedBox(width: 12),
            Expanded(child: _buildPreviewPanel()),
          ],
        ),
      ),
      actions: [
        Button(
          key: const Key('packPreviewCloseButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildTreePanel() {
    final List<_PreviewRow> rows = _buildRows(_tree, 0);
    final FluentThemeData theme = FluentTheme.of(context);
    if (rows.isEmpty) {
      return _buildCenteredMessage('暂无打包内容');
    }
    return Container(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: ListView(
        key: const Key('packPreviewTree'),
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: <Widget>[for (final _PreviewRow row in rows) _buildRow(row)],
      ),
    );
  }

  List<_PreviewRow> _buildRows(_PreviewNode node, int depth) {
    final List<_PreviewRow> rows = <_PreviewRow>[];
    final List<_PreviewNode> directories = node.children.values.toList()
      ..sort(
        (_PreviewNode first, _PreviewNode second) =>
            comparePackagePaths(first.name, second.name),
      );
    for (final _PreviewNode directory in directories) {
      final bool expanded = _expandedDirs.contains(directory.path);
      rows.add(
        _PreviewDirRow(node: directory, depth: depth, expanded: expanded),
      );
      if (expanded) {
        rows.addAll(_buildRows(directory, depth + 1));
      }
    }
    final List<_PreviewFile> files = node.files.toList()
      ..sort(
        (_PreviewFile first, _PreviewFile second) =>
            comparePackagePaths(first.name, second.name),
      );
    for (final _PreviewFile file in files) {
      rows.add(_PreviewFileRow(file: file, depth: depth));
    }
    return rows;
  }

  Widget _buildRow(_PreviewRow row) {
    return switch (row) {
      _PreviewDirRow() => _buildDirectoryRow(row),
      _PreviewFileRow() => _buildFileRow(row),
    };
  }

  Widget _buildDirectoryRow(_PreviewDirRow row) {
    return _buildRowContainer(
      key: Key('previewDirectory_${row.node.path}'),
      depth: row.depth,
      onTap: () => _toggleDirectory(row.node.path),
      children: <Widget>[
        SizedBox(
          width: _indentWidth,
          child: Icon(
            row.expanded ? FluentIcons.chevron_down : FluentIcons.chevron_right,
            size: 10,
          ),
        ),
        _buildIcon(row.node.name, isDirectory: true, isExpanded: row.expanded),
        const SizedBox(width: 6),
        Expanded(child: Text(row.node.name, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildFileRow(_PreviewFileRow row) {
    final bool selected = identical(_selected, row.file.entry);
    return _buildRowContainer(
      key: Key('previewFile_${row.file.entry.packagePath}'),
      depth: row.depth,
      selected: selected,
      onTap: () => _selectEntry(row.file.entry),
      children: <Widget>[
        const SizedBox(width: _indentWidth),
        _buildIcon(row.file.name),
        const SizedBox(width: 6),
        Expanded(child: Text(row.file.name, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildRowContainer({
    required Key key,
    required int depth,
    required VoidCallback onTap,
    required List<Widget> children,
    bool selected = false,
  }) {
    final FluentThemeData theme = FluentTheme.of(context);
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: _rowHeight),
        color: selected ? theme.selectionColor : null,
        padding: EdgeInsets.only(left: 4 + depth * _indentWidth, right: 8),
        child: Row(children: children),
      ),
    );
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

  Widget _buildPreviewPanel() {
    final PackageEntry? selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected != null) ...[
          _buildEntryHeader(selected),
          const SizedBox(height: 8),
        ],
        Expanded(child: _buildPreviewBody()),
      ],
    );
  }

  Widget _buildEntryHeader(PackageEntry entry) {
    final FluentThemeData theme = FluentTheme.of(context);
    final (String category, Color color) = switch (entry.source) {
      PackageGeneratedSource() => ('生成文件', UCColors.flavor.blue),
      PackageFileSource(isBinary: true) => ('二进制文件', UCColors.flavor.peach),
      PackageFileSource() => ('源文件', UCColors.flavor.green),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            entry.packagePath,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '（${formatBytes(entry.source.size)}）',
          style: TextStyle(
            color: theme.resources.textFillColorSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        Tag(text: category, color: color, fontSize: 10),
      ],
    );
  }

  Widget _buildPreviewBody() {
    final PackageEntry? selected = _selected;
    if (selected == null) {
      return _buildCenteredMessage('选择左侧文件预览内容');
    }
    return switch (selected.source) {
      PackageFileSource(isBinary: true, :final int size) =>
        _buildCenteredMessage('二进制文件（${formatBytes(size)}），无法预览'),
      PackageFileSource() => _buildFileBody(),
      PackageGeneratedSource(:final String content) => _buildText(content),
    };
  }

  Widget _buildFileBody() {
    if (_loading) {
      return const Center(child: ProgressRing());
    }
    final Object? error = _previewError;
    if (error != null) {
      return _buildCenteredMessage('读取失败：${formatError(error)}');
    }
    return _buildText(_previewText ?? '');
  }

  Widget _buildText(String content) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Scrollbar(
        controller: _previewScrollController,
        child: SingleChildScrollView(
          controller: _previewScrollController,
          primary: false,
          padding: const EdgeInsets.all(12),
          child: SelectableText(content, style: _monoTextStyle),
        ),
      ),
    );
  }

  Widget _buildCenteredMessage(String message) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: theme.resources.textFillColorSecondary),
      ),
    );
  }
}

class _PreviewNode {
  _PreviewNode({required this.name, required this.path});

  final String name;
  final String path;
  final Map<String, _PreviewNode> children = <String, _PreviewNode>{};
  final List<_PreviewFile> files = <_PreviewFile>[];
}

class _PreviewFile {
  const _PreviewFile({required this.name, required this.entry});

  final String name;
  final PackageEntry entry;
}

sealed class _PreviewRow {
  const _PreviewRow({required this.depth});

  final int depth;
}

class _PreviewDirRow extends _PreviewRow {
  const _PreviewDirRow({
    required this.node,
    required super.depth,
    required this.expanded,
  });

  final _PreviewNode node;
  final bool expanded;
}

class _PreviewFileRow extends _PreviewRow {
  const _PreviewFileRow({required this.file, required super.depth});

  final _PreviewFile file;
}
