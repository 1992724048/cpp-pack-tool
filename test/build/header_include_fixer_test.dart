import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cnp_include_fixer_');
    // 包源目录的 basename 即包内 include 命名空间（见 includeNamespaceOf），
    // 固定名才能对改写后的 include 字面量做精确断言。
    source = Directory('${root.path}/gtest')..createSync();
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> writeText(String relativePath, String content) async {
    final File file = File('${source.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    final File file = File('${source.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<String> readText(String relativePath) =>
      File('${source.path}/$relativePath').readAsString();

  Future<List<int>> readBytes(String relativePath) =>
      File('${source.path}/$relativePath').readAsBytes();

  Future<HeaderIncludeFixReport> runFixer({String packageName = 'gtest'}) =>
      fixHeaderIncludes(source.path, packageName: packageName);

  /// gtest 式样本：`gtest-all.cc` 引同目录 `.cc` 与 `src/` 下的 `.h`；`.h` 那条
  /// 修复后在包内落 include 根之下可修，`.cc` 那条落 `files/` 无改写目标。
  Future<void> writeGtestLikeTree() async {
    await writeText(
      'src/gtest/gtest-all.cc',
      '#include "gtest/gtest.h"\n#include "src/gtest.cc"\n',
    );
    for (final String name in <String>[
      'gtest.cc',
      'gtest-port.cc',
      'gtest-printers.cc',
      'gtest-test-part.cc',
      'gtest-death-test.cc',
    ]) {
      await writeText('src/gtest/$name', '#include "src/gtest-internal-inl.h"\n');
    }
    await writeText('src/gtest/gtest-internal-inl.h', '#pragma once\n');
    await writeText('include/gtest/gtest.h', '#pragma once\n');
  }

  test('gtest 式样本：5 处 .h 跨类引用全部改写为 include 根相对路径，.cc 引用回落报告', () async {
    await writeGtestLikeTree();

    final HeaderIncludeFixReport report = await runFixer();

    // 命名空间取源目录 basename（gtest）：`src/gtest/gtest-internal-inl.h` 落
    // `gtest/src/gtest/gtest-internal-inl.h`，在 include 根之下，可改写。
    expect(report.fixedCount, 5);
    expect(
      report.issues.single.filePath,
      'src/gtest/gtest-all.cc',
    );
    expect(report.issues.single.kind, HeaderIncludeIssueKind.crossTree);
    expect(report.issues.single.include, 'src/gtest.cc');
    expect(report.issues.single.candidates, <String>['src/gtest/gtest.cc']);

    for (final HeaderIncludeFix fix in report.fixed) {
      expect(fix.from, 'src/gtest-internal-inl.h');
      expect(fix.to, 'gtest/src/gtest/gtest-internal-inl.h');
      expect(fix.filePath, startsWith('src/gtest/'));
      expect(
        await readText(fix.filePath),
        '#include "gtest/src/gtest/gtest-internal-inl.h"\n',
      );
    }

    // `.cc` 目标落 files/，include 根搜不到，原样不动
    expect(
      await readText('src/gtest/gtest-all.cc'),
      '#include "gtest/gtest.h"\n#include "src/gtest.cc"\n',
    );
  });

  test('跨子树修复：源文件在包内落 files/、头文件落 include/<命名空间>/', () async {
    await writeText(
      'cpp_client_wrapper/core_implementations.cc',
      '#include "binary_messenger_impl.h"\n',
    );
    await writeText('flutter/cpp_client_wrapper/binary_messenger_impl.h', '#pragma once\n');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.issues, isEmpty);
    expect(report.fixedCount, 1);
    final HeaderIncludeFix fix = report.fixed.single;
    expect(fix.from, 'binary_messenger_impl.h');
    expect(fix.to, 'gtest/flutter/cpp_client_wrapper/binary_messenger_impl.h');
    expect(
      await readText('cpp_client_wrapper/core_implementations.cc'),
      '#include "gtest/flutter/cpp_client_wrapper/binary_messenger_impl.h"\n',
    );
  });

  test('包布局已能解析则不动：源码层解析不了、经 include 根能解析的引用', () async {
    // 第 1 步守卫：该字面量在包内正是 include 根相对的真实路径，源码层却没有
    // 对应文件（源码 include 根为 include/，其下没有 gtest/ 子树）。
    await writeText(
      'src/a/user.cc',
      '#include "gtest/flutter/cpp_client_wrapper/binary_messenger_impl.h"\n',
    );
    await writeText(
      'flutter/cpp_client_wrapper/binary_messenger_impl.h',
      '#pragma once\n',
    );

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues, isEmpty);
    expect(
      await readText('src/a/user.cc'),
      '#include "gtest/flutter/cpp_client_wrapper/binary_messenger_impl.h"\n',
    );
  });

  test('改写结果自检回落：候选不在 include 根之下时仍报 crossTree 且不改写', () async {
    // 字面量 `a/helper.cc` 是从包根书写的过期路径（源码层解析不到），唯一候选是
    // 引用文件同目录的 `src/a/helper.cc`；`.cc` 落 files/、include 根搜不到，
    // 没有可用的改写目标 → 不写、回落报告（旧规则此时会改写成裸文件名）。
    await writeText('src/a/one.cc', '#include "a/helper.cc"\n');
    await writeText('src/a/helper.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues.single.kind, HeaderIncludeIssueKind.crossTree);
    expect(report.issues.single.candidates, <String>['src/a/helper.cc']);
    expect(report.issues.single.description, contains('不在 include 根之下'));
    expect(await readText('src/a/one.cc'), '#include "a/helper.cc"\n');
  });

  test('多候选时报 multipleCandidates 且不修改', () async {
    await writeText('src/a/one.cc', '#include "q/helper.h"\n');
    await writeText('x/helper.h', '');
    await writeText('y/helper.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(
      report.issues.single.kind,
      HeaderIncludeIssueKind.multipleCandidates,
    );
    expect(report.issues.single.candidates, <String>['x/helper.h', 'y/helper.h']);
    expect(report.issues.single.description, contains('多个同名候选'));
    expect(await readText('src/a/one.cc'), '#include "q/helper.h"\n');
  });

  test('候选排除引用文件自身：自包含引用不再被误改为裸文件名', () async {
    await writeText('foo/bar.h', '#include "baz/bar.h"\n');
    await writeText('baz/other.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues.single.kind, HeaderIncludeIssueKind.noCandidate);
    expect(report.issues.single.filePath, 'foo/bar.h');
    expect(report.issues.single.include, 'baz/bar.h');
    expect(await readText('foo/bar.h'), '#include "baz/bar.h"\n');
  });

  test('候选排除引用文件自身：其他同名文件照常参与判定', () async {
    await writeText('foo/bar.h', '#include "baz/bar.h"\n');
    await writeText('x/bar.h', '');
    await writeText('y/bar.h', '');
    await writeText('baz/other.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(
      report.issues.single.kind,
      HeaderIncludeIssueKind.multipleCandidates,
    );
    expect(report.issues.single.candidates, <String>['x/bar.h', 'y/bar.h']);
    expect(await readText('foo/bar.h'), '#include "baz/bar.h"\n');
  });

  test('唯一候选位于其他目录时报 crossTree 且不修改', () async {
    await writeText('src/a/one.cc', '#include "src/helper.cc"\n');
    await writeText('src/b/helper.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues.single.kind, HeaderIncludeIssueKind.crossTree);
    expect(report.issues.single.candidates, <String>['src/b/helper.cc']);
    expect(await readText('src/a/one.cc'), '#include "src/helper.cc"\n');
  });

  test('无候选：包内风格引用报告，外部依赖（absl/re2）不报告', () async {
    await writeText(
      'src/gtest/gtest.cc',
      '#if GTEST_HAS_ABSL\n'
      '#include "absl/strings/string_view.h"\n'
      '#include "re2/re2.h"\n'
      '#endif\n'
      '#include "src/prim/windows/etw.h"\n'
      '#include "../src/prim/windows/etw.h"\n',
    );

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues, hasLength(2));
    expect(report.issues.first.include, 'src/prim/windows/etw.h');
    expect(report.issues.last.include, '../src/prim/windows/etw.h');
    expect(
      report.issues.every(
        (HeaderIncludeIssue issue) =>
            issue.kind == HeaderIncludeIssueKind.noCandidate,
      ),
      isTrue,
    );
    expect(report.issues.first.description, contains('未找到同名文件'));
    expect(
      await readText('src/gtest/gtest.cc'),
      contains('absl/strings/string_view.h'),
    );
  });

  test('尖括号：自引用缺失报告，系统头与解析成功引用跳过', () async {
    await writeText('include/gtest/gtest.h', '');
    await writeText(
      'src/a.cc',
      '#include <gtest/gtest.h>\n'
      '#include <gtest/missing.h>\n'
      '#include <vector>\n'
      '#include <windows.h>\n'
      '#include <absl/strings/string_view.h>\n',
    );

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues, hasLength(1));
    final HeaderIncludeIssue issue = report.issues.single;
    expect(issue.kind, HeaderIncludeIssueKind.missingAngle);
    expect(issue.include, 'gtest/missing.h');
    expect(issue.line, 2);
    expect(issue.description, contains('尖括号'));
  });

  test('可解析引用（相对目录/include 根/包根）不报告不修改', () async {
    await writeText('src/a/self.h', '');
    await writeText('include/foo/bar.h', '');
    await writeText(
      'src/a/user.cc',
      '#include "self.h"\n'
      '#include "foo/bar.h"\n'
      '#include "src/a/self.h"\n',
    );

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.isEmpty, isTrue);
    expect(
      await readText('src/a/user.cc'),
      '#include "self.h"\n'
      '#include "foo/bar.h"\n'
      '#include "src/a/self.h"\n',
    );
  });

  test('重复执行幂等：二次运行零修复', () async {
    await writeText('src/gtest/gtest-all.cc', '#include "src/helper.h"\n');
    await writeText('src/gtest/helper.h', '');

    final HeaderIncludeFixReport first = await runFixer();
    expect(first.fixedCount, 1);
    expect(first.fixed.single.to, 'gtest/src/gtest/helper.h');
    final List<int> afterFirst = await readBytes('src/gtest/gtest-all.cc');

    final HeaderIncludeFixReport second = await runFixer();
    expect(second.fixedCount, 0);
    expect(await readBytes('src/gtest/gtest-all.cc'), afterFirst);
    expect(
      await readText('src/gtest/gtest-all.cc'),
      '#include "gtest/src/gtest/helper.h"\n',
    );
  });

  test('修复保留 BOM 与 CRLF 行尾', () async {
    await writeBytes('src/gtest/gtest-all.cc', <int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('#include "src/helper.h"\r\n// 中文注释\r\n'),
    ]);
    await writeText('src/gtest/helper.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    final List<int> fixed = await readBytes('src/gtest/gtest-all.cc');
    expect(fixed.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
    expect(
      utf8.decode(fixed.sublist(3)),
      '#include "gtest/src/gtest/helper.h"\r\n// 中文注释\r\n',
    );
  });

  test('非 UTF-8 字节文件修复后其余字节不变', () async {
    await writeBytes(
      'src/gtest/gtest-all.cc',
      latin1.encode('#include "src/helper.h" // caf\xE9\n'),
    );
    await writeText('src/gtest/helper.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(
      await readBytes('src/gtest/gtest-all.cc'),
      latin1.encode('#include "gtest/src/gtest/helper.h" // caf\xE9\n'),
    );
  });

  test('注释中的 include 不处理', () async {
    await writeText(
      'src/gtest/gtest-all.cc',
      '#include "src/helper.h"\n'
      '// #include "src/helper.h"\n'
      '/*\n'
      '#include "src/helper.h"\n'
      '*/\n'
      '/* #include "src/helper.h" */\n',
    );
    await writeText('src/gtest/helper.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.issues, isEmpty);
    expect(
      await readText('src/gtest/gtest-all.cc'),
      '#include "gtest/src/gtest/helper.h"\n'
      '// #include "src/helper.h"\n'
      '/*\n'
      '#include "src/helper.h"\n'
      '*/\n'
      '/* #include "src/helper.h" */\n',
    );
  });

  test('普通字符串中的 /* 不进入块注释态，后续行照常检出', () async {
    await writeText(
      'src/gtest/gtest-all.cc',
      'const char* pattern = "/*";\n'
      '#include "src/helper.h"\n'
      '#include "src/lost.h"\n',
    );
    await writeText('src/gtest/helper.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 2);
    expect(report.fixed.single.to, 'gtest/src/gtest/helper.h');
    expect(report.issues.single.kind, HeaderIncludeIssueKind.noCandidate);
    expect(report.issues.single.include, 'src/lost.h');
    expect(
      await readText('src/gtest/gtest-all.cc'),
      'const char* pattern = "/*";\n'
      '#include "gtest/src/gtest/helper.h"\n'
      '#include "src/lost.h"\n',
    );
  });

  test('普通字符串含转义引号：字符串内 /* 不误判，后续真实引用照常修复', () async {
    await writeText(
      'src/gtest/gtest-all.cc',
      'const char* quoted = "a\\"/*\\"b";\n'
      '#include "src/helper.h"\n',
    );
    await writeText('src/gtest/helper.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 2);
    expect(report.fixed.single.to, 'gtest/src/gtest/helper.h');
    expect(
      await readText('src/gtest/gtest-all.cc'),
      'const char* quoted = "a\\"/*\\"b";\n'
      '#include "gtest/src/gtest/helper.h"\n',
    );
  });

  test('raw string 内以 #include 开头的行不改写，其后真实引用照常修复', () async {
    await writeText(
      'src/gtest/a.cc',
      'const char* sample = R"(\n'
      '#include "sub/b.h"\n'
      ')";\n'
      '#include "sub/b.h"\n',
    );
    await writeText('src/gtest/b.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 4);
    expect(report.fixed.single.to, 'gtest/src/gtest/b.h');
    expect(
      await readText('src/gtest/a.cc'),
      'const char* sample = R"(\n'
      '#include "sub/b.h"\n'
      ')";\n'
      '#include "gtest/src/gtest/b.h"\n',
    );
  });

  test('自定义分隔符 raw string 同样隔离', () async {
    await writeText(
      'src/gtest/a.cc',
      'const char* sample = R"cpp(\n'
      '#include "sub/b.h"\n'
      ')cpp";\n'
      '#include "sub/b.h"\n',
    );
    await writeText('src/gtest/b.h', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 4);
    expect(
      await readText('src/gtest/a.cc'),
      'const char* sample = R"cpp(\n'
      '#include "sub/b.h"\n'
      ')cpp";\n'
      '#include "gtest/src/gtest/b.h"\n',
    );
  });

  test('非源码扩展名不扫描', () async {
    await writeText('src/gtest/gtest.cc', '');
    await writeText('notes.txt', '#include "src/gtest.cc"\n');
    await writeText('readme.md', '#include "src/gtest.cc"\n');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.isEmpty, isTrue);
    expect(await readText('notes.txt'), '#include "src/gtest.cc"\n');
    expect(await readText('readme.md'), '#include "src/gtest.cc"\n');
  });

  test('IO 可注入：只写回含修复的文件', () async {
    await writeText('src/a/a.cc', '');
    await writeText('src/a/b.h', '');
    final Map<String, List<int>> written = <String, List<int>>{};

    final HeaderIncludeFixReport report = await fixHeaderIncludes(
      source.path,
      packageName: 'demo',
      readFile: (String path) async => path.endsWith('a.cc')
          ? utf8.encode('#include "src/b.h"\n')
          : utf8.encode(''),
      writeFile: (String path, List<int> bytes) async {
        written[path] = bytes;
      },
    );

    expect(report.fixedCount, 1);
    expect(written.keys, hasLength(1));
    expect(written.keys.single.replaceAll('\\', '/'), endsWith('src/a/a.cc'));
    expect(written.values.single, utf8.encode('#include "gtest/src/a/b.h"\n'));
  });

  test('缺少源目录时抛出文件系统异常', () async {
    await expectLater(
      fixHeaderIncludes('${source.path}/missing', packageName: 'demo'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
