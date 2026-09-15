import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 时间线步骤 ID（稳定标识：用于 `buildTimelineStep_<id>` Key 与步骤表）。
enum BuildTimelineStepId { prepare, download, build, includes, classify, remap, done }

/// 时间线步骤状态。
enum BuildTimelineStepStatus {
  /// 未开始：弱化圆点。
  pending,

  /// 进行中：16px ProgressRing。
  active,

  /// 已完成：16px 对勾图标。
  done,

  /// 失败：16px 错误图标 + 错误文本。
  failed,

  /// 跳过：当前流程未执行该步骤（弱化空点）。
  skipped,
}

/// 时间线会话状态。
enum BuildTimelineSessionState { running, completed, failed }

/// 时间线详情行（进行中步骤的过程信息 / 完成步骤的结果摘要）。
class BuildTimelineDetail {
  const BuildTimelineDetail(this.text, {this.key});

  final String text;

  /// 可选 Key（如工具下载进度的 `buildDownloadProgress`）。
  final Key? key;
}

/// 时间线步骤（视图模型）。
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

  /// 失败文本（仅 [BuildTimelineStepStatus.failed] 时非空；展示 ≤ 3 行）。
  final String? error;
}

/// 常规构建的步骤表。
const List<BuildTimelineStepId> normalTimelineOrder = <BuildTimelineStepId>[
  BuildTimelineStepId.prepare,
  BuildTimelineStepId.download,
  BuildTimelineStepId.build,
  BuildTimelineStepId.includes,
  BuildTimelineStepId.remap,
  BuildTimelineStepId.done,
];

/// 预构建配方（`# source: none`）的步骤表。
const List<BuildTimelineStepId> sourceNoneTimelineOrder = <BuildTimelineStepId>[
  BuildTimelineStepId.download,
  BuildTimelineStepId.classify,
  BuildTimelineStepId.includes,
  BuildTimelineStepId.remap,
  BuildTimelineStepId.done,
];

/// 步骤展示标签（`下载源码` 在预构建配方下为 `下载`）。
String buildTimelineStepLabel(
  BuildTimelineStepId id, {
  bool sourceNone = false,
}) {
  return switch (id) {
    BuildTimelineStepId.prepare => '准备环境',
    BuildTimelineStepId.download => sourceNone ? '下载' : '下载源码',
    BuildTimelineStepId.build => '执行构建',
    BuildTimelineStepId.includes => '检查头文件引用',
    BuildTimelineStepId.classify => '分类',
    BuildTimelineStepId.remap => '重新映射',
    BuildTimelineStepId.done => '完成',
  };
}

/// 组装时间线步骤（纯函数，便于单测）：
///
/// - [activeStep] 为当前进行中步骤；失败会话传失败所在步骤；
/// - [visitedSteps] 为已实际执行过的步骤：位于活动步骤之前但未执行过的步骤
///   显示为「跳过」（如预构建配方未打印分类标记时的 `分类` 步骤）；
/// - 失败会话仅保留到失败步骤为止（其后步骤隐藏），失败文本显示在该步骤下方；
/// - 完成会话的活动步骤（`完成`）展示 [doneDetails] 结果摘要。
List<BuildTimelineStep> buildTimelineSteps({
  required BuildTimelineStepId activeStep,
  required BuildTimelineSessionState sessionState,
  bool sourceNone = false,
  Set<BuildTimelineStepId> visitedSteps = const <BuildTimelineStepId>{},
  List<BuildTimelineDetail> activeDetails = const <BuildTimelineDetail>[],
  List<BuildTimelineDetail> doneDetails = const <BuildTimelineDetail>[],
  String? failureText,
}) {
  final List<BuildTimelineStepId> order = sourceNone
      ? sourceNoneTimelineOrder
      : normalTimelineOrder;
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
      status = visitedSteps.contains(id)
          ? BuildTimelineStepStatus.done
          : BuildTimelineStepStatus.skipped;
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

/// 进行中步骤的过程详情（纯函数）：
///
/// - 准备环境阶段（[preparing]）展示工具下载进度（Key `buildDownloadProgress`）；
/// - 预构建配方（[sourceNone]）的下载步骤展示 `已下载 NN%`；
/// - 管理员重试（[elevatedRetry]）期间下载/构建步骤切管理员文案。
List<BuildTimelineDetail> buildActiveStepDetails({
  required BuildTimelineStepId step,
  required bool preparing,
  required bool sourceNone,
  ToolDownloadProgress? downloadProgress,
  int? buildProgressPercent,
  bool elevatedRetry = false,
}) {
  final List<BuildTimelineDetail> details = <BuildTimelineDetail>[];
  if (preparing && downloadProgress != null) {
    details.add(
      BuildTimelineDetail(
        formatToolDownloadProgress(downloadProgress),
        key: const Key('buildDownloadProgress'),
      ),
    );
  }
  if (sourceNone &&
      step == BuildTimelineStepId.download &&
      buildProgressPercent != null) {
    details.add(BuildTimelineDetail('已下载 $buildProgressPercent%'));
  }
  if (!sourceNone && step == BuildTimelineStepId.download && elevatedRetry) {
    details.add(const BuildTimelineDetail('正在以管理员身份拉取源码…'));
  }
  if (!sourceNone && step == BuildTimelineStepId.build && elevatedRetry) {
    details.add(const BuildTimelineDetail('正在以管理员身份执行构建…'));
  }
  return details;
}

/// 完成步骤的结果摘要详情（文件数量 / 总大小 / 新增 / 移除 + 版本同步）。
List<BuildTimelineDetail> buildCompletionDetails({
  required int fileCount,
  required int totalSize,
  required int addedCount,
  required int removedCount,
  String? syncedVersion,
}) {
  return <BuildTimelineDetail>[
    BuildTimelineDetail('文件数量：$fileCount'),
    BuildTimelineDetail('总大小：${formatBytes(totalSize)}'),
    BuildTimelineDetail('新增：$addedCount 个文件'),
    BuildTimelineDetail('移除：$removedCount 个文件'),
    if (syncedVersion != null)
      BuildTimelineDetail(
        '已自动同步版本：$syncedVersion',
        key: const Key('buildSyncedVersion'),
      ),
  ];
}

/// 阶段时间线视图：24 宽指示器列（圆点 / ProgressRing / 对勾 / 错误图标）
/// + 连接线 + 标签与详情行。
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
      child: SizedBox(
        width: 1,
        height: 8,
        child: ColoredBox(color: theme.resources.dividerStrokeColorDefault),
      ),
    );
  }

  Widget _buildStep(FluentThemeData theme, BuildTimelineStep step) {
    final Color labelColor = switch (step.status) {
      BuildTimelineStepStatus.pending ||
      BuildTimelineStepStatus.skipped => theme.resources.textFillColorTertiary,
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
          SizedBox(
            width: 24,
            height: 24,
            child: Center(child: _buildIndicator(theme, step.status)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.label,
                  style: TextStyle(fontSize: 13, color: labelColor),
                ),
                for (final BuildTimelineDetail detail in step.details)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail.text,
                      key: detail.key,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ),
                if (step.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      step.error!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.critical(theme.brightness),
                      ),
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
            border: Border.all(
              color: theme.resources.controlStrongFillColorDefault,
            ),
          ),
        );
      case BuildTimelineStepStatus.active:
        return const SizedBox(
          width: 16,
          height: 16,
          child: ProgressRing(strokeWidth: 2),
        );
      case BuildTimelineStepStatus.done:
        return Icon(
          FluentIcons.check_mark,
          size: 16,
          color: AppColors.success(theme.brightness),
        );
      case BuildTimelineStepStatus.failed:
        return Icon(
          FluentIcons.error,
          size: 16,
          color: AppColors.critical(theme.brightness),
        );
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

/// 构建对话框左栏：信息区（包名 / 源目录 / 编译器 / 运行库）+ 阶段时间线；
/// 提供 [onRetryElevated] 时在时间线下方追加提权重试入口。
class BuildStatusColumn extends StatelessWidget {
  const BuildStatusColumn({
    super.key,
    required this.packName,
    required this.sourcePath,
    required this.runtimeLabel,
    required this.steps,
    this.compilerLabel,
    this.onRetryElevated,
  });

  final String packName;

  /// 源目录（单行省略 + Tooltip 全量）。
  final String sourcePath;

  /// 运行库展示（`MD（动态）` / `MT（静态）` / `跟随配方`）。
  final String runtimeLabel;

  final List<BuildTimelineStep> steps;

  /// 编译器展示（`编译器：<名称> <版本>`）；环境未就绪时为 null 不显示。
  final String? compilerLabel;

  /// 提权重试回调；null 时不显示重试入口。
  final VoidCallback? onRetryElevated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('包名：$packName'),
        const SizedBox(height: 4),
        Tooltip(
          message: sourcePath,
          child: Text(
            '源目录：$sourcePath',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (compilerLabel != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(compilerLabel!, key: const Key('buildCompilerLabel')),
        ],
        const SizedBox(height: 4),
        Text('运行库：$runtimeLabel', key: const Key('buildRuntimeLabel')),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: BuildTimeline(steps: steps),
          ),
        ),
        if (onRetryElevated != null) ...<Widget>[
          const SizedBox(height: 8),
          const Text(
            '检测到临时目录权限问题（可能由内存盘等原因引起），可尝试以管理员身份重试。',
            key: Key('buildElevatedRetryHint'),
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Button(
            key: const Key('buildElevatedRetryButton'),
            onPressed: onRetryElevated,
            child: const Text('以管理员身份重试'),
          ),
        ],
      ],
    );
  }
}
