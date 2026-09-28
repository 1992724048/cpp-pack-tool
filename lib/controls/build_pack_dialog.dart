import 'dart:async';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/controls/build_output_panel.dart';
import 'package:cpp_nuget_pack/controls/build_timeline.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/pack_remap.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _BuildStage { preparing, staging, building, fixingIncludes, classifying, remapping, completed, failed }

typedef BuildPackPrepare = Future<BuildEnvironment> Function(PackModel pack);

const int _maxOutputLineCount = 2000;
const double _statusColumnWidth = 260;
const double _panelHeight = 360;

/// 构建对话框关闭载荷：[fixReport] 为头文件引用检查报告（未执行时为 null），
/// [failureEntry] 为失败会话的历史条目（成功完成时为 null）。
class BuildDialogResult {
  const BuildDialogResult({this.fixReport, this.failureEntry});

  final HeaderIncludeFixReport? fixReport;
  final HistoryModel? failureEntry;
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
    this.now = DateTime.now,
  });

  final PackModel pack;
  final bool sourceNone;
  final PackBuildRunner build;
  final BuildPackPrepare prepare;
  final Future<List<FileModel>> Function(String sourcePath) scanFiles;
  final Future<void> Function(PackModel pack) onApply;
  final PackHeaderIncludeFixer fixIncludes;
  final DateTime Function() now;

  @override
  State<BuildPackDialog> createState() => _BuildPackDialogState();
}

class _BuildPackDialogState extends State<BuildPackDialog> {
  final Stopwatch _sessionWatch = Stopwatch();

  /// 失败会话的历史条目：首次失败构造一次，成功完成时丢弃。
  HistoryModel? _failureEntry;
  _BuildStage _stage = _BuildStage.preparing;
  Object? _error;
  final List<String> _outputLines = <String>[];
  int _outputRevision = 0;
  BuildEnvironment? _environment;
  List<FileModel> _files = const <FileModel>[];
  int _addedCount = 0;
  int _removedCount = 0;
  HeaderIncludeFixReport? _fixReport;
  BuildTimelineStepId _failedStep = BuildTimelineStepId.prepare;
  final Set<BuildTimelineStepId> _visitedSteps = <BuildTimelineStepId>{};
  int? _buildProgressPercent;

  @override
  void initState() {
    super.initState();
    _visitedSteps.add(_activeStep);
    _sessionWatch.start();
    _prepare();
  }

  BuildTimelineStepId _stepFor(_BuildStage stage) {
    return switch (stage) {
      _BuildStage.preparing => widget.sourceNone ? BuildTimelineStepId.download : BuildTimelineStepId.prepare,
      _BuildStage.staging => BuildTimelineStepId.download,
      _BuildStage.building => widget.sourceNone ? BuildTimelineStepId.download : BuildTimelineStepId.build,
      _BuildStage.fixingIncludes => BuildTimelineStepId.includes,
      _BuildStage.classifying => BuildTimelineStepId.classify,
      _BuildStage.remapping => BuildTimelineStepId.remap,
      _BuildStage.completed => BuildTimelineStepId.done,
      _BuildStage.failed => _failedStep,
    };
  }

  BuildTimelineStepId get _activeStep => _stepFor(_stage);

  void _advanceTo(_BuildStage stage) {
    _visitedSteps.add(_stepFor(stage));
    _stage = stage;
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
    await _afterBuildSucceeded();
  }

  Future<void> _afterBuildSucceeded() async {
    final String? sourcePath = widget.pack.sourcePath;
    if (sourcePath == null) {
      _showFailure(const PackBuildException('该包缺少源目录信息'));
      return;
    }
    await _fixIncludes(sourcePath);
    if (!mounted) {
      return;
    }
    setState(() => _advanceTo(_BuildStage.remapping));

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
    final String elapsedText = formatDuration(_sessionWatch.elapsed);
    updated.history = appendHistoryEntry(
      updated.history,
      HistoryModel(
        time: widget.now(),
        type: HistoryType.built,
        message: '构建成功：耗时 $elapsedText',
      ),
    );
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
    _sessionWatch.stop();
    setState(() {
      _advanceTo(_BuildStage.completed);
      _failureEntry = null;
    });
  }

  /// 构建成功、重新映射扫描前的 include 引用检查（含自动修复）。
  ///
  /// 检查失败不阻断构建成功流程：错误记入输出面板并跳过报告，继续重新映射。
  Future<void> _fixIncludes(String sourcePath) async {
    setState(() => _advanceTo(_BuildStage.fixingIncludes));
    try {
      _fixReport = await widget.fixIncludes(sourcePath, packageName: widget.pack.name);
    } catch (error) {
      _onBuildOutput('头文件引用检查失败：${formatError(error)}');
    }
  }

  void _onBuildStage(PackBuildStage stage) {
    if (!mounted) {
      return;
    }
    setState(() {
      _advanceTo(switch (stage) {
        PackBuildStage.staging => _BuildStage.staging,
        PackBuildStage.building => _BuildStage.building,
      });
    });
  }

  void _onBuildOutput(String line) {
    if (!mounted) {
      return;
    }
    final int? percent = widget.sourceNone ? extractProgressPercent(line) : null;
    final bool classify = widget.sourceNone && isClassifyStartLine(line);
    setState(() {
      _outputLines.add(line);
      _trimOutputLines();
      _outputRevision++;
      if (percent != null) {
        _buildProgressPercent = percent;
      }
      if (classify) {
        _advanceTo(_BuildStage.classifying);
      }
    });
  }

  /// 展示失败：保留已流式积累的输出行并补齐 [outputTail]（面板中已有的行不重复
  /// 追加）；失败条目只在首次失败时构造一次。
  void _showFailure(Object error, {String? outputTail}) {
    if (!mounted) {
      return;
    }
    _sessionWatch.stop();
    _failureEntry ??= HistoryModel(time: widget.now(), type: HistoryType.built, message: _buildFailureMessage(error));
    setState(() {
      _failedStep = _activeStep;
      _advanceTo(_BuildStage.failed);
      _error = error;
      if (outputTail != null && outputTail.isNotEmpty) {
        final Set<String> existing = _outputLines.toSet();
        for (final String line in outputTail.split('\n')) {
          if (existing.add(line)) {
            _outputLines.add(line);
          }
        }
        _trimOutputLines();
        _outputRevision++;
      }
    });
  }

  void _trimOutputLines() {
    if (_outputLines.length > _maxOutputLineCount) {
      _outputLines.removeRange(0, _outputLines.length - _maxOutputLineCount);
    }
  }

  static String? _tailOf(Object error) => error is PackBuildException ? error.outputTail : null;

  static String _buildFailureMessage(Object error) {
    final String reason = formatError(error)
        .split('\n')
        .map((String line) => line.trim())
        .firstWhere((String line) => line.isNotEmpty, orElse: () => '未知错误');
    final String truncated = reason.length <= 120 ? reason : '${reason.substring(0, 120)}…';
    return '构建失败：$truncated';
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final BuildEnvironment? environment = _environment;
    return ContentDialog(
      key: const Key('buildPackDialog'),
      title: const Text('构建'),
      constraints: const BoxConstraints(maxWidth: 880),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _statusColumnWidth,
            height: _panelHeight,
            child: BuildStatusColumn(
              packName: widget.pack.name,
              sourcePath: widget.pack.sourcePath ?? '未知',
              compilerLabel: environment == null
                  ? null
                  : '编译器：${compilerKindLabel(environment.compiler.kind)} '
                        '${environment.compiler.version}',
              steps: _timelineSteps,
            ),
          ),
          Container(width: 1, height: _panelHeight, color: theme.resources.cardStrokeColorDefault),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: _panelHeight,
              child: BuildOutputPanel(lines: _outputLines, revision: _outputRevision),
            ),
          ),
        ],
      ),
      actions: [
        Button(
          key: const Key('buildCloseButton'),
          onPressed: _isRunning
              ? null
              : () => Navigator.pop(context, BuildDialogResult(fixReport: _fixReport, failureEntry: _failureEntry)),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  bool get _isRunning =>
      _stage == _BuildStage.preparing ||
      _stage == _BuildStage.staging ||
      _stage == _BuildStage.building ||
      _stage == _BuildStage.fixingIncludes ||
      _stage == _BuildStage.classifying ||
      _stage == _BuildStage.remapping;

  List<BuildTimelineStep> get _timelineSteps {
    final bool failed = _stage == _BuildStage.failed;
    return buildTimelineSteps(
      sourceNone: widget.sourceNone,
      activeStep: _activeStep,
      sessionState: switch (_stage) {
        _BuildStage.failed => BuildTimelineSessionState.failed,
        _BuildStage.completed => BuildTimelineSessionState.completed,
        _ => BuildTimelineSessionState.running,
      },
      visitedSteps: <BuildTimelineStepId>{..._visitedSteps, _activeStep},
      activeDetails: buildActiveStepDetails(
        step: _activeStep,
        preparing: _stage == _BuildStage.preparing,
        sourceNone: widget.sourceNone,
        buildProgressPercent: _buildProgressPercent,
      ),
      doneDetails: buildCompletionDetails(
        fileCount: _files.length,
        totalSize: totalFileSize(_files),
        addedCount: _addedCount,
        removedCount: _removedCount,
      ),
      failureText: failed ? '构建失败：${formatError(_error!)}' : null,
    );
  }
}
