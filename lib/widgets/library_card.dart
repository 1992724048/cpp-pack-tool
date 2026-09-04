import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:flutter/material.dart';

class LibraryCard extends StatefulWidget {
  final String title;
  final String? description;
  final bool isSelected;
  final ValueChanged<bool>? onTap;

  const LibraryCard({super.key, required this.title, this.description, this.isSelected = false, this.onTap});

  @override
  State<LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<LibraryCard> {
  late bool _isSelected;

  late final VoidCallback _handleTap;

  @override
  void initState() {
    super.initState();
    _isSelected = widget.isSelected;
    _handleTap = _onTapHandler;
  }

  void _onTapHandler() {
    setState(() {
      _isSelected = true;
    });
    widget.onTap?.call(_isSelected);
  }

  @override
  void didUpdateWidget(LibraryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      _isSelected = widget.isSelected;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      key: const Key('libraryCardMaterial'),
      color: Colors.transparent,
      child: InkWell(
        key: const Key('libraryCardInkWell'),
        onTap: _handleTap,
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.2),
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutExpo,
          decoration: BoxDecoration(
            color: _isSelected ? theme.colorScheme.primaryContainer : Colors.transparent,
            border: Border(left: BorderSide(color: _isSelected ? theme.colorScheme.primary : Colors.transparent, width: 2)),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: .start,
                children: [
                  Row(
                    children: [
                      Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(width: 4),
                      Tag(text: 'v1.0.0', fontSize: 9),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(widget.description ?? '暂无描述', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              Spacer(),
              IconButton(onPressed: () {}, icon: Icon(Icons.more_vert)),
            ],
          ),
        ),
      ),
    );
  }
}
