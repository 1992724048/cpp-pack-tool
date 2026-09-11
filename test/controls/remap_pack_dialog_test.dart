import 'dart:async';

import 'package:cpp_nuget_pack/controls/remap_pack_dialog.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('扫描进行中时显示进度环与提示', (tester) async {
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();
    int applyCount = 0;

    await _pumpDialog(
      tester,
      pack: _pack(),
      scanFuture: completer.future,
      onApply: (PackModel pack) async {
        applyCount++;
      },
    );

    expect(find.byKey(const Key('remapPackDialog')), findsOneWidget);
    expect(find.text('重新映射'), findsOneWidget);
    expect(find.text('包名：demo'), findsOneWidget);
    expect(find.text(r'源目录：C:\libs\demo'), findsOneWidget);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.text('正在扫描…'), findsOneWidget);
    expect(find.byKey(const Key('remapCloseButton')), findsOneWidget);
    expect(applyCount, 0);

    completer.complete(const <FileModel>[]);
    await tester.pump();
  });

  testWidgets('扫描成功后自动调用 onApply 并展示结果统计', (tester) async {
    final PackModel pack = _pack(
      files: <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 100),
        FileModel(name: 'old.cpp', path: 'src/old.cpp', size: 200),
      ],
    );
    PackModel? applied;
    int applyCount = 0;
    final Completer<void> applyCompleter = Completer<void>();

    await _pumpDialog(
      tester,
      pack: pack,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 1024),
        FileModel(name: 'logo.svg', path: 'assets/logo.svg', size: 1024),
      ]),
      onApply: (PackModel updated) {
        applyCount++;
        applied = updated;
        return applyCompleter.future;
      },
    );

    expect(applyCount, 1);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(find.text('正在更新配置…'), findsOneWidget);

    applyCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('重新映射完成'), findsOneWidget);
    expect(find.text('文件数量：2'), findsOneWidget);
    expect(find.text('总大小：2.0 KB'), findsOneWidget);
    expect(find.text('新增：1 个文件'), findsOneWidget);
    expect(find.text('移除：1 个文件'), findsOneWidget);

    expect(applied, isNotNull);
    expect(applied!.name, 'demo');
    expect(applied!.version, '1.0.0');
    expect(applied!.author, 'tester');
    expect(applied!.description, '描述');
    expect(applied!.license, 'MIT');
    expect(applied!.sourcePath, r'C:\libs\demo');
    expect(applied!.files, hasLength(2));
    expect(applied!.iconPath, 'assets/logo.svg');
  });

  testWidgets('重新映射保留依赖与命令列表', (tester) async {
    final PackModel pack = _pack()
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '1.0'),
      ]
      ..commands = <CmdModel>[
        CmdModel(command: 'echo hi', type: CmdType.preBuild),
      ]
      ..macros = <MacroModel>[const MacroModel(value: 'MY_MACRO=1')]
      ..libDirectories = <LibDirModel>[
        const LibDirModel(path: 'third_party/lib'),
      ]
      ..libraries = <LibraryModel>[const LibraryModel(name: 'mylib.lib')];
    PackModel? applied;

    await _pumpDialog(
      tester,
      pack: pack,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'new.h', path: 'include/new.h', size: 10),
      ]),
      onApply: (PackModel updated) async {
        applied = updated;
      },
    );

    expect(applied, isNotNull);
    expect(applied!.files, hasLength(1));
    expect(applied!.dependencies, hasLength(1));
    expect(applied!.dependencies.single.name, 'libfoo');
    expect(applied!.dependencies.single.version, '1.0');
    expect(applied!.commands, hasLength(1));
    expect(applied!.commands.single.command, 'echo hi');
    expect(applied!.commands.single.type, CmdType.preBuild);
    expect(applied!.macros.single.value, 'MY_MACRO=1');
    expect(applied!.libDirectories.single.path, 'third_party/lib');
    expect(applied!.libraries.single.name, 'mylib.lib');
  });

  testWidgets('重新映射保留脚本列表', (tester) async {
    final PackModel pack = _pack()
      ..scripts = <ScriptProjectModel>[
        ScriptProjectModel(
          id: 'script_1',
          name: '脚本 1',
          trigger: ScriptTrigger.pre,
        ),
      ];
    PackModel? applied;

    await _pumpDialog(
      tester,
      pack: pack,
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'new.h', path: 'include/new.h', size: 10),
      ]),
      onApply: (PackModel updated) async {
        applied = updated;
      },
    );

    expect(applied, isNotNull);
    expect(applied!.files, hasLength(1));
    expect(applied!.scripts, hasLength(1));
    expect(applied!.scripts.single.id, 'script_1');
  });

  testWidgets('扫描结果无图片文件时 iconPath 为空', (tester) async {
    PackModel? applied;

    await _pumpDialog(
      tester,
      pack: _pack(),
      scanFuture: Future<List<FileModel>>.value(<FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 512),
      ]),
      onApply: (PackModel updated) async {
        applied = updated;
      },
    );

    expect(applied, isNotNull);
    expect(applied!.iconPath, isNull);
    expect(find.text('重新映射完成'), findsOneWidget);
    expect(find.text('新增：1 个文件'), findsOneWidget);
  });

  testWidgets('扫描失败时显示去前缀错误且不调用 onApply', (tester) async {
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();
    int applyCount = 0;

    await _pumpDialog(
      tester,
      pack: _pack(),
      scanFuture: completer.future,
      onApply: (PackModel pack) async {
        applyCount++;
      },
    );
    completer.completeError(ArgumentError('目录不存在: X'));
    await tester.pump();

    expect(find.text('扫描失败：目录不存在: X'), findsOneWidget);
    expect(find.textContaining('Invalid argument(s):'), findsNothing);
    expect(applyCount, 0);
    expect(find.byKey(const Key('remapCloseButton')), findsOneWidget);
  });

  testWidgets('onApply 抛异常时显示更新失败', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(),
      scanFuture: Future<List<FileModel>>.value(const <FileModel>[]),
      onApply: (PackModel pack) async {
        throw Exception('写入失败');
      },
    );

    expect(find.text('更新失败：Exception: 写入失败'), findsOneWidget);
    expect(find.text('重新映射完成'), findsNothing);
    expect(find.byKey(const Key('remapCloseButton')), findsOneWidget);
  });

  testWidgets('点击关闭按钮关闭对话框', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(),
      scanFuture: Future<List<FileModel>>.value(const <FileModel>[]),
      onApply: (PackModel pack) async {},
    );

    await tester.tap(find.byKey(const Key('remapCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('remapPackDialog')), findsNothing);
  });

  testWidgets('扫描完成前关闭对话框时不调用 onApply', (tester) async {
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();
    int applyCount = 0;

    await _pumpDialog(
      tester,
      pack: _pack(),
      scanFuture: completer.future,
      onApply: (PackModel pack) async {
        applyCount++;
      },
    );

    await tester.tap(find.byKey(const Key('remapCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('remapPackDialog')), findsNothing);

    completer.complete(const <FileModel>[]);
    await tester.pump();

    expect(applyCount, 0);
    expect(tester.takeException(), isNull);
  });
}

PackModel _pack({List<FileModel>? files}) {
  return PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
    description: '描述',
    license: 'MIT',
    iconPath: 'assets/old.png',
    sourcePath: r'C:\libs\demo',
  )..files = <FileModel>[...?files];
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required PackModel pack,
  required Future<List<FileModel>> scanFuture,
  required Future<void> Function(PackModel pack) onApply,
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
              builder: (_) => RemapPackDialog(
                pack: pack,
                scanFuture: scanFuture,
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
