import 'dart:async';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/pack_remap.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _BuildStage {
  preparing,
  downloading,
  building,
  remapping,
  completed,
  failed,
}

/// 输出面板保留的最大行数（超出后丢弃最早的行）。
const int _maxOutputLineCount = 2000;

const double _outputPanelHeight = 300;
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
    this.build = runPackBuild,
    required this.prepare,
    required this.scanFiles,
    required this.onApply,
  });

  final PackModel pack;
  final PackBuildRunner build;
  final Future<BuildEnvironment> Function(PackModel pack) prepare;
  final Future<List<FileModel>> Function(String sourcePath) scanFiles;
  final Future<void> Function(PackModel pack) onApply;

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

  _BuildStage _stage = _BuildStage.preparing;
  Object? _error;
  final List<String> _outputLines = <String>[];
  BuildEnvironment? _environment;
  List<FileModel> _files = const <FileModel>[];
  int _addedCount = 0;
  int _removedCount = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _outputScroller.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final BuildEnvironment environment;
    try {
      environment = await widget.prepare(widget.pack);
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

  void _onBuildStage(PackBuildStage stage) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = switch (stage) {
        PackBuildStage.downloading => _BuildStage.downloading,
        PackBuildStage.building => _BuildStage.building,
      };
    });
  }

  void _onBuildOutput(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _outputLines.add(line);
      _trimOutputLines();
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

  void _showFailure(Object error, {String? outputTail}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = _BuildStage.failed;
      _error = error;
      _outputLines.clear();
      if (outputTail != null && outputTail.isNotEmpty) {
        _outputLines.addAll(outputTail.split('\n'));
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
          onPressed: _isRunning ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  bool get _isRunning =>
      _stage == _BuildStage.preparing ||
      _stage == _BuildStage.downloading ||
      _stage == _BuildStage.building ||
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
      child: _outputLines.isEmpty
          ? Center(
              child: Text(
                '等待输出…',
                style: _outputTextStyle.copyWith(
                  color: UCColors.flavor.subtext0,
                ),
              ),
            )
          : SingleChildScrollView(
              controller: _outputScroller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final String line in _outputLines)
                    _buildOutputLine(line),
                ],
              ),
            ),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: RichText(
        text: TextSpan(
          style: textStyle,
          children: _splitOutputLine(line, keywordStyle),
        ),
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

  Widget _buildStatus() {
    switch (_stage) {
      case _BuildStage.preparing:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在准备构建环境…')],
        );
      case _BuildStage.downloading:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在下载源码…')],
        );
      case _BuildStage.building:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在执行构建…')],
        );
      case _BuildStage.remapping:
        return const Row(
          children: [ProgressRing(), SizedBox(width: 12), Text('正在重新映射…')],
        );
      case _BuildStage.failed:
        return _buildFailure();
      case _BuildStage.completed:
        return _buildResult();
    }
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
