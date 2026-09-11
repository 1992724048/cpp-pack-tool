import 'package:cpp_nuget_pack/util/colors.dart';

enum ThemeModeSetting { system, dark, light }

class SettingsModel {
  const SettingsModel({
    this.outputDirectory,
    this.themeMode = ThemeModeSetting.system,
    this.darkFlavor = 'mocha',
    this.accent = 'teal',
  });

  final String? outputDirectory;
  final ThemeModeSetting themeMode;
  final String darkFlavor;
  final String accent;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (outputDirectory != null) 'outputDirectory': outputDirectory,
      'themeMode': themeMode.name,
      'darkFlavor': darkFlavor,
      'accent': accent,
    };
  }

  factory SettingsModel.fromMap(Map<String, Object?> map) {
    return SettingsModel(
      outputDirectory: _optionalString(map['outputDirectory']),
      themeMode: _themeModeFrom(map['themeMode']),
      darkFlavor: _allowedValue(map['darkFlavor'], darkFlavorNames, 'mocha'),
      accent: _allowedValue(map['accent'], accentColorNames, 'teal'),
    );
  }
}

String? _optionalString(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return value;
}

ThemeModeSetting _themeModeFrom(Object? value) {
  if (value is String) {
    for (final ThemeModeSetting mode in ThemeModeSetting.values) {
      if (mode.name == value) {
        return mode;
      }
    }
  }
  return ThemeModeSetting.system;
}

String _allowedValue(Object? value, List<String> allowed, String fallback) {
  if (value is String && allowed.contains(value)) {
    return value;
  }
  return fallback;
}
