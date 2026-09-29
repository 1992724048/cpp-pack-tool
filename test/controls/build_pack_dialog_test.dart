import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/controls/build_output_panel.dart';
import 'package:cpp_nuget_pack/controls/build_pack_dialog.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/shared/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('构建成功后依次经历各阶段并显示完成统计', (tester) async {
    final Completer<BuildEnvironment> prepareGate =
        Completer<BuildEnvironment>();
    final Completer<void> buildGate = Completer<void>();
    final Completer<List<FileModel>> scanCompleter =
        Completer<List<FileModel>>();
    final Completer<void> applyCompleter = Completer<void>();
    PackModel? applied;

    await _pumpDialog(
      tester,
      prepare: (PackModel pack) => prepareGate.future,
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
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
    expect(_stepIsActive(tester, 'prepare'), isTrue);
    expect(find.text('准备环境'), findsOneWidget);
    expect(find.text('准备源码'), findsOneWidget);
    expect(find.text('执行构建'), findsOneWidget);
    expect(find.text('检查头文件引用'), findsOneWidget);
    expect(find.text('重新映射'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.byKey(const Key('buildCompilerLabel')), findsNothing);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    prepareGate.complete(_environment());
    await tester.pump();
    expect(
      _stepIsActive(tester, 'build'),
      isTrue,
      reason: '备源阶段已消失：环境就绪后整个会话就是构建',
    );
    expect(
      find.text('准备源码'),
      findsOneWidget,
      reason: '该步骤仍留在时间线里（跳过态），让用户知道曾有此阶段',
    );
    expect(find.byKey(const Key('buildCompilerLabel')), findsOneWidget);
    expect(find.text('编译器：ICX 2026.1.1'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    buildGate.complete();
    await tester.pump();
    expect(_stepIsActive(tester, 'remap'), isTrue);
    expect(_closeButton(tester).onPressed, isNull);

    scanCompleter.complete(<FileModel>[
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 1024),
      FileModel(name: 'logo.svg', path: 'assets/logo.svg', size: 1024),
    ]);
    await tester.pump();
    expect(_stepIsActive(tester, 'remap'), isTrue);
    expect(applied, isNotNull);
    expect(_closeButton(tester).onPressed, isNull);

    applyCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_stepIsDone(tester, 'done'), isTrue);
    expect(find.text('完成'), findsOneWidget);
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
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
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
    expect(
      _stepIsFailed(tester, 'build'),
      isTrue,
      reason: '环境已就绪，失败发生在构建步骤而非准备步骤',
    );
    expect(find.textContaining('boom', findRichText: true), findsOneWidget);
    expect(scanCount, 0);
    expect(find.byType(ProgressRing), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('重新扫描失败时显示去前缀错误', (tester) async {
    await _pumpDialog(
      tester,
      build: (
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
      }) async {},
      scanFiles: (String sourcePath) async => throw ArgumentError('目录不存在: X'),
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：目录不存在: X'), findsOneWidget);
    expect(_stepIsFailed(tester, 'remap'), isTrue);
    expect(find.text('完成'), findsNothing, reason: '失败步骤之后的步骤隐藏');
    expect(find.textContaining('Invalid argument(s):'), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('应用更新失败时显示错误', (tester) async {
    await _pumpDialog(
      tester,
      build: (
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
      }) async {},
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async => throw Exception('写入失败'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：Exception: 写入失败'), findsOneWidget);
    expect(find.text('完成'), findsNothing, reason: '失败步骤之后的步骤隐藏');
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('构建成功后缺少源目录信息时显示错误', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(sourcePath: null),
      build: (
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
      }) async {},
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：该包缺少源目录信息'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('构建失败后关闭返回失败条目', (tester) async {
    BuildDialogResult? closedWith;

    await _pumpDialog(
      tester,
      onResult: (BuildDialogResult? value) => closedWith = value,
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
            throw const PackBuildException('构建失败（退出码 1）');
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(closedWith, isNotNull);
    expect(closedWith!.fixReport, isNull);
    final HistoryModel entry = closedWith!.failureEntry!;
    expect(entry.type, HistoryType.built);
    expect(entry.message, '构建失败：构建失败（退出码 1）');
  });

  testWidgets('失败条目取首行、去换行且超 120 字符截断', (tester) async {
    BuildDialogResult? closedWith;
    final DateTime now = DateTime(2026, 9, 16, 10, 30);

    await _pumpDialog(
      tester,
      now: () => now,
      onResult: (BuildDialogResult? value) => closedWith = value,
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
            throw PackBuildException('${'x' * 200}\nsecond line');
          },
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final HistoryModel entry = closedWith!.failureEntry!;
    expect(entry.message, '构建失败：${'x' * 120}…');
    expect(entry.time, now);
  });

  testWidgets('完成后点击关闭按钮关闭对话框', (tester) async {
    await _pumpDialog(
      tester,
      build: (
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
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
      prepare: (PackModel pack) async => throw const BuildPreparationException(
        '未检测到可用编译器（优先级：icx > clang-cl > msvc）',
      ),
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
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
      prepare: (PackModel pack) async => prepared,
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
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
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
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
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
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

    expect(
      _outputLine(tester, 'INFO: 开始构建'),
      AppColors.info(_theme(tester).brightness),
    );
    expect(
      _outputLine(tester, 'WARNING: 未启用 LTO'),
      AppColors.caution(_theme(tester).brightness),
    );
    expect(findOutputKeyword('error: 编译失败')?.keyword, 'ERROR');
    expect(
      _outputLine(tester, 'error: 编译失败'),
      AppColors.critical(_theme(tester).brightness),
    );
    expect(
      _outputLine(tester, '普通输出'),
      _theme(tester).resources.textFillColorPrimary,
    );
  });

  testWidgets('失败时保留流式输出并补充尾部', (tester) async {
    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
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
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
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
    // 横向滚动内容为文本行区域（面板顶部起第一行），鼠标自文本行起拖拽平移。
    await tester.dragFrom(
      Offset(panel.left + 80, panel.top + 20),
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
    expect(
      _outputLine(tester, 'error: 编译失败'),
      AppColors.critical(_theme(tester).brightness),
    );

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
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
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

  testWidgets('输出面板文本可选择（SelectionArea）', (tester) async {
    await _pumpDialog(
      tester,
      build: _emitLines(const <String>['INFO: 开始构建', '普通输出']),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('输出文本支持 Ctrl+A / Ctrl+C 复制', (tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpDialog(
      tester,
      build: _emitLines(const <String>['alpha line', 'beta line']),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.textContaining('alpha line', findRichText: true));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.textContaining('alpha line', findRichText: true),
    );
    expect(paragraph.selections, isNotEmpty, reason: 'Ctrl+A 应全选输出文本');
  });

  testWidgets('复制按钮随输出从禁用变为可用并复制完整原始输出', (tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final Completer<BuildEnvironment> prepareGate =
        Completer<BuildEnvironment>();

    await _pumpDialog(
      tester,
      prepare: (PackModel pack) => prepareGate.future,
      build: _emitLines(const <String>['INFO: 开始构建', 'error: 编译失败']),
      scanFiles: (String sourcePath) async => const <FileModel>[],
      onApply: (PackModel pack) async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_copyButton(tester).onPressed, isNull, reason: '无输出时禁用');

    prepareGate.complete(_environment());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_copyButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('buildOutputFilter')), 'ERROR');
    await tester.pump();
    expect(find.textContaining('INFO: 开始构建', findRichText: true), findsNothing);

    await tester.tap(find.byKey(const Key('buildOutputCopyButton')));
    await tester.pump();

    final List<MethodCall> clipboardCalls = calls
        .where((MethodCall call) => call.method == 'Clipboard.setData')
        .toList();
    expect(clipboardCalls, hasLength(1));
    final Map<Object?, Object?> arguments =
        clipboardCalls.single.arguments as Map<Object?, Object?>;
    expect(
      arguments['text'],
      'INFO: 开始构建\nerror: 编译失败',
      reason: '复制范围恒为完整原始输出，过滤仅影响显示',
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('构建阶段恒显示「执行构建」且不出现下载进度文案', (tester) async {
    // 时间线已合一：构建期只有一个「执行构建」步骤在跑，既不显示「下载」步骤，
    // 也不把构建输出行里的 progress 百分比说成下载进度（它记的是下载）。
    final Completer<void> buildGate = Completer<void>();
    final Completer<List<FileModel>> scanCompleter =
        Completer<List<FileModel>>();
    final Completer<void> applyCompleter = Completer<void>();

    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
            onOutput?.call(
              '[openvino] progress 42.0% (88000000/208000000 bytes)',
            );
            await buildGate.future;
          },
      scanFiles: (_) => scanCompleter.future,
      onApply: (PackModel pack) => applyCompleter.future,
    );

    expect(_stepIsActive(tester, 'build'), isTrue);
    expect(find.text('执行构建'), findsOneWidget);
    expect(find.text('下载'), findsNothing);
    expect(find.text('分类'), findsNothing);
    expect(find.text('已下载 42%'), findsNothing, reason: '构建输出的百分比不是下载进度');

    buildGate.complete();
    await tester.pump();
    expect(_stepIsActive(tester, 'remap'), isTrue);

    scanCompleter.complete(const <FileModel>[]);
    await tester.pump();
    applyCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_stepIsDone(tester, 'done'), isTrue);
  });

  testWidgets('构建输出行不触发阶段切换', (tester) async {
    final Completer<void> buildGate = Completer<void>();
    final Completer<List<FileModel>> scanCompleter =
        Completer<List<FileModel>>();
    final Completer<void> applyCompleter = Completer<void>();

    await _pumpDialog(
      tester,
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
            onOutput?.call('[cnp_build_support] classify: C:\\src -> C:\\out');
            onOutput?.call('任意其他输出');
            await buildGate.future;
          },
      scanFiles: (_) => scanCompleter.future,
      onApply: (PackModel pack) => applyCompleter.future,
    );
    await tester.pump();

    expect(
      _stepIsActive(tester, 'build'),
      isTrue,
      reason: '构建输出行是日志而非阶段信号，不得推进时间线',
    );
    expect(_stepIsActive(tester, 'includes'), isFalse);

    buildGate.complete();
    await tester.pump();
    expect(_stepIsActive(tester, 'remap'), isTrue);

    scanCompleter.complete(const <FileModel>[]);
    await tester.pump();
    applyCompleter.complete();
    await tester.pump();
  });

  testWidgets('构建成功后先检查头文件引用再重新映射并随关闭返回报告', (tester) async {
    final List<String> order = <String>[];
    final Completer<HeaderIncludeFixReport> fixGate =
        Completer<HeaderIncludeFixReport>();
    BuildDialogResult? closedWith;
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
      onResult: (BuildDialogResult? value) => closedWith = value,
      fixIncludes: (String sourcePath, {required String packageName}) {
        order.add('fix:$sourcePath:$packageName');
        return fixGate.future;
      },
      build:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
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
    expect(_stepIsActive(tester, 'includes'), isTrue);
    expect(_closeButton(tester).onPressed, isNull);

    fixGate.complete(report);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(order, <String>['build', r'fix:C:\libs\demo:demo', 'scan', 'apply']);
    expect(_stepIsDone(tester, 'done'), isTrue);

    await tester.tap(find.byKey(const Key('buildCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(closedWith!.fixReport, same(report));
    expect(closedWith!.failureEntry, isNull);
    expect(find.byKey(const Key('buildPackDialog')), findsNothing);
  });

  testWidgets('头文件引用检查失败不阻断重新映射并在输出面板提示', (tester) async {
    int scanCount = 0;

    await _pumpDialog(
      tester,
      fixIncludes: (String sourcePath, {required String packageName}) async =>
          throw const FileSystemException(': 目录不可访问'),
      build: (
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
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
    expect(_stepIsDone(tester, 'done'), isTrue);
    expect(
      find.textContaining('头文件引用检查失败', findRichText: true),
      findsOneWidget,
    );
  });
}

/// 输出面板中某行的关键字颜色（无关键字行取常规文本色）。
Color _outputLine(WidgetTester tester, String line) {
  return outputLineColor(
    tester
        .widget<RichText>(find.textContaining(line, findRichText: true))
        .text
        .toPlainText(),
    _theme(tester),
  );
}

Finder _timelineStep(String id) => find.byKey(Key('buildTimelineStep_$id'));

bool _stepIsActive(WidgetTester tester, String id) {
  return find
      .descendant(of: _timelineStep(id), matching: find.byType(ProgressRing))
      .evaluate()
      .isNotEmpty;
}

bool _stepIsDone(WidgetTester tester, String id) {
  return find
      .descendant(
        of: _timelineStep(id),
        matching: find.byIcon(FluentIcons.check_mark),
      )
      .evaluate()
      .isNotEmpty;
}

bool _stepIsFailed(WidgetTester tester, String id) {
  return find
      .descendant(
        of: _timelineStep(id),
        matching: find.byIcon(FluentIcons.error),
      )
      .evaluate()
      .isNotEmpty;
}

FluentThemeData _theme(WidgetTester tester) {
  return FluentTheme.of(tester.element(find.byType(BuildPackDialog)));
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
    environment: <String, String>{
      'CNP_COMPILER_KIND': 'icx',
      'Path': r'C:\tools\bin',
    },
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

IconButton _copyButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('buildOutputCopyButton')));

PackBuildRunner _emitLines(List<String> lines) {
  return (
    PackModel pack, {
    Map<String, String>? environment,
    void Function(String line)? onOutput,
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
  PackHeaderIncludeFixer? fixIncludes,
  ValueChanged<BuildDialogResult?>? onResult,
  DateTime Function()? now,
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
              final BuildDialogResult? result =
                  await showDialog<BuildDialogResult>(
                    context: context,
                    builder: (_) => BuildPackDialog(
                      pack: pack ?? _pack(),
                      build: build,
                      prepare:
                          prepare ?? (PackModel pack) async => _environment(),
                      scanFiles: scanFiles,
                      onApply: onApply,
                      fixIncludes: fixIncludes ?? _emptyFixIncludes,
                      now: now ?? DateTime.now,
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
  await tester.tap(find.text('打开对话框').hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<HeaderIncludeFixReport> _emptyFixIncludes(
  String sourcePath, {
  required String packageName,
}) async => const HeaderIncludeFixReport();
