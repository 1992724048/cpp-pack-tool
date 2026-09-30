import 'dart:io';

import 'package:cpp_nuget_pack/app/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

// 正式版形如 26.3，预发布版形如 26.4.0-a（预发布标识限单段 ASCII 字母数字）
final RegExp _appVersionPattern = RegExp(
  r'^(?:\d{2}\.\d+|\d{2}\.\d+\.0-[0-9A-Za-z]+)$',
);

void main() {
  test('appVersion 与 pubspec.yaml 保持同步', () {
    final String? pubspecVersion = _pubspecVersion(
      File('pubspec.yaml').readAsStringSync(),
    );

    expect(pubspecVersion, isNotNull);
    expect(appVersion, pubspecVersion);
  });

  test('appVersion 为「年份.发布数量」或「年份.发布数量.0-预发布」格式', () {
    for (final String accepted in <String>[
      '26.3',
      '26.10',
      '26.4.0-a',
      '26.4.0-alpha',
      '26.4.0-a1',
    ]) {
      expect(
        accepted,
        matches(_appVersionPattern),
        reason: '「$accepted」应是合法版本形态',
      );
    }

    for (final String rejected in <String>[
      'abc',
      '26',
      '26.4a',
      '26.4.0a',
      '26.4.0-',
      '26.4.0-a-b-c',
      '26.4.0-a.1',
      '26.4.0-a*',
    ]) {
      expect(
        rejected,
        isNot(matches(_appVersionPattern)),
        reason: '「$rejected」不是合法版本形态，须被拒绝',
      );
    }

    expect(
      appVersion,
      matches(_appVersionPattern),
      reason: 'appVersion 须落在上述形态内（正式版 26.3 / 预发布版 26.4.0-a）',
    );
  });

  test('pubspec 预发布版本号不经尾部 .0 截断', () {
    expect(_pubspecVersion('version: 26.4.0-a+1'), '26.4.0-a');
    expect(_pubspecVersion('version: 26.3.0+1'), '26.3');
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
