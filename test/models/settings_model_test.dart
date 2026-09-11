import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认值为 system / mocha / teal 且输出目录为空', () {
    const SettingsModel settings = SettingsModel();

    expect(settings.outputDirectory, isNull);
    expect(settings.themeMode, ThemeModeSetting.system);
    expect(settings.darkFlavor, 'mocha');
    expect(settings.accent, 'teal');
  });

  test('toMap 省略 null 输出目录且保留其余字段', () {
    final Map<String, Object?> map = const SettingsModel().toMap();

    expect(map.containsKey('outputDirectory'), isFalse);
    expect(map['themeMode'], 'system');
    expect(map['darkFlavor'], 'mocha');
    expect(map['accent'], 'teal');
  });

  test('往返保留全部字段', () {
    const SettingsModel settings = SettingsModel(
      outputDirectory: r'D:\nuget\out',
      themeMode: ThemeModeSetting.dark,
      darkFlavor: 'frappe',
      accent: 'mauve',
    );

    final SettingsModel loaded = SettingsModel.fromMap(settings.toMap());

    expect(loaded.outputDirectory, r'D:\nuget\out');
    expect(loaded.themeMode, ThemeModeSetting.dark);
    expect(loaded.darkFlavor, 'frappe');
    expect(loaded.accent, 'mauve');
  });

  test('未知枚举与非法值回退默认', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{
      'themeMode': 'pink',
      'darkFlavor': 'latte',
      'accent': 'rainbow',
      'outputDirectory': 42,
    });

    expect(loaded.themeMode, ThemeModeSetting.system);
    expect(loaded.darkFlavor, 'mocha');
    expect(loaded.accent, 'teal');
    expect(loaded.outputDirectory, isNull);
  });

  test('空映射返回默认值', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{});

    expect(loaded.themeMode, ThemeModeSetting.system);
    expect(loaded.darkFlavor, 'mocha');
    expect(loaded.accent, 'teal');
    expect(loaded.outputDirectory, isNull);
  });

  test('空字符串输出目录视为未设置', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{
      'outputDirectory': '',
    });

    expect(loaded.outputDirectory, isNull);
  });
}
