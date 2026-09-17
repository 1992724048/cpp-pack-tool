import 'dart:async';

import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum FloatingToastType { success, info, error }

OverlayEntry? _currentToastEntry;

/// 在右上角显示悬浮提示；新的提示会立即替换仍在显示的上一条。
///
/// [duration] 为完全可见的保持时长，不含进出场动画时间。
void showFloatingToast(
  BuildContext context,
  String message, {
  FloatingToastType type = FloatingToastType.success,
  Duration duration = const Duration(seconds: 3),
}) {
  assert(debugCheckHasOverlay(context));

  _currentToastEntry?.remove();
  _currentToastEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) => _FloatingToast(
      message: message,
      type: type,
      duration: duration,
      onDismissed: () {
        if (!entry.mounted) {
          return;
        }
        entry.remove();
        if (identical(_currentToastEntry, entry)) {
          _currentToastEntry = null;
        }
      },
    ),
  );
  _currentToastEntry = entry;
  Overlay.of(context).insert(entry);
}

class _FloatingToast extends StatefulWidget {
  const _FloatingToast({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final FloatingToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_FloatingToast> createState() => _FloatingToastState();
}

class _FloatingToastState extends State<_FloatingToast>
    with SingleTickerProviderStateMixin {
  static const Duration _animationDuration = Duration(milliseconds: 180);
  static const Offset _slideFrom = Offset(1, 0);

  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late final Animation<Offset> _slide;
  Timer? _autoCloseTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
      reverseDuration: _animationDuration,
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(begin: _slideFrom, end: Offset.zero).animate(_curve);
    _controller.addStatusListener(_handleStatus);
    _controller.forward();
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _autoCloseTimer = Timer(widget.duration, _dismiss);
    }
  }

  void _dismiss() {
    if (_closing) {
      return;
    }
    _closing = true;
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _controller.reverse().whenCompleteOrCancel(() {
      if (mounted) {
        widget.onDismissed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final ({IconData icon, Color color}) style = switch (widget.type) {
      FloatingToastType.success => (
        icon: WindowsIcons.completed,
        color: AppColors.success(theme.brightness),
      ),
      FloatingToastType.error => (
        icon: WindowsIcons.error_badge,
        color: AppColors.critical(theme.brightness),
      ),
      FloatingToastType.info => (
        icon: WindowsIcons.info,
        color: AppColors.info(theme.brightness),
      ),
    };

    return Positioned(
      top: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _curve,
          child: Container(
            key: const Key('floatingToast'),
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: theme.resources.cardBackgroundFillColorDefault,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.resources.cardStrokeColorDefault),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(style.icon, size: 16, color: style.color),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(widget.message, style: theme.typography.body),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '关闭',
                  child: IconButton(
                    key: const Key('floatingToastCloseButton'),
                    icon: const Icon(WindowsIcons.chrome_close, size: 12),
                    onPressed: _dismiss,
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(EdgeInsets.all(4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
