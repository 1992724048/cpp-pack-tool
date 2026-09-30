import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/nuget/header_include_fixer.dart';
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
  /// 走新规则改成 include 根相对路径，`.cc` 那条落 `files/`、回落到裸文件名。
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

  test('gtest 式样本：5 处 .h 引用改写为 include 根相对路径，.cc 引用回落到裸文件名', () async {
    await writeGtestLikeTree();

    final HeaderIncludeFixReport report = await runFixer();

    // 命名空间取源目录 basename（gtest）：`src/gtest/gtest-internal-inl.h` 落
    // `gtest/src/gtest/gtest-internal-inl.h`，在 include 根之下，走新规则。
    expect(report.fixedCount, 6);
    expect(report.issues, isEmpty);

    final List<HeaderIncludeFix> headerFixes = report.fixed
        .where((HeaderIncludeFix fix) => fix.from == 'src/gtest-internal-inl.h')
        .toList();
    expect(headerFixes, hasLength(5));
    for (final HeaderIncludeFix fix in headerFixes) {
      expect(fix.to, 'gtest/src/gtest/gtest-internal-inl.h');
      expect(fix.filePath, startsWith('src/gtest/'));
      expect(
        await readText(fix.filePath),
        '#include "gtest/src/gtest/gtest-internal-inl.h"\n',
      );
    }

    // `.cc` 目标落 files/、include 根搜不到，回落到裸文件名：候选与引用文件同目录
    // 且打包落点目录一致，包内由「引用文件所在目录」命中。
    final HeaderIncludeFix sourceFix = report.fixed
        .singleWhere((HeaderIncludeFix fix) => fix.from == 'src/gtest.cc');
    expect(sourceFix.to, 'gtest.cc');
    expect(sourceFix.filePath, 'src/gtest/gtest-all.cc');
    expect(
      await readText('src/gtest/gtest-all.cc'),
      '#include "gtest/gtest.h"\n#include "gtest.cc"\n',
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

  test('配方 include/ 镜像在场仍被改写：候选按包内落点去重，不判多候选', () async {
    // 配方把头文件镜像到 `<包源目录>/include/` 时，构建完成后同一个头文件在包源
    // 目录里有两份（原始的与镜像的）。二者落到同一包内位置，是同一份
    // 产物而非两个候选；按源路径去重会让本阶段最常见的这类失效引用在主流程退化成
    // multipleCandidates，主打能力兑现不了。
    await writeText(
      'cpp_client_wrapper/core_implementations.cc',
      '#include "binary_messenger_impl.h"\n',
    );
    await writeText('cpp_client_wrapper/binary_messenger_impl.h', '#pragma once\n');
    await writeText(
      'include/cpp_client_wrapper/binary_messenger_impl.h',
      '#pragma once\n',
    );

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.issues, isEmpty);
    expect(report.fixedCount, 1);
    final HeaderIncludeFix fix = report.fixed.single;
    expect(fix.from, 'binary_messenger_impl.h');
    expect(fix.to, 'gtest/cpp_client_wrapper/binary_messenger_impl.h');
    expect(
      await readText('cpp_client_wrapper/core_implementations.cc'),
      '#include "gtest/cpp_client_wrapper/binary_messenger_impl.h"\n',
    );
  });

  test('落点不同的同名文件仍报 multipleCandidates：镜像对去重不掩盖真歧义', () async {
    // 三份文件、两个包内落点：原始的与 `include/` 镜像落同一处算同一候选，
    // `x/binary_messenger_impl.h` 落另一处算另一候选，歧义依然成立。
    await writeText(
      'cpp_client_wrapper/a.cc',
      '#include "binary_messenger_impl.h"\n',
    );
    await writeText('cpp_client_wrapper/binary_messenger_impl.h', '#pragma once\n');
    await writeText(
      'include/cpp_client_wrapper/binary_messenger_impl.h',
      '#pragma once\n',
    );
    await writeText('x/binary_messenger_impl.h', '#pragma once\n');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(
      report.issues.single.kind,
      HeaderIncludeIssueKind.multipleCandidates,
    );
    expect(report.issues.single.candidates, <String>[
      'cpp_client_wrapper/binary_messenger_impl.h',
      'x/binary_messenger_impl.h',
    ]);
    expect(
      await readText('cpp_client_wrapper/a.cc'),
      '#include "binary_messenger_impl.h"\n',
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

  test('源码层能解析、包内解析不了：同目录 .cc 引 .h 改写为 include 根相对路径', () async {
    // 唯一的判据是包布局：两者源码同目录，`.cc` 落 files/、`.h` 落
    // include/<命名空间>/，裸文件名在包内两条查找路径都落空，属真正失效的引用。
    // 若仍按源码布局放行，这类引用会被静默放过。
    await writeText(
      'cpp_client_wrapper/core_implementations.cc',
      '#include "binary_messenger_impl.h"\n',
    );
    await writeText('cpp_client_wrapper/binary_messenger_impl.h', '#pragma once\n');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.issues, isEmpty);
    expect(report.fixedCount, 1);
    final HeaderIncludeFix fix = report.fixed.single;
    expect(fix.filePath, 'cpp_client_wrapper/core_implementations.cc');
    expect(fix.from, 'binary_messenger_impl.h');
    expect(fix.to, 'gtest/cpp_client_wrapper/binary_messenger_impl.h');
    expect(
      await readText('cpp_client_wrapper/core_implementations.cc'),
      '#include "gtest/cpp_client_wrapper/binary_messenger_impl.h"\n',
    );
  });

  test('回落裸文件名修复：候选不在 include 根之下时改写为裸文件名', () async {
    // 字面量 `a/helper.cc` 是从包根书写的过期路径（包内解析不到），唯一候选是
    // 引用文件同目录的 `src/a/helper.cc`；`.cc` 落 files/、include 根搜不到，
    // 新规则无目标，回落到裸文件名（同目录 + 打包落点目录一致）。
    await writeText('src/a/one.cc', '#include "a/helper.cc"\n');
    await writeText('src/a/helper.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.issues, isEmpty);
    expect(report.fixedCount, 1);
    final HeaderIncludeFix fix = report.fixed.single;
    expect(fix.filePath, 'src/a/one.cc');
    expect(fix.from, 'a/helper.cc');
    expect(fix.to, 'helper.cc');
    expect(await readText('src/a/one.cc'), '#include "helper.cc"\n');
  });

  test('同目录 .lib 候选不做裸文件名回落：落 files/library 无搜索根，报 crossTree', () async {
    // `.lib` 落 `build/native/files/library/`，`.targets` 不为库文件下发可包含搜索根，
    // 裸文件名在包内必然解析不到。少了文件类型闸就会产出一次 from != to 的无效改写且不报告。
    await writeText('src/x/one.cc', '#include "q/helper.lib"\n');
    await writeText('src/x/helper.lib', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues.single.kind, HeaderIncludeIssueKind.crossTree);
    expect(report.issues.single.candidates, <String>['src/x/helper.lib']);
    expect(await readText('src/x/one.cc'), '#include "q/helper.lib"\n');
  });

  test('files/ 同目录裸文件名引用不产生 from == to 的空修复', () async {
    // 包内可解析（引用文件落 files/<原路径>/，由「本文件所在目录」命中裸文件名），
    // 少了 files/ 兄弟支就会走回落规则改写成同一个字面量，fixedCount 虚增。
    await writeText('src/a/one.cc', '#include "helper.cc"\n');
    await writeText('src/a/helper.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    // isEmpty 蕴含 fixedCount 为 0；连同文件内容一起钉住，防止回落规则产出一次
    // from == to 的空修复。
    expect(report.isEmpty, isTrue);
    expect(await readText('src/a/one.cc'), '#include "helper.cc"\n');
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

  test('尖括号：包内能经 include 根解析的引用不报告', () async {
    // 源码层无 `include/gtest/flutter/...` 这条路，但包内它正是 include 根相对
    // 路径；尖括号与引号同一判据，否则同一文件里会出现「引号已按包布局修复、
    // 尖括号却报失效」的自相矛盾。
    await writeText(
      'src/a.cc',
      '#include <gtest/flutter/cpp_client_wrapper/binary_messenger_impl.h>\n',
    );
    await writeText('flutter/cpp_client_wrapper/binary_messenger_impl.h', '#pragma once\n');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.isEmpty, isTrue);
    expect(
      await readText('src/a.cc'),
      '#include <gtest/flutter/cpp_client_wrapper/binary_messenger_impl.h>\n',
    );
  });

  test('唯一候选位于其他目录时报 crossTree 且不修改', () async {
    // 两条改写规则都不适用：既不在 include 根之下（给不出根相对路径），也不与
    // 引用文件同目录（给不出裸文件名）。
    await writeText('src/a/one.cc', '#include "src/helper.cc"\n');
    await writeText('src/b/helper.cc', '');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues.single.kind, HeaderIncludeIssueKind.crossTree);
    expect(report.issues.single.candidates, <String>['src/b/helper.cc']);
    expect(report.issues.single.description, contains('无适用改写形态'));
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

  test('尖括号不查「引用文件所在目录」：本目录查找本可命中的同名文件不算命中', () async {
    // 决策钉子：`missing.h` 就在 `one.h` 所在目录之下，引号那条「本文件目录」查找能
    // 命中它；若尖括号也查本目录（MSVC 不会，`<...>` 直接走搜索路径）就会被判为可
    // 解析而静默放过。`gtest` 是包内 include 根的子目录，故属要报告的自引用形式。
    await writeText('include/gtest/gtest.h', '');
    await writeText('src/x/one.h', '#include <gtest/missing.h>\n');
    await writeText('src/x/gtest/missing.h', '#pragma once\n');

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.fixedCount, 0);
    expect(report.issues.single.kind, HeaderIncludeIssueKind.missingAngle);
    expect(report.issues.single.include, 'gtest/missing.h');
    expect(report.issues.single.filePath, 'src/x/one.h');
    expect(await readText('src/x/one.h'), '#include <gtest/missing.h>\n');
  });

  test('源码层能解析的引用（相对目录/include 根/包根）按包布局改写', () async {
    // 三条在源码树里都解析得到，但包内解析不到：`.cc` 落 files/ 与头文件分属两棵
    // 树，源码的相对目录与包根写法都不是 include 根相对路径。判据只看包布局，
    // 故三条都要改写，其中第 1、3 条收敛到同一目标。
    await writeText('src/a/self.h', '');
    await writeText('include/foo/bar.h', '');
    await writeText(
      'src/a/user.cc',
      '#include "self.h"\n'
      '#include "foo/bar.h"\n'
      '#include "src/a/self.h"\n',
    );

    final HeaderIncludeFixReport report = await runFixer();

    expect(report.issues, isEmpty);
    expect(report.fixedCount, 3);
    expect(
      report.fixed.map((HeaderIncludeFix fix) => fix.from).toList(),
      <String>['self.h', 'foo/bar.h', 'src/a/self.h'],
    );
    expect(
      report.fixed.map((HeaderIncludeFix fix) => fix.to).toList(),
      <String>[
        'gtest/src/a/self.h',
        'gtest/foo/bar.h',
        'gtest/src/a/self.h',
      ],
    );
    expect(
      await readText('src/a/user.cc'),
      '#include "gtest/src/a/self.h"\n'
      '#include "gtest/foo/bar.h"\n'
      '#include "gtest/src/a/self.h"\n',
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
