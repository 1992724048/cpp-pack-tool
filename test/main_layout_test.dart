import 'dart:io';

import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/main.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
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

    expect(find.text('设置内容'), findsOneWidget);
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

  testWidgets('配置文件加载失败时通过 InfoBar 提示', (tester) async {
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

    expect(find.byType(InfoBar), findsOneWidget);
    expect(find.text('1 个配置加载失败'), findsOneWidget);
    expect(find.textContaining('broken.yaml'), findsOneWidget);
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
}

Future<void> _pumpMainLayout(
  WidgetTester tester, {
  required Future<String?> Function() pickDirectory,
  required Future<List<FileModel>> Function(String directoryPath) scanFiles,
  PackStore? store,
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

PackModel _pack(String name, String version) =>
    PackModel(name: name, version: version, author: 'tester');

class _FakePackStore extends PackStore {
  _FakePackStore({List<PackModel>? packs, List<PackLoadError>? errors})
    : _packs = <PackModel>[...?packs],
      _errors = <PackLoadError>[...?errors],
      super(rootPath: 'fake');

  final List<PackModel> _packs;
  final List<PackLoadError> _errors;
  int saveCount = 0;
  bool failSave = false;

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
}
