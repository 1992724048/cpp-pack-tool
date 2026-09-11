import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/main.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/pages/setting.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('取消目录选择时不弹出对话框', (tester) async {
    await _pumpMainLayout(
      tester,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('添加文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('选择目录后弹出对话框并显示扫描统计', (tester) async {
    await _pumpMainLayout(
      tester,
      pickDirectory: () async => r'C:\libs\foo',
      scanFiles: (_) async => <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 1024),
        FileModel(name: 'foo.cpp', path: 'src/foo.cpp', size: 1024),
      ],
    );

    await tester.tap(find.byTooltip('添加文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text('添加包'), findsOneWidget);
    expect(find.text(r'路径：C:\libs\foo'), findsOneWidget);
    expect(find.text('文件数量：2'), findsOneWidget);
    expect(find.text('总大小：2.0 KB'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });

  testWidgets('未有包时显示引导文案且设置仍可用', (tester) async {
    await _pumpMainLayout(
      tester,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(find.text('尚未添加包'), findsOneWidget);
    expect(find.text('点击工具栏「添加文件夹」开始'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('主题模式'), findsOneWidget);
    expect(find.byKey(const Key('settingPickDirButton')), findsOneWidget);
  });

  testWidgets('footer 设置页可操作且回传新设置', (tester) async {
    SettingsModel? saved;

    await _pumpMainLayout(
      tester,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      onSaveSettings: (SettingsModel settings) async => saved = settings,
    );

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('settingThemeModeField')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('深色').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.themeMode, ThemeModeSetting.dark);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('footer 设置页铺满内容区域并带页面背景表面', (tester) async {
    await _pumpMainLayout(
      tester,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    final Rect contentArea = tester.getRect(
      find.ancestor(of: find.text('尚未添加包'), matching: find.byType(Center)),
    );

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.getRect(find.byType(Setting)), contentArea);

    final Finder surface = _pageSurface(tester);
    expect(surface, findsOneWidget);
    expect(tester.getRect(surface), contentArea);
  });

  testWidgets('启动后显示已加载的包', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('beta', '2.0.0'), _pack('alpha', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(find.text('alpha'), findsWidgets);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('尚未添加包'), findsNothing);
  });

  testWidgets('配置文件加载失败时通过悬浮提示', (tester) async {
    final _FakePackStore store = _FakePackStore(
      errors: <PackLoadError>[
        const PackLoadError(fileName: 'broken.yaml', message: '解析失败'),
      ],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(find.byType(InfoBar), findsNothing);
    expect(find.byKey(const Key('floatingToast')), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(find.textContaining('1 个配置加载失败'), findsOneWidget);
    expect(find.textContaining('broken.yaml'), findsOneWidget);
    expect(find.textContaining('解析失败'), findsOneWidget);
  });

  testWidgets('添加成功后列表更新并选中新包', (tester) async {
    final _FakePackStore store = _FakePackStore();

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => r'C:\libs\foo',
      scanFiles: (_) async => <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
      ],
    );

    await tester.tap(find.byTooltip('添加文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _fillRequiredFields(tester, name: 'demo');
    await _tapDialogButton(tester, '确定');

    expect(store.saveCount, 1);
    expect(store.packs, hasLength(1));
    expect(find.byType(ContentDialog), findsNothing);
    expect(find.text('demo'), findsWidgets);
    expect(find.text('尚未添加包'), findsNothing);
  });

  testWidgets('添加同 ID 包时覆盖且列表不重复', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => r'C:\libs\foo',
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('添加文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _fillRequiredFields(tester, name: 'DEMO', version: '9.9.9');
    await _tapDialogButton(tester, '确定');

    expect(store.packs, hasLength(1));
    expect(store.packs.single.version, '9.9.9');
    expect(find.text('9.9.9'), findsWidgets);
    expect(find.text('1.0.0'), findsNothing);
  });

  testWidgets('保存失败时弹出错误提示且列表不变', (tester) async {
    final _FakePackStore store = _FakePackStore()..failSave = true;

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => r'C:\libs\foo',
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('添加文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _fillRequiredFields(tester, name: 'demo');
    await _tapDialogButton(tester, '确定');

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.textContaining('包「demo」保存失败'), findsOneWidget);
    expect(store.packs, isEmpty);
    expect(find.text('尚未添加包'), findsOneWidget);
  });

  testWidgets('编辑包信息保存后侧边栏更新并显示已保存', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byKey(const Key('packInfoEditButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '2.0.0',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(store.saveCount, 1);
    expect(store.packs.single.version, '2.0.0');
    expect(find.text('2.0.0'), findsWidgets);
    expect(find.text('已保存'), findsOneWidget);
    expect(find.byKey(const Key('packInfoSaveButton')), findsNothing);
    expect(find.byKey(const Key('packInfoEditButton')), findsOneWidget);
  });

  testWidgets('编辑保存失败时弹出错误对话框且停留编辑态', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    )..failSave = true;

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byKey(const Key('packInfoEditButton')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '2.0.0',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.textContaining('包「demo」保存失败'), findsOneWidget);
    expect(store.saveCount, 0);

    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(ContentDialog), findsNothing);
    expect(find.byKey(const Key('packInfoSaveButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoCancelButton')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('packInfoSaveButton')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('删除选中包确认后调用 deletePack 并从列表移除', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack('alpha', '1.0.0'),
        _pack('beta', '1.0.0'),
        _pack('gamma', '1.0.0'),
      ],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('beta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('deletePackDialog')), findsOneWidget);
    expect(find.text('确定要删除包「beta」吗？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deletePackConfirmButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.deleteCount, 1);
    expect(store.deletedNames, <String>['beta']);
    expect(store.packs.map((PackModel pack) => pack.name).toList(), <String>[
      'alpha',
      'gamma',
    ]);
    expect(find.text('beta'), findsNothing);
    expect(find.text('已删除'), findsOneWidget);
    expect(_selectedIndex(tester), 1);
  });

  testWidgets('删除被依赖的包时对话框显示依赖方名称', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'alpha',
          '1.0.0',
          dependencies: <DependencyModel>[
            const DependencyModel(name: 'beta', version: '1.0'),
          ],
        ),
        _pack('beta', '1.0.0'),
        _pack(
          'gamma',
          '1.0.0',
          dependencies: <DependencyModel>[
            const DependencyModel(name: 'BETA', version: '1.0'),
          ],
        ),
      ],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('beta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('deletePackDependents')), findsOneWidget);
    expect(find.text('以下包依赖它：alpha、gamma'), findsOneWidget);
    expect(find.text('删除后这些依赖将显示为「缺失」。'), findsOneWidget);
  });

  testWidgets('删除未被依赖的包时不显示依赖提示', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('alpha', '1.0.0'), _pack('beta', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('beta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('deletePackDependents')), findsNothing);
    expect(find.textContaining('以下包依赖它'), findsNothing);
  });

  testWidgets('删除最后一项后选择回退到前一项', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('alpha', '1.0.0'), _pack('beta', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('beta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('deletePackConfirmButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.packs, hasLength(1));
    expect(_selectedIndex(tester), 0);
  });

  testWidgets('取消删除时列表与存储不变', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('deletePackCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(store.deleteCount, 0);
    expect(store.packs, hasLength(1));
    expect(find.byKey(const Key('deletePackDialog')), findsNothing);
    expect(find.text('demo'), findsWidgets);
    expect(find.text('已删除'), findsNothing);
  });

  testWidgets('无包时删除按钮禁用', (tester) async {
    await _pumpMainLayout(
      tester,
      store: _FakePackStore(),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_deleteButton(tester).onPressed, isNull);
  });

  testWidgets('选中设置项时删除按钮禁用', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_deleteButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_deleteButton(tester).onPressed, isNull);
  });

  testWidgets('删除失败时显示错误提示且列表不变', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    )..failDelete = true;

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('删除文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('deletePackConfirmButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.deleteCount, 1);
    expect(store.packs, hasLength(1));
    expect(find.text('demo'), findsWidgets);
    expect(find.textContaining('删除失败'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(find.byKey(const Key('deletePackDialog')), findsNothing);
  });

  testWidgets('无包时重新映射按钮禁用', (tester) async {
    await _pumpMainLayout(
      tester,
      store: _FakePackStore(),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_remapButton(tester).onPressed, isNull);
  });

  testWidgets('选中设置项时重新映射按钮禁用', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_remapButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_remapButton(tester).onPressed, isNull);
  });

  testWidgets('重新映射成功后保存并更新包文件列表', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[FileModel(name: 'old.h', path: 'old.h', size: 64)],
        ),
      ],
    );
    String? scannedPath;
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (String path) {
        scannedPath = path;
        return completer.future;
      },
    );

    await tester.tap(find.byTooltip('重新映射'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('remapPackDialog')), findsOneWidget);
    expect(find.text('重新映射'), findsOneWidget);
    expect(find.text('正在扫描…'), findsOneWidget);
    expect(scannedPath, r'C:\libs\demo');

    completer.complete(<FileModel>[
      FileModel(name: 'new.h', path: 'new/new.h', size: 2048),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.saveCount, 1);
    expect(store.packs.single.files, hasLength(1));
    expect(store.packs.single.files.single.path, 'new/new.h');
    expect(find.text('重新映射完成'), findsOneWidget);
    expect(find.text('新增：1 个文件'), findsOneWidget);
    expect(find.text('移除：1 个文件'), findsOneWidget);
  });

  testWidgets('缺少源目录信息时提示错误且不弹出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_remapButton(tester).onPressed, isNotNull);

    await tester.tap(find.byTooltip('重新映射'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('remapPackDialog')), findsNothing);
    expect(find.text('该包缺少源目录信息，无法重新映射'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
  });

  testWidgets('无包时打包按钮禁用', (tester) async {
    await _pumpMainLayout(
      tester,
      store: _FakePackStore(),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_packButton(tester).onPressed, isNull);
  });

  testWidgets('选中设置项时打包按钮禁用', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_packButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_packButton(tester).onPressed, isNull);
  });

  testWidgets('未设置输出目录时提示错误且不弹出导出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('请先在设置页配置打包输出目录'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(find.byKey(const Key('packExportDialog')), findsNothing);
  });

  testWidgets('缺少源目录时提示错误且不弹出导出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('该包缺少源目录信息，无法打包'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(find.byKey(const Key('packExportDialog')), findsNothing);
  });

  testWidgets('设置输出目录后打开导出对话框并传入选中包与目录', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );
    PackModel? exportedPack;
    String? exportedDirectory;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportedPack = pack;
        exportedDirectory = outputDirectory;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 8,
          packageSize: 1024,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(exportedPack, isNotNull);
    expect(exportedPack!.name, 'demo');
    expect(exportedDirectory, r'D:\out');
    expect(find.text('打包完成'), findsOneWidget);
    expect(find.text('文件数量：8'), findsOneWidget);
  });
}

Future<void> _pumpMainLayout(
  WidgetTester tester, {
  required Future<String?> Function() pickDirectory,
  required Future<List<FileModel>> Function(String directoryPath) scanFiles,
  PackStore? store,
  SettingsModel settings = const SettingsModel(),
  Future<void> Function(SettingsModel settings)? onSaveSettings,
  Future<PackageExportResult> Function(PackModel pack, String outputDirectory)?
  exportPackage,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: MainLayout(
        pickDirectory: pickDirectory,
        scanFiles: scanFiles,
        store: store ?? _FakePackStore(),
        settings: settings,
        onSaveSettings: onSaveSettings ?? (SettingsModel settings) async {},
        exportPackage: exportPackage ?? exportNuGetPackage,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _fillRequiredFields(
  WidgetTester tester, {
  required String name,
  String version = '1.0.0',
}) async {
  await tester.enterText(find.byKey(const Key('packIdField')), name);
  await tester.enterText(find.byKey(const Key('packVersionField')), version);
  await tester.enterText(find.byKey(const Key('packAuthorField')), 'tester');
  await tester.pump();
}

Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

IconButton _deleteButton(WidgetTester tester) => tester.widget<IconButton>(
  find.descendant(
    of: find.byTooltip('删除文件夹'),
    matching: find.byType(IconButton),
  ),
);

IconButton _remapButton(WidgetTester tester) => tester.widget<IconButton>(
  find.descendant(
    of: find.byTooltip('重新映射'),
    matching: find.byType(IconButton),
  ),
);

IconButton _packButton(WidgetTester tester) => tester.widget<IconButton>(
  find.descendant(
    of: find.byTooltip('打包文件夹'),
    matching: find.byType(IconButton),
  ),
);

int? _selectedIndex(WidgetTester tester) =>
    tester.widget<NavigationView>(find.byType(NavigationView)).pane?.selected;

PackModel _pack(
  String name,
  String version, {
  String? sourcePath,
  List<FileModel>? files,
  List<DependencyModel>? dependencies,
}) {
  final PackModel pack = PackModel(
    name: name,
    version: version,
    author: 'tester',
    sourcePath: sourcePath,
  );
  if (files != null) {
    pack.files.addAll(files);
  }
  if (dependencies != null) {
    pack.dependencies.addAll(dependencies);
  }
  return pack;
}

Finder _pageSurface(WidgetTester tester) {
  final Color cardColor = FluentTheme.of(tester.element(find.byType(Setting)))
      .cardColor;
  return find.descendant(
    of: find.byType(Setting),
    matching: find.byWidgetPredicate((Widget widget) {
      if (widget is! Container) {
        return false;
      }
      final Decoration? decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == cardColor;
    }),
  );
}

class _FakePackStore extends PackStore {
  _FakePackStore({List<PackModel>? packs, List<PackLoadError>? errors})
    : _packs = <PackModel>[...?packs],
      _errors = <PackLoadError>[...?errors],
      super(rootPath: 'fake');

  final List<PackModel> _packs;
  final List<PackLoadError> _errors;
  int saveCount = 0;
  int deleteCount = 0;
  bool failSave = false;
  bool failDelete = false;
  final List<String> deletedNames = <String>[];

  List<PackModel> get packs => _packs;

  @override
  Future<void> ensureConfigExist() async {}

  @override
  Future<PackLoadResult> loadPacks() async => (
    packs: List<PackModel>.of(_packs),
    errors: List<PackLoadError>.of(_errors),
  );

  @override
  Future<void> savePack(PackModel pack) async {
    if (failSave) {
      throw const FileSystemException('磁盘已满');
    }
    saveCount++;
    final int existing = _packs.indexWhere(
      (PackModel item) => item.name.toLowerCase() == pack.name.toLowerCase(),
    );
    if (existing >= 0) {
      _packs[existing] = pack;
    } else {
      _packs.add(pack);
    }
  }

  @override
  Future<void> deletePack(String name) async {
    deleteCount++;
    if (failDelete) {
      throw const FileSystemException('删除出错');
    }
    deletedNames.add(name);
    _packs.removeWhere(
      (PackModel item) => item.name.toLowerCase() == name.toLowerCase(),
    );
  }
}
