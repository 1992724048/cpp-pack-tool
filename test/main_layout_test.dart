import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/app_info.dart';
import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/main.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/packaging/cmake_exporter.dart' as cmake_exporter;
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/pages/about.dart';
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
      detectCompilers: () async => <DetectedCompiler>[
        _compiler(CompilerKind.icx, '2026.1.1'),
      ],
      onSaveSettings: (SettingsModel settings) async => saved = settings,
    );

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('settingCompilerRow_icx')), findsOneWidget);
    expect(find.text('2026.1.1'), findsOneWidget);

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

  testWidgets('设置页无缓存时自动检测并经保存链写回', (tester) async {
    SettingsModel? saved;

    await _pumpMainLayout(
      tester,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      detectCompilers: () async => <DetectedCompiler>[
        _compiler(CompilerKind.icx, '2026.1.1'),
      ],
      onSaveSettings: (SettingsModel settings) async => saved = settings,
    );

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('2026.1.1'), findsOneWidget);
    expect(saved, isNotNull);
    expect(saved!.detectedCompilers, hasLength(1));
    expect(saved!.detectedCompilers.single.kind, CompilerKind.icx);
    expect(saved!.detectedCompilers.single.version, '2026.1.1');
  });

  testWidgets('构建准备透传缓存并经保存链写回新检测结果', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: _buildPyFiles(),
        ),
      ],
    );
    SettingsModel? saved;
    List<String>? receivedPriority;
    List<DetectedCompiler>? receivedCache;
    final BuildEnvironment prepared = _buildEnvironment();

    await _pumpMainLayout(
      tester,
      store: store,
      settings: SettingsModel(
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[
        FileModel(name: 'build.py', path: 'build.py', size: 10),
      ],
      onSaveSettings: (SettingsModel settings) async => saved = settings,
      loadBuildHeader: (PackModel pack) async => null,
      prepareBuildEnv:
          (
            PackModel pack, {
            required List<String> compilerPriority,
            required List<DetectedCompiler> cachedCompilers,
            required CompilerDetectionCallback onCompilersDetected,
          }) async {
            receivedPriority = compilerPriority;
            receivedCache = cachedCompilers;
            onCompilersDetected(<DetectedCompiler>[
              _compiler(CompilerKind.icx, '2026.2.0'),
            ]);
            return prepared;
          },
      buildPack: (
        PackModel pack,
        void Function(PackBuildStage) onStage, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
        void Function(String version)? onSourceVersion,
      }) async {},
    );

    await tester.tap(find.text('文件管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildPackButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(receivedPriority, <String>['icx']);
    expect(receivedCache?.single.version, '2026.1.0');
    expect(saved, isNotNull);
    expect(saved!.compilerPriority, <String>['icx']);
    expect(saved!.detectedCompilers.single.version, '2026.2.0');
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

  testWidgets('点击「关于」显示关于页', (tester) async {
    await _pumpMainLayout(
      tester,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('关于'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(About), findsOneWidget);
    expect(
      find.descendant(of: find.byType(About), matching: find.text(appName)),
      findsOneWidget,
    );
    expect(find.text('v$appVersion'), findsOneWidget);
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

  testWidgets('删除被依赖的包时对话框以表格显示依赖方及版本范围', (tester) async {
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
            const DependencyModel(name: 'BETA', version: '[2.0,3.0)'),
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

    final Finder dialog = find.byKey(const Key('deletePackDialog'));
    expect(find.byKey(const Key('deletePackDependents')), findsOneWidget);
    expect(find.text('以下包依赖它：'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('gamma')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('1.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('[2.0,3.0)')),
      findsOneWidget,
    );
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

  testWidgets('重新映射后自动注册 pre/post.bat 与 build.py 依赖系统条目', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[FileModel(name: 'old.h', path: 'old.h', size: 64)],
        ),
        _pack('libfoo', '2.5.0'),
      ],
    );
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (String path) => completer.future,
      loadBuildHeader: (PackModel pack) async => const BuildScriptHeader(
        repo: 'https://example.com/demo.git',
        dependencies: <BuildScriptDependency>[
          BuildScriptDependency(name: 'libfoo'),
          BuildScriptDependency(name: 'ghost', version: '[1.0,)'),
        ],
      ),
    );

    await tester.tap(find.byTooltip('重新映射'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    completer.complete(<FileModel>[
      FileModel(name: 'build.py', path: 'build.py', size: 10),
      FileModel(name: 'pre.bat', path: 'pre.bat', size: 10),
      FileModel(name: 'post.bat', path: 'post.bat', size: 10),
      FileModel(name: 'new.h', path: 'new/new.h', size: 2048),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.saveCount, 1);
    final PackModel saved = store.packs.firstWhere(
      (PackModel pack) => pack.name == 'demo',
    );
    expect(saved.commands, hasLength(2));
    final CmdModel pre = saved.commands[0];
    expect(
      pre.command,
      r'"$(MSBuildThisFileDirectory)files\pre.bat" "$(TargetPath)"',
    );
    expect(pre.type, CmdType.preBuild);
    expect(pre.system, isTrue);
    expect(saved.commands[1].type, CmdType.postBuild);
    expect(saved.commands[1].system, isTrue);
    expect(saved.dependencies, hasLength(2));
    expect(saved.dependencies[0].name, 'libfoo');
    expect(saved.dependencies[0].version, '[2.5.0,)');
    expect(saved.dependencies[0].system, isTrue);
    expect(saved.dependencies[1].name, 'ghost');
    expect(saved.dependencies[1].version, '[1.0,)');
    expect(find.text('重新映射完成'), findsOneWidget);
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

  testWidgets('文件管理页点击构建打开对话框并完成重新映射', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[
            FileModel(name: 'build.py', path: 'build.py', size: 10),
            FileModel(name: 'old.h', path: 'old/old.h', size: 64),
          ],
        ),
      ],
    );
    PackModel? builtPack;
    final List<PackBuildStage> stages = <PackBuildStage>[];
    final BuildEnvironment prepared = _buildEnvironment();
    Map<String, String>? receivedEnvironment;

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[
        FileModel(name: 'new.h', path: 'new/new.h', size: 2048),
      ],
      prepareBuildEnv: (
        PackModel pack, {
        required List<String> compilerPriority,
        required List<DetectedCompiler> cachedCompilers,
        required CompilerDetectionCallback onCompilersDetected,
      }) async => prepared,
      buildPack:
          (
            PackModel pack,
            void Function(PackBuildStage) onStage, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
            void Function(String version)? onSourceVersion,
          }) async {
            builtPack = pack;
            receivedEnvironment = environment;
            for (final PackBuildStage stage in <PackBuildStage>[
              PackBuildStage.downloading,
              PackBuildStage.building,
            ]) {
              stages.add(stage);
              onStage(stage);
            }
            onSourceVersion?.call('v9.9.9');
          },
    );

    await tester.tap(find.text('文件管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('buildPackButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(builtPack?.name, 'demo');
    expect(receivedEnvironment, same(prepared.environment));
    expect(find.byKey(const Key('buildPackDialog')), findsOneWidget);
    expect(find.text('构建完成'), findsOneWidget);
    expect(find.text('新增：1 个文件'), findsOneWidget);
    expect(find.text('移除：2 个文件'), findsOneWidget);
    expect(stages, <PackBuildStage>[
      PackBuildStage.downloading,
      PackBuildStage.building,
    ]);
    expect(store.saveCount, 1);
    expect(store.packs.single.files, hasLength(1));
    expect(store.packs.single.files.single.path, 'new/new.h');
    expect(store.packs.single.sourceVersion, 'v9.9.9');
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

    expect(find.byKey(const Key('missingDependenciesDialog')), findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(exportedPack, isNotNull);
    expect(exportedPack!.name, 'demo');
    expect(exportedDirectory, r'D:\out');
    expect(find.text('打包完成'), findsOneWidget);
    expect(find.text('文件数量：8'), findsOneWidget);
  });

  testWidgets('存在缺失依赖时先弹警告，继续后打开导出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          dependencies: <DependencyModel>[
            const DependencyModel(name: 'missinglib', version: '[1.0,2.0)'),
            const DependencyModel(name: 'MISSINGLIB', version: '9.9'),
            const DependencyModel(name: 'other', version: '3.0'),
          ],
        ),
        _pack('other', '3.0.0', sourcePath: r'C:\libs\other'),
      ],
    );
    PackModel? exportedPack;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportedPack = pack;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 2,
          packageSize: 128,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder dialog = find.byKey(const Key('missingDependenciesDialog'));
    expect(dialog, findsOneWidget);
    expect(find.text('缺失依赖'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('missinglib')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('[1.0,2.0)')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('9.9')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('other')),
      findsNothing,
    );
    expect(find.byKey(const Key('packExportDialog')), findsNothing);

    await tester.tap(
      find.byKey(const Key('missingDependenciesContinueButton')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(dialog, findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(exportedPack?.name, 'demo');
  });

  testWidgets('缺失依赖警告取消时不打开导出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          dependencies: <DependencyModel>[
            const DependencyModel(name: 'missinglib', version: '1.0'),
          ],
        ),
      ],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('missingDependenciesCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byKey(const Key('missingDependenciesDialog')), findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsNothing);
    expect(exportCalls, 0);
  });

  testWidgets('导出校验无问题时直接打开导出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byKey(const Key('packagingIssuesDialog')), findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(exportCalls, 1);
  });

  testWidgets('导出校验发现问题时弹窗，继续后打开导出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          scripts: <ScriptProjectModel>[_brokenScript()],
        ),
      ],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder dialog = find.byKey(const Key('packagingIssuesDialog'));
    expect(dialog, findsOneWidget);
    expect(find.text('导出校验'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('坏脚本')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('包内将随附可执行二进制，脚本可在构建时调用；请确认来源可信。'),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('packExportDialog')), findsNothing);
    expect(exportCalls, 0);

    await tester.tap(find.byKey(const Key('packagingIssuesContinueButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(dialog, findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(exportCalls, 1);
  });

  testWidgets('导出校验发现问题时取消则不打开导出对话框', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          scripts: <ScriptProjectModel>[_brokenScript()],
        ),
      ],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder dialog = find.byKey(const Key('packagingIssuesDialog'));
    expect(dialog, findsOneWidget);

    await tester.tap(find.byKey(const Key('packagingIssuesCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(dialog, findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsNothing);
    expect(exportCalls, 0);
  });

  testWidgets('NuGet 格式包内 exe 弹导出校验并显示供应链提示', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[
            FileModel(name: 'tool.exe', path: 'bin/tool.exe', size: 64),
          ],
        ),
      ],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder dialog = find.byKey(const Key('packagingIssuesDialog'));
    expect(dialog, findsOneWidget);
    expect(find.text('导出校验'), findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('build/native/files/bin/tool.exe'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('可执行二进制随包分发')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('包内将随附可执行二进制，脚本可在构建时调用；请确认来源可信。'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('packExportDialog')), findsNothing);
    expect(exportCalls, 0);

    await tester.tap(find.byKey(const Key('packagingIssuesContinueButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(dialog, findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(exportCalls, 1);
  });

  testWidgets('NuGet 格式脚本问题与 exe 警告合并展示且可继续', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          scripts: <ScriptProjectModel>[_brokenScript()],
          files: <FileModel>[
            FileModel(name: 'tool.exe', path: 'bin/tool.exe', size: 64),
          ],
        ),
      ],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        exportCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder dialog = find.byKey(const Key('packagingIssuesDialog'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('坏脚本')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('build/native/files/bin/tool.exe'),
      ),
      findsOneWidget,
    );
    // 两类问题并存时仍展示供应链提示
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('包内将随附可执行二进制，脚本可在构建时调用；请确认来源可信。'),
      ),
      findsOneWidget,
    );
    expect(exportCalls, 0);

    await tester.tap(find.byKey(const Key('packagingIssuesContinueButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(dialog, findsNothing);
    expect(exportCalls, 1);
  });

  testWidgets('选择 CMake 格式时坏脚本不入校验且无 exe 不弹窗', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          scripts: <ScriptProjectModel>[_brokenScript()],
        ),
      ],
    );
    int nugetCalls = 0;
    int cmakeCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        nugetCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      exportCmakePackage: (PackModel pack, String outputDirectory) async {
        cmakeCalls++;
        return (
          outputPath: r'D:\out\demo-1.0.0-cmake.zip',
          fileCount: 2,
          packageSize: 128,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('打包设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('packagingBuilderField')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('CMake').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byKey(const Key('packagingIssuesDialog')), findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(cmakeCalls, 1);
    expect(nugetCalls, 0);
  });

  testWidgets('选择 CMake 格式时包内 exe 弹导出校验并调用 CMake 导出器', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[
            FileModel(name: 'tool.exe', path: 'bin/tool.exe', size: 64),
          ],
        ),
      ],
    );
    int nugetCalls = 0;
    int cmakeCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        nugetCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      exportCmakePackage: (PackModel pack, String outputDirectory) async {
        cmakeCalls++;
        return (
          outputPath: r'D:\out\demo-1.0.0-cmake.zip',
          fileCount: 2,
          packageSize: 128,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('打包设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('packagingBuilderField')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('CMake').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder dialog = find.byKey(const Key('packagingIssuesDialog'));
    expect(dialog, findsOneWidget);
    expect(find.text('导出校验'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('files/bin/tool.exe')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('包内将随附可执行二进制，脚本可在构建时调用；请确认来源可信。'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('packExportDialog')), findsNothing);
    expect(cmakeCalls, 0);

    await tester.tap(find.byKey(const Key('packagingIssuesContinueButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(dialog, findsNothing);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(cmakeCalls, 1);
    expect(nugetCalls, 0);
  });

  testWidgets('选择 CMake 格式后打包调用 CMake 导出器', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );
    int nugetCalls = 0;
    int cmakeCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async {
        nugetCalls++;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 1,
          packageSize: 64,
        );
      },
      exportCmakePackage: (PackModel pack, String outputDirectory) async {
        cmakeCalls++;
        return (
          outputPath: r'D:\out\demo-1.0.0-cmake.zip',
          fileCount: 2,
          packageSize: 128,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.text('打包设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('packagingBuilderField')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('CMake').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(cmakeCalls, 1);
    expect(nugetCalls, 0);
    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(find.text('打包完成'), findsOneWidget);
    expect(find.text('文件数量：2'), findsOneWidget);
  });

  testWidgets('无包时历史按钮禁用', (tester) async {
    await _pumpMainLayout(
      tester,
      store: _FakePackStore(),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_historyButton(tester).onPressed, isNull);
  });

  testWidgets('选中设置项时历史按钮禁用', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_historyButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_historyButton(tester).onPressed, isNull);
  });

  testWidgets('创建包后追加创建历史条目', (tester) async {
    final _FakePackStore store = _FakePackStore();

    await _pumpMainLayout(
      tester,
      store: store,
      now: () => DateTime(2026, 9, 11, 14, 30, 5),
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

    expect(store.packs, hasLength(1));
    expect(store.packs.single.history, hasLength(1));
    final HistoryModel entry = store.packs.single.history.single;
    expect(entry.type, HistoryType.created);
    expect(entry.time, DateTime(2026, 9, 11, 14, 30, 5));
    expect(entry.message, '创建包：1 个文件，总大小 128 B');
  });

  testWidgets('版本变更保存后追加版本历史条目', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      now: () => DateTime(2026, 9, 11, 14, 30, 5),
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

    expect(store.packs.single.version, '2.0.0');
    expect(store.packs.single.history, hasLength(1));
    final HistoryModel entry = store.packs.single.history.single;
    expect(entry.type, HistoryType.versionChanged);
    expect(entry.time, DateTime(2026, 9, 11, 14, 30, 5));
    expect(entry.message, '版本变更：1.0.0 → 2.0.0');
  });

  testWidgets('重新映射有变化时追加映射历史条目', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[FileModel(name: 'old.h', path: 'old.h', size: 64)],
        )..buildOptions = <String, String>{'tbb': 'on'},
      ],
    );
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpMainLayout(
      tester,
      store: store,
      now: () => DateTime(2026, 9, 11, 14, 30, 5),
      pickDirectory: () async => null,
      scanFiles: (String path) => completer.future,
    );

    await tester.tap(find.byTooltip('重新映射'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    completer.complete(<FileModel>[
      FileModel(name: 'new.h', path: 'new/new.h', size: 2048),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.packs.single.files.single.path, 'new/new.h');
    expect(store.packs.single.buildOptions, <String, String>{'tbb': 'on'});
    expect(store.packs.single.history, hasLength(1));
    final HistoryModel entry = store.packs.single.history.single;
    expect(entry.type, HistoryType.filesChanged);
    expect(entry.time, DateTime(2026, 9, 11, 14, 30, 5));
    expect(entry.message, '重新映射：新增 1 个文件、移除 1 个；总大小 64 B → 2.0 KB');
  });

  testWidgets('重新映射无变化时不追加历史条目', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[
            FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
          ],
          history: <HistoryModel>[
            HistoryModel(
              time: DateTime(2026, 9, 11, 14, 30, 5),
              type: HistoryType.created,
              message: '创建包：1 个文件，总大小 128 B',
            ),
          ],
        ),
      ],
    );
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpMainLayout(
      tester,
      store: store,
      now: () => DateTime(2026, 9, 12, 9, 0, 0),
      pickDirectory: () async => null,
      scanFiles: (String path) => completer.future,
    );

    await tester.tap(find.byTooltip('重新映射'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    completer.complete(<FileModel>[
      FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.saveCount, 1);
    expect(store.packs.single.history, hasLength(1));
    expect(store.packs.single.history.single.type, HistoryType.created);
    expect(store.packs.single.history.single.message, '创建包：1 个文件，总大小 128 B');
  });

  testWidgets('手工重新映射保留已记录的仓库版本', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[FileModel(name: 'old.h', path: 'old.h', size: 64)],
        )..sourceVersion = 'v1.0.0',
      ],
    );
    final Completer<List<FileModel>> completer = Completer<List<FileModel>>();

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (String path) => completer.future,
    );

    await tester.tap(find.byTooltip('重新映射'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    completer.complete(<FileModel>[
      FileModel(name: 'new.h', path: 'new/new.h', size: 128),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.packs.single.sourceVersion, 'v1.0.0');
    expect(store.packs.single.files.single.path, 'new/new.h');
  });

  testWidgets('导出成功后追加打包历史条目', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      now: () => DateTime(2026, 9, 11, 14, 30, 5),
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (PackModel pack, String outputDirectory) async => (
        outputPath: r'D:\out\demo.1.0.0.nupkg',
        fileCount: 8,
        packageSize: 1024,
      ),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('打包文件夹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.saveCount, 1);
    expect(store.packs.single.history, hasLength(1));
    final HistoryModel entry = store.packs.single.history.single;
    expect(entry.type, HistoryType.exported);
    expect(entry.time, DateTime(2026, 9, 11, 14, 30, 5));
    expect(entry.message, r'打包导出：D:\out\demo.1.0.0.nupkg');
  });

  testWidgets('删除历史条目后保存并更新列表', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          history: <HistoryModel>[
            HistoryModel(
              time: DateTime(2026, 9, 11, 14, 30, 5),
              type: HistoryType.created,
              message: '创建包：1 个文件',
            ),
            HistoryModel(
              time: DateTime(2026, 9, 12, 9, 0, 0),
              type: HistoryType.exported,
              message: r'打包导出：D:\out\demo.nupkg',
            ),
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

    await tester.tap(find.byTooltip('历史记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('packHistoryDialog')), findsOneWidget);
    expect(find.text(r'打包导出：D:\out\demo.nupkg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('historyDeleteButton_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(store.saveCount, 1);
    expect(store.packs.single.history, hasLength(1));
    expect(store.packs.single.history.single.type, HistoryType.created);
    expect(find.text(r'打包导出：D:\out\demo.nupkg'), findsNothing);
    expect(find.text('已删除'), findsOneWidget);
  });

  testWidgets('有包时点击依赖关系图按钮打开对话框并显示节点', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack('alpha', '1.0.0'),
        _pack(
          'beta',
          '1.0.0',
          dependencies: <DependencyModel>[
            const DependencyModel(name: 'alpha', version: '1.0'),
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

    await tester.tap(find.byTooltip('依赖关系图'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder dialog = find.byKey(const Key('dependencyGraphDialog'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('beta')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('dependencyGraphCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byKey(const Key('dependencyGraphDialog')), findsNothing);
  });

  testWidgets('无包时依赖关系图按钮禁用', (tester) async {
    await _pumpMainLayout(
      tester,
      store: _FakePackStore(),
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_dependencyGraphButton(tester).onPressed, isNull);
  });

  testWidgets('选中设置项时依赖关系图按钮禁用', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_dependencyGraphButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_dependencyGraphButton(tester).onPressed, isNull);
  });

  testWidgets('选中关于项时依赖关系图按钮禁用', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(_dependencyGraphButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('关于'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_dependencyGraphButton(tester).onPressed, isNull);
  });

  testWidgets('有仓库的包显示 git 徽标，有新版本时替换为更新徽标', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'alpha',
          '1.0.0',
          sourcePath: r'C:\libs\alpha',
          files: _buildPyFiles(),
        )..sourceVersion = 'v1.0.0',
        _pack(
          'beta',
          '1.0.0',
          sourcePath: r'C:\libs\beta',
          files: _buildPyFiles(),
        )..sourceVersion = 'v2.0.0',
        _pack('gamma', '1.0.0'),
      ],
    );
    int remoteCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      loadBuildHeader: (PackModel pack) async => pack.name == 'gamma'
          ? null
          : const BuildScriptHeader(repo: 'https://example.com/demo.git'),
      loadRemoteTags: (String repoUrl) async {
        remoteCalls++;
        return <String>['v1.0.0', 'v2.0.0'];
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('repoUpdateBadge_alpha')), findsOneWidget);
    expect(find.byKey(const Key('repoBadge_alpha')), findsNothing);
    expect(find.byKey(const Key('repoBadge_beta')), findsOneWidget);
    expect(find.byKey(const Key('repoUpdateBadge_beta')), findsNothing);
    expect(find.byKey(const Key('repoBadge_gamma')), findsNothing);
    expect(find.byKey(const Key('repoUpdateBadge_gamma')), findsNothing);
    expect(remoteCalls, 1, reason: '同一仓库 URL 只查询一次（会话缓存）');
  });

  testWidgets('远端查询失败时仅显示 git 徽标', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: _buildPyFiles(),
        )..sourceVersion = 'v1.0.0',
      ],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      loadBuildHeader: (PackModel pack) async =>
          const BuildScriptHeader(repo: 'https://example.com/demo.git'),
      loadRemoteTags: (String repoUrl) async => null,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('repoBadge_demo')), findsOneWidget);
    expect(find.byKey(const Key('repoUpdateBadge_demo')), findsNothing);
  });

  testWidgets('文件管理页显示当前与远端最新版本', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: _buildPyFiles(),
        )..sourceVersion = 'v1.0.0',
      ],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      loadBuildHeader: (PackModel pack) async =>
          const BuildScriptHeader(repo: 'https://example.com/demo.git'),
      loadRemoteTags: (String repoUrl) async => <String>['v2.0.0'],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('文件管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('packRepoVersionLabel')), findsOneWidget);
    expect(find.text('当前版本：v1.0.0'), findsOneWidget);
    expect(find.text('最新版本：v2.0.0'), findsOneWidget);
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
  Future<PackageExportResult> Function(PackModel pack, String outputDirectory)?
  exportCmakePackage,
  PackBuildRunner? buildPack,
  PackBuildEnvironmentPreparer? prepareBuildEnv,
  Future<List<DetectedCompiler>> Function()? detectCompilers,
  DateTime Function()? now,
  Future<BuildScriptHeader?> Function(PackModel pack)? loadBuildHeader,
  Future<List<String>?> Function(String repoUrl)? loadRemoteTags,
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
        exportCmakePackage:
            exportCmakePackage ?? cmake_exporter.exportCmakePackage,
        buildPack: buildPack ?? runPackBuild,
        prepareBuildEnv: prepareBuildEnv,
        detectCompilers: detectCompilers ?? _noCompilers,
        loadBuildHeader: loadBuildHeader ?? loadBuildScriptHeader,
        loadRemoteTags: loadRemoteTags ?? _noRemoteTags,
        now: now ?? DateTime.now,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<List<DetectedCompiler>> _noCompilers() async =>
    const <DetectedCompiler>[];

Future<List<String>?> _noRemoteTags(String repoUrl) async => null;

DetectedCompiler _compiler(CompilerKind kind, String version) {
  return DetectedCompiler(
    kind: kind,
    version: version,
    executablePath: 'C:/fake/${compilerKindId(kind)}.exe',
    environmentScript: null,
  );
}

BuildEnvironment _buildEnvironment() {
  return BuildEnvironment(
    compiler: _compiler(CompilerKind.icx, '2026.1.1'),
    environment: const <String, String>{
      'CNP_COMPILER_KIND': 'icx',
      'Path': r'C:\tools\bin',
    },
    cmakePath: r'C:\tools\cmake\bin\cmake.exe',
    ninjaPath: r'C:\tools\ninja\ninja.exe',
    toolsDir: r'C:\tools',
  );
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

IconButton _historyButton(WidgetTester tester) => tester.widget<IconButton>(
  find.descendant(
    of: find.byTooltip('历史记录'),
    matching: find.byType(IconButton),
  ),
);

IconButton _dependencyGraphButton(WidgetTester tester) =>
    tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('依赖关系图'),
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
  List<HistoryModel>? history,
  List<ScriptProjectModel>? scripts,
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
  if (history != null) {
    pack.history.addAll(history);
  }
  if (scripts != null) {
    pack.scripts.addAll(scripts);
  }
  return pack;
}

/// 无节点脚本：图校验必然报错，用于导出前校验三态测试。
ScriptProjectModel _brokenScript() =>
    ScriptProjectModel(id: 'script_1', name: '坏脚本', trigger: ScriptTrigger.pre);

List<FileModel> _buildPyFiles() => <FileModel>[
  FileModel(name: 'build.py', path: 'build.py', size: 10),
];

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
