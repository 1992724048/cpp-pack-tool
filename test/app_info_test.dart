import 'dart:io';

import 'package:cpp_nuget_pack/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appVersion 与 pubspec.yaml 保持同步', () {
    final String? pubspecVersion = _pubspecVersion(
      File('pubspec.yaml').readAsStringSync(),
    );

    expect(pubspecVersion, isNotNull);
    expect(appVersion, pubspecVersion);
  });

  test('appVersion 为「年份.发布数量」格式', () {
    expect(appVersion, matches(RegExp(r'^\d{2}\.\d+$')));
  });

  test('应用信息常量非空且仓库链接为 https', () {
    expect(appName, isNotEmpty);
    expect(appDescription, isNotEmpty);
    expect(appRepositoryUrl, startsWith('https://'));
  });
}

String? _pubspecVersion(String content) {
  final RegExpMatch? match = RegExp(
    r'^\s*version\s*:\s*(.+?)\s*$',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) {
    return null;
  }
  final String value = match
      .group(1)!
      .replaceAll(RegExp(r'''^["']|["']$'''), '');
  final String version = value.split('+').first;
  final RegExpMatch? releaseMatch = RegExp(r'^(\d+\.\d+)\.0$')
      .firstMatch(version);
  return releaseMatch?.group(1) ?? version;
}
