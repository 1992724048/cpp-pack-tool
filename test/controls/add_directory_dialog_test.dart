import 'dart:async';

import 'package:cpp_nuget_pack/controls/add_directory_dialog.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const String _directoryPath = r'C:\libs\foo';

void main() {
  testWidgets('扫描进行中时显示进度环与提示', (tester) async {
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpDialog(tester, scanFuture: completer.future);

    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.text('正在扫描…'), findsOneWidget);
    expect(find.text('已选择目录'), findsOneWidget);
    expect(find.text('路径：$_directoryPath'), findsOneWidget);

    completer.complete(const <FileModel>[]);
    await tester.pump();
  });

  testWidgets('扫描成功时显示文件数量与总大小', (tester) async {
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 1024),
        FileModel(name: 'foo.cpp', path: 'src/foo.cpp', size: 1024),
      ]),
    );

    expect(find.byType(ProgressRing), findsNothing);
    expect(find.text('文件数量：2'), findsOneWidget);
    expect(find.text('总大小：2.0 KB'), findsOneWidget);
  });

  testWidgets('扫描失败时显示错误信息', (tester) async {
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpDialog(tester, scanFuture: completer.future);
    completer.completeError(ArgumentError('目录不存在: X'));
    await tester.pump();

    expect(find.textContaining('扫描失败'), findsOneWidget);
    expect(find.textContaining('目录不存在: X'), findsOneWidget);
  });

  testWidgets('点击关闭按钮后对话框关闭', (tester) async {
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(const <FileModel>[]),
    );

    await tester.tap(find.text('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Future<List<FileModel>> scanFuture,
}) async {
  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (context) => Center(
          child: Button(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AddDirectoryDialog(
                directoryPath: _directoryPath,
                scanFuture: scanFuture,
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
