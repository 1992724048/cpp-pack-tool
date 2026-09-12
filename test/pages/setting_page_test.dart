import 'dart:async';

import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/pages/setting.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('渲染分区标题与三项设置字段', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    expect(find.text('打包输出目录'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('深色主题配色'), findsOneWidget);
    expect(find.text('强调色'), findsOneWidget);
    expect(find.byKey(const Key('settingPickDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingClearDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingThemeModeField')), findsOneWidget);
    expect(find.byKey(const Key('settingDarkFlavorField')), findsOneWidget);
    expect(find.byKey(const Key('settingAccentField')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已设置输出目录时显示路径且清除按钮可用', (tester) async {
    await _pumpSetting(
      tester,
      settings: const SettingsModel(outputDirectory: r'D:\nuget\out'),
      onSave: (_) async {},
    );

    expect(find.text(r'D:\nuget\out'), findsOneWidget);
    expect(find.text('未设置'), findsNothing);
    expect(_clearButton(tester).onPressed, isNotNull);
  });

  testWidgets('未设置输出目录时清除按钮禁用', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    expect(_clearButton(tester).onPressed, isNull);
  });

  testWidgets('切换主题模式回传新值并提示已保存', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await _selectCombo(tester, const Key('settingThemeModeField'), '深色');

    expect(saved, isNotNull);
    expect(saved!.themeMode, ThemeModeSetting.dark);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('切换深色主题配色回传新值', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await _selectCombo(tester, const Key('settingDarkFlavorField'), 'Frappe');

    expect(saved, isNotNull);
    expect(saved!.darkFlavor, 'frappe');
    expect(saved!.themeMode, ThemeModeSetting.system);
  });

  testWidgets('切换强调色回传新值', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await _selectCombo(tester, const Key('settingAccentField'), 'Mauve');

    expect(saved, isNotNull);
    expect(saved!.accent, 'mauve');
  });

  testWidgets('选择目录后回传并显示新路径', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      pickDirectory: () async => r'D:\nuget\out',
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.tap(find.byKey(const Key('settingPickDirButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.outputDirectory, r'D:\nuget\out');
    expect(find.text(r'D:\nuget\out'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('取消目录选择时不回传', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      pickDirectory: () async => null,
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.tap(find.byKey(const Key('settingPickDirButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNull);
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('清除目录回传空值并显示未设置', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: const SettingsModel(outputDirectory: r'D:\nuget\out'),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.tap(find.byKey(const Key('settingClearDirButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.outputDirectory, isNull);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('保存失败时提示错误且不显示已保存', (tester) async {
    await _pumpSetting(tester, onSave: (_) async => throw Exception('磁盘写入失败'));

    await _selectCombo(tester, const Key('settingThemeModeField'), '浅色');

    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.textContaining('磁盘写入失败'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('编译器列表按优先级顺序展示检测结果', (tester) async {
    await _pumpSetting(
      tester,
      settings: const SettingsModel(compilerPriority: <String>['msvc', 'icx']),
      onSave: (_) async {},
      detectCompilers: () async => <DetectedCompiler>[
        _compiler(CompilerKind.icx, '2026.1.1'),
        _compiler(CompilerKind.msvc, '14.44.35207'),
      ],
    );

    expect(find.text('编译器'), findsOneWidget);
    expect(find.text('MSVC'), findsOneWidget);
    expect(find.text('14.44.35207'), findsOneWidget);
    expect(find.text('ICX'), findsOneWidget);
    expect(find.text('2026.1.1'), findsOneWidget);

    final double msvcTop = tester
        .getTopLeft(find.byKey(const Key('settingCompilerRow_msvc')))
        .dy;
    final double icxTop = tester
        .getTopLeft(find.byKey(const Key('settingCompilerRow_icx')))
        .dy;
    expect(msvcTop, lessThan(icxTop));
  });

  testWidgets('未检测到的编译器显示未检测到', (tester) async {
    await _pumpSetting(
      tester,
      settings: const SettingsModel(
        compilerPriority: <String>['icx', 'clang-cl'],
      ),
      onSave: (_) async {},
      detectCompilers: () async => <DetectedCompiler>[
        _compiler(CompilerKind.icx, '2026.1.1'),
      ],
    );

    expect(find.text('clang-cl'), findsOneWidget);
    expect(find.text('未检测到'), findsOneWidget);
    expect(find.text('2026.1.1'), findsOneWidget);
  });

  testWidgets('检测进行中显示加载态', (tester) async {
    final Completer<List<DetectedCompiler>> gate =
        Completer<List<DetectedCompiler>>();

    await _pumpSetting(
      tester,
      onSave: (_) async {},
      detectCompilers: () => gate.future,
    );

    expect(find.text('正在检测编译器…'), findsOneWidget);
    expect(find.byKey(const Key('settingCompilerRow_icx')), findsNothing);

    gate.complete(<DetectedCompiler>[_compiler(CompilerKind.icx, '2026.1.1')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('正在检测编译器…'), findsNothing);
    expect(find.byKey(const Key('settingCompilerRow_icx')), findsOneWidget);
    expect(find.text('2026.1.1'), findsOneWidget);
  });

  testWidgets('上移下移交换顺序并保存完整模型', (tester) async {
    SettingsModel? saved;

    await _pumpSetting(
      tester,
      settings: const SettingsModel(
        outputDirectory: r'D:\nuget\out',
        themeMode: ThemeModeSetting.dark,
        darkFlavor: 'frappe',
        accent: 'mauve',
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.tap(find.byKey(const Key('settingCompilerMoveDown_icx')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.compilerPriority, <String>['clang-cl', 'icx', 'msvc']);
    expect(saved!.outputDirectory, r'D:\nuget\out');
    expect(saved!.themeMode, ThemeModeSetting.dark);
    expect(saved!.darkFlavor, 'frappe');
    expect(saved!.accent, 'mauve');
    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingCompilerMoveUp_icx')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved!.compilerPriority, <String>['icx', 'clang-cl', 'msvc']);
  });

  testWidgets('编译器首行上移与末行下移禁用', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    expect(_moveUpButton(tester, 'icx').onPressed, isNull);
    expect(_moveDownButton(tester, 'icx').onPressed, isNotNull);
    expect(_moveUpButton(tester, 'msvc').onPressed, isNotNull);
    expect(_moveDownButton(tester, 'msvc').onPressed, isNull);
  });

  testWidgets('重新检测刷新编译器版本', (tester) async {
    int calls = 0;

    await _pumpSetting(
      tester,
      settings: const SettingsModel(compilerPriority: <String>['icx']),
      onSave: (_) async {},
      detectCompilers: () async {
        calls++;
        return <DetectedCompiler>[
          _compiler(CompilerKind.icx, calls == 1 ? '2026.1.1' : '2026.2.0'),
        ];
      },
    );

    expect(find.text('2026.1.1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingCompilerRefreshButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(calls, 2);
    expect(find.text('2026.2.0'), findsOneWidget);
    expect(find.text('2026.1.1'), findsNothing);
  });

  testWidgets('宽松约束下铺满可用区域且带页面背景表面', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      FluentApp(
        home: Center(
          key: const Key('settingLooseBox'),
          child: Setting(
            settings: const SettingsModel(),
            pickDirectory: () async => null,
            onSave: (_) async {},
            detectCompilers: _noCompilers,
          ),
        ),
      ),
    );
    await tester.pump();

    final Size available = tester.getSize(
      find.byKey(const Key('settingLooseBox')),
    );
    expect(tester.getSize(find.byType(Setting)), available);

    final Finder surface = _pageSurface(tester);
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface), available);
  });
}

Future<void> _pumpSetting(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  required Future<void> Function(SettingsModel settings) onSave,
  Future<String?> Function()? pickDirectory,
  Future<List<DetectedCompiler>> Function()? detectCompilers,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Setting(
            settings: settings,
            pickDirectory: pickDirectory ?? () async => null,
            onSave: (SettingsModel next) async {
              await onSave(next);
              setState(() => settings = next);
            },
            detectCompilers: detectCompilers ?? _noCompilers,
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

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

IconButton _moveUpButton(WidgetTester tester, String id) =>
    tester.widget<IconButton>(find.byKey(Key('settingCompilerMoveUp_$id')));

IconButton _moveDownButton(WidgetTester tester, String id) =>
    tester.widget<IconButton>(find.byKey(Key('settingCompilerMoveDown_$id')));

Future<void> _selectCombo(WidgetTester tester, Key key, String label) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Button _clearButton(WidgetTester tester) =>
    tester.widget<Button>(find.byKey(const Key('settingClearDirButton')));

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
