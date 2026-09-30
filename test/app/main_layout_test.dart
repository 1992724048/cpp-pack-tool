import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/app/app_info.dart';
import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/nuget/header_include_fixer.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/pack/pack_store.dart';
import 'package:cpp_nuget_pack/main.dart';
import 'package:cpp_nuget_pack/pack/model/cmd_model.dart';
import 'package:cpp_nuget_pack/pack/model/dependency_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/history_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/pack/package_scaffold.dart';
import 'package:cpp_nuget_pack/settings/settings_model.dart';
import 'package:cpp_nuget_pack/nuget/ui/pack_export_dialog.dart';
import 'package:cpp_nuget_pack/nuget/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/app/about_page.dart';
import 'package:cpp_nuget_pack/app/pack_app.dart';
import 'package:cpp_nuget_pack/settings/ui/setting.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
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
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
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

  testWidgets('重新映射后自动注册 pre/post.bat 系统条目', (tester) async {
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
      r'"$(MSBuildThisFileDirectory)files\script\pre.bat" "$(TargetPath)"',
    );
    expect(pre.type, CmdType.preBuild);
    expect(pre.system, isTrue);
    expect(saved.commands[1].type, CmdType.postBuild);
    expect(saved.commands[1].system, isTrue);
    expect(saved.dependencies, isEmpty);
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
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
            builtPack = pack;
            receivedEnvironment = environment;
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
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('新增：1 个文件'), findsOneWidget);
    expect(find.text('移除：2 个文件'), findsOneWidget);
    expect(store.saveCount, 1);
    expect(store.packs.single.files, hasLength(1));
    expect(store.packs.single.files.single.path, 'new/new.h');
  });

  testWidgets('默认构建接线使用流式构建执行器', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      FluentApp(
        home: MainLayout(
          pickDirectory: () async => null,
          scanFiles: (_) async => <FileModel>[],
          store: _FakePackStore(),
          detectCompilers: _noCompilers,
        ),
      ),
    );
    await tester.pump();

    final MainLayout layout = tester.widget<MainLayout>(
      find.byType(MainLayout),
    );
    expect(
      layout.buildPack,
      runPackBuildStreaming,
      reason: '生产默认应经 Process.start 流式转发构建输出',
    );
  });

  testWidgets('构建对话框：时间线恒为准备环境 → 准备源码 → 执行构建 → 检查头文件引用 → 重新映射 → 完成', (tester) async {
    // 时间线已合一：不再按「源码区有无」分叉，打开对话框只可能是这一张表，
    // 过去那对「注入 true / 注入 false」的极性用例随之失去判别对象。下面把六步
    // 的文案、步骤节点与「下载」「分类」不再是任何步骤的标签一并钉住——实现若把
    // 构建阶段映回 download 步骤、或把下载百分比说成下载进度，此处即转红。
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
    final Completer<BuildEnvironment> prepareGate =
        Completer<BuildEnvironment>();
    final Completer<void> buildGate = Completer<void>();

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      prepareBuildEnv: (
        PackModel pack, {
        required List<String> compilerPriority,
        required List<DetectedCompiler> cachedCompilers,
        required CompilerDetectionCallback onCompilersDetected,
      }) => prepareGate.future,
      buildPack: (
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
      }) async {
        await buildGate.future;
      },
    );

    await tester.tap(find.text('文件管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('buildPackButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('准备环境'), findsOneWidget);
    expect(find.text('准备源码'), findsOneWidget);
    expect(find.text('执行构建'), findsOneWidget);
    expect(find.text('检查头文件引用'), findsOneWidget);
    expect(find.text('重新映射'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('下载'), findsNothing, reason: '「下载」不再是任何步骤的标签');
    expect(find.text('分类'), findsNothing, reason: '分类步骤已随时间线合一删除');
    expect(find.byKey(const Key('buildTimelineStep_prepare')), findsOneWidget);
    expect(find.byKey(const Key('buildTimelineStep_download')), findsOneWidget);
    expect(find.byKey(const Key('buildTimelineStep_build')), findsOneWidget);
    expect(find.byKey(const Key('buildTimelineStep_includes')), findsOneWidget);
    expect(find.byKey(const Key('buildTimelineStep_remap')), findsOneWidget);
    expect(find.byKey(const Key('buildTimelineStep_done')), findsOneWidget);
    expect(
      find.byKey(const Key('buildTimelineStep_classify')),
      findsNothing,
      reason: '分类步骤已随时间线合一删除，序列表里不再有它',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('buildTimelineStep_prepare')),
        matching: find.byType(ProgressRing),
      ),
      findsOneWidget,
      reason: '环境准备未完成时进行中的步骤恒为准备环境',
    );

    prepareGate.complete(_buildEnvironment());
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('buildTimelineStep_build')),
        matching: find.byType(ProgressRing),
      ),
      findsOneWidget,
      reason: '环境就绪后进行中的步骤恒为执行构建，不再是下载/准备源码',
    );

    buildGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('构建后自动修复头文件引用并以悬浮提示与待处理对话框上报', (tester) async {
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
    (String, String)? received;
    const HeaderIncludeFixReport report = HeaderIncludeFixReport(
      fixed: <HeaderIncludeFix>[
        HeaderIncludeFix(
          filePath: 'src/gtest/gtest-all.cc',
          line: 2,
          from: 'src/gtest.cc',
          to: 'gtest.cc',
        ),
      ],
      issues: <HeaderIncludeIssue>[
        HeaderIncludeIssue(
          filePath: 'src/gtest/gtest.cc',
          line: 133,
          include: 'src/gtest-internal-inl.h',
          kind: HeaderIncludeIssueKind.crossTree,
          candidates: <String>['src/gtest/gtest-internal-inl.h'],
        ),
      ],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[
        FileModel(name: 'new.h', path: 'new/new.h', size: 1),
      ],
      prepareBuildEnv: (
        PackModel pack, {
        required List<String> compilerPriority,
        required List<DetectedCompiler> cachedCompilers,
        required CompilerDetectionCallback onCompilersDetected,
      }) async => _buildEnvironment(),
      buildPack: (
        PackModel pack, {
        Map<String, String>? environment,
        void Function(String line)? onOutput,
      }) async {},
      fixIncludes: (String sourcePath, {required String packageName}) async {
        received = (sourcePath, packageName);
        return report;
      },
    );

    await tester.tap(find.text('文件管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('buildPackButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(received, (r'C:\libs\demo', 'demo'));

    await tester.tap(find.byKey(const Key('buildCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('已自动修复 1 处头文件引用'), findsOneWidget);
    expect(find.byKey(const Key('headerIncludeIssuesDialog')), findsOneWidget);
    expect(find.text('src/gtest/gtest.cc:133'), findsOneWidget);
    expect(
      find.text(
        '"src/gtest-internal-inl.h"：唯一候选无适用改写形态：src/gtest/gtest-internal-inl.h',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('headerIncludeIssuesCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('headerIncludeIssuesDialog')), findsNothing);
  });

  testWidgets('打包前自动修复失效引用并刷新被改写文件的大小快照', (tester) async {
    // 真实文件 I/O 必须整体放进 runAsync：testWidgets 的 fake_async 测试区里
    // 真实 future 永不落定，createTemp / stat 任一处漏出去都会挂死整个用例。
    // 清理改用同步删除，避免在 tearDown 里留下同样的真实 future。
    late Directory sourceRoot;
    late File patched;
    await tester.runAsync(() async {
      sourceRoot = await Directory.systemTemp.createTemp('cnp_export_fix_');
      patched = File('${sourceRoot.path}/src/gtest/gtest.cc')
        ..createSync(recursive: true)
        ..writeAsStringSync('// hello\n');
    });
    addTearDown(() {
      if (sourceRoot.existsSync()) {
        sourceRoot.deleteSync(recursive: true);
      }
    });
    // size 故意写错：修复改写了文件字节数，导出用的快照必须被重新 stat 刷新
    const int staleSize = 1;
    expect(patched.lengthSync(), isNot(staleSize));

    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: sourceRoot.path,
          files: <FileModel>[
            FileModel(
              name: 'gtest.cc',
              path: 'src/gtest/gtest.cc',
              size: staleSize,
            ),
            ..._buildPyFiles(),
          ],
        ),
      ],
    );
    (String, String)? received;
    PackModel? exportedPack;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
        exportedPack = pack;
        return (
          outputPath: r'D:\out\demo.1.0.0.nupkg',
          fileCount: 8,
          packageSize: 1024,
        );
      },
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      fixIncludes: (String sourcePath, {required String packageName}) async {
        received = (sourcePath, packageName);
        return const HeaderIncludeFixReport(
          fixed: <HeaderIncludeFix>[
            HeaderIncludeFix(
              filePath: 'src/gtest/gtest.cc',
              line: 1,
              from: 'src/gtest-internal-inl.h',
              to: 'gtest/src/gtest/gtest-internal-inl.h',
            ),
          ],
          issues: <HeaderIncludeIssue>[
            HeaderIncludeIssue(
              filePath: 'src/gtest/gtest.cc',
              line: 2,
              include: 'src/prim/windows/etw.h',
              kind: HeaderIncludeIssueKind.noCandidate,
            ),
          ],
        );
      },
    );

    // 大小刷新同样含真实文件 I/O，导出点击也须在 runAsync 的真实事件循环中完成
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('打包文件夹'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(received, (sourceRoot.path, 'demo'));
    expect(find.text('打包前自动修复 1 处失效引用'), findsOneWidget);
    expect(find.byKey(const Key('headerIncludeIssuesDialog')), findsOneWidget);
    expect(find.text('src/gtest/gtest.cc:2'), findsOneWidget);

    // 悬浮提示的自动关闭是 fake_async 区的待决定时器，runAsync 拒绝在其仍挂起时
    // 再次进入；先把它跑完。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    // 整条导出链（含等待问题对话框关闭）都起自 runAsync 的真实事件循环，
    // 关闭动作同样得在真实事件循环里点：tester.pump 只推进 fake_async，
    // 真实事件循环不转，链上后续的 await 永不落定。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('headerIncludeIssuesCloseButton')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.byKey(const Key('packExportDialog')), findsOneWidget);
    expect(exportedPack, isNotNull);
    final Map<String, int> sizes = <String, int>{
      for (final FileModel file in exportedPack!.files) file.path: file.size,
    };
    expect(sizes['src/gtest/gtest.cc'], patched.lengthSync());
    expect(sizes['build.py'], 10);
  });

  testWidgets('构建失败后按 Esc 不关闭对话框且关闭按钮仍记录失败条目', (tester) async {
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

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
      prepareBuildEnv: (
        PackModel pack, {
        required List<String> compilerPriority,
        required List<DetectedCompiler> cachedCompilers,
        required CompilerDetectionCallback onCompilersDetected,
      }) async => _buildEnvironment(),
      buildPack:
          (
            PackModel pack, {
            Map<String, String>? environment,
            void Function(String line)? onOutput,
          }) async {
            throw const PackBuildException('构建失败（退出码 1）');
          },
    );

    await tester.tap(find.text('文件管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('buildPackButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('构建失败：构建失败（退出码 1）'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const Key('buildPackDialog')),
      findsOneWidget,
      reason: '失败态按 Esc 不得撤走对话框：失败条目必须经关闭按钮回传落盘',
    );

    await tester.tap(find.byKey(const Key('buildCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('buildPackDialog')), findsNothing);
    expect(store.saveCount, 1);
    expect(store.packs.single.history, hasLength(1));
    final HistoryModel entry = store.packs.single.history.single;
    expect(entry.type, HistoryType.built);
    expect(entry.message, '构建失败：构建失败（退出码 1）');
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

    expect(find.text('请先在设置页配置 NuGet 打包输出目录'), findsOneWidget);
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
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
          files: _collidingHeaderFiles(),
        ),
      ],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
      find.descendant(of: dialog, matching: find.text('包内路径')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('包内将随附可执行二进制；请确认来源可信。'),
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
          files: _collidingHeaderFiles(),
        ),
      ],
    );
    int exportCalls = 0;

    await _pumpMainLayout(
      tester,
      store: store,
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
      find.descendant(of: dialog, matching: find.text('tool.exe')),
      findsOneWidget,
    );
    expect(find.byTooltip('build/native/files/executable/bin/tool.exe'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('可执行二进制随包分发')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('包内将随附可执行二进制；请确认来源可信。'),
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

  testWidgets('NuGet 格式包内路径重复与 exe 警告合并展示且可继续', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[
        _pack(
          'demo',
          '1.0.0',
          sourcePath: r'C:\libs\demo',
          files: <FileModel>[
            ..._collidingHeaderFiles(),
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
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async {
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
      find.descendant(of: dialog, matching: find.text('包内路径')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('tool.exe')),
      findsOneWidget,
    );
    expect(find.byTooltip('build/native/files/executable/bin/tool.exe'), findsOneWidget);
    // 两类问题并存时仍展示供应链提示
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('包内将随附可执行二进制；请确认来源可信。'),
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
        ),
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

  testWidgets('导出成功后追加打包历史条目', (tester) async {
    final _FakePackStore store = _FakePackStore(
      packs: <PackModel>[_pack('demo', '1.0.0', sourcePath: r'C:\libs\demo')],
    );

    await _pumpMainLayout(
      tester,
      store: store,
      now: () => DateTime(2026, 9, 11, 14, 30, 5),
      settings: const SettingsModel(outputDirectory: r'D:\out'),
      exportPackage: (
        PackModel pack,
        String outputDirectory, {
        void Function(double fraction)? onProgress,
        ExportCancelToken? cancelToken,
      }) async => (
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

  testWidgets('工具栏创建包结构按钮无条件可用', (tester) async {
    final _FakePackStore store = _FakePackStore();

    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    expect(store.packs, isEmpty);
    expect(_createPackageStructureButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_createPackageStructureButton(tester).onPressed, isNotNull);
  });

  testWidgets('取消目录选择时不弹出创建包结构对话框', (tester) async {
    await _pumpMainLayout(
      tester,
      pickDirectory: () async => null,
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('创建包结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('选定目录后弹出创建包结构对话框并显示路径与时序说明', (tester) async {
    await _pumpMainLayout(
      tester,
      pickDirectory: () async => r'C:\libs\foo',
      scanFiles: (_) async => <FileModel>[],
    );

    await tester.tap(find.byTooltip('创建包结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text(r'路径：C:\libs\foo'), findsOneWidget);
    expect(find.byKey(const Key('packIdField')), findsOneWidget);
    expect(find.textContaining('不会因为创建文件就自动注册进命令列表'), findsOneWidget);
  });

  testWidgets('创建包结构确认后落盘为包、记一次创建历史并选中新建的包', (tester) async {
    // 真实文件 I/O 整体放进 runAsync（口径同「打包前自动修复」用例）：先用真实脚手架
    // 把结构铺满，对话框内那次落盘便只剩同步存在性检查，fake_async 测试区不会挂死。
    late Directory sourceRoot;
    await tester.runAsync(() async {
      sourceRoot = await Directory.systemTemp.createTemp('cnp_scaffold_');
      await createPackageStructure(sourceRoot.path);
    });
    addTearDown(() {
      if (sourceRoot.existsSync()) {
        sourceRoot.deleteSync(recursive: true);
      }
    });

    // 预置 aaa：只有 1 个包时选中下标 0 是唯一可能值，抓不到「选错了包」。
    final _FakePackStore store = _FakePackStore(packs: <PackModel>[_pack('aaa', '0.9.0')]);
    await _pumpMainLayout(
      tester,
      store: store,
      now: () => DateTime(2026, 9, 30, 10, 0, 0),
      pickDirectory: () async => sourceRoot.path,
      scanFiles: (_) async => <FileModel>[
        FileModel(name: 'build.py', path: 'build.py', size: 900),
        FileModel(name: 'post.bat', path: 'post.bat', size: 120),
        FileModel(name: 'pre.bat', path: 'pre.bat', size: 120),
      ],
    );

    await tester.tap(find.byTooltip('创建包结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _fillRequiredFields(tester, name: 'demo');
    await tester.enterText(find.byKey(const Key('packDescriptionField')), '端到端演示包');
    await _selectLicense(tester, 'MIT');
    await _tapDialogButton(tester, '确定');
    expect(find.text('目标目录非空'), findsOneWidget);
    await _tapDialogButton(tester, '继续创建');

    expect(store.saveCount, 1);
    expect(store.packs, hasLength(2));
    final PackModel saved = store.packs.lastWhere((PackModel pack) => pack.name == 'demo');
    expect(saved.version, '1.0.0');
    expect(saved.author, 'tester');
    expect(saved.description, '端到端演示包');
    expect(saved.license, 'MIT');
    expect(saved.sourcePath, sourceRoot.path);
    expect(saved.files, hasLength(3));
    expect(saved.history, hasLength(1));
    expect(saved.history.single.type, HistoryType.created);
    expect(saved.history.single.message, '创建包：3 个文件，总大小 1.1 KB');
    expect(_selectedIndex(tester), 1, reason: '按名排序后 demo 在 aaa 之后；硬编码选中第 0 项会被这条抓住');
    expect(find.text('尚未添加'), findsNothing);
    // 结构已预铺，3 个模板文件全部走「已存在、未覆盖」：规格 §7.5 要求记入汇总，
    // 而落盘前的确认框只是预演，不能当汇总用。
    expect(find.textContaining('跳过 3 个已存在、未覆盖的文件'), findsOneWidget);
  });

  testWidgets('创建包结构关闭对话框后的扫描空窗期工具栏保持忙碌态', (tester) async {
    late Directory sourceRoot;
    await tester.runAsync(() async {
      sourceRoot = await Directory.systemTemp.createTemp('cnp_scaffold_busy_');
      await createPackageStructure(sourceRoot.path);
    });
    addTearDown(() {
      if (sourceRoot.existsSync()) {
        sourceRoot.deleteSync(recursive: true);
      }
    });

    // 扫描用 Completer 挂起，把「对话框已关、扫描未完」这段空窗固定住。
    final Completer<List<FileModel>> scan = Completer<List<FileModel>>();
    final _FakePackStore store = _FakePackStore();
    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => sourceRoot.path,
      scanFiles: (_) => scan.future,
    );

    await tester.tap(find.byTooltip('创建包结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _fillRequiredFields(tester, name: 'demo');
    await _tapDialogButton(tester, '确定');
    await _tapDialogButton(tester, '继续创建');

    expect(find.byType(ContentDialog), findsNothing);
    expect(_createPackageStructureButton(tester).onPressed, isNull);
    expect(
      find.descendant(of: find.byTooltip('创建包结构'), matching: find.byType(ProgressRing)),
      findsOneWidget,
      reason: '扫描与保存期间没有任何对话框遮挡，忙碌态是用户唯一的进度反馈',
    );
    expect(store.saveCount, 0);

    scan.complete(<FileModel>[FileModel(name: 'build.py', path: 'build.py', size: 10)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(store.saveCount, 1);
    expect(_createPackageStructureButton(tester).onPressed, isNotNull);
  });

  testWidgets('创建包结构后扫描源目录失败时提示且不落盘', (tester) async {
    late Directory sourceRoot;
    await tester.runAsync(() async {
      sourceRoot = await Directory.systemTemp.createTemp('cnp_scaffold_scan_');
      await createPackageStructure(sourceRoot.path);
    });
    addTearDown(() {
      if (sourceRoot.existsSync()) {
        sourceRoot.deleteSync(recursive: true);
      }
    });

    final _FakePackStore store = _FakePackStore();
    await _pumpMainLayout(
      tester,
      store: store,
      pickDirectory: () async => sourceRoot.path,
      scanFiles: (_) async => throw ArgumentError('目录不存在: ${sourceRoot.path}'),
    );

    await tester.tap(find.byTooltip('创建包结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _fillRequiredFields(tester, name: 'demo');
    await _tapDialogButton(tester, '确定');
    await _tapDialogButton(tester, '继续创建');

    expect(store.saveCount, 0, reason: '扫描抛错时不得落盘，store 从未被写入');
    expect(find.textContaining('扫描包源目录失败'), findsOneWidget);
    expect(_createPackageStructureButton(tester).onPressed, isNotNull, reason: '失败后按钮必须恢复可用');
  });
}

Future<void> _pumpMainLayout(
  WidgetTester tester, {
  required Future<String?> Function() pickDirectory,
  required Future<List<FileModel>> Function(String directoryPath) scanFiles,
  PackStore? store,
  SettingsModel settings = const SettingsModel(),
  Future<void> Function(SettingsModel settings)? onSaveSettings,
  PackExportRunner? exportPackage,
  PackBuildRunner? buildPack,
  PackBuildEnvironmentPreparer? prepareBuildEnv,
  Future<List<DetectedCompiler>> Function()? detectCompilers,
  DateTime Function()? now,
  PackHeaderIncludeFixer? fixIncludes,
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
        buildPack: buildPack ?? runPackBuild,
        prepareBuildEnv: prepareBuildEnv,
        detectCompilers: detectCompilers ?? _noCompilers,
        fixIncludes: fixIncludes ?? _emptyFixIncludes,
        now: now ?? DateTime.now,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<HeaderIncludeFixReport> _emptyFixIncludes(
  String sourcePath, {
  required String packageName,
}) async => const HeaderIncludeFixReport();

Future<List<DetectedCompiler>> _noCompilers() async =>
    const <DetectedCompiler>[];

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

IconButton _createPackageStructureButton(WidgetTester tester) =>
    tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('创建包结构'),
        matching: find.byType(IconButton),
      ),
    );

int? _selectedIndex(WidgetTester tester) =>
    tester.widget<NavigationView>(find.byType(NavigationView)).pane?.selected;

PackModel _pack(
  String name,
  String version, {
  String author = 'tester',
  String? sourcePath,
  List<FileModel>? files,
  List<DependencyModel>? dependencies,
  List<HistoryModel>? history,
}) {
  final PackModel pack = PackModel(
    name: name,
    version: version,
    author: author,
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
  return pack;
}

/// 源目录为 `C:\libs\demo` 时命名空间取 `demo`：`include/demo/foo.h` 命中前缀被
/// 保留，`include/foo.h` 则被补上命名空间，两者落到同一包内路径以触发重复。
List<FileModel> _collidingHeaderFiles() => <FileModel>[
  FileModel(name: 'foo.h', path: 'include/foo.h', size: 8),
  FileModel(name: 'foo.h', path: 'include/demo/foo.h', size: 8),
];

List<FileModel> _buildPyFiles() => <FileModel>[
  FileModel(name: 'build.py', path: 'build.py', size: 10),
];

Finder _pageSurface(WidgetTester tester) {
  return find.descendant(
    of: find.byType(Setting),
    matching: find.byKey(const Key('settingsPageSurface')),
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
  final Set<String> failSaveFor = <String>{};
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
    if (failSave || failSaveFor.contains(pack.name.toLowerCase())) {
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
