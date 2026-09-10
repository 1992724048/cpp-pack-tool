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
}

Future<void> _pumpSetting(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  required Future<void> Function(SettingsModel settings) onSave,
  Future<String?> Function()? pickDirectory,
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
          );
        },
      ),
    ),
  );
  await tester.pump();
}

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
