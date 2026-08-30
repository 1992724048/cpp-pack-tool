import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/services/path_utils.dart';
import 'package:cpp_nuget_pack/services/scanner.dart';

void main() {
  late Directory tempRoot;
  late Directory sourceDir;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('scanner_test_');
    sourceDir = Directory(joinPath([tempRoot.path, 'v8']))
      ..createSync(recursive: true);
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // 清理失败不阻塞测试。
    }
  });

  File makeFile(String rel) {
    final file = File(joinPath([sourceDir.path, ...rel.split('/')]));
    file.createSync(recursive: true);
    file.writeAsStringSync('x');
    return file;
  }

  test('扫不到不存在的路径会抛异常', () {
    expect(
      () => scanSourceDir(joinPath([tempRoot.path, 'nope'])),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('按扩展名分类并生成建议映射（含忽略生成目录）', () {
    makeFile('v8.h');
    makeFile('v8-internal.hxx');
    makeFile('cppgc/gc.h');
    makeFile('lib/x64/Debug/v8_monolith.lib');
    makeFile('lib/x64/Release/v8_monolith.lib');
    makeFile('lib/x64/Debug/icudtl.dat');
    makeFile('data/icudtl.dat');
    makeFile('build/ignored.h');
    makeFile('out/ignored.lib');
    makeFile('.git/config.h');
    makeFile('.dart_tool/x.h');
    makeFile('.temp/tmp.dat');

    final result = scanSourceDir(sourceDir.path);

    expect(
      result.headers,
      unorderedEquals(['v8.h', 'v8-internal.hxx', r'cppgc\gc.h']),
    );
    expect(
      result.libraries,
      unorderedEquals([
        r'lib\x64\Debug\v8_monolith.lib',
        r'lib\x64\Release\v8_monolith.lib',
      ]),
    );
    expect(
      result.dataFiles,
      unorderedEquals([r'data\icudtl.dat', r'lib\x64\Debug\icudtl.dat']),
    );

    // 生成目录 / 隐藏目录被忽略。
    expect(result.headers, isNot(contains(r'build\ignored.h')));
    expect(result.libraries, isNot(contains(r'out\ignored.lib')));
    expect(result.headers, isNot(contains(r'.git\config.h')));

    final globs = result.suggestedMappings.map(
      (m) => '${m.srcGlob} -> ${m.target}',
    );
    // 头文件：按父目录簇分组，按扩展名各生成一条 glob（目标为最终 #include 路径）。
    expect(globs, contains(r'*.h -> v8'));
    expect(globs, contains(r'*.hxx -> v8'));
    expect(globs, contains(r'cppgc\*.h -> v8\cppgc'));
    // 库文件：按配置识别，映射到平台×配置目录。
    expect(
      globs,
      contains(r'lib\x64\Debug\*.lib -> build\native\lib\x64\Debug'),
    );
    expect(
      globs,
      contains(r'lib\x64\Release\*.lib -> build\native\lib\x64\Release'),
    );
    // Debug 目录内的数据文件随库一起映射。
    expect(
      globs,
      contains(r'lib\x64\Debug\*.dat -> build\native\lib\x64\Debug'),
    );
  });

  test('不递归超过最大深度', () {
    makeFile('l1/l2/l3/l4/deep.h');
    makeFile('l1/l2/l3/l4/l5/deeper.h');

    final result = scanSourceDir(sourceDir.path);

    expect(result.headers, unorderedEquals([r'l1\l2\l3\l4\deep.h']));
    expect(result.headers, isNot(contains(r'l1\l2\l3\l4\l5\deeper.h')));
  });

  test('单一目录条目超出上限会截断并记录告警', () {
    makeFile('a.h');
    makeFile('b.h');
    makeFile('c.h');

    final result = scanSourceDir(sourceDir.path, maxFilesPerDir: 2);

    expect(result.truncated, isTrue);
    expect(result.headers, hasLength(2));
    expect(result.warnings, isNotEmpty);
  });

  test('符号链接指向父目录不会循环', () {
    // Windows 创建符号链接通常需要管理员/开发者模式，失败时跳过本断言。
    final linkPath = joinPath([sourceDir.path, 'loop']);
    try {
      Link(linkPath).createSync(sourceDir.path);
    } on FileSystemException {
      markTestSkipped('当前环境无法创建符号链接，跳过循环测试');
      return;
    }

    makeFile('real.h');
    final result = scanSourceDir(sourceDir.path);

    expect(result.headers, unorderedEquals(['real.h']));
  });
}
