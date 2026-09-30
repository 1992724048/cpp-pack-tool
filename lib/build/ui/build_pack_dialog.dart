import 'dart:async';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/nuget/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/build/ui/build_output_panel.dart';
import 'package:cpp_nuget_pack/build/ui/build_timeline.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/history_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:cpp_nuget_pack/pack/pack_remap.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _BuildStage { preparing, building, fixingIncludes, remapping, completed, failed }

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
    this.build = runPackBuild,
    required this.prepare,
    required this.scanFiles,
    required this.onApply,
    this.fixIncludes = fixHeaderIncludes,
    this.now = DateTime.now,
  });

  final PackModel pack;
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
  /// 配方经版本通道声明的版本（trim 后的原始串，空串表示声明了却没给值），
  /// 构建成功后才落到包配置。null 表示配方没声明版本。
  String? _declaredVersion;
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

  @override
  void initState() {
    super.initState();
    _visitedSteps.add(_activeStep);
    _sessionWatch.start();
    _prepare();
  }

  BuildTimelineStepId _stepFor(_BuildStage stage) {
    return switch (stage) {
      _BuildStage.preparing => BuildTimelineStepId.prepare,
      _BuildStage.building => BuildTimelineStepId.build,
      _BuildStage.fixingIncludes => BuildTimelineStepId.includes,
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
    if (!mounted) {
      return;
    }
    setState(() => _advanceTo(_BuildStage.building));
    try {
      await widget.build(
        widget.pack,
        environment: environment.environment,
        onOutput: _onBuildOutput,
        onVersion: _onDeclaredVersion,
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
    final PackModel remapped = copyPackWithFiles(widget.pack, files);
    final PackModel updated = _withDeclaredVersion(remapped);
    final String elapsedText = formatDuration(_sessionWatch.elapsed);
    updated.history = appendHistoryEntry(
      updated.history,
      HistoryModel(time: widget.now(), type: HistoryType.built, message: '构建成功：耗时 $elapsedText'),
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

  Future<void> _fixIncludes(String sourcePath) async {
    setState(() => _advanceTo(_BuildStage.fixingIncludes));
    try {
      _fixReport = await widget.fixIncludes(sourcePath, packageName: widget.pack.name);
    } catch (error) {
      _onBuildOutput('头文件引用检查失败：${formatError(error)}');
    }
  }

  void _onDeclaredVersion(String version) {
    _declaredVersion = version;
  }

  /// 只认版本通道的回调，不从输出缓冲二次解析：非流式路径不产生输出行，
  /// 输出缓冲又会被 2000 行上限裁剪，两条路都会让声明凭空消失。
  /// 与现值相同则原样返回（不必打扰用户），空声明显式警告忽略。
  PackModel _withDeclaredVersion(PackModel remapped) {
    final String? declared = _declaredVersion;
    if (declared == null) {
      return remapped;
    }
    if (declared.isEmpty) {
      _onBuildOutput('配方声明了版本号但值为空，已忽略（保持 ${remapped.version}）');
      return remapped;
    }
    if (declared == remapped.version) {
      return remapped;
    }
    _onBuildOutput('版本已更新：${remapped.version} → $declared');
    return remapped.copyWith(version: declared);
  }

  void _onBuildOutput(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _outputLines.add(line);
      _trimOutputLines();
      _outputRevision++;
    });
  }

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
      _stage == _BuildStage.building ||
      _stage == _BuildStage.fixingIncludes ||
      _stage == _BuildStage.remapping;

  List<BuildTimelineStep> get _timelineSteps {
    final bool failed = _stage == _BuildStage.failed;
    return buildTimelineSteps(
      activeStep: _activeStep,
      sessionState: switch (_stage) {
        _BuildStage.failed => BuildTimelineSessionState.failed,
        _BuildStage.completed => BuildTimelineSessionState.completed,
        _ => BuildTimelineSessionState.running,
      },
      visitedSteps: <BuildTimelineStepId>{..._visitedSteps, _activeStep},
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
