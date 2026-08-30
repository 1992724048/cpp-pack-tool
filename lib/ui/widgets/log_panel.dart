/// 底部日志面板：级别着色、清空、折叠、自动贴底（`reverse: true` 列表）。
///
/// 对照 `docs/ui-spec.md` §3.7 与 §5.2。
library;

import 'package:flutter/material.dart';

import '../log_controller.dart';
import '../tokens.dart';

/// 底部日志面板。
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, required this.controller});

  /// 日志控制器（外部通过它追加/清空）。
  final LogController controller;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _collapsed
          ? _header()
          : SizedBox(
              height: AppDims.logPanelHeight,
              child: Column(
                children: [
                  _header(),
                  Expanded(child: _body()),
                ],
              ),
            ),
    );
  }

  Widget _header() {
    return Container(
      height: AppDims.logHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      decoration: const BoxDecoration(
        color: AppColors.bgApp,
        border: Border(top: BorderSide(color: AppColors.borderStrong)),
      ),
      child: Row(
        children: [
          const Text(
            '日志',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppFontSizes.body,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _handleClear,
            icon: const Icon(Icons.delete_outline, size: 14),
            label: const Text('清空'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
              minimumSize: const Size(0, 24),
              textStyle: const TextStyle(fontSize: AppFontSizes.small),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _collapsed = !_collapsed),
            tooltip: _collapsed ? '展开日志' : '折叠日志',
            icon: Icon(
              _collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  void _handleClear() {
    widget.controller.clear();
    widget.controller.info('日志已清空');
  }

  Widget _body() {
    // SelectionArea 使日志文本可选择/复制（桌面端 Ctrl+C 可用）；空态与操作按钮不受影响。
    return SelectionArea(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final entries = widget.controller.entries;
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                '暂无日志',
                style: TextStyle(
                  color: AppColors.textSemantic,
                  fontSize: AppFontSizes.body,
                ),
              ),
            );
          }
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.sm,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) => _row(entries[index]),
          );
        },
      ),
    );
  }

  Widget _row(LogEntry entry) {
    final color = switch (entry.level) {
      LogLevel.info => AppColors.textSemantic,
      LogLevel.warn => AppColors.warn,
      LogLevel.error => AppColors.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_two(entry.time.hour)}:${_two(entry.time.minute)}:${_two(entry.time.second)}',
            style: const TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.caption,
              fontFamily: AppFonts.mono,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
          ),
          const SizedBox(width: AppSpacing.s1),
          SizedBox(
            width: 44,
            child: Text(
              entry.level.name.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: AppFontSizes.caption,
                fontWeight: FontWeight.w600,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallback,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppFontSizes.caption,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallback,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
