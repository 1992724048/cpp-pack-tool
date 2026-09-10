import 'dart:async';

import 'package:cpp_nuget_pack/controls/add_directory_dialog.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const String _directoryPath = r'C:\libs\foo';

void main() {
  testWidgets('扫描进行中时显示进度环与提示', (tester) async {
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpDialog(tester, scanFuture: completer.future);

    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.text('正在扫描…'), findsOneWidget);
    expect(find.text('添加包'), findsOneWidget);
    expect(find.text('路径：$_directoryPath'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

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

  testWidgets('扫描失败时显示去除前缀的错误信息且确定禁用', (tester) async {
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpDialog(tester, scanFuture: completer.future);
    completer.completeError(ArgumentError('目录不存在: X'));
    await tester.pump();

    expect(find.text('扫描失败：目录不存在: X'), findsOneWidget);
    expect(find.textContaining('Invalid argument(s):'), findsNothing);
    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('点击取消按钮后对话框关闭且不返回数据', (tester) async {
    bool completed = false;
    PackModel? result;
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(const <FileModel>[]),
      onResult: (PackModel? value) {
        completed = true;
        result = value;
      },
    );

    await _tapDialogButton(tester, '取消');

    expect(find.byType(ContentDialog), findsNothing);
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('必填字段为空或纯空格时确定按钮禁用', (tester) async {
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(const <FileModel>[]),
    );

    expect(_confirmButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('packIdField')), '   ');
    await tester.enterText(find.byKey(const Key('packVersionField')), '   ');
    await tester.enterText(find.byKey(const Key('packAuthorField')), '   ');
    await tester.pump();

    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('填齐必填字段且扫描成功后确定按钮可用', (tester) async {
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(const <FileModel>[]),
    );

    await _fillRequiredFields(tester);

    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('点击确定返回填写的 PackModel', (tester) async {
    PackModel? result;
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 512),
        FileModel(name: 'logo.svg', path: 'assets/logo.svg', size: 256),
      ]),
      onResult: (PackModel? value) => result = value,
    );

    await _fillRequiredFields(tester);
    await tester.enterText(
      find.byKey(const Key('packDescriptionField')),
      '测试描述',
    );
    await _selectLicense(tester, 'MIT');
    await _tapDialogButton(tester, '确定');

    expect(result, isNotNull);
    expect(result!.name, 'demo');
    expect(result!.version, '1.0.0');
    expect(result!.author, 'tester');
    expect(result!.description, '测试描述');
    expect(result!.license, 'MIT');
    expect(result!.iconPath, 'assets/logo.svg');
    expect(result!.sourcePath, _directoryPath);
    expect(result!.files.length, 2);
  });

  testWidgets('许可证选中后可清除回空', (tester) async {
    PackModel? result;
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(const <FileModel>[]),
      onResult: (PackModel? value) => result = value,
    );

    await _fillRequiredFields(tester);
    await _selectLicense(tester, 'MIT');
    await _selectLicense(tester, '无');
    await _tapDialogButton(tester, '确定');

    expect(result, isNotNull);
    expect(result!.license, isNull);
  });

  testWidgets('扫描到 SVG 图标时显示预览与相对路径', (tester) async {
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
        FileModel(name: 'logo.svg', path: 'assets/logo.svg', size: 256),
      ]),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('图标：assets/logo.svg'), findsOneWidget);
  });

  testWidgets('多个图片中取第一个并显示位图预览', (tester) async {
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'banner.png', path: 'images/banner.png', size: 512),
        FileModel(name: 'logo.svg', path: 'images/logo.svg', size: 256),
      ]),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.errorBuilder, isNotNull);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('图标：images/banner.png'), findsOneWidget);
  });

  testWidgets('未找到图片文件时显示提示且确定返回的 iconPath 为空', (tester) async {
    PackModel? result;
    await _pumpDialog(
      tester,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
      ]),
      onResult: (PackModel? value) => result = value,
    );

    expect(find.text('未找到图标文件'), findsOneWidget);

    await _fillRequiredFields(tester);
    await _tapDialogButton(tester, '确定');

    expect(result, isNotNull);
    expect(result!.iconPath, isNull);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Future<List<FileModel>> scanFuture,
  ValueChanged<PackModel?>? onResult,
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
              final PackModel? result = await showDialog<PackModel>(
                context: context,
                builder: (_) => AddDirectoryDialog(
                  directoryPath: _directoryPath,
                  scanFuture: scanFuture,
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

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('packIdField')), 'demo');
  await tester.enterText(find.byKey(const Key('packVersionField')), '1.0.0');
  await tester.enterText(find.byKey(const Key('packAuthorField')), 'tester');
  await tester.pump();
}

Future<void> _selectLicense(WidgetTester tester, String option) async {
  final Finder field = find.byKey(const Key('packLicenseField'));
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.tap(field);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(option).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

FilledButton _confirmButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确定'));
