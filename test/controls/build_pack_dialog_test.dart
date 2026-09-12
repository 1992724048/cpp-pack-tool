import 'dart:async';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/controls/build_pack_dialog.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
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
      prepare: (PackModel pack) => prepareGate.future,
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
      prepare: (PackModel pack) async => throw const BuildPreparationException(
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
      prepare: (PackModel pack) async => prepared,
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

  testWidgets('失败时输出尾部进入面板且不残留流式行', (tester) async {
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
      findsNothing,
    );
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('构建回调的仓库版本写入应用包', (tester) async {
    PackModel? applied;

    await _pumpDialog(
      tester,
      build: (
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

Future<void> _pumpDialog(
  WidgetTester tester, {
  required PackBuildRunner build,
  Future<BuildEnvironment> Function(PackModel pack)? prepare,
  required Future<List<FileModel>> Function(String sourcePath) scanFiles,
  required Future<void> Function(PackModel pack) onApply,
  PackModel? pack,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => BuildPackDialog(
                pack: pack ?? _pack(),
                build: build,
                prepare: prepare ?? (PackModel pack) async => _environment(),
                scanFiles: scanFiles,
                onApply: onApply,
              ),
            ),
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
