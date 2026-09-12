import 'dart:async';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/controls/build_pack_dialog.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('构建成功后依次经历阶段并显示完成统计', (tester) async {
    final Completer<void> downloadGate = Completer<void>();
    final Completer<void> buildGate = Completer<void>();
    final Completer<List<FileModel>> scanCompleter =
        Completer<List<FileModel>>();
    final Completer<void> applyCompleter = Completer<void>();
    PackModel? applied;

    await _pumpDialog(
      tester,
      build: (PackModel pack, void Function(PackBuildStage) onStage) async {
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
    expect(find.text('正在下载源码…'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNull);

    downloadGate.complete();
    await tester.pump();
    expect(find.text('正在执行构建…'), findsOneWidget);
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
      build: (PackModel pack, void Function(PackBuildStage) onStage) async {
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
    expect(find.textContaining('boom'), findsOneWidget);
    expect(scanCount, 0);
    expect(find.byType(ProgressRing), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('重新扫描失败时显示去前缀错误', (tester) async {
    await _pumpDialog(
      tester,
      build: (PackModel pack, void Function(PackBuildStage) onStage) async {},
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
      build: (PackModel pack, void Function(PackBuildStage) onStage) async {},
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
      build: (PackModel pack, void Function(PackBuildStage) onStage) async {},
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
      build: (PackModel pack, void Function(PackBuildStage) onStage) async {},
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
