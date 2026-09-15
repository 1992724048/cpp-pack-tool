import 'dart:async';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/pack_remap.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;

enum _BuildStage {
  preparing,
  downloading,
  building,

  /// 构建成功后、重新映射扫描前的 `#include` 引用检查与自动修复阶段。
  fixingIncludes,

  /// 预构建配方（`# source: none`）的产物分类阶段（见 [classifyStartMarkerPrefix]）。
  classifying,
  remapping,
  completed,
  failed,
}

/// 构建环境准备函数：`onDownloadProgress` 为工具下载进度回调（可为 null 不显示）。
typedef BuildPackPrepare = Future<BuildEnvironment> Function(
  PackModel pack, {
  ToolDownloadProgressCallback? onDownloadProgress,
});

/// `cnp_build_support.classify_tree` 的开始标记前缀（见 SKILL.md「分类标记」）；
/// 预构建配方据此把阶段从「正在下载」切换到「正在分类」。
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

/// 触发下载进度重绘的最小字节差：更小的更新被跳过，降低 setState 频率；
/// 首个事件（新工具）与完成事件不受此限制。
const int _progressMinDeltaBytes = 256 * 1024;

/// 输出面板保留的最大行数（超出后丢弃最早的行）。
const int _maxOutputLineCount = 2000;

const double _outputPanelHeight = 340;
const double _statusColumnWidth = 240;

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
Color outputLineColor(String line) {
  final MatchKeyword? match = findOutputKeyword(line);
  return switch (match?.keyword) {
    _errorKeyword => UCColors.flavor.red,
    _warningKeyword => UCColors.flavor.peach,
    _infoKeyword => UCColors.flavor.blue,
    _ => UCColors.flavor.text,
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

class BuildPackDialog extends StatefulWidget {
  const BuildPackDialog({
    super.key,
    required this.pack,
    this.sourceNone = false,
    this.build = runPackBuild,
    required this.prepare,
    required this.scanFiles,
    required this.onApply,
    this.fixIncludes = fixHeaderIncludes,
  });

  final PackModel pack;

  /// 预构建配方（`# source: none`）：隐藏「准备环境/下载源码/执行构建」文案，
  /// 改为 正在下载 → 正在分类（`classify_tree` 开始标记）→ 重新映射。
  final bool sourceNone;

  final PackBuildRunner build;
  final BuildPackPrepare prepare;
  final Future<List<FileModel>> Function(String sourcePath) scanFiles;
  final Future<void> Function(PackModel pack) onApply;

  /// 构建成功后、重新映射扫描前的 include 引用检查与自动修复。
  final PackHeaderIncludeFixer fixIncludes;

  @override
  State<BuildPackDialog> createState() => _BuildPackDialogState();
}

class _BuildPackDialogState extends State<BuildPackDialog> {
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

  _BuildStage _stage = _BuildStage.preparing;
  Object? _error;
  final List<String> _outputLines = <String>[];
  BuildEnvironment? _environment;
  List<FileModel> _files = const <FileModel>[];
  int _addedCount = 0;
  int _removedCount = 0;
  String? _sourceVersion;

  /// include 引用检查结果：关闭对话框时随 [Navigator.pop] 返回给调用方展示。
  HeaderIncludeFixReport? _fixReport;

  /// 工具下载进度（准备环境阶段）；离开准备阶段时清空。
  ToolDownloadProgress? _downloadProgress;

  /// 构建脚本输出的下载百分比（`progress NN%` 行；预构建配方阶段文案使用）。
  int? _buildProgressPercent;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _outputScroller.dispose();
    _outputHorizontalScroller.dispose();
    _outputFilterController.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final BuildEnvironment environment;
    try {
      environment = await widget.prepare(
        widget.pack,
        onDownloadProgress: _onDownloadProgress,
      );
    } catch (error) {
      _showFailure(error);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _environment = environment);
    await _build(environment);
  }

  Future<void> _build(BuildEnvironment environment) async {
    try {
      await widget.build(
        widget.pack,
        _onBuildStage,
        environment: environment.environment,
        onOutput: _onBuildOutput,
        onSourceVersion: _onSourceVersion,
      );
    } catch (error) {
      _showFailure(error, outputTail: _tailOf(error));
      return;
    }
    if (!mounted) {
      return;
    }

    final String? sourcePath = widget.pack.sourcePath;
    if (sourcePath == null) {
      _showFailure(const PackBuildException('该包缺少源目录信息'));
      return;
    }
    await _fixIncludes(sourcePath);
    if (!mounted) {
      return;
    }
    setState(() => _stage = _BuildStage.remapping);

    final List<FileModel> files;
    try {
      files = await widget.scanFiles(sourcePath);
    } catch (error) {
      _showFailure(error);
      return;
    }
    if (!mounted) {
      return;
    }

    final PackFilesDiff diff = comparePackFiles(widget.pack.files, files);
    final PackModel updated = copyPackWithFiles(widget.pack, files);
    updated.sourceVersion = _sourceVersion ?? widget.pack.sourceVersion;
    setState(() {
      _files = files;
      _addedCount = diff.added;
      _removedCount = diff.removed;
    });

    try {
      await widget.onApply(updated);
    } catch (error) {
      _showFailure(error);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _stage = _BuildStage.completed);
  }

  /// 构建成功、重新映射扫描前的 include 引用检查（含自动修复）。
  ///
  /// 检查失败不阻断构建成功流程：错误记入输出面板，跳过报告继续重新映射。
  Future<void> _fixIncludes(String sourcePath) async {
    setState(() => _stage = _BuildStage.fixingIncludes);
    try {
      _fixReport = await widget.fixIncludes(
        sourcePath,
        packageName: widget.pack.name,
      );
    } catch (error) {
      _onBuildOutput('头文件引用检查失败：${formatError(error)}');
    }
  }

  void _onBuildStage(PackBuildStage stage) {
    if (!mounted) {
      return;
    }
    setState(() {
      _downloadProgress = null;
      _stage = switch (stage) {
        PackBuildStage.downloading => _BuildStage.downloading,
        PackBuildStage.building => _BuildStage.building,
      };
    });
  }

  void _onSourceVersion(String version) {
    _sourceVersion = version;
  }

  void _onDownloadProgress(ToolDownloadProgress progress) {
    if (!mounted) {
      return;
    }
    final ToolDownloadProgress? current = _downloadProgress;
    final bool isNewTool = current?.name != progress.name;
    final int deltaBytes = current == null
        ? 0
        : progress.receivedBytes - current.receivedBytes;
    final bool isComplete =
        progress.totalBytes > 0 &&
        progress.receivedBytes >= progress.totalBytes;
    if (!isNewTool && !isComplete && deltaBytes < _progressMinDeltaBytes) {
      return;
    }
    setState(() => _downloadProgress = progress);
  }

  void _onBuildOutput(String line) {
    if (!mounted) {
      return;
    }
    final int? percent = widget.sourceNone
        ? extractProgressPercent(line)
        : null;
    final bool classify = widget.sourceNone && isClassifyStartLine(line);
    setState(() {
      _outputLines.add(line);
      _trimOutputLines();
      if (percent != null) {
        _buildProgressPercent = percent;
      }
      if (classify) {
        _stage = _BuildStage.classifying;
      }
    });
    _scrollOutputToBottom();
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

  /// 展示失败：保留已流式积累的输出行并补充 [outputTail]（已在面板中的行不重复）；
  /// 无任何输出时仅显示 tail。
  void _showFailure(Object error, {String? outputTail}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = _BuildStage.failed;
      _error = error;
      _downloadProgress = null;
      if (outputTail != null && outputTail.isNotEmpty) {
        final Set<String> existing = _outputLines.toSet();
        for (final String line in outputTail.split('\n')) {
          if (existing.add(line)) {
            _outputLines.add(line);
          }
        }
        _trimOutputLines();
      }
    });
    _scrollOutputToBottom();
  }

  void _trimOutputLines() {
    if (_outputLines.length > _maxOutputLineCount) {
      _outputLines.removeRange(0, _outputLines.length - _maxOutputLineCount);
    }
  }

  static String? _tailOf(Object error) =>
      error is PackBuildException ? error.outputTail : null;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final BuildEnvironment? environment = _environment;
    return ContentDialog(
      key: const Key('buildPackDialog'),
      title: const Text('构建'),
      constraints: const BoxConstraints(maxWidth: 800),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _statusColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('包名：${widget.pack.name}'),
                  const SizedBox(height: 4),
                  Text('源目录：${widget.pack.sourcePath ?? '未知'}'),
                  if (environment != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '编译器：${compilerKindLabel(environment.compiler.kind)} '
                      '${environment.compiler.version}',
                      key: const Key('buildCompilerLabel'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildStatus(),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: _outputPanelHeight,
            color: theme.resources.cardStrokeColorDefault,
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildOutputPanel()),
        ],
      ),
      actions: [
        Button(
          key: const Key('buildCloseButton'),
          onPressed: _isRunning
              ? null
              : () => Navigator.pop(context, _fixReport),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  bool get _isRunning =>
      _stage == _BuildStage.preparing ||
      _stage == _BuildStage.downloading ||
      _stage == _BuildStage.building ||
      _stage == _BuildStage.fixingIncludes ||
      _stage == _BuildStage.classifying ||
      _stage == _BuildStage.remapping;

  Widget _buildOutputPanel() {
    final FluentThemeData theme = FluentTheme.of(context);
    return Container(
      key: const Key('buildOutputPanel'),
      height: _outputPanelHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: 32, child: _buildOutputFilter()),
          const SizedBox(height: 8),
          Expanded(child: _buildOutputContent()),
        ],
      ),
    );
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

  /// 过滤只影响显示，不改变 [_outputLines] 原始行列表。
  List<String> get _visibleOutputLines {
    final String query = _outputFilter.toLowerCase();
    if (query.isEmpty) {
      return _outputLines;
    }
    return <String>[
      for (final String line in _outputLines)
        if (line.toLowerCase().contains(query)) line,
    ];
  }

  Widget _buildOutputContent() {
    if (_outputLines.isEmpty) {
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
            child: Column(
              key: const Key('buildOutputContent'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String line in lines) _buildOutputLine(line),
              ],
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
        style: _outputTextStyle.copyWith(color: UCColors.flavor.subtext0),
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

  Widget _buildOutputLine(String line) {
    final Color keywordColor = outputLineColor(line);
    final TextStyle keywordStyle = _outputTextStyle.copyWith(
      color: keywordColor,
      fontWeight: FontWeight.w600,
    );
    final TextStyle textStyle = _outputTextStyle.copyWith(
      color: UCColors.flavor.text,
    );
    return RichText(
      text: TextSpan(
        style: textStyle,
        children: _splitOutputLine(line, keywordStyle),
      ),
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

  /// 预构建配方的下载阶段文案（附构建脚本上报的百分比，若有）。
  String get _sourceNoneDownloadText {
    final int? percent = _buildProgressPercent;
    return percent == null ? '正在下载…' : '正在下载…（$percent%）';
  }

  String get _preparingText =>
      widget.sourceNone ? _sourceNoneDownloadText : '正在准备构建环境…';

  String get _downloadingText =>
      widget.sourceNone ? _sourceNoneDownloadText : '正在下载源码…';

  String get _buildingText =>
      widget.sourceNone ? _sourceNoneDownloadText : '正在执行构建…';

  Widget _buildStatus() {
    switch (_stage) {
      case _BuildStage.preparing:
        return _buildProgressStatus(_preparingText, showDownloadProgress: true);
      case _BuildStage.downloading:
        return _buildProgressStatus(_downloadingText);
      case _BuildStage.building:
        return _buildProgressStatus(_buildingText);
      case _BuildStage.fixingIncludes:
        return _buildProgressStatus('正在检查头文件引用…');
      case _BuildStage.classifying:
        return _buildProgressStatus('正在分类…');
      case _BuildStage.remapping:
        return _buildProgressStatus('正在重新映射…');
      case _BuildStage.failed:
        return _buildFailure();
      case _BuildStage.completed:
        return _buildResult();
    }
  }

  Widget _buildProgressStatus(
    String label, {
    bool showDownloadProgress = false,
  }) {
    final ToolDownloadProgress? progress = _downloadProgress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [ProgressRing(), const SizedBox(width: 12), Text(label)]),
        if (showDownloadProgress && progress != null) ...[
          const SizedBox(height: 8),
          Text(
            _downloadProgressText(progress),
            key: const Key('buildDownloadProgress'),
            style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
          ),
        ],
      ],
    );
  }

  String _downloadProgressText(ToolDownloadProgress progress) {
    final String amount = progress.totalBytes > 0
        ? '${(progress.receivedBytes * 100 / progress.totalBytes).round()}%'
              '（${formatBytes(progress.receivedBytes)} / '
              '${formatBytes(progress.totalBytes)}）'
        : formatBytes(progress.receivedBytes);
    final String speed = progress.bytesPerSecond > 0
        ? '，${formatBytes(progress.bytesPerSecond.round())}/s'
        : '';
    return '正在下载 ${progress.name}：$amount$speed';
  }

  Widget _buildFailure() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('构建失败：${formatError(_error!)}'),
        const SizedBox(height: 8),
        const Text('详细输出见右侧面板'),
      ],
    );
  }

  Widget _buildResult() {
    final int totalSize = totalFileSize(_files);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('构建完成'),
        const SizedBox(height: 8),
        Text('文件数量：${_files.length}'),
        const SizedBox(height: 4),
        Text('总大小：${formatBytes(totalSize)}'),
        const SizedBox(height: 4),
        Text('新增：$_addedCount 个文件'),
        const SizedBox(height: 4),
        Text('移除：$_removedCount 个文件'),
      ],
    );
  }
}
