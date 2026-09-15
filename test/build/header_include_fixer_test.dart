import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/header_include_fixer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cnp_include_fixer_');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> writeText(String relativePath, String content) async {
    final File file = File('${root.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    final File file = File('${root.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<String> readText(String relativePath) =>
      File('${root.path}/$relativePath').readAsString();

  Future<List<int>> readBytes(String relativePath) =>
      File('${root.path}/$relativePath').readAsBytes();

  Future<HeaderIncludeFixReport> runFixer({String packageName = 'gtest'}) =>
      fixHeaderIncludes(root.path, packageName: packageName);

  /// gtest 式样本：`gtest-all.cc` 同目录 `.cc→.cc` 引用可安全修；
  /// `gtest-internal-inl.h` 被 `.cc` 引用属跨树（打包后头文件搬进 include 树），不动。
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

  test('gtest 式样本：同目录 .cc 引用改写为裸文件名，跨树 .h 引用全部不动', () async {
    await writeGtestLikeTree();

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    final HeaderIncludeFix fix = report.fixed.single;
    expect(fix.filePath, 'src/gtest/gtest-all.cc');
    expect(fix.line, 2);
    expect(fix.from, 'src/gtest.cc');
    expect(fix.to, 'gtest.cc');

    expect(
      await readText('src/gtest/gtest-all.cc'),
      '#include "gtest/gtest.h"\n#include "gtest.cc"\n',
    );

    // 5 条 `.cc → .h` 跨类引用均不动（含引用文件内容原样）
    expect(report.issues, hasLength(5));
    expect(
      report.issues.map((HeaderIncludeIssue issue) => issue.kind).toSet(),
      <HeaderIncludeIssueKind>{HeaderIncludeIssueKind.crossTree},
    );
    expect(
      report.issues
          .map((HeaderIncludeIssue issue) => issue.filePath)
          .toSet(),
      <String>{
        'src/gtest/gtest.cc',
        'src/gtest/gtest-port.cc',
        'src/gtest/gtest-printers.cc',
        'src/gtest/gtest-test-part.cc',
        'src/gtest/gtest-death-test.cc',
      },
    );
    for (final HeaderIncludeIssue issue in report.issues) {
      expect(issue.include, 'src/gtest-internal-inl.h');
      expect(issue.candidates, <String>['src/gtest/gtest-internal-inl.h']);
      expect(
        await readText(issue.filePath),
        '#include "src/gtest-internal-inl.h"\n',
      );
    }
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
    await writeText('src/gtest/gtest-all.cc', '#include "src/gtest.cc"\n');
    await writeText('src/gtest/gtest.cc', '');

    final HeaderIncludeFixReport first = await runFixer();
    expect(first.fixedCount, 1);
    final List<int> afterFirst = await readBytes('src/gtest/gtest-all.cc');

    final HeaderIncludeFixReport second = await runFixer();
    expect(second.fixedCount, 0);
    expect(await readBytes('src/gtest/gtest-all.cc'), afterFirst);
    expect(await readText('src/gtest/gtest-all.cc'), '#include "gtest.cc"\n');
  });

  test('修复保留 BOM 与 CRLF 行尾', () async {
    await writeBytes('src/gtest/gtest-all.cc', <int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('#include "src/gtest.cc"\r\n// 中文注释\r\n'),
    ]);
    await writeText('src/gtest/gtest.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    final List<int> fixed = await readBytes('src/gtest/gtest-all.cc');
    expect(fixed.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
    expect(
      utf8.decode(fixed.sublist(3)),
      '#include "gtest.cc"\r\n// 中文注释\r\n',
    );
  });

  test('非 UTF-8 字节文件修复后其余字节不变', () async {
    await writeBytes(
      'src/gtest/gtest-all.cc',
      latin1.encode('#include "src/gtest.cc" // caf\xE9\n'),
    );
    await writeText('src/gtest/gtest.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(
      await readBytes('src/gtest/gtest-all.cc'),
      latin1.encode('#include "gtest.cc" // caf\xE9\n'),
    );
  });

  test('注释中的 include 不处理', () async {
    await writeText(
      'src/gtest/gtest-all.cc',
      '#include "src/gtest.cc"\n'
      '// #include "src/gtest.cc"\n'
      '/*\n'
      '#include "src/gtest.cc"\n'
      '*/\n'
      '/* #include "src/gtest.cc" */\n',
    );
    await writeText('src/gtest/gtest.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.issues, isEmpty);
    expect(
      await readText('src/gtest/gtest-all.cc'),
      '#include "gtest.cc"\n'
      '// #include "src/gtest.cc"\n'
      '/*\n'
      '#include "src/gtest.cc"\n'
      '*/\n'
      '/* #include "src/gtest.cc" */\n',
    );
  });

  test('普通字符串中的 /* 不进入块注释态，后续行照常检出', () async {
    await writeText(
      'src/gtest/gtest-all.cc',
      'const char* pattern = "/*";\n'
      '#include "src/gtest.cc"\n'
      '#include "src/lost.cc"\n',
    );
    await writeText('src/gtest/gtest.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 2);
    expect(report.fixed.single.to, 'gtest.cc');
    expect(report.issues.single.kind, HeaderIncludeIssueKind.noCandidate);
    expect(report.issues.single.include, 'src/lost.cc');
    expect(
      await readText('src/gtest/gtest-all.cc'),
      'const char* pattern = "/*";\n'
      '#include "gtest.cc"\n'
      '#include "src/lost.cc"\n',
    );
  });

  test('普通字符串含转义引号：字符串内 /* 不误判，后续真实引用照常修复', () async {
    await writeText(
      'src/gtest/gtest-all.cc',
      'const char* quoted = "a\\"/*\\"b";\n'
      '#include "src/gtest.cc"\n',
    );
    await writeText('src/gtest/gtest.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 2);
    expect(
      await readText('src/gtest/gtest-all.cc'),
      'const char* quoted = "a\\"/*\\"b";\n'
      '#include "gtest.cc"\n',
    );
  });

  test('raw string 内以 #include 开头的行不改写，其后真实引用照常修复', () async {
    await writeText(
      'src/gtest/a.cc',
      'const char* sample = R"(\n'
      '#include "sub/b.cc"\n'
      ')";\n'
      '#include "sub/b.cc"\n',
    );
    await writeText('src/gtest/b.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 4);
    expect(report.fixed.single.to, 'b.cc');
    expect(
      await readText('src/gtest/a.cc'),
      'const char* sample = R"(\n'
      '#include "sub/b.cc"\n'
      ')";\n'
      '#include "b.cc"\n',
    );
  });

  test('自定义分隔符 raw string 同样隔离', () async {
    await writeText(
      'src/gtest/a.cc',
      'const char* sample = R"cpp(\n'
      '#include "sub/b.cc"\n'
      ')cpp";\n'
      '#include "sub/b.cc"\n',
    );
    await writeText('src/gtest/b.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 1);
    expect(report.fixed.single.line, 4);
    expect(
      await readText('src/gtest/a.cc'),
      'const char* sample = R"cpp(\n'
      '#include "sub/b.cc"\n'
      ')cpp";\n'
      '#include "b.cc"\n',
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
    await writeText('src/a/b.cc', '');
    final Map<String, List<int>> written = <String, List<int>>{};

    final HeaderIncludeFixReport report = await fixHeaderIncludes(
      root.path,
      packageName: 'demo',
      readFile: (String path) async => path.endsWith('a.cc')
          ? utf8.encode('#include "src/b.cc"\n')
          : utf8.encode(''),
      writeFile: (String path, List<int> bytes) async {
        written[path] = bytes;
      },
    );

    expect(report.fixedCount, 1);
    expect(written.keys, hasLength(1));
    expect(written.keys.single.replaceAll('\\', '/'), endsWith('src/a/a.cc'));
    expect(written.values.single, utf8.encode('#include "b.cc"\n'));
  });

  test('缺少源目录时抛出文件系统异常', () async {
    await expectLater(
      fixHeaderIncludes('${root.path}/missing', packageName: 'demo'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
