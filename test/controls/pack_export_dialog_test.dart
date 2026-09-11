import 'dart:async';

import 'package:cpp_nuget_pack/controls/pack_export_dialog.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const PackageExportResult _result = (
  outputPath: r'D:\out\demo.1.0.0.nupkg',
  fileCount: 8,
  packageSize: 2048,
);

void main() {
  testWidgets('导出进行中显示进度环且关闭按钮禁用', (tester) async {
    final Completer<PackageExportResult> completer =
        Completer<PackageExportResult>();
    PackModel? exportedPack;
    String? exportedDirectory;

    await _pumpDialog(
      tester,
      pack: _pack(),
      outputDirectory: r'D:\out',
      exportPackage: (PackModel pack, String outputDirectory) {
        exportedPack = pack;
        exportedDirectory = outputDirectory;
        return completer.future;
      },
    );

    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(find.text('打包文件夹'), findsOneWidget);
    expect(find.text('包名：demo'), findsOneWidget);
    expect(find.text(r'输出目录：D:\out'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.text('正在打包…'), findsOneWidget);
    expect(find.byKey(const Key('packExportRevealButton')), findsNothing);
    expect(_closeButton(tester).onPressed, isNull);
    expect(exportedPack, isNotNull);
    expect(exportedPack!.name, 'demo');
    expect(exportedDirectory, r'D:\out');

    completer.complete(_result);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('打包完成'), findsOneWidget);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('导出完成后显示结果并可打开所在目录', (tester) async {
    String? revealedPath;

    await _pumpDialog(
      tester,
      pack: _pack(),
      outputDirectory: r'D:\out',
      exportPackage: (PackModel pack, String outputDirectory) async => _result,
      revealFile: (String filePath) async {
        revealedPath = filePath;
        return true;
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('打包完成'), findsOneWidget);
    expect(find.text(r'输出路径：D:\out\demo.1.0.0.nupkg'), findsOneWidget);
    expect(find.text('文件数量：8'), findsOneWidget);
    expect(find.text('包大小：2.0 KB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('packExportRevealButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(revealedPath, r'D:\out\demo.1.0.0.nupkg');
    expect(find.byKey(const Key('floatingToast')), findsNothing);
  });

  testWidgets('打开所在目录失败时显示错误提示', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(),
      outputDirectory: r'D:\out',
      exportPackage: (PackModel pack, String outputDirectory) async => _result,
      revealFile: (String filePath) async => false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('packExportRevealButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('无法打开所在目录'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
  });

  testWidgets('导出失败时显示去前缀错误信息', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(),
      outputDirectory: r'D:\out',
      exportPackage: (PackModel pack, String outputDirectory) async =>
          throw ArgumentError('目标目录不可写'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('打包失败：目标目录不可写'), findsOneWidget);
    expect(find.textContaining('Invalid argument(s)'), findsNothing);
    expect(find.byKey(const Key('packExportRevealButton')), findsNothing);
    expect(_closeButton(tester).onPressed, isNotNull);
  });

  testWidgets('完成后点击关闭按钮关闭对话框', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(),
      outputDirectory: r'D:\out',
      exportPackage: (PackModel pack, String outputDirectory) async => _result,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('packExportCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('packExportDialog')), findsNothing);
  });
}

PackModel _pack() {
  return PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
    description: '描述',
    sourcePath: r'C:\libs\demo',
  );
}

Button _closeButton(WidgetTester tester) =>
    tester.widget<Button>(find.byKey(const Key('packExportCloseButton')));

Future<void> _pumpDialog(
  WidgetTester tester, {
  required PackModel pack,
  required String outputDirectory,
  required Future<PackageExportResult> Function(
    PackModel pack,
    String outputDirectory,
  )
  exportPackage,
  Future<bool> Function(String filePath)? revealFile,
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
              builder: (_) => PackExportDialog(
                pack: pack,
                outputDirectory: outputDirectory,
                exportPackage: exportPackage,
                revealFile: revealFile ?? (String filePath) async => true,
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
