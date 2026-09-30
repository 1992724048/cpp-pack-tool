import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/pack/package_scaffold.dart';
import 'package:cpp_nuget_pack/pack/ui/dialogs/create_package_structure_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const String _directoryPath = r'C:\libs\foo';

/// 落盘的可观测结果。对话框单测一律注入它：`testWidgets` 的 fake_async 测试区里
/// 真实文件 future 永不落定，真实落盘由 `test/pack/package_scaffold_test.dart` 覆盖。
Future<ScaffoldOutcome> _scaffoldSucceeding(String rootPath) async {
  return const ScaffoldOutcome(
    createdDirectories: <String>['lib/x64/Debug', 'lib/x64/Release', 'bin/x64/Debug', 'bin/x64/Release'],
    createdFiles: <String>['build.py', 'pre.bat', 'post.bat'],
    skippedFiles: <String>[],
  );
}

Future<ScaffoldOutcome> _scaffoldFailing(String rootPath) async {
  throw PackageScaffoldException('无法创建包结构：FileSystemException: $rootPath\\pre.bat');
}

void main() {
  testWidgets('展示路径、元数据表单与命令注册时序说明', (tester) async {
    await _pumpDialog(tester);

    expect(find.text('路径：$_directoryPath'), findsOneWidget);
    expect(find.byKey(const Key('packIdField')), findsOneWidget);
    expect(find.byKey(const Key('packLicenseField')), findsOneWidget);
    expect(find.textContaining('不会因为创建文件就自动注册进命令列表'), findsOneWidget);
    expect(find.textContaining('已存在的文件不会被覆盖'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('必填字段为空或纯空格时确定禁用，填齐后启用', (tester) async {
    await _pumpDialog(tester);

    await tester.enterText(find.byKey(const Key('packIdField')), '   ');
    await tester.enterText(find.byKey(const Key('packVersionField')), '   ');
    await tester.enterText(find.byKey(const Key('packAuthorField')), '   ');
    await tester.pump();

    expect(_confirmButton(tester).onPressed, isNull);

    await _fillRequiredFields(tester);

    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('自定义许可证未填文本时确定禁用', (tester) async {
    await _pumpDialog(tester);

    await _fillRequiredFields(tester);
    await _selectLicense(tester, '自定义…');

    expect(find.byKey(const Key('packLicenseCustomField')), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('packLicenseCustomField')), 'MyLicense');
    await tester.pump();

    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('填齐元数据后落盘并返回元数据与汇总', (tester) async {
    CreatePackageStructureResult? result;
    await _pumpDialog(tester, onResult: (CreatePackageStructureResult? value) => result = value);

    await _fillRequiredFields(tester);
    await tester.enterText(find.byKey(const Key('packDescriptionField')), '测试描述');
    await _selectLicense(tester, 'MIT');
    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
    expect(result, isNotNull);
    expect(result!.metadata.name, 'demo');
    expect(result!.metadata.version, '1.0.0');
    expect(result!.metadata.author, 'tester');
    expect(result!.metadata.description, '测试描述');
    expect(result!.metadata.license, 'MIT');
    expect(result!.outcome.createdFiles, <String>['build.py', 'pre.bat', 'post.bat']);
    expect(result!.outcome.skippedFiles, isEmpty);
  });

  testWidgets('目标目录非空时先弹确认框并列出将跳过与将创建的项', (tester) async {
    int createCalls = 0;
    await _pumpDialog(
      tester,
      preview: (String _) => const ScaffoldPreview(
        existingEntryCount: 2,
        existingDirectories: <String>[],
        existingFiles: <String>['build.py', 'pre.bat'],
      ),
      createStructure: (String rootPath) {
        createCalls++;
        return _scaffoldSucceeding(rootPath);
      },
    );

    await _fillRequiredFields(tester);
    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('目标目录非空'), findsOneWidget);
    expect(find.textContaining('目录中已有 2 个条目'), findsOneWidget);
    expect(find.text('已存在，将跳过：build.py、pre.bat'), findsOneWidget);
    expect(find.text('  build.py'), findsNothing);
    expect(find.text('  post.bat'), findsOneWidget);
    expect(find.text('  lib/x64/Debug/'), findsOneWidget);
    expect(find.text('  bin/x64/Release/'), findsOneWidget);
    expect(createCalls, 0);
  });

  testWidgets('确认框把既有目录与将创建目录分列，已存在的不计入将创建', (tester) async {
    await _pumpDialog(
      tester,
      preview: (String _) => const ScaffoldPreview(
        existingEntryCount: 2,
        existingDirectories: <String>['lib/x64/Debug', 'bin/x64/Release'],
        existingFiles: <String>[],
      ),
    );

    await _fillRequiredFields(tester);
    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('已存在，将跳过：lib/x64/Debug/、bin/x64/Release/'), findsOneWidget);
    expect(find.text('  lib/x64/Debug/'), findsNothing);
    expect(find.text('  bin/x64/Release/'), findsNothing);
    expect(find.text('  lib/x64/Release/'), findsOneWidget);
    expect(find.text('  bin/x64/Debug/'), findsOneWidget);
  });

  testWidgets('包结构已完整时确认框只报已存在，不列将创建项', (tester) async {
    await _pumpDialog(
      tester,
      preview: (String _) => const ScaffoldPreview(
        existingEntryCount: 7,
        existingDirectories: <String>[
          'lib/x64/Debug',
          'lib/x64/Release',
          'bin/x64/Debug',
          'bin/x64/Release',
        ],
        existingFiles: <String>['build.py', 'pre.bat', 'post.bat'],
      ),
    );

    await _fillRequiredFields(tester);
    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('将创建的目录：'), findsNothing);
    expect(find.text('将创建的文件：'), findsNothing);
    expect(find.text('包结构已完整，不会新增任何目录或文件。'), findsOneWidget);
    expect(find.textContaining('已存在，将跳过：lib/x64/Debug/、lib/x64/Release/、'), findsOneWidget);
    expect(find.textContaining('bin/x64/Release/、build.py、pre.bat、post.bat'), findsOneWidget);
  });

  testWidgets('默认预演读到真实非空目录时同样弹确认框', (tester) async {
    // 预演是同步 IO（existsSync / listSync），可在 fake_async 测试区里跑真实目录；
    // 落盘则注入替身，避免真实写盘。
    final Directory root = Directory.systemTemp.createTempSync('cnp_scaffold_preview_');
    final File existing = File('${root.path}/build.py')..writeAsStringSync('keep me');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    await _pumpDialog(tester, directoryPath: root.path);

    await _fillRequiredFields(tester);
    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('目标目录非空'), findsOneWidget);
    expect(find.text('已存在，将跳过：build.py'), findsOneWidget);
    expect(existing.existsSync(), isTrue);
  });

  testWidgets('确认框取消时不落盘且对话框保持打开可再次提交', (tester) async {
    int createCalls = 0;
    await _pumpDialog(
      tester,
      preview: (String _) => const ScaffoldPreview(
        existingEntryCount: 1,
        existingDirectories: <String>[],
        existingFiles: <String>[],
      ),
      createStructure: (String rootPath) {
        createCalls++;
        return _scaffoldSucceeding(rootPath);
      },
    );

    await _fillRequiredFields(tester);
    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _tapTopmostDialogButton(tester, '取消');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text('目标目录非空'), findsNothing);
    expect(createCalls, 0);
    expect(_confirmButton(tester).onPressed, isNotNull);

    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _tapTopmostDialogButton(tester, '继续创建');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
    expect(createCalls, 1);
  });

  testWidgets('落盘失败时显示含路径的错误提示且对话框保持打开可重试', (tester) async {
    int createCalls = 0;
    CreatePackageStructureResult? result;
    await _pumpDialog(
      tester,
      onResult: (CreatePackageStructureResult? value) => result = value,
      createStructure: (String rootPath) {
        createCalls++;
        return createCalls == 1 ? _scaffoldFailing(rootPath) : _scaffoldSucceeding(rootPath);
      },
    );

    await _fillRequiredFields(tester);
    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('floatingToast')), findsOneWidget);
    expect(find.textContaining('无法创建包结构'), findsOneWidget);
    expect(find.textContaining(r'pre.bat'), findsWidgets);
    expect(find.byType(ContentDialog), findsOneWidget);
    expect(result, isNull);
    expect(_confirmButton(tester).onPressed, isNotNull);

    // 悬浮提示 5s 后自动消失，避免残留计时器
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('floatingToast')), findsNothing);

    await _tapDialogButton(tester, '确定');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(createCalls, 2);
    expect(result, isNotNull);
    expect(result!.outcome.createdFiles, <String>['build.py', 'pre.bat', 'post.bat']);
  });

  testWidgets('落盘在途时确定按钮显示创建中并禁用', (tester) async {
    final Completer<ScaffoldOutcome> pending = Completer<ScaffoldOutcome>();
    await _pumpDialog(
      tester,
      createStructure: (String _) => pending.future,
    );

    await _fillRequiredFields(tester);
    await tester.tap(find.text('确定'));
    await tester.pump();

    expect(find.text('确定'), findsNothing);
    expect(find.text('创建中…'), findsOneWidget);
    expect(_submittingButton(tester).onPressed, isNull);

    pending.complete(
      const ScaffoldOutcome(
        createdDirectories: <String>['.'],
        createdFiles: <String>['build.py', 'pre.bat', 'post.bat'],
        skippedFiles: <String>[],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('点击取消按钮后对话框关闭且不返回数据', (tester) async {
    bool completed = false;
    CreatePackageStructureResult? result;
    await _pumpDialog(
      tester,
      onResult: (CreatePackageStructureResult? value) {
        completed = true;
        result = value;
      },
    );

    await _tapDialogButton(tester, '取消');

    expect(find.byType(ContentDialog), findsNothing);
    expect(completed, isTrue);
    expect(result, isNull);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  String directoryPath = _directoryPath,
  ScaffoldPreview Function(String rootPath)? preview,
  Future<ScaffoldOutcome> Function(String rootPath)? createStructure,
  ValueChanged<CreatePackageStructureResult?>? onResult,
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
              final CreatePackageStructureResult? result = await showDialog<CreatePackageStructureResult>(
                context: context,
                builder: (_) => CreatePackageStructureDialog(
                  directoryPath: directoryPath,
                  preview: preview ?? previewPackageStructure,
                  createStructure: createStructure ?? _scaffoldSucceeding,
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

/// 确认框叠在主对话框之上且两者都有「取消」，只能取最顶层的一个匹配。
Future<void> _tapTopmostDialogButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

FilledButton _confirmButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确定'));

FilledButton _submittingButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '创建中…'));
