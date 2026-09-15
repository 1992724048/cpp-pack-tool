import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show SelectionRegistrar;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// `cnp_build_support.classify_tree` 的开始标记前缀（见 SKILL.md「分类标记」）；
/// 预构建配方据此把阶段从「下载」切换到「分类」。
const String classifyStartMarkerPrefix = '[cnp_build_support] classify:';

final RegExp _classifyStartPattern = RegExp(
  '^${RegExp.escape(classifyStartMarkerPrefix)}',
);

/// 构建脚本进度行的百分比提取：匹配 `... progress 42.0% ...` 形态（不依赖
/// 具体库名）；不可解析返回 null。
final RegExp _progressPercentPattern = RegExp(
  r'progress[^0-9%]*([0-9]{1,3}(?:\.[0-9]+)?)\s*%',
  caseSensitive: false,
);

bool isClassifyStartLine(String line) =>
    _classifyStartPattern.hasMatch(line.trim());

int? extractProgressPercent(String line) {
  final RegExpMatch? match = _progressPercentPattern.firstMatch(line);
  if (match == null) {
    return null;
  }
  final double? value = double.tryParse(match.group(1)!);
  if (value == null || value < 0 || value > 100) {
    return null;
  }
  return value.round();
}

const String _errorKeyword = 'ERROR';
const String _warningKeyword = 'WARNING';
const String _infoKeyword = 'INFO';
const List<String> _outputKeywords = <String>[
  _errorKeyword,
  _warningKeyword,
  _infoKeyword,
];

/// 输出行中的关键字匹配：关键字原文与起始下标。
typedef MatchKeyword = ({String keyword, int index});

/// 构建输出行的着色（ERROR 红 / WARNING 橙 / INFO 蓝 / 其余常规色）。
///
/// 关键字按字界匹配（大小写不敏感），避免 `terror`/`errorHandler` 一类
/// 片段误判；一行含多个关键字时取最靠前者。
Color outputLineColor(String line, FluentThemeData theme) {
  final MatchKeyword? match = findOutputKeyword(line);
  return switch (match?.keyword) {
    _errorKeyword => AppColors.critical(theme.brightness),
    _warningKeyword => AppColors.caution(theme.brightness),
    _infoKeyword => AppColors.info(theme.brightness),
    _ => theme.resources.textFillColorPrimary,
  };
}

/// 首个字界匹配的输出关键字（大小写不敏感），无匹配时为 null。
MatchKeyword? findOutputKeyword(String line) {
  final String lower = line.toLowerCase();
  MatchKeyword? found;
  for (final String keyword in _outputKeywords) {
    final int index = lower.indexOf(keyword.toLowerCase());
    if (index < 0 || (found != null && index >= found.index)) {
      continue;
    }
    if (!_isKeywordBoundary(line, index, keyword.length)) {
      continue;
    }
    found = (keyword: keyword, index: index);
  }
  return found;
}

bool _isKeywordBoundary(String line, int start, int length) {
  final bool startOk =
      start == 0 || !_isAsciiLetter(line.codeUnitAt(start - 1));
  final int end = start + length;
  final bool endOk =
      end >= line.length || !_isAsciiLetter(line.codeUnitAt(end));
  return startOk && endOk;
}

bool _isAsciiLetter(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}

/// 构建输出区：过滤框 + 复制按钮（列表包裹区上方）+ 列表包裹区
/// （文本可选择 + 横向滚动 + 纵向自动滚底）。
///
/// [lines] 为原始输出行（调用方持有并负责 2000 行裁剪）；[revision] 每次输出
/// 变更自增，面板据此在内容增长时自动滚动到底部。过滤只影响显示，不改变
/// [lines]；复制按钮复制 [lines] 的全部原始行（与过滤状态无关）。
class BuildOutputPanel extends StatefulWidget {
  const BuildOutputPanel({
    super.key,
    required this.lines,
    required this.revision,
  });

  final List<String> lines;
  final int revision;

  @override
  State<BuildOutputPanel> createState() => _BuildOutputPanelState();
}

class _BuildOutputPanelState extends State<BuildOutputPanel> {
  static const TextStyle _outputTextStyle = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: <String>['Courier New', 'monospace'],
    fontSize: 12,
    height: 1.5,
  );

  final ScrollController _outputScroller = ScrollController();
  final ScrollController _outputHorizontalScroller = ScrollController();
  final TextEditingController _outputFilterController = TextEditingController();
  String _outputFilter = '';

  @override
  void didUpdateWidget(covariant BuildOutputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) {
      _scrollOutputToBottom();
    }
  }

  @override
  void dispose() {
    _outputScroller.dispose();
    _outputHorizontalScroller.dispose();
    _outputFilterController.dispose();
    super.dispose();
  }

  void _scrollOutputToBottom({bool retried = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_outputScroller.hasClients) {
        if (!retried) {
          _scrollOutputToBottom(retried: true);
        }
        return;
      }
      _outputScroller.jumpTo(_outputScroller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(height: 32, child: _buildOutputFilter()),
            ),
            const SizedBox(width: 8),
            _buildCopyButton(),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildOutputPanel()),
      ],
    );
  }

  Widget _buildCopyButton() {
    return SizedBox(
      width: 28,
      height: 28,
      child: Tooltip(
        message: '复制日志',
        child: IconButton(
          key: const Key('buildOutputCopyButton'),
          icon: const Icon(FluentIcons.copy, size: 14),
          onPressed: widget.lines.isEmpty ? null : _copyOutput,
        ),
      ),
    );
  }

  /// 复制完整原始输出（过滤仅影响显示，不影响复制范围）；成功后悬浮提示。
  void _copyOutput() {
    Clipboard.setData(ClipboardData(text: widget.lines.join('\n')));
    showFloatingToast(context, '已复制');
  }

  Widget _buildOutputFilter() {
    return TextBox(
      key: const Key('buildOutputFilter'),
      controller: _outputFilterController,
      placeholder: '过滤日志…',
      prefix: const Padding(
        padding: EdgeInsets.only(left: 8, right: 6),
        child: Icon(FluentIcons.search, size: 14),
      ),
      suffix: _outputFilter.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 2),
              child: IconButton(
                key: const Key('buildOutputFilterClear'),
                icon: const Icon(FluentIcons.clear, size: 12),
                onPressed: _clearOutputFilter,
              ),
            ),
      onChanged: (String value) => setState(() => _outputFilter = value),
    );
  }

  void _clearOutputFilter() {
    _outputFilterController.clear();
    setState(() => _outputFilter = '');
  }

  /// 过滤只影响显示，不改变 [BuildOutputPanel.lines] 原始行列表。
  List<String> get _visibleOutputLines {
    final String query = _outputFilter.toLowerCase();
    if (query.isEmpty) {
      return widget.lines;
    }
    return <String>[
      for (final String line in widget.lines)
        if (line.toLowerCase().contains(query)) line,
    ];
  }

  Widget _buildOutputPanel() {
    final FluentThemeData theme = FluentTheme.of(context);
    return Container(
      key: const Key('buildOutputPanel'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      padding: const EdgeInsets.all(12),
      child: SelectionArea(child: _buildOutputContent()),
    );
  }

  Widget _buildOutputContent() {
    if (widget.lines.isEmpty) {
      return _buildOutputPlaceholder('等待输出…');
    }
    final List<String> lines = _visibleOutputLines;
    if (lines.isEmpty) {
      return _buildOutputPlaceholder('无匹配行');
    }
    return _withMouseDrag(
      Scrollbar(
        key: const Key('buildOutputHorizontalScrollbar'),
        controller: _outputHorizontalScroller,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (ScrollNotification notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _outputScroller,
          padding: const EdgeInsets.only(bottom: 12),
          child: SingleChildScrollView(
            controller: _outputHorizontalScroller,
            scrollDirection: Axis.horizontal,
            child: Builder(
              builder: (BuildContext contentContext) {
                final SelectionRegistrar? registrar =
                    SelectionContainer.maybeOf(contentContext);
                final Color selectionColor =
                    DefaultSelectionStyle.of(contentContext).selectionColor ??
                    DefaultSelectionStyle.defaultColor;
                return Column(
                  key: const Key('buildOutputContent'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final String line in lines)
                      _buildOutputLine(
                        line,
                        registrar: registrar,
                        selectionColor: selectionColor,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutputPlaceholder(String message) {
    return Center(
      child: Text(
        message,
        style: _outputTextStyle.copyWith(
          color: FluentTheme.of(context).resources.textFillColorTertiary,
        ),
      ),
    );
  }

  /// 桌面默认 dragDevices 不含鼠标（内容不可拖拽平移），此处补充，
  /// 与横向 Scrollbar 拖拽一起保证鼠标用户的横向滚动可达。
  Widget _withMouseDrag(Widget child) {
    final ScrollBehavior behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(
        dragDevices: <PointerDeviceKind>{
          ...behavior.dragDevices,
          PointerDeviceKind.mouse,
        },
      ),
      child: child,
    );
  }

  Widget _buildOutputLine(
    String line, {
    required SelectionRegistrar? registrar,
    required Color selectionColor,
  }) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color keywordColor = outputLineColor(line, theme);
    final TextStyle keywordStyle = _outputTextStyle.copyWith(
      color: keywordColor,
      fontWeight: FontWeight.w600,
    );
    final TextStyle textStyle = _outputTextStyle.copyWith(
      color: theme.resources.textFillColorPrimary,
    );
    return RichText(
      text: TextSpan(
        style: textStyle,
        children: _splitOutputLine(line, keywordStyle),
      ),
      selectionRegistrar: registrar,
      selectionColor: selectionColor,
    );
  }

  List<TextSpan> _splitOutputLine(String line, TextStyle keywordStyle) {
    final MatchKeyword? match = findOutputKeyword(line);
    if (match == null) {
      return <TextSpan>[TextSpan(text: line)];
    }
    final int end = match.index + match.keyword.length;
    return <TextSpan>[
      if (match.index > 0) TextSpan(text: line.substring(0, match.index)),
      TextSpan(text: line.substring(match.index, end), style: keywordStyle),
      if (end < line.length) TextSpan(text: line.substring(end)),
    ];
  }
}
