import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';

Future<void> showPackHistoryDialog(
  BuildContext context, {
  required PackModel pack,
  required Future<bool> Function(PackModel pack) onSave,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => PackHistoryDialog(pack: pack, onSave: onSave),
  );
}

class PackHistoryDialog extends StatefulWidget {
  const PackHistoryDialog({
    super.key,
    required this.pack,
    required this.onSave,
  });

  final PackModel pack;
  final Future<bool> Function(PackModel pack) onSave;

  @override
  State<PackHistoryDialog> createState() => _PackHistoryDialogState();
}

class _PackHistoryDialogState extends State<PackHistoryDialog> {
  late List<HistoryModel> _history;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _history = List<HistoryModel>.of(widget.pack.history);
  }

  Future<void> _delete(int displayIndex) async {
    if (_saving) {
      return;
    }
    final int index = _history.length - 1 - displayIndex;
    if (index < 0 || index >= _history.length) {
      return;
    }
    final List<HistoryModel> next = <HistoryModel>[
      for (int i = 0; i < _history.length; i++)
        if (i != index) _history[i],
    ];
    setState(() => _saving = true);
    final bool saved = await widget.onSave(_updatedPack(next));
    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    setState(() {
      _history = next;
      _saving = false;
    });
    showFloatingToast(context, '已删除');
  }

  PackModel _updatedPack(List<HistoryModel> history) {
    return PackModel(
        name: widget.pack.name,
        version: widget.pack.version,
        author: widget.pack.author,
        description: widget.pack.description,
        license: widget.pack.license,
        iconPath: widget.pack.iconPath,
        sourcePath: widget.pack.sourcePath,
        sourceVersion: widget.pack.sourceVersion,
      )
      ..files = widget.pack.files
      ..commands = widget.pack.commands
      ..dependencies = widget.pack.dependencies
      ..macros = widget.pack.macros
      ..libDirectories = widget.pack.libDirectories
      ..libraries = widget.pack.libraries
      ..history = history
      ..scripts = widget.pack.scripts
      ..buildOptions = widget.pack.buildOptions
      ..enabledFormats = widget.pack.enabledFormats;
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('packHistoryDialog'),
      title: const Text('历史记录'),
      constraints: const BoxConstraints(maxWidth: 520),
      content: SizedBox(
        width: 480,
        height: 380,
        child: _history.isEmpty
            ? const Center(child: Text('暂无历史记录'))
            : _buildList(),
      ),
      actions: [
        Button(
          key: const Key('packHistoryCloseButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView(
      children: <Widget>[
        for (
          int displayIndex = 0;
          displayIndex < _history.length;
          displayIndex++
        )
          _buildRow(
            _history[_history.length - 1 - displayIndex],
            displayIndex,
            isLast: displayIndex == _history.length - 1,
          ),
      ],
    );
  }

  Widget _buildRow(
    HistoryModel entry,
    int displayIndex, {
    required bool isLast,
  }) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color color = _typeColor(entry.type);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRail(color: color, isLast: isLast),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tag(text: historyTypeLabels[entry.type]!, color: color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.message)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatTimestamp(entry.time),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: '删除该记录',
            child: IconButton(
              key: Key('historyDeleteButton_$displayIndex'),
              icon: const Icon(FluentIcons.delete, size: 16),
              onPressed: _saving ? null : () => _delete(displayIndex),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail({required Color color, required bool isLast}) {
    return SizedBox(
      width: 16,
      child: Column(
        children: [
          const SizedBox(height: 6),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          if (!isLast)
            Expanded(
              child: Container(width: 2, color: UCColors.flavor.surface2),
            ),
        ],
      ),
    );
  }
}

Color _typeColor(HistoryType type) {
  return switch (type) {
    HistoryType.created => UCColors.flavor.green,
    HistoryType.versionChanged => UCColors.flavor.blue,
    HistoryType.filesChanged => UCColors.flavor.peach,
    HistoryType.exported => UCColors.flavor.mauve,
    HistoryType.built => UCColors.flavor.teal,
  };
}
