import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum BuildTimelineStepId { prepare, download, build, includes, classify, remap, done }

enum BuildTimelineStepStatus { pending, active, done, failed, skipped }

enum BuildTimelineSessionState { running, completed, failed }

class BuildTimelineDetail {
  const BuildTimelineDetail(this.text, {this.key});

  final String text;
  final Key? key;
}

class BuildTimelineStep {
  const BuildTimelineStep({
    required this.id,
    required this.label,
    required this.status,
    this.details = const <BuildTimelineDetail>[],
    this.error,
  });

  final BuildTimelineStepId id;
  final String label;
  final BuildTimelineStepStatus status;
  final List<BuildTimelineDetail> details;
  final String? error;
}

const List<BuildTimelineStepId> normalTimelineOrder = <BuildTimelineStepId>[
  BuildTimelineStepId.prepare,
  BuildTimelineStepId.download,
  BuildTimelineStepId.build,
  BuildTimelineStepId.includes,
  BuildTimelineStepId.remap,
  BuildTimelineStepId.done,
];

const List<BuildTimelineStepId> sourceNoneTimelineOrder = <BuildTimelineStepId>[
  BuildTimelineStepId.download,
  BuildTimelineStepId.classify,
  BuildTimelineStepId.includes,
  BuildTimelineStepId.remap,
  BuildTimelineStepId.done,
];

String buildTimelineStepLabel(BuildTimelineStepId id, {bool sourceNone = false}) {
  return switch (id) {
    BuildTimelineStepId.prepare => '准备环境',
    BuildTimelineStepId.download => sourceNone ? '下载' : '准备源码',
    BuildTimelineStepId.build => '执行构建',
    BuildTimelineStepId.includes => '检查头文件引用',
    BuildTimelineStepId.classify => '分类',
    BuildTimelineStepId.remap => '重新映射',
    BuildTimelineStepId.done => '完成',
  };
}

/// 组装时间线步骤（纯函数，便于单测）：
///
/// - [activeStep] 为当前进行中步骤（失败会话传失败所在步骤），失败会话截断到该步
///   为止，其后步骤不渲染；
/// - [visitedSteps] 为已实际执行过的步骤：位于活动步骤之前但未执行过的显示为
///   「跳过」，命中的显示为「完成」。
List<BuildTimelineStep> buildTimelineSteps({
  required BuildTimelineStepId activeStep,
  required BuildTimelineSessionState sessionState,
  bool sourceNone = false,
  Set<BuildTimelineStepId> visitedSteps = const <BuildTimelineStepId>{},
  List<BuildTimelineDetail> activeDetails = const <BuildTimelineDetail>[],
  List<BuildTimelineDetail> doneDetails = const <BuildTimelineDetail>[],
  String? failureText,
}) {
  final List<BuildTimelineStepId> order = sourceNone ? sourceNoneTimelineOrder : normalTimelineOrder;
  final int found = order.indexOf(activeStep);
  final int activeIndex = found < 0 ? 0 : found;
  final bool failed = sessionState == BuildTimelineSessionState.failed;
  final List<BuildTimelineStep> steps = <BuildTimelineStep>[];
  for (int index = 0; index < order.length; index++) {
    if (failed && index > activeIndex) {
      break;
    }
    final BuildTimelineStepId id = order[index];
    final BuildTimelineStepStatus status;
    List<BuildTimelineDetail> details = const <BuildTimelineDetail>[];
    String? error;
    if (index == activeIndex) {
      if (failed) {
        status = BuildTimelineStepStatus.failed;
        error = failureText;
      } else if (sessionState == BuildTimelineSessionState.completed) {
        status = BuildTimelineStepStatus.done;
        details = doneDetails;
      } else {
        status = BuildTimelineStepStatus.active;
        details = activeDetails;
      }
    } else if (index < activeIndex) {
      status = visitedSteps.contains(id) ? BuildTimelineStepStatus.done : BuildTimelineStepStatus.skipped;
    } else {
      status = BuildTimelineStepStatus.pending;
    }
    steps.add(
      BuildTimelineStep(
        id: id,
        label: buildTimelineStepLabel(id, sourceNone: sourceNone),
        status: status,
        details: details,
        error: error,
      ),
    );
  }
  return steps;
}

List<BuildTimelineDetail> buildActiveStepDetails({
  required BuildTimelineStepId step,
  required bool preparing,
  required bool sourceNone,
  int? buildProgressPercent,
}) {
  final List<BuildTimelineDetail> details = <BuildTimelineDetail>[];
  if (sourceNone && step == BuildTimelineStepId.download && buildProgressPercent != null) {
    details.add(BuildTimelineDetail('已下载 $buildProgressPercent%'));
  }
  return details;
}

List<BuildTimelineDetail> buildCompletionDetails({
  required int fileCount,
  required int totalSize,
  required int addedCount,
  required int removedCount,
}) {
  return <BuildTimelineDetail>[
    BuildTimelineDetail('文件数量：$fileCount'),
    BuildTimelineDetail('总大小：${formatBytes(totalSize)}'),
    BuildTimelineDetail('新增：$addedCount 个文件'),
    BuildTimelineDetail('移除：$removedCount 个文件'),
  ];
}

class BuildTimeline extends StatelessWidget {
  const BuildTimeline({super.key, required this.steps});

  final List<BuildTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Column(
      key: const Key('buildTimeline'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int index = 0; index < steps.length; index++) ...<Widget>[
          if (index > 0) _buildConnector(theme),
          _buildStep(theme, steps[index]),
        ],
      ],
    );
  }

  Widget _buildConnector(FluentThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 11.5),
      child: SizedBox(width: 1, height: 8, child: ColoredBox(color: theme.resources.dividerStrokeColorDefault)),
    );
  }

  Widget _buildStep(FluentThemeData theme, BuildTimelineStep step) {
    final Color labelColor = switch (step.status) {
      BuildTimelineStepStatus.pending || BuildTimelineStepStatus.skipped => theme.resources.textFillColorTertiary,
      BuildTimelineStepStatus.active ||
      BuildTimelineStepStatus.done ||
      BuildTimelineStepStatus.failed => theme.resources.textFillColorPrimary,
    };
    return Container(
      key: Key('buildTimelineStep_${step.id.name}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 24, height: 24, child: Center(child: _buildIndicator(theme, step.status))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(step.label, style: TextStyle(fontSize: 13, color: labelColor)),
                for (final BuildTimelineDetail detail in step.details)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail.text,
                      key: detail.key,
                      style: TextStyle(fontSize: 12, color: theme.resources.textFillColorSecondary),
                    ),
                  ),
                if (step.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      step.error!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.critical(theme.brightness)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(FluentThemeData theme, BuildTimelineStepStatus status) {
    switch (status) {
      case BuildTimelineStepStatus.pending:
        return _buildDot(theme.resources.controlStrongFillColorDefault);
      case BuildTimelineStepStatus.skipped:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.resources.controlStrongFillColorDefault),
          ),
        );
      case BuildTimelineStepStatus.active:
        return const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2));
      case BuildTimelineStepStatus.done:
        return Icon(FluentIcons.check_mark, size: 16, color: AppColors.success(theme.brightness));
      case BuildTimelineStepStatus.failed:
        return Icon(FluentIcons.error, size: 16, color: AppColors.critical(theme.brightness));
    }
  }

  Widget _buildDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class BuildStatusColumn extends StatelessWidget {
  const BuildStatusColumn({
    super.key,
    required this.packName,
    required this.sourcePath,
    required this.steps,
    this.compilerLabel,
  });

  final String packName;
  final String sourcePath;
  final List<BuildTimelineStep> steps;
  final String? compilerLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('包名：$packName'),
        const SizedBox(height: 4),
        Tooltip(
          message: sourcePath,
          child: Text('源目录：$sourcePath', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (compilerLabel != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(compilerLabel!, key: const Key('buildCompilerLabel')),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(child: BuildTimeline(steps: steps)),
        ),
      ],
    );
  }
}
