import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/models/pack_project.dart';
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
    makeFile('src/v8wrap/win32.cpp');
    makeFile('src/mod/foo.cppm');
    makeFile('bin/x64/Debug/mylib.dll');
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
      result.sources,
      unorderedEquals([r'src\v8wrap\win32.cpp', r'src\mod\foo.cppm']),
    );
    // .dll 动态库按数据处理，不进入 libraries。
    expect(result.libraries, isNot(contains(r'bin\x64\Debug\mylib.dll')));
    expect(
      result.dataFiles,
      unorderedEquals([
        r'data\icudtl.dat',
        r'lib\x64\Debug\icudtl.dat',
        r'bin\x64\Debug\mylib.dll',
      ]),
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
    // 独立数据文件（非配置目录）建议映射到默认 build\native\lib。
    expect(globs, contains(r'data\*.dat -> build\native\lib'));
    // 源码文件建议映射到 build\native\src\...（按源目录名/父目录保留结构）。
    expect(
      globs,
      contains(r'src\v8wrap\*.cpp -> build\native\src\v8\src\v8wrap'),
    );
    // C++ Module 与源码同策略（target 前缀同为 build\native\src）。
    expect(globs, contains(r'src\mod\*.cppm -> build\native\src\v8\src\mod'));
    // .dll 数据映射（位于配置目录）随库/配置映射到平台×配置目录。
    expect(
      globs,
      contains(r'bin\x64\Debug\*.dll -> build\native\lib\x64\Debug'),
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

  group('findIconFile', () {
    File writeIcon(String name, [String? dir]) {
      final file = File(joinPath([dir ?? sourceDir.path, name]))
        ..writeAsStringSync('x');
      return file;
    }

    test('返回顶层 icon.png 的完整路径', () {
      final icon = writeIcon('icon.png');
      expect(findIconFile(sourceDir.path), icon.path);
    });

    test('按优先级 icon.png > icon.jpg > icon.ico', () {
      writeIcon('icon.ico');
      writeIcon('icon.jpg');
      final png = writeIcon('icon.png');
      expect(findIconFile(sourceDir.path), png.path);
    });

    test('文件名大小写不敏感', () {
      final icon = writeIcon('ICON.PNG');
      expect(findIconFile(sourceDir.path), icon.path);
    });

    test('目录不存在或未找到图标时返回 null', () {
      expect(findIconFile(joinPath([tempRoot.path, 'nope'])), isNull);
      expect(findIconFile(sourceDir.path), isNull);
    });
  });

  group('映射刷新变化检测', () {
    ScanResult scanWithGlobs(List<String> globs) {
      return ScanResult(
        headers: const [],
        sources: const [],
        libraries: const [],
        dataFiles: const [],
        suggestedMappings: [
          for (final glob in globs) FileMapping(srcGlob: glob, target: 't'),
        ],
      );
    }

    test('目录无变化（文件集合相同）返回 false', () {
      final current = [
        FileMapping(srcGlob: '*.h', target: 'v8'),
        FileMapping(srcGlob: r'src\*.cpp'),
      ];
      final scan = scanWithGlobs(['*.h', r'src\*.cpp']);
      expect(hasMappingChanged(current, scan), isFalse);
    });

    test('新增文件类条目返回 true', () {
      final current = [FileMapping(srcGlob: '*.h')];
      final scan = scanWithGlobs(['*.h', r'src\*.cpp']);
      expect(hasMappingChanged(current, scan), isTrue);
    });

    test('移除文件类条目返回 true', () {
      final current = [
        FileMapping(srcGlob: '*.h'),
        FileMapping(srcGlob: '*.cpp'),
      ];
      final scan = scanWithGlobs(['*.h']);
      expect(hasMappingChanged(current, scan), isTrue);
    });

    test('大小写/分隔符归一化视为同一文件条目', () {
      final current = [FileMapping(srcGlob: r'SRC\A.H')];
      final scan = scanWithGlobs([r'src\a.h']);
      expect(hasMappingChanged(current, scan), isFalse);
    });

    test('mergeMappingConditions 保留同 glob 旧条件，新条目默认空', () {
      final old = [
        FileMapping(
          srcGlob: '*.h',
          target: 'v8',
          platforms: ['x64'],
          configurations: ['Debug'],
        ),
        FileMapping(srcGlob: r'src\*.cpp'),
      ];
      final scan = scanWithGlobs(['*.h', r'src\*.cpp', r'data\*.dat']);
      final merged = mergeMappingConditions(old, scan.suggestedMappings);

      expect(merged[0].platforms, ['x64']);
      expect(merged[0].configurations, ['Debug']);
      expect(merged[1].platforms, isEmpty);
      expect(merged[1].configurations, isEmpty);
      expect(merged[2].platforms, isEmpty);
      expect(merged[2].configurations, isEmpty);
    });
  });
}
