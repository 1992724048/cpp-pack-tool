import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/elevated_build.dart';
import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/controls/build_pack_dialog.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('构建成功后依次经历各阶段并显示完成统计', (tester) async {
    final Completer<BuildEnvironment> prepareGate =
        Completer<BuildEnvironment>();
    final Completer<void> downloadGate = Completer<void>();
    final Completer<void> buildGate = Completer<void>();
    final Completer<List<FileModel>> scanCompleter =
        Completer<List<FileModel>>();
    final Completer<void> applyCompleter = Completer<void>();
    PackModel? applied;

    await _pumpDialog(
      tester,
      prepare: (
        PackModel pack, {
        ToolDownloadProgressCallback? onDownloadProgress,
      }) => prepareGate.future,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onStage(PackBuildStage.downloading);
            await downloadGate.future;
            onStage(PackBuildStage.building);
            await buildGate.future;
          },
      scanFiles: (_) => scanCompleter.future,
      onApply: (PackModel pack) {
        applied = pack;
        return applyCompleter.future;
      },
    );

    expect(find.byKey(const Key('buildPackDialog')), findsOneWidget);
    expect(find.text('构建'), findsOneWidget);
    expect(find.text('包名：demo'), findsOneWidget);
    expect(find.text(r'源目录：C:\libs\demo'), findsOneWidget);
    expect(find.text('正在准备构建环境…'), findsOneWidget);
    expect(find.byKey(const Key('buildCompilerLabel')), findsNothing);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    prepareGate.complete(_environment());
    await tester.pump();
    expect(find.text('正在下载源码…'), findsOneWidget);
    expect(find.byKey(const Key('buildCompilerLabel')), findsOneWidget);
    expect(find.text('编译器：ICX 2026.1.1'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    downloadGate.complete();
    await tester.pump();
    expect(find.text('正在执行构建…'), findsOneWidget);
    expect(find.text('编译器：ICX 2026.1.1'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    buildGate.complete();
    await tester.pump();
    expect(find.text('正在重新映射…'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    scanCompleter.complete(<FileModel>[
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 1024),
      FileModel(name: 'logo.svg', path: 'assets/logo.svg', size: 1024),
    ]);
    await tester.pump();
    expect(find.text('正在重新映射…'), findsOneWidget);
    expect(applied, isNotNull);
    expect(_closeButton(tester).onPressed, isNull);

    applyCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建完成'), findsOneWidget);
    expect(find.text('文件数量：2'), findsOneWidget);
    expect(find.text('总大小：2.0 KB'), findsOneWidget);
    expect(find.text('新增：2 个文件'), findsOneWidget);
    expect(find.text('移除：1 个文件'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNotNull);

    expect(applied!.name, 'demo');
    expect(applied!.version, '1.0.0');
    expect(applied!.author, 'tester');
    expect(applied!.description, '描述');
    expect(applied!.license, 'MIT');
    expect(applied!.sourcePath, r'C:\libs\demo');
    expect(applied!.files, hasLength(2));
    expect(applied!.iconPath, 'assets/logo.svg');
  });

  testWidgets('构建失败时显示错误与输出尾部且不再扫描', (tester) async {
    int scanCount = 0;

    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            throw const PackBuildException(
              '构建失败（退出码 1）',
              outputTail: 'Traceback (most recent call last):\nboom',
            );
          },
      scanFiles: (String sourcePath) async {
        scanCount++;
        return const <FileModel>[];
      },
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：构建失败（退出码 1）'), findsOneWidget);
    expect(find.textContaining('boom', findRichText: true), findsOneWidget);
    expect(scanCount, 0);
    expect(find.byType(ProgressRing), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('重新扫描失败时显示去前缀错误', (tester) async {
    await _pumpDialog(
      tester,
      build: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
      scanFiles: (String sourcePath) async => throw ArgumentError('目录不存在: X'),
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：目录不存在: X'), findsOneWidget);
    expect(find.textContaining('Invalid argument(s):'), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('应用更新失败时显示错误', (tester) async {
    await _pumpDialog(
      tester,
      build: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async => throw Exception('写入失败'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：Exception: 写入失败'), findsOneWidget);
    expect(find.text('构建完成'), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('构建成功后缺少源目录信息时显示错误', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(sourcePath: null),
      build: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：该包缺少源目录信息'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('完成后点击关闭按钮关闭对话框', (tester) async {
    await _pumpDialog(
      tester,
      build: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('buildPackDialog')), findsNothing);
  });

  testWidgets('准备环境失败时显示错误且不执行构建', (tester) async {
    int buildCount = 0;

    await _pumpDialog(
      tester,
      prepare:
          (
            PackModel pack, {
            ToolDownloadProgressCallback? onDownloadProgress,
          }) async => throw const BuildPreparationException(
            '未检测到可用编译器（优先级：icx > clang-cl > msvc）',
          ),
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            buildCount++;
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('构建失败：未检测到可用编译器（优先级：icx > clang-cl > msvc）'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('buildCompilerLabel')), findsNothing);
    expect(buildCount, 0);
    expect(find.byType(ProgressRing), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('准备环境结果透传给构建函数并显示 MSVC 标签', (tester) async {
    final BuildEnvironment prepared = _environment(
      kind: CompilerKind.msvc,
      version: '14.44.35207',
    );
    Map<String, String>? received;

    await _pumpDialog(
      tester,
      prepare: (
        PackModel pack, {
        ToolDownloadProgressCallback? onDownloadProgress,
      }) async => prepared,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            received = environment;
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(received, same(prepared.environment));
    expect(find.text('编译器：MSVC 14.44.35207'), findsOneWidget);
  });

  testWidgets('无输出时显示等待占位', (tester) async {
    final Completer<void> buildGate = Completer<void>();

    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onStage(PackBuildStage.building);
            await buildGate.future;
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('buildOutputPanel')), findsOneWidget);
    expect(find.text('等待输出…'), findsOneWidget);

    buildGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('构建输出逐行展示并高亮 ERROR/WARNING/INFO', (tester) async {
    List<String>? receivedLines;

    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            receivedLines = <String>[
              'INFO: 开始构建',
              'WARNING: 未启用 LTO',
              'error: 编译失败',
              '普通输出',
            ];
            for (final String line in receivedLines!) {
              onOutput?.call(line);
            }
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(receivedLines, isNotNull, reason: '构建函数应收到输出回调');
    expect(find.text('等待输出…'), findsNothing);
    for (final String line in receivedLines!) {
      expect(
        find.textContaining(line, findRichText: true),
        findsOneWidget,
        reason: '面板应展示输出行：$line',
      );
    }

    expect(_outputLine(tester, 'INFO: 开始构建'), UCColors.flavor.blue);
    expect(_outputLine(tester, 'WARNING: 未启用 LTO'), UCColors.flavor.peach);
    expect(findOutputKeyword('error: 编译失败')?.keyword, 'ERROR');
    expect(_outputLine(tester, 'error: 编译失败'), UCColors.flavor.red);
    expect(_outputLine(tester, '普通输出'), UCColors.flavor.text);
  });

  testWidgets('失败时保留流式输出并补充尾部', (tester) async {
    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onOutput?.call('ERROR: 即将失败');
            throw const PackBuildException(
              '构建失败（退出码 1）',
              outputTail: 'trace line A\ntrace line B',
            );
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：构建失败（退出码 1）'), findsOneWidget);
    expect(
      find.textContaining('trace line A', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('trace line B', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('ERROR: 即将失败', findRichText: true),
      findsOneWidget,
    );
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('失败时已在面板中的输出行不重复补充', (tester) async {
    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onOutput?.call('line one');
            onOutput?.call('line two');
            throw const PackBuildException(
              '构建失败（退出码 1）',
              outputTail: 'line one\nline two\nline three',
            );
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('line one', findRichText: true), findsOneWidget);
    expect(find.textContaining('line two', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('line three', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('输出区共享横向滚动且鼠标可拖拽', (tester) async {
    final String lineA = 'first-${'a' * 160}';
    final String lineB = 'second-${'b' * 160}';

    await _pumpDialog(
      tester,
      build: _emitLines(<String>[lineA, lineB]),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Scrollbar scrollbar = tester.widget<Scrollbar>(
      find.byKey(const Key('buildOutputHorizontalScrollbar')),
    );
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.bottom);

    final ScrollableState horizontal = _horizontalOutputScrollable(tester);
    expect(horizontal.position.pixels, 0);
    expect(horizontal.position.maxScrollExtent, greaterThan(0));

    final Finder findA = find.textContaining(lineA, findRichText: true);
    final Finder findB = find.textContaining(lineB, findRichText: true);
    final double lineABefore = tester.getTopLeft(findA).dx;
    final double lineBBefore = tester.getTopLeft(findB).dx;

    final Rect panel = tester.getRect(
      find.byKey(const Key('buildOutputPanel')),
    );
    await tester.dragFrom(
      Offset(panel.left + 80, panel.top + 80),
      const Offset(-150, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(horizontal.position.pixels, greaterThan(0));
    final double lineAShift = lineABefore - tester.getTopLeft(findA).dx;
    final double lineBShift = lineBBefore - tester.getTopLeft(findB).dx;
    expect(lineAShift, greaterThan(0));
    expect(lineBShift, closeTo(lineAShift, 0.5));

    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('日志过滤大小写不敏感且清空恢复', (tester) async {
    const List<String> lines = <String>[
      'INFO: 开始构建',
      'WARNING: 未启用 LTO',
      'error: 编译失败',
      '普通输出',
    ];

    await _pumpDialog(
      tester,
      build: _emitLines(lines),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('buildOutputFilter')), findsOneWidget);
    expect(find.byKey(const Key('buildOutputFilterClear')), findsNothing);

    await tester.enterText(find.byKey(const Key('buildOutputFilter')), 'ERROR');
    await tester.pump();

    expect(
      find.textContaining('error: 编译失败', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('普通输出', findRichText: true), findsNothing);
    expect(find.textContaining('INFO: 开始构建', findRichText: true), findsNothing);
    expect(_outputLine(tester, 'error: 编译失败'), UCColors.flavor.red);

    await tester.tap(find.byKey(const Key('buildOutputFilterClear')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    for (final String line in lines) {
      expect(
        find.textContaining(line, findRichText: true),
        findsOneWidget,
        reason: '清空过滤后应恢复显示：$line',
      );
    }
    expect(find.byKey(const Key('buildOutputFilterClear')), findsNothing);
  });

  testWidgets('日志过滤无匹配时显示无匹配行提示', (tester) async {
    await _pumpDialog(
      tester,
      build: _emitLines(const <String>['INFO: 开始构建', '普通输出']),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byKey(const Key('buildOutputFilter')), '没有的内容');
    await tester.pump();

    expect(find.text('无匹配行'), findsOneWidget);
    expect(find.text('等待输出…'), findsNothing);
    expect(find.textContaining('普通输出', findRichText: true), findsNothing);
  });

  testWidgets('无输出时过滤输入保持等待占位', (tester) async {
    final Completer<void> buildGate = Completer<void>();

    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onStage(PackBuildStage.building);
            await buildGate.future;
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('等待输出…'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('buildOutputFilter')), 'error');
    await tester.pump();

    expect(find.text('等待输出…'), findsOneWidget);
    expect(find.text('无匹配行'), findsNothing);

    buildGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('准备环境阶段展示工具下载进度与瞬时速度', (tester) async {
    final Completer<BuildEnvironment> prepareGate =
        Completer<BuildEnvironment>();
    ToolDownloadProgressCallback? progressCallback;

    await _pumpDialog(
      tester,
      prepare:
          (PackModel pack, {ToolDownloadProgressCallback? onDownloadProgress}) {
            progressCallback = onDownloadProgress;
            return prepareGate.future;
          },
      build: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );

    expect(find.text('正在准备构建环境…'), findsOneWidget);
    expect(find.byKey(const Key('buildDownloadProgress')), findsNothing);
    expect(progressCallback, isNotNull);

    progressCallback!(
      const ToolDownloadProgress(
        name: 'cmake',
        receivedBytes: 0,
        totalBytes: 4 * 1024 * 1024,
        bytesPerSecond: 0,
      ),
    );
    await tester.pump();
    expect(find.text('正在下载 cmake：0%（0 B / 4.0 MB）'), findsOneWidget);

    progressCallback!(
      const ToolDownloadProgress(
        name: 'cmake',
        receivedBytes: 2 * 1024 * 1024,
        totalBytes: 4 * 1024 * 1024,
        bytesPerSecond: 1024 * 1024,
      ),
    );
    await tester.pump();
    expect(
      find.text('正在下载 cmake：50%（2.0 MB / 4.0 MB），1.0 MB/s'),
      findsOneWidget,
    );

    progressCallback!(
      const ToolDownloadProgress(
        name: 'ninja',
        receivedBytes: 512,
        totalBytes: -1,
        bytesPerSecond: 0,
      ),
    );
    await tester.pump();
    expect(find.text('正在下载 ninja：512 B'), findsOneWidget);

    prepareGate.complete(_environment());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('buildDownloadProgress')), findsNothing);
  });

  testWidgets('预构建包阶段：正在下载 → 正在分类 → 正在重新映射 → 完成', (tester) async {
    final Completer<void> downloadGate = Completer<void>();
    final Completer<void> classifyGate = Completer<void>();
    final Completer<void> buildGate = Completer<void>();
    final Completer<List<FileModel>> scanCompleter =
        Completer<List<FileModel>>();
    final Completer<void> applyCompleter = Completer<void>();

    await _pumpDialog(
      tester,
      sourceNone: true,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onStage(PackBuildStage.downloading);
            await downloadGate.future;
            onStage(PackBuildStage.building);
            onOutput?.call(
              '[openvino] progress 42.0% (88000000/208000000 bytes)',
            );
            await classifyGate.future;
            onOutput?.call('[cnp_build_support] classify: C:\\src -> C:\\out');
            await buildGate.future;
          },
      scanFiles: (_) => scanCompleter.future,
      onApply: (PackModel pack) => applyCompleter.future,
    );

    expect(find.text('正在下载…'), findsOneWidget);
    expect(find.text('正在准备构建环境…'), findsNothing);
    expect(find.text('正在下载源码…'), findsNothing);

    downloadGate.complete();
    await tester.pump();
    expect(find.text('正在下载…（42%）'), findsOneWidget);
    expect(find.text('正在执行构建…'), findsNothing);

    classifyGate.complete();
    await tester.pump();
    expect(find.text('正在分类…'), findsOneWidget);

    buildGate.complete();
    await tester.pump();
    expect(find.text('正在重新映射…'), findsOneWidget);

    scanCompleter.complete(const <FileModel>[]);
    await tester.pump();
    applyCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('构建完成'), findsOneWidget);
  });

  test('extractProgressPercent 通用提取 progress 百分比', () {
    expect(extractProgressPercent('[openvino] progress 42.0% (1/2 bytes)'), 42);
    expect(extractProgressPercent('progress: 7%'), 7);
    expect(extractProgressPercent('Receiving objects: 45% (9/20)'), isNull);
    expect(extractProgressPercent('progress 120%'), isNull);
    expect(extractProgressPercent('无进度行'), isNull);
  });

  test('isClassifyStartLine 匹配分类标记前缀', () {
    expect(
      isClassifyStartLine('[cnp_build_support] classify: C:\\src -> C:\\out'),
      isTrue,
    );
    expect(isClassifyStartLine('  [cnp_build_support] classify: x'), isTrue);
    expect(
      isClassifyStartLine('[cnp_build_support] cmake_configure: x'),
      isFalse,
    );
  });

  testWidgets('构建回调的仓库版本写入应用包', (tester) async {
    PackModel? applied;

    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onSourceVersion?.call('v3.1.4');
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {
        applied = pack;
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(applied, isNotNull);
    expect(applied!.sourceVersion, 'v3.1.4');
  });

  testWidgets('未收到版本回调时保留原记录', (tester) async {
    PackModel? applied;

    await _pumpDialog(
      tester,
      pack: _pack()..sourceVersion = 'v1.0.0',
      build: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {
        applied = pack;
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(applied, isNotNull);
    expect(applied!.sourceVersion, 'v1.0.0');
  });

  testWidgets('构建成功后先检查头文件引用再重新映射并随关闭返回报告', (tester) async {
    final List<String> order = <String>[];
    final Completer<HeaderIncludeFixReport> fixGate =
        Completer<HeaderIncludeFixReport>();
    HeaderIncludeFixReport? closedWith;
    const HeaderIncludeFixReport report = HeaderIncludeFixReport(
      fixed: <HeaderIncludeFix>[
        HeaderIncludeFix(
          filePath: 'src/gtest/gtest-all.cc',
          line: 2,
          from: 'src/gtest.cc',
          to: 'gtest.cc',
        ),
      ],
    );

    await _pumpDialog(
      tester,
      onResult: (HeaderIncludeFixReport? value) => closedWith = value,
      fixIncludes: (String sourcePath, {required String packageName}) {
        order.add('fix:$sourcePath:$packageName');
        return fixGate.future;
      },
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            order.add('build');
          },
      scanFiles: (String sourcePath) async {
        order.add('scan');
        return const <FileModel>[];
      },
      onApply: (PackModel pack) async {
        order.add('apply');
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(order, <String>['build', r'fix:C:\libs\demo:demo']);
    expect(find.text('正在检查头文件引用…'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    fixGate.complete(report);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(order, <String>['build', r'fix:C:\libs\demo:demo', 'scan', 'apply']);
    expect(find.text('构建完成'), findsOneWidget);

    await tester.tap(find.byKey(const Key('buildCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(closedWith, same(report));
    expect(find.byKey(const Key('buildPackDialog')), findsNothing);
  });

  testWidgets('头文件引用检查失败不阻断重新映射并在输出面板提示', (tester) async {
    int scanCount = 0;

    await _pumpDialog(
      tester,
      fixIncludes: (String sourcePath, {required String packageName}) async =>
          throw const FileSystemException(': 目录不可访问'),
      build: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
      scanFiles: (String sourcePath) async {
        scanCount++;
        return const <FileModel>[];
      },
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(scanCount, 1);
    expect(find.text('构建完成'), findsOneWidget);
    expect(
      find.textContaining('头文件引用检查失败', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('命中临时目录权限特征时显示提权重试入口', (tester) async {
    await _pumpDialog(
      tester,
      retryElevated: _noopElevatedRunner(),
      build: _permissionFailureBuild(),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('buildElevatedRetryButton')), findsOneWidget);
    expect(find.byKey(const Key('buildElevatedRetryHint')), findsOneWidget);
    expect(find.text('以管理员身份重试'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('未命中特征或未提供提权入口时不显示按钮', (tester) async {
    await _pumpDialog(
      tester,
      retryElevated: _noopElevatedRunner(),
      build:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            throw const PackBuildException(
              '构建失败（退出码 1）',
              outputTail: 'error: cannot find file foo.h',
            );
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('buildElevatedRetryButton')), findsNothing);
    expect(find.byKey(const Key('buildElevatedRetryHint')), findsNothing);

    await _pumpDialog(
      tester,
      build: _permissionFailureBuild(),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const Key('buildElevatedRetryButton')),
      findsNothing,
      reason: '未注入提权入口（retryElevated 为 null）时不显示按钮',
    );
  });

  testWidgets('点击以管理员身份重试成功后继续重新映射并完成', (tester) async {
    final List<String> order = <String>[];
    BuildEnvironment? receivedEnvironment;

    await _pumpDialog(
      tester,
      retryElevated:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            required BuildEnvironment buildEnvironment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            order.add('elevated');
            receivedEnvironment = buildEnvironment;
            onStage(PackBuildStage.downloading);
            onOutput?.call('管理员构建输出');
            onStage(PackBuildStage.building);
          },
      build: _permissionFailureBuild(),
      scanFiles: (String sourcePath) async {
        order.add('scan');
        return const <FileModel>[];
      },
      onApply: (PackModel pack) async => order.add('apply'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildElevatedRetryButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(order, <String>['elevated', 'scan', 'apply']);
    expect(receivedEnvironment?.environment['CNP_COMPILER_KIND'], 'icx');
    expect(find.text('构建完成'), findsOneWidget);
    expect(find.byKey(const Key('buildElevatedRetryButton')), findsNothing);
    expect(find.textContaining('管理员构建输出', findRichText: true), findsOneWidget);
  });

  testWidgets('提权重试期间显示管理员阶段文案', (tester) async {
    final Completer<void> downloadGate = Completer<void>();
    final Completer<void> buildGate = Completer<void>();

    await _pumpDialog(
      tester,
      retryElevated:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            required BuildEnvironment buildEnvironment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onStage(PackBuildStage.downloading);
            await downloadGate.future;
            onStage(PackBuildStage.building);
            await buildGate.future;
          },
      build: _permissionFailureBuild(),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildElevatedRetryButton')));
    await tester.pump();
    expect(find.text('正在以管理员身份拉取源码…'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    downloadGate.complete();
    await tester.pump();
    expect(find.text('正在以管理员身份执行构建…'), findsOneWidget);

    buildGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('构建完成'), findsOneWidget);
  });

  testWidgets('提权重试被取消时显示提示并保留重试入口', (tester) async {
    await _pumpDialog(
      tester,
      retryElevated:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            required BuildEnvironment buildEnvironment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            throw const PackBuildException('已取消以管理员身份重试（UAC 授权被拒绝）');
          },
      build: _permissionFailureBuild(),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildElevatedRetryButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：已取消以管理员身份重试（UAC 授权被拒绝）'), findsOneWidget);
    expect(find.byKey(const Key('buildElevatedRetryButton')), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('提权重试失败保留输出并回到失败态', (tester) async {
    int scanCount = 0;

    await _pumpDialog(
      tester,
      retryElevated:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            required BuildEnvironment buildEnvironment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            onOutput?.call('管理员构建输出行');
            throw const PackBuildException(
              '以管理员身份构建失败（退出码 3）',
              outputTail: '管理员输出尾部',
            );
          },
      build: _permissionFailureBuild(),
      scanFiles: (String sourcePath) async {
        scanCount++;
        return const <FileModel>[];
      },
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildElevatedRetryButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：以管理员身份构建失败（退出码 3）'), findsOneWidget);
    expect(find.textContaining('管理员构建输出行', findRichText: true), findsOneWidget);
    expect(find.textContaining('管理员输出尾部', findRichText: true), findsOneWidget);
    expect(scanCount, 0);
    expect(find.byKey(const Key('buildElevatedRetryButton')), findsOneWidget);
  });
}

/// 失败于临时目录权限特征的构建函数（ICX `error #10026`）。
PackBuildRunner _permissionFailureBuild() {
  return (
    PackModel pack,
    void Function(PackBuildStage) onStage, {
    Map<String, String>? environment,
    void Function(String line)? onOutput,
    void Function(String version)? onSourceVersion,
  }) async {
    throw const PackBuildException(
      '构建失败（退出码 1）',
      outputTail: 'icx: error #10026: error generating temporary file',
    );
  };
}

/// 不做任何事的提权构建替身（仅用于让按钮可渲染）。
ElevatedPackBuildRunner _noopElevatedRunner() {
  return (
    PackModel pack,
    void Function(PackBuildStage) onStage, {
    required BuildEnvironment buildEnvironment,
    void Function(String line)? onOutput,
    void Function(String version)? onSourceVersion,
  }) async {};
}

/// 输出面板中某行的关键字颜色（无关键字行取常规文本色）。
Color _outputLine(WidgetTester tester, String line) {
  return outputLineColor(
    tester
        .widget<RichText>(find.textContaining(line, findRichText: true))
        .text
        .toPlainText(),
  );
}

BuildEnvironment _environment({
  CompilerKind kind = CompilerKind.icx,
  String version = '2026.1.1',
}) {
  return BuildEnvironment(
    compiler: DetectedCompiler(
      kind: kind,
      version: version,
      executablePath: r'C:\tools\icx-cl.exe',
      environmentScript: null,
    ),
    environment: const <String, String>{
      'CNP_COMPILER_KIND': 'icx',
      'Path': r'C:\tools\bin',
    },
    cmakePath: r'C:\tools\cmake\bin\cmake.exe',
    ninjaPath: r'C:\tools\ninja\ninja.exe',
    toolsDir: r'C:\tools',
  );
}

PackModel _pack({String? sourcePath = r'C:\libs\demo'}) {
  return PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      description: '描述',
      license: 'MIT',
      sourcePath: sourcePath,
    )
    ..files = <FileModel>[
      FileModel(name: 'old.cpp', path: 'src/old.cpp', size: 100),
    ];
}

Button _closeButton(WidgetTester tester) =>
    tester.widget<Button>(find.byKey(const Key('buildCloseButton')));

PackBuildRunner _emitLines(List<String> lines) {
  return (
    PackModel pack,
    void Function(PackBuildStage) onStage, {
    Map<String, String>? environment,
    void Function(String line)? onOutput,
    void Function(String version)? onSourceVersion,
  }) async {
    for (final String line in lines) {
      onOutput?.call(line);
    }
  };
}

ScrollableState _horizontalOutputScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(
    find.ancestor(
      of: find.byKey(const Key('buildOutputContent')),
      matching: find.byWidgetPredicate(
        (Widget widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    ),
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required PackBuildRunner build,
  BuildPackPrepare? prepare,
  required Future<List<FileModel>> Function(String sourcePath) scanFiles,
  required Future<void> Function(PackModel pack) onApply,
  PackModel? pack,
  bool sourceNone = false,
  PackHeaderIncludeFixer? fixIncludes,
  ElevatedPackBuildRunner? retryElevated,
  ValueChanged<HeaderIncludeFixReport?>? onResult,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () async {
              final HeaderIncludeFixReport? result =
                  await showDialog<HeaderIncludeFixReport>(
                    context: context,
                    builder: (_) => BuildPackDialog(
                      pack: pack ?? _pack(),
                      sourceNone: sourceNone,
                      build: build,
                      prepare:
                          prepare ??
                          (
                            PackModel pack, {
                            ToolDownloadProgressCallback? onDownloadProgress,
                          }) async => _environment(),
                      scanFiles: scanFiles,
                      onApply: onApply,
                      fixIncludes: fixIncludes ?? _emptyFixIncludes,
                      retryElevated: retryElevated,
                    ),
                  );
              onResult?.call(result);
            },
            child: const Text('打开对话框'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开对话框'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<HeaderIncludeFixReport> _emptyFixIncludes(
  String sourcePath, {
  required String packageName,
}) async => const HeaderIncludeFixReport();
