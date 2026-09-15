import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/controls/build_timeline.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildTimelineSteps', () {
    test('常规构建：已完成 / 进行中 / 未开始', () {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        activeStep: BuildTimelineStepId.build,
        sessionState: BuildTimelineSessionState.running,
        visitedSteps: const <BuildTimelineStepId>{
          BuildTimelineStepId.prepare,
          BuildTimelineStepId.download,
          BuildTimelineStepId.build,
        },
      );

      expect(
        steps.map((BuildTimelineStep step) => step.id),
        <BuildTimelineStepId>[
          BuildTimelineStepId.prepare,
          BuildTimelineStepId.download,
          BuildTimelineStepId.build,
          BuildTimelineStepId.includes,
          BuildTimelineStepId.remap,
          BuildTimelineStepId.done,
        ],
      );
      expect(
        steps.map((BuildTimelineStep step) => step.status),
        <BuildTimelineStepStatus>[
          BuildTimelineStepStatus.done,
          BuildTimelineStepStatus.done,
          BuildTimelineStepStatus.active,
          BuildTimelineStepStatus.pending,
          BuildTimelineStepStatus.pending,
          BuildTimelineStepStatus.pending,
        ],
      );
      expect(
        steps.map((BuildTimelineStep step) => step.label),
        <String>['准备环境', '下载源码', '执行构建', '检查头文件引用', '重新映射', '完成'],
      );
    });

    test('预构建配方：步骤表为 下载 → 分类 → 检查头文件引用 → 重新映射 → 完成', () {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        sourceNone: true,
        activeStep: BuildTimelineStepId.download,
        sessionState: BuildTimelineSessionState.running,
        visitedSteps: const <BuildTimelineStepId>{
          BuildTimelineStepId.download,
        },
      );

      expect(
        steps.map((BuildTimelineStep step) => step.id),
        <BuildTimelineStepId>[
          BuildTimelineStepId.download,
          BuildTimelineStepId.classify,
          BuildTimelineStepId.includes,
          BuildTimelineStepId.remap,
          BuildTimelineStepId.done,
        ],
      );
      expect(steps.first.label, '下载');
      expect(steps.first.status, BuildTimelineStepStatus.active);
    });

    test('越过但未执行的步骤显示跳过', () {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        sourceNone: true,
        activeStep: BuildTimelineStepId.includes,
        sessionState: BuildTimelineSessionState.running,
        visitedSteps: const <BuildTimelineStepId>{
          BuildTimelineStepId.download,
          BuildTimelineStepId.includes,
        },
      );

      final BuildTimelineStep classify = steps.singleWhere(
        (BuildTimelineStep step) => step.id == BuildTimelineStepId.classify,
      );
      expect(classify.status, BuildTimelineStepStatus.skipped);
      expect(
        steps.first.status,
        BuildTimelineStepStatus.done,
        reason: '已执行的下载步骤保持完成',
      );
    });

    test('失败会话隐藏失败步骤之后的步骤并携带失败文本', () {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        activeStep: BuildTimelineStepId.remap,
        sessionState: BuildTimelineSessionState.failed,
        visitedSteps: const <BuildTimelineStepId>{
          BuildTimelineStepId.prepare,
          BuildTimelineStepId.download,
          BuildTimelineStepId.build,
          BuildTimelineStepId.includes,
          BuildTimelineStepId.remap,
        },
        failureText: '构建失败：错误 X',
      );

      expect(steps, hasLength(5));
      expect(steps.last.id, BuildTimelineStepId.remap);
      expect(steps.last.status, BuildTimelineStepStatus.failed);
      expect(steps.last.error, '构建失败：错误 X');
      expect(
        steps.map((BuildTimelineStep step) => step.id),
        isNot(contains(BuildTimelineStepId.done)),
      );
    });

    test('完成会话在完成步骤附加结果摘要详情', () {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        activeStep: BuildTimelineStepId.done,
        sessionState: BuildTimelineSessionState.completed,
        visitedSteps: BuildTimelineStepId.values.toSet(),
        doneDetails: const <BuildTimelineDetail>[
          BuildTimelineDetail('文件数量：2'),
          BuildTimelineDetail('总大小：2.0 KB', key: Key('buildSyncedVersion')),
        ],
      );

      final BuildTimelineStep done = steps.last;
      expect(done.status, BuildTimelineStepStatus.done);
      expect(
        done.details.map((BuildTimelineDetail detail) => detail.text),
        <String>['文件数量：2', '总大小：2.0 KB'],
      );
      expect(done.details.last.key, const Key('buildSyncedVersion'));
    });

    test('进行中步骤附加活动详情', () {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        activeStep: BuildTimelineStepId.prepare,
        sessionState: BuildTimelineSessionState.running,
        activeDetails: const <BuildTimelineDetail>[
          BuildTimelineDetail('正在下载 cmake：50%'),
        ],
      );

      expect(steps.first.details.single.text, '正在下载 cmake：50%');
    });
  });

  group('buildActiveStepDetails', () {
    test('准备环境阶段展示工具下载进度并带 Key', () {
      final List<BuildTimelineDetail> details = buildActiveStepDetails(
        step: BuildTimelineStepId.prepare,
        preparing: true,
        sourceNone: false,
        downloadProgress: const ToolDownloadProgress(
          name: 'cmake',
          receivedBytes: 1024,
          totalBytes: 4096,
          bytesPerSecond: 0,
        ),
      );

      expect(details.single.text, '正在下载 cmake：25%（1.0 KB / 4.0 KB）');
      expect(details.single.key, const Key('buildDownloadProgress'));
    });

    test('预构建配方下载步骤展示已下载百分比', () {
      final List<BuildTimelineDetail> details = buildActiveStepDetails(
        step: BuildTimelineStepId.download,
        preparing: false,
        sourceNone: true,
        buildProgressPercent: 42,
      );

      expect(details.single.text, '已下载 42%');
      expect(details.single.key, isNull);
    });

    test('管理员重试期间下载/构建步骤切管理员文案', () {
      final List<BuildTimelineDetail> download = buildActiveStepDetails(
        step: BuildTimelineStepId.download,
        preparing: false,
        sourceNone: false,
        elevatedRetry: true,
      );
      final List<BuildTimelineDetail> build = buildActiveStepDetails(
        step: BuildTimelineStepId.build,
        preparing: false,
        sourceNone: false,
        elevatedRetry: true,
      );

      expect(download.single.text, '正在以管理员身份拉取源码…');
      expect(build.single.text, '正在以管理员身份执行构建…');
    });
  });

  group('buildCompletionDetails', () {
    test('结果摘要含数量/大小/增删与版本同步', () {
      final List<BuildTimelineDetail> details = buildCompletionDetails(
        fileCount: 2,
        totalSize: 2048,
        addedCount: 1,
        removedCount: 3,
        syncedVersion: '1.2.3',
      );

      expect(
        details.map((BuildTimelineDetail detail) => detail.text),
        <String>[
          '文件数量：2',
          '总大小：2.0 KB',
          '新增：1 个文件',
          '移除：3 个文件',
          '已自动同步版本：1.2.3',
        ],
      );
      expect(details.last.key, const Key('buildSyncedVersion'));
    });

    test('未同步版本时省略版本行', () {
      final List<BuildTimelineDetail> details = buildCompletionDetails(
        fileCount: 0,
        totalSize: 0,
        addedCount: 0,
        removedCount: 0,
      );

      expect(details, hasLength(4));
    });
  });

  group('BuildTimeline', () {
    testWidgets('渲染步骤 Key、标签与状态指示器', (tester) async {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        activeStep: BuildTimelineStepId.build,
        sessionState: BuildTimelineSessionState.running,
        visitedSteps: const <BuildTimelineStepId>{
          BuildTimelineStepId.prepare,
          BuildTimelineStepId.download,
          BuildTimelineStepId.build,
        },
      );

      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: SizedBox(width: 260, child: BuildTimeline(steps: steps)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('buildTimeline')), findsOneWidget);
      expect(find.text('准备环境'), findsOneWidget);
      expect(find.text('下载源码'), findsOneWidget);
      expect(find.text('执行构建'), findsOneWidget);
      expect(find.text('检查头文件引用'), findsOneWidget);
      expect(find.text('重新映射'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.byIcon(FluentIcons.check_mark), findsNWidgets(2));
      expect(find.byIcon(FluentIcons.error), findsNothing);
    });

    testWidgets('失败步骤渲染错误图标与错误文本', (tester) async {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        activeStep: BuildTimelineStepId.download,
        sessionState: BuildTimelineSessionState.failed,
        visitedSteps: const <BuildTimelineStepId>{
          BuildTimelineStepId.prepare,
          BuildTimelineStepId.download,
        },
        failureText: '构建失败：拉取源码失败',
      );

      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: SizedBox(width: 260, child: BuildTimeline(steps: steps)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(FluentIcons.error), findsOneWidget);
      expect(find.text('构建失败：拉取源码失败'), findsOneWidget);
      expect(find.byType(ProgressRing), findsNothing);
      expect(find.text('完成'), findsNothing, reason: '失败步骤之后的步骤隐藏');
    });

    testWidgets('跳过步骤不渲染对勾与进度指示', (tester) async {
      final List<BuildTimelineStep> steps = buildTimelineSteps(
        sourceNone: true,
        activeStep: BuildTimelineStepId.includes,
        sessionState: BuildTimelineSessionState.running,
        visitedSteps: const <BuildTimelineStepId>{
          BuildTimelineStepId.download,
          BuildTimelineStepId.includes,
        },
      );

      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: SizedBox(width: 260, child: BuildTimeline(steps: steps)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(FluentIcons.check_mark), findsOneWidget);
      expect(find.byIcon(FluentIcons.error), findsNothing);
      expect(find.byType(ProgressRing), findsOneWidget);
    });
  });
}
