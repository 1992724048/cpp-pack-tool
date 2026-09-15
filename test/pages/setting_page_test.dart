import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/pages/setting.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('渲染六个分区标题与设置字段', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    for (final String header in <String>[
      '打包',
      '新包默认值',
      '外观',
      '编译器',
      '网络',
      'AI 技能',
    ]) {
      expect(find.text(header), findsOneWidget, reason: '缺少分区：$header');
    }
    expect(find.text('NuGet 打包输出目录'), findsOneWidget);
    expect(find.text('CMake 打包输出目录'), findsOneWidget);
    expect(find.text('默认作者'), findsOneWidget);
    expect(find.text('未设置'), findsNWidgets(2));
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('代理模式'), findsOneWidget);
    expect(find.text('SKILL.md'), findsOneWidget);
    expect(find.byKey(const Key('settingPickDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingClearDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingPickCmakeDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingClearCmakeDirButton')), findsOneWidget);
    expect(find.byKey(const Key('settingDefaultAuthorField')), findsOneWidget);
    expect(find.byKey(const Key('settingThemeModeField')), findsOneWidget);
    expect(find.byKey(const Key('settingProxyModeField')), findsOneWidget);
    expect(find.byKey(const Key('settingProxyHostField')), findsNothing);
    expect(find.byKey(const Key('settingProxyPortField')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换代理模式为手动后渲染地址与端口字段并保存', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      // 有检测缓存，避免页面打开时自动检测写回干扰断言。
      settings: SettingsModel(
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await _selectCombo(tester, const Key('settingProxyModeField'), '手动设置');

    expect(saved, isNotNull);
    expect(saved!.proxyMode, ProxyModeSetting.manual);
    expect(find.byKey(const Key('settingProxyHostField')), findsOneWidget);
    expect(find.byKey(const Key('settingProxyPortField')), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);

    await _selectCombo(tester, const Key('settingProxyModeField'), '关闭（直连）');
    expect(saved!.proxyMode, ProxyModeSetting.off);
    expect(find.byKey(const Key('settingProxyHostField')), findsNothing);
  });

  testWidgets('手动代理地址保存原样（含 http:// 前缀）', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: SettingsModel(
        proxyMode: ProxyModeSetting.manual,
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.enterText(
      find.byKey(const Key('settingProxyHostField')),
      ' http://127.0.0.1 ',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.proxyHost, 'http://127.0.0.1');
    expect(saved!.proxyMode, ProxyModeSetting.manual);
  });

  testWidgets('手动代理端口非法时内联报错且不写盘', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: SettingsModel(
        proxyMode: ProxyModeSetting.manual,
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.enterText(
      find.byKey(const Key('settingProxyPortField')),
      '70000',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('端口需为 1–65535 的整数'), findsOneWidget);
    expect(saved, isNull);

    await tester.enterText(
      find.byKey(const Key('settingProxyPortField')),
      '7890',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('端口需为 1–65535 的整数'), findsNothing);
    expect(saved, isNotNull);
    expect(saved!.proxyPort, 7890);
  });

  testWidgets('切回手动模式时保留并回显手动字段值', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: SettingsModel(
        proxyMode: ProxyModeSetting.manual,
        proxyHost: '10.0.0.1',
        proxyPort: 8080,
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    expect(
      tester
          .widget<TextBox>(find.byKey(const Key('settingProxyHostField')))
          .controller
          ?.text,
      '10.0.0.1',
    );

    await _selectCombo(tester, const Key('settingProxyModeField'), '自动检测');
    expect(saved!.proxyMode, ProxyModeSetting.auto);
    expect(saved!.proxyHost, '10.0.0.1');
    expect(saved!.proxyPort, 8080);

    await _selectCombo(tester, const Key('settingProxyModeField'), '手动设置');
    expect(saved!.proxyMode, ProxyModeSetting.manual);
    expect(find.text('10.0.0.1'), findsOneWidget);
    expect(
      tester
          .widget<TextBox>(find.byKey(const Key('settingProxyPortField')))
          .controller
          ?.text,
      '8080',
    );
  });

  testWidgets('已设置输出目录时显示路径且清除按钮可用', (tester) async {
    await _pumpSetting(
      tester,
      settings: const SettingsModel(outputDirectory: r'D:\nuget\out'),
      onSave: (_) async {},
    );

    expect(find.text(r'D:\nuget\out'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
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
      // 有检测缓存，页面打开时不自动检测写回，便于隔离目录取消行为。
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
    expect(find.text('未设置'), findsNWidgets(2));
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

  testWidgets('选择 CMake 目录后回传并显示新路径', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      pickDirectory: () async => r'D:\out\cmake',
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.tap(find.byKey(const Key('settingPickCmakeDirButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.cmakeOutputDirectory, r'D:\out\cmake');
    expect(saved!.outputDirectory, isNull);
    expect(find.text(r'D:\out\cmake'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('清除 CMake 目录回传空值', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: const SettingsModel(cmakeOutputDirectory: r'D:\out\cmake'),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.tap(find.byKey(const Key('settingClearCmakeDirButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved!.cmakeOutputDirectory, isNull);
    expect(find.text('未设置'), findsNWidgets(2));
  });

  testWidgets('主题变更保存时保留双目录与默认作者字段', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: const SettingsModel(
        outputDirectory: r'D:\out\nuget',
        cmakeOutputDirectory: r'D:\out\cmake',
        defaultAuthor: '张三',
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await _selectCombo(tester, const Key('settingThemeModeField'), '深色');

    expect(saved!.outputDirectory, r'D:\out\nuget');
    expect(saved!.cmakeOutputDirectory, r'D:\out\cmake');
    expect(saved!.defaultAuthor, '张三');
    expect(saved!.themeMode, ThemeModeSetting.dark);
  });

  testWidgets('默认作者失焦时保存并提示已保存', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      // 有检测缓存，页面打开时不自动检测写回，便于隔离默认作者行为。
      settings: SettingsModel(
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.enterText(
      find.byKey(const Key('settingDefaultAuthorField')),
      '张三',
    );
    await tester.pump();
    expect(saved, isNull);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.defaultAuthor, '张三');
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('默认作者回车时保存', (tester) async {
    SettingsModel? saved;
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
    );

    await tester.enterText(
      find.byKey(const Key('settingDefaultAuthorField')),
      '李四',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved!.defaultAuthor, '李四');
  });

  testWidgets('默认作者未变化时不写盘', (tester) async {
    SettingsModel? saved;
    await _pumpSetting(
      tester,
      settings: SettingsModel(
        defaultAuthor: '张三',
        compilerPriority: const <String>['icx'],
        detectedCompilers: <DetectedCompiler>[
          _compiler(CompilerKind.icx, '2026.1.0'),
        ],
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.enterText(
      find.byKey(const Key('settingDefaultAuthorField')),
      '张三',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNull);
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
      ),
      onSave: (SettingsModel next) async {
        saved = next;
      },
    );

    await tester.tap(find.byKey(const Key('settingCompilerMoveDown_icx')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.compilerPriority, <String>[
      'clang-cl',
      'icx',
      'msvc',
      'mingw',
    ]);
    expect(saved!.outputDirectory, r'D:\nuget\out');
    expect(saved!.themeMode, ThemeModeSetting.dark);
    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingCompilerMoveUp_icx')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved!.compilerPriority, <String>[
      'icx',
      'clang-cl',
      'msvc',
      'mingw',
    ]);
  });

  testWidgets('编译器首行上移与末行下移禁用', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    expect(_moveUpButton(tester, 'icx').onPressed, isNull);
    expect(_moveDownButton(tester, 'icx').onPressed, isNotNull);
    expect(_moveUpButton(tester, 'mingw').onPressed, isNotNull);
    expect(_moveDownButton(tester, 'mingw').onPressed, isNull);
  });

  testWidgets('MinGW 行展示标签与环境标注版本', (tester) async {
    await _pumpSetting(
      tester,
      settings: const SettingsModel(compilerPriority: <String>['icx', 'mingw']),
      onSave: (_) async {},
      detectCompilers: () async => <DetectedCompiler>[
        _compiler(CompilerKind.icx, '2026.1.1'),
        _compiler(CompilerKind.mingw, '14.2.0（UCRT64）'),
      ],
    );

    expect(find.text('MinGW'), findsOneWidget);
    expect(find.text('14.2.0（UCRT64）'), findsOneWidget);
    final double icxTop = tester
        .getTopLeft(find.byKey(const Key('settingCompilerRow_icx')))
        .dy;
    final double mingwTop = tester
        .getTopLeft(find.byKey(const Key('settingCompilerRow_mingw')))
        .dy;
    expect(icxTop, lessThan(mingwTop));
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

  testWidgets('渲染 SKILL.md 分区与生成按钮', (tester) async {
    await _pumpSetting(tester, onSave: (_) async {});

    expect(find.text('SKILL.md'), findsOneWidget);
    expect(find.text('生成 SKILL.md…'), findsOneWidget);
    expect(find.byKey(const Key('settingGenerateSkillButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('生成 SKILL.md 写入所选路径并提示已生成', (tester) async {
    final Directory directory = _createTempDir('setting_skill');
    final String targetPath = _join(directory.path, 'SKILL.md');
    String? suggestedName;

    await _pumpSetting(
      tester,
      onSave: (_) async {},
      pickSaveFile: (String name) async {
        suggestedName = name;
        return targetPath;
      },
      loadSkillTemplate: () async => '# 模板内容',
    );

    await _tapSkillButton(tester);
    await _drainRealIo(
      tester,
      () => find.text('已生成 SKILL.md').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(suggestedName, 'SKILL.md');
    expect(File(targetPath).readAsStringSync(), '# 模板内容');
    expect(find.text('已生成 SKILL.md'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消保存位置时不写入也不加载模板', (tester) async {
    int loadCalls = 0;

    await _pumpSetting(
      tester,
      onSave: (_) async {},
      pickSaveFile: (_) async => null,
      loadSkillTemplate: () async {
        loadCalls++;
        return '# 模板内容';
      },
    );

    await _tapSkillButton(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(loadCalls, 0);
    expect(find.text('已生成 SKILL.md'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('模板加载失败时提示生成失败', (tester) async {
    final Directory directory = _createTempDir('setting_skill_load_fail');
    final String targetPath = _join(directory.path, 'SKILL.md');

    await _pumpSetting(
      tester,
      onSave: (_) async {},
      pickSaveFile: (_) async => targetPath,
      loadSkillTemplate: () async => throw Exception('模板缺失'),
    );

    await _tapSkillButton(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('生成失败'), findsOneWidget);
    expect(find.textContaining('模板缺失'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(File(targetPath).existsSync(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写入失败时提示生成失败', (tester) async {
    final Directory directory = _createTempDir('setting_skill_write_fail');

    await _pumpSetting(
      tester,
      onSave: (_) async {},
      // 以目录路径作为保存目标：写入必然失败。
      pickSaveFile: (_) async => directory.path,
      loadSkillTemplate: () async => '# 模板内容',
    );

    await _tapSkillButton(tester);
    await _drainRealIo(
      tester,
      () => find.textContaining('生成失败').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('生成失败'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SKILL.md 模板 asset 可载入且含 frontmatter', (tester) async {
    final String source = await rootBundle.loadString('assets/build/SKILL.md');
    // CI 检出可能因 git autocrlf 将文本资产转为 CRLF（本机为 LF），统一行尾后再断言。
    final String normalizedSource = source.replaceAll('\r\n', '\n');

    expect(normalizedSource, startsWith('---\n'));
    expect(normalizedSource, contains('name: generating-build-py'));
    expect(normalizedSource, contains('description: Use when'));
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
            pickSaveFile: _noSaveLocation,
            loadSkillTemplate: _fakeSkillTemplate,
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
    final Container surfaceBox = tester.widget<Container>(surface);
    final BoxDecoration decoration = surfaceBox.decoration! as BoxDecoration;
    expect(
      decoration.color,
      FluentTheme.of(tester.element(find.byType(Setting))).cardColor,
    );
  });
}

Future<void> _pumpSetting(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  required Future<void> Function(SettingsModel settings) onSave,
  Future<String?> Function()? pickDirectory,
  Future<List<DetectedCompiler>> Function()? detectCompilers,
  Future<String?> Function(String suggestedName)? pickSaveFile,
  Future<String> Function()? loadSkillTemplate,
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
            pickSaveFile: pickSaveFile ?? _noSaveLocation,
            loadSkillTemplate: loadSkillTemplate ?? _fakeSkillTemplate,
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

Future<String?> _noSaveLocation(String suggestedName) async => null;

Future<String> _fakeSkillTemplate() async => '# 模板内容';

/// 交替 runAsync（推进真实文件 I/O）与 pump（冲刷微任务并刷新帧），直至 [done] 成立。
Future<void> _drainRealIo(WidgetTester tester, bool Function() done) async {
  for (var cycle = 0; cycle < 30; cycle++) {
    if (done()) {
      return;
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }
}

Directory _createTempDir(String prefix) {
  final Directory directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

String _join(String base, String name) => '$base${Platform.pathSeparator}$name';

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

/// 滚动到 SKILL.md 分区后点击生成按钮（页面分区增多后按钮可能位于视口外）。
Future<void> _tapSkillButton(WidgetTester tester) async {
  final Finder button = find.byKey(const Key('settingGenerateSkillButton'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

Button _clearButton(WidgetTester tester) =>
    tester.widget<Button>(find.byKey(const Key('settingClearDirButton')));

Finder _pageSurface(WidgetTester tester) {
  return find.descendant(
    of: find.byType(Setting),
    matching: find.byKey(const Key('settingsPageSurface')),
  );
}
