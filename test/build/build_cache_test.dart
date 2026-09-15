import 'dart:io';

import 'package:cpp_nuget_pack/build/build_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('build_cache_test');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('缓存路径为 <cacheRoot>/build/<清洗包ID>', () {
    final Directory directory = packBuildCacheDirectory(
      'MyLib',
      cacheRoot: root.path,
    );

    expect(directory.path, endsWith('build/MyLib'));
    expect(directory.path, startsWith(root.path));
  });

  test('包名非法字符按 sanitizeFileName 清洗', () {
    final Directory directory = packBuildCacheDirectory(
      'a:b/c',
      cacheRoot: root.path,
    );

    expect(directory.path, endsWith('build/a_b_c'));
  });

  test('探测：目录不存在为 false，存在为 true', () async {
    expect(await hasPackBuildCache('demo', cacheRoot: root.path), isFalse);

    packBuildCacheDirectory(
      'demo',
      cacheRoot: root.path,
    ).createSync(recursive: true);

    expect(await hasPackBuildCache('demo', cacheRoot: root.path), isTrue);
  });

  test('删除：递归删除缓存目录', () async {
    final Directory directory = packBuildCacheDirectory(
      'demo',
      cacheRoot: root.path,
    );
    Directory('${directory.path}${Platform.pathSeparator}src')
        .createSync(recursive: true);
    File(
      '${directory.path}${Platform.pathSeparator}src${Platform.pathSeparator}a.c',
    ).writeAsStringSync('int a;');

    await deletePackBuildCache('demo', cacheRoot: root.path);

    expect(await directory.exists(), isFalse);
    expect(await hasPackBuildCache('demo', cacheRoot: root.path), isFalse);
  });

  test('删除：目录不存在视为成功', () async {
    await deletePackBuildCache('missing', cacheRoot: root.path);

    expect(await hasPackBuildCache('missing', cacheRoot: root.path), isFalse);
  });
}
