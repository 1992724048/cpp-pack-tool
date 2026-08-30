import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/services/settings.dart';

void main() {
  test('nugetGlobalCacheDir 默认值为 %USERPROFILE%\\.nuget\\packages', () {
    expect(AppSettings().nugetGlobalCacheDir, kDefaultNugetGlobalCacheDir);
    expect(kDefaultNugetGlobalCacheDir, r'%USERPROFILE%\.nuget\packages');
  });

  test('toJson/fromJson 往返保留 nugetGlobalCacheDir', () {
    final settings = AppSettings(nugetGlobalCacheDir: r'C:\cache');
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.nugetGlobalCacheDir, r'C:\cache');
  });

  test('旧 settings.json 缺省 nugetGlobalCacheDir 时回退到默认值', () {
    final restored = AppSettings.fromJson(<String, dynamic>{
      'nugetExePath': null,
      'defaultOutputDir': r'C:\out',
      'recentProjects': <String>[],
    });
    expect(restored.nugetGlobalCacheDir, kDefaultNugetGlobalCacheDir);
    expect(restored.defaultOutputDir, r'C:\out');
  });
}
