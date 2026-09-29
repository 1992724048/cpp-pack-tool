import 'dart:async';

import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/settings/settings_model.dart';
import 'package:cpp_nuget_pack/settings/ui/setting.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('渲染三个分区标题与设置字段', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    for (final String header in <String>['打包', '外观', '编译器']) {
      expect(find.text(header), findsOneWidget, reason: '缺少分区：$header');
    }
    expect(find.text('NuGet 打包输出目录'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.byKey(const Key('settingPickDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingClearDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingThemeModeField')), findsOneWidget);
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

  testWidgets('外观分区仅保留主题模式（无深色配色与强调色）', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    expect(find.byKey(const Key('settingThemeModeField')), findsOneWidget);
    expect(find.byKey(const Key('settingDarkFlavorField')), findsNothing);
    expect(find.byKey(const Key('settingAccentField')), findsNothing);
    expect(find.text('深色主题配色'), findsNothing);
    expect(find.text('强调色'), findsNothing);
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
      settings: SettingsModel(
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
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

  testWidgets('主题变更保存时保留输出目录', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: const SettingsModel(outputDirectory: r'D:\out\nuget'),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await _selectCombo(tester, const Key('settingThemeModeField'), '深色');

    expect(saved!.outputDirectory, r'D:\out\nuget');
    expect(saved!.themeMode, ThemeModeSetting.dark);
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

  testWidgets('编译器行按优先级自上而下展示标签与版本', (tester) async {
    await _pumpSetting(
      tester,
      settings: const SettingsModel(compilerPriority: <String>['icx', 'clang-cl']),
      onSave: (_) async {},
      detectCompilers: () async => <DetectedCompiler>[
        _compiler(CompilerKind.icx, '2026.1.1'),
        _compiler(CompilerKind.clangCl, '23.1.1'),
      ],
    );

    expect(find.text('clang-cl'), findsOneWidget);
    expect(find.text('23.1.1'), findsOneWidget);
    final double icxTop = tester
        .getTopLeft(find.byKey(const Key('settingCompilerRow_icx')))
        .dy;
    final double clangClTop = tester
        .getTopLeft(find.byKey(const Key('settingCompilerRow_clang-cl')))
        .dy;
    expect(icxTop, lessThan(clangClTop));
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

  testWidgets('有缓存时直接显示缓存版本且不触发检测', (tester) async {
    int calls = 0;

    await _pumpSetting(
      tester,
      settings: SettingsModel(
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (_) async {},
      detectCompilers: () async {
        calls++;
        return const <DetectedCompiler>[];
      },
    );

    expect(calls, 0);
    expect(find.text('2026.1.0'), findsOneWidget);
    expect(find.text('未检测到'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无缓存时自动检测并写回设置（不提示已保存）', (tester) async {
    SettingsModel? saved;

    await _pumpSetting(
      tester,
      settings: const SettingsModel(compilerPriority: <String>['icx']),
      onSave: (SettingsModel next) async {
        saved = next;
      },
      detectCompilers: () async => <DetectedCompiler>[
        _compiler(CompilerKind.icx, '2026.1.1'),
      ],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2026.1.1'), findsOneWidget);
    expect(saved, isNotNull);
    expect(saved!.compilerPriority, <String>['icx']);
    expect(saved!.detectedCompilers, hasLength(1));
    expect(saved!.detectedCompilers.single.kind, CompilerKind.icx);
    expect(saved!.detectedCompilers.single.version, '2026.1.1');
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('重新检测更新显示并写回缓存', (tester) async {
    SettingsModel? saved;
    int calls = 0;

    await _pumpSetting(
      tester,
      settings: SettingsModel(
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
      detectCompilers: () async {
        calls++;
        return <DetectedCompiler>[_compiler(CompilerKind.icx, '2026.2.0')];
      },
    );

    expect(calls, 0);
    expect(find.text('2026.1.0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingCompilerRefreshButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('2026.2.0'), findsOneWidget);
    expect(find.text('2026.1.0'), findsNothing);
    expect(saved, isNotNull);
    expect(saved!.detectedCompilers.single.version, '2026.2.0');
    expect(saved!.compilerPriority, <String>['icx']);
  });

  testWidgets('重新检测失败时保留缓存显示且不写回', (tester) async {
    SettingsModel? saved;
    int calls = 0;

    await _pumpSetting(
      tester,
      settings: SettingsModel(
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
      detectCompilers: () async {
        calls++;
        throw Exception('探测失败');
      },
    );

    await tester.tap(find.byKey(const Key('settingCompilerRefreshButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(calls, 1);
    expect(find.text('2026.1.0'), findsOneWidget);
    expect(find.textContaining('编译器检测失败'), findsOneWidget);
    expect(saved, isNull);
  });

  testWidgets('宽松约束下铺满可用区域且页面表面无背景装饰', (tester) async {
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
    expect(find.text('设置'), findsOneWidget);
    expect(find.textContaining('配置打包输出目录'), findsOneWidget);

    final Finder surface = _pageSurface(tester);
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface), available);
    final Container surfaceBox = tester.widget<Container>(surface);
    expect(surfaceBox.decoration, isNull);
    expect(tester.takeException(), isNull);
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
  // 设置页分区变多后下拉可能位于视口外，先滚动到可见再点击。
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
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
  return find.descendant(
    of: find.byType(Setting),
    matching: find.byKey(const Key('settingsPageSurface')),
  );
}
