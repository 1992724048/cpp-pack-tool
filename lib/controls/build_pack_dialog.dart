import 'dart:async';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/elevated_build.dart';
import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/build/repo_version.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/controls/build_output_panel.dart';
import 'package:cpp_nuget_pack/controls/build_timeline.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/pack_remap.dart';
import 'package:fluent_ui/fluent_ui.dart';

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

/// 触发下载进度重绘的最小字节差：更小的更新被跳过，降低 setState 频率；
/// 首个事件（新工具）与完成事件不受此限制。
const int _progressMinDeltaBytes = 256 * 1024;

/// 输出面板保留的最大行数（超出后丢弃最早的行）。
const int _maxOutputLineCount = 2000;

/// 左栏（信息 + 时间线）宽度与内容区高度（右侧输出区同高）。
const double _statusColumnWidth = 260;
const double _panelHeight = 360;

/// 构建对话框关闭载荷：[fixReport] 为头文件引用检查报告（未执行时为 null），
/// [failureEntry] 为失败会话的历史条目（成功完成时为 null，提权重试成功后丢弃）。
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
    this.retryElevated,
    this.now = DateTime.now,
    this.gitGlobalArguments = const <String>[],
  });

  final PackModel pack;

  /// 预构建配方（`# source: none`）：步骤表为 下载 → 分类（`classify_tree`
  /// 开始标记）→ 检查头文件引用 → 重新映射 → 完成。
  final bool sourceNone;

  final PackBuildRunner build;
  final BuildPackPrepare prepare;
  final Future<List<FileModel>> Function(String sourcePath) scanFiles;
  final Future<void> Function(PackModel pack) onApply;

  /// 构建成功后、重新映射扫描前的 include 引用检查与自动修复。
  final PackHeaderIncludeFixer fixIncludes;

  /// 提权重试入口（临时目录权限失败时提供「以管理员身份重试」）；null 时不提供。
  final ElevatedPackBuildRunner? retryElevated;

  /// 时间源（历史记录时间戳）；测试可注入。
  final DateTime Function() now;

  /// git 命令全局参数（手动代理 `-c http.proxy=...`），透传给 [build]。
  final List<String> gitGlobalArguments;

  @override
  State<BuildPackDialog> createState() => _BuildPackDialogState();
}

class _BuildPackDialogState extends State<BuildPackDialog> {
  /// 构建会话计时：initState 启动，成功在完成态定格、失败在首次 [_showFailure] 定格；
  /// 提权重试时继续累计（不重置），即累计流水线执行时长。
  final Stopwatch _sessionWatch = Stopwatch();

  /// 失败会话的历史条目（首次失败构造一次；成功完成时丢弃）。
  HistoryModel? _failureEntry;

  _BuildStage _stage = _BuildStage.preparing;
  Object? _error;
  final List<String> _outputLines = <String>[];

  /// 输出行版本号：每次追加/补齐自增，输出面板据此自动滚动到底部。
  int _outputRevision = 0;

  BuildEnvironment? _environment;
  List<FileModel> _files = const <FileModel>[];
  int _addedCount = 0;
  int _removedCount = 0;
  String? _sourceVersion;

  /// 构建成功后由源码版本自动同步出的包版本（未同步时为 null）。
  String? _syncedVersion;

  /// include 引用检查结果：关闭对话框时随 [Navigator.pop] 返回给调用方展示。
  HeaderIncludeFixReport? _fixReport;

  /// 当前是否处于「以管理员身份重试」流程（步骤详情据此切管理员文案）。
  bool _elevatedRetry = false;

  /// 失败所在步骤：时间线据此标红并隐藏其后步骤。
  BuildTimelineStepId _failedStep = BuildTimelineStepId.prepare;

  /// 已实际执行过的步骤：越过但未执行的步骤在时间线上显示为「跳过」。
  final Set<BuildTimelineStepId> _visitedSteps = <BuildTimelineStepId>{};

  /// 工具下载进度（准备环境步骤）；离开该步骤时清空。
  ToolDownloadProgress? _downloadProgress;

  /// 构建脚本输出的下载百分比（`progress NN%` 行；预构建配方使用）。
  int? _buildProgressPercent;

  @override
  void initState() {
    super.initState();
    _visitedSteps.add(_activeStep);
    _sessionWatch.start();
    _prepare();
  }

  /// 阶段对应的步骤 ID（预构建配方的准备/下载/构建阶段统一归「下载」步骤）。
  BuildTimelineStepId _stepFor(_BuildStage stage) {
    return switch (stage) {
      _BuildStage.preparing => widget.sourceNone
          ? BuildTimelineStepId.download
          : BuildTimelineStepId.prepare,
      _BuildStage.downloading => BuildTimelineStepId.download,
      _BuildStage.building => widget.sourceNone
          ? BuildTimelineStepId.download
          : BuildTimelineStepId.build,
      _BuildStage.fixingIncludes => BuildTimelineStepId.includes,
      _BuildStage.classifying => BuildTimelineStepId.classify,
      _BuildStage.remapping => BuildTimelineStepId.remap,
      _BuildStage.completed => BuildTimelineStepId.done,
      _BuildStage.failed => _failedStep,
    };
  }

  BuildTimelineStepId get _activeStep => _stepFor(_stage);

  /// 推进阶段并记录该步骤已执行（时间线据此区分「完成」与「跳过」）。
  void _advanceTo(_BuildStage stage) {
    _visitedSteps.add(_stepFor(stage));
    _stage = stage;
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
    setState(() {
      _environment = environment;
      _downloadProgress = null;
    });
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
        gitGlobalArguments: widget.gitGlobalArguments,
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

  /// 以管理员身份重试整条构建流水线（临时目录权限失败时由失败态按钮触发）。
  ///
  /// 环境与正常构建完全相同（复用准备阶段结果）；成功走同一后续流程
  /// （头文件检查 → 重新映射 → 完成），失败保留输出回到失败态。
  Future<void> _retryElevated() async {
    final ElevatedPackBuildRunner? runner = widget.retryElevated;
    final BuildEnvironment? environment = _environment;
    if (runner == null || environment == null || _stage != _BuildStage.failed) {
      return;
    }
    setState(() {
      _elevatedRetry = true;
      _advanceTo(_BuildStage.downloading);
      _error = null;
      _downloadProgress = null;
    });
    _sessionWatch.start();
    try {
      await runner(
        widget.pack,
        _onBuildStage,
        buildEnvironment: environment,
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
    await _afterBuildSucceeded();
  }

  /// 构建脚本成功后的公共后续：include 引用检查 → 重新映射 → 应用 → 完成。
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
    PackModel updated = copyPackWithFiles(widget.pack, files);
    // 仅本次构建解析出来源版本时执行同步：预构建配方（source:none）不会产出
    // 来源版本，沿用旧记录可避免每次构建用陈旧值重复同步。
    String? syncedVersion;
    if (_sourceVersion != null) {
      updated.sourceVersion = _sourceVersion;
      final String? versionFromTag = packageVersionFromTag(_sourceVersion);
      if (versionFromTag != null && versionFromTag != updated.version) {
        syncedVersion = versionFromTag;
      }
    }
    final String previousVersion = updated.version;
    final bool versionSynced =
        syncedVersion != null && syncedVersion != previousVersion;
    final String elapsedText = formatDuration(_sessionWatch.elapsed);
    updated.history = appendHistoryEntry(
      updated.history,
      HistoryModel(
        time: widget.now(),
        type: HistoryType.built,
        message: versionSynced
            ? '构建成功：耗时 $elapsedText，版本已同步 $previousVersion → $syncedVersion'
            : '构建成功：耗时 $elapsedText',
      ),
    );
    if (versionSynced) {
      updated = copyPackWithVersion(updated, syncedVersion);
    }
    setState(() {
      _files = files;
      _addedCount = diff.added;
      _removedCount = diff.removed;
      _syncedVersion = syncedVersion;
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
  /// 检查失败不阻断构建成功流程：错误记入输出面板，跳过报告继续重新映射。
  Future<void> _fixIncludes(String sourcePath) async {
    setState(() => _advanceTo(_BuildStage.fixingIncludes));
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
      _advanceTo(switch (stage) {
        PackBuildStage.downloading => _BuildStage.downloading,
        PackBuildStage.building => _BuildStage.building,
      });
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
      _outputRevision++;
      if (percent != null) {
        _buildProgressPercent = percent;
      }
      if (classify) {
        _advanceTo(_BuildStage.classifying);
      }
    });
  }

  /// 展示失败：保留已流式积累的输出行并补充 [outputTail]（已在面板中的行不重复）；
  /// 无任何输出时仅显示 tail。失败会话的构建条目在首次失败时构造一次。
  void _showFailure(Object error, {String? outputTail}) {
    if (!mounted) {
      return;
    }
    _sessionWatch.stop();
    _failureEntry ??= HistoryModel(
      time: widget.now(),
      type: HistoryType.built,
      message: _buildFailureMessage(error),
    );
    setState(() {
      _failedStep = _activeStep;
      _advanceTo(_BuildStage.failed);
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
        _outputRevision++;
      }
    });
  }

  void _trimOutputLines() {
    if (_outputLines.length > _maxOutputLineCount) {
      _outputLines.removeRange(0, _outputLines.length - _maxOutputLineCount);
    }
  }

  static String? _tailOf(Object error) =>
      error is PackBuildException ? error.outputTail : null;

  /// 失败条目原因：`formatError` 首个非空行、超 120 字符截断加省略号。
  static String _buildFailureMessage(Object error) {
    final String reason = formatError(error)
        .split('\n')
        .map((String line) => line.trim())
        .firstWhere((String line) => line.isNotEmpty, orElse: () => '未知错误');
    final String truncated = reason.length <= 120
        ? reason
        : '${reason.substring(0, 120)}…';
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
              runtimeLabel: _runtimeLabel,
              steps: _timelineSteps,
              onRetryElevated: _canRetryElevated ? _retryElevated : null,
            ),
          ),
          Container(
            width: 1,
            height: _panelHeight,
            color: theme.resources.cardStrokeColorDefault,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: _panelHeight,
              child: BuildOutputPanel(
                lines: _outputLines,
                revision: _outputRevision,
              ),
            ),
          ),
        ],
      ),
      actions: [
        Button(
          key: const Key('buildCloseButton'),
          onPressed: _isRunning
              ? null
              : () => Navigator.pop(
                  context,
                  BuildDialogResult(
                    fixReport: _fixReport,
                    failureEntry: _failureEntry,
                  ),
                ),
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

  /// 运行库展示（⑥）：优先取已解析构建环境的 `CNP_RUNTIME_LIBRARY`
  /// （最终生效值：用户选择 > `# runtime:` 配方默认 > md）；准备完成前按
  /// 用户显式选择推导；无法判定时显示「跟随配方」。
  String get _runtimeLabel {
    final String? resolved = normalizeRuntimeLibrary(
      _environment?.environment[runtimeLibraryEnvName],
    );
    final String? userChoice = normalizeRuntimeLibrary(
      widget.pack.buildOptions[runtimeOptionName],
    );
    return switch (resolved ?? userChoice) {
      'mt' => 'MT（静态）',
      'md' => 'MD（动态）',
      _ => '跟随配方',
    };
  }

  /// 时间线步骤：三模式步骤表 + 当前会话状态（失败时隐藏后续步骤）。
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
        downloadProgress: _downloadProgress,
        buildProgressPercent: _buildProgressPercent,
        elevatedRetry: _elevatedRetry,
      ),
      doneDetails: buildCompletionDetails(
        fileCount: _files.length,
        totalSize: totalFileSize(_files),
        addedCount: _addedCount,
        removedCount: _removedCount,
        syncedVersion: _syncedVersion,
      ),
      failureText: failed ? '构建失败：${formatError(_error!)}' : null,
    );
  }

  /// 仅当失败信息命中临时目录权限特征且提供了提权重试入口时，才显示重试按钮。
  bool get _canRetryElevated =>
      widget.retryElevated != null &&
      _environment != null &&
      _stage == _BuildStage.failed &&
      _error != null &&
      detectTempPermissionFailure(_failureText);

  /// 失败态的全部文本（异常信息 + 输出面板行，含已补充的输出尾部）。
  String get _failureText =>
      <String>[formatError(_error!), ..._outputLines].join('\n');
}
