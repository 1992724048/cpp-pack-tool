import 'dart:io';

import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 随代码同步维护的项目文档：MinGW 删除后它们不得再教用户使用旧工具链。
const List<String> _projectDocuments = <String>[
  'AGENTS.md',
  'README.md',
  'assets/build/SKILL.md',
];

/// 已删除的 MinGW 工具链术语（编译器、安装根、子环境、资源编译器）。
/// 全部小写：匹配前文档正文会 `toLowerCase()`，故 `MinGW`、`msys2_ROOT` 等大小写变体同样命中。
const List<String> _retiredToolchainTerms = <String>[
  'mingw',
  'mingw64',
  'msys2',
  'msys2_root',
  'msys64',
  'ucrt64',
  'clang64',
  'windres',
];

/// 已删除的 GNU 编译旗标与 GNU 驱动探测口径（同为小写归一）。
const List<String> _retiredGnuTerms = <String>[
  '-mavx2',
  '-static-libgcc',
  '-static-libstdc++',
  '-ffunction-sections',
  '-fdata-sections',
  '-dumpmachine',
];

/// 构建 Profile 契约由独立计划接手，本批文档不得提前声明。
const List<String> _profileTerms = <String>['# profile:', 'cnp_build_profile'];

/// 三份负向 token 表，供「表已小写归一」用例遍历。
const List<List<String>> _negativeTokenTables = <List<String>>[
  _retiredToolchainTerms,
  _retiredGnuTerms,
  _profileTerms,
];

/// 逐份读取项目文档：缺文件即以具名断言失败，而非抛出无路径线索的 `FileSystemException`。
Map<String, String> _readProjectDocuments() {
  final Map<String, String> documents = <String, String>{};
  for (final String path in _projectDocuments) {
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '项目文档 $path 不存在，文档契约无从判定');
    final String text = file.readAsStringSync();
    expect(text.trim(), isNotEmpty, reason: '$path 内容为空，负向断言会对空文本恒真');
    documents[path] = text;
  }
  return documents;
}

/// 逐 token 断言文档正文（先小写归一）不含已删除口径。
void _expectNoTokens(
  Map<String, String> documents,
  List<String> tokens,
  String label,
) {
  expect(tokens, isNotEmpty, reason: '$label 的负向 token 表为空，用例会静默通过');
  for (final MapEntry<String, String> document in documents.entries) {
    final String haystack = document.value.toLowerCase();
    for (final String token in tokens) {
      expect(
        haystack,
        isNot(contains(token)),
        reason: '${document.key} 仍含$label $token',
      );
    }
  }
}

void main() {
  test('删除 MinGW 后只保留 icx、clang-cl、msvc 三种编译器种类', () {
    expect(CompilerKind.values, <CompilerKind>[
      CompilerKind.icx,
      CompilerKind.clangCl,
      CompilerKind.msvc,
    ]);
  });

  test('mingw 稳定标识读回为未知值，R23 clang 也不映射为 clang-cl', () {
    expect(compilerKindFromId('mingw'), isNull);
    expect(compilerKindFromId('MINGW'), isNull);
    expect(compilerKindFromId('clang'), isNull);
    expect(isLegacyCompilerKindId('clang'), isTrue);
  });

  test('三种有效标识与显示名保持契约', () {
    expect(compilerKindId(CompilerKind.icx), 'icx');
    expect(compilerKindId(CompilerKind.clangCl), 'clang-cl');
    expect(compilerKindId(CompilerKind.msvc), 'msvc');
    expect(compilerKindLabel(CompilerKind.icx), 'ICX');
    expect(compilerKindLabel(CompilerKind.clangCl), 'clang-cl');
    expect(compilerKindLabel(CompilerKind.msvc), 'MSVC');
  });

  group('项目文档契约', () {
    test('三份项目文档均被真实读取且内容非空', () {
      final Map<String, String> documents = _readProjectDocuments();
      expect(documents.keys.toSet(), _projectDocuments.toSet());
      for (final MapEntry<String, String> document in documents.entries) {
        expect(
          document.value.length,
          greaterThan(200),
          reason: '${document.key} 内容过短，负向断言可能对空文本恒真',
        );
      }
    });

    test('负向 token 表已统一小写，大小写变体无法绕过扫描', () {
      for (final List<String> table in _negativeTokenTables) {
        for (final String token in table) {
          expect(
            token,
            token.toLowerCase(),
            reason: '负向 token $token 含大写字母，将漏判文档中的大小写变体',
          );
        }
      }
    });

    test('项目文档不再出现已删除的 MinGW 工具链术语', () {
      _expectNoTokens(_readProjectDocuments(), _retiredToolchainTerms, '已删除术语');
    });

    test('项目文档不再出现 GNU 编译旗标与 GNU 驱动探测口径', () {
      _expectNoTokens(_readProjectDocuments(), _retiredGnuTerms, '已删除的 GNU 口径');
    });

    test('项目文档不提前声明构建 Profile 契约', () {
      _expectNoTokens(
        _readProjectDocuments(),
        _profileTerms,
        '提前写入的 Profile 口径',
      );
    });

    test('README 与 SKILL.md 的编译器优先级为 ICX > clang-cl > MSVC', () {
      final Map<String, String> documents = _readProjectDocuments();
      expect(documents['README.md'], contains('ICX > clang-cl > MSVC'));
      expect(
        documents['assets/build/SKILL.md'],
        contains('ICX > clang-cl > MSVC'),
      );
    });

    test('SKILL.md 的 CNP_COMPILER_KIND 覆盖当前全部编译器标识', () {
      final String skill = _readProjectDocuments()['assets/build/SKILL.md']!;
      expect(skill, contains('CNP_COMPILER_KIND'));
      for (final CompilerKind kind in CompilerKind.values) {
        expect(
          skill,
          contains(compilerKindId(kind)),
          reason: 'SKILL.md 缺少编译器标识 ${compilerKindId(kind)}',
        );
      }
    });

    test('AGENTS.md 记录的 helper 版本与辅助模块源码一致', () {
      final String helper = File('assets/build/cnp_build_support.py')
          .readAsStringSync();
      final RegExpMatch? version = RegExp(r'VERSION\s*=\s*"(\d+)"')
          .firstMatch(helper);
      expect(version, isNotNull, reason: '未从辅助模块解析到 VERSION 常量');
      expect(
        _readProjectDocuments()['AGENTS.md'],
        contains('VERSION ${version!.group(1)}'),
        reason: 'AGENTS.md 的 helper 版本与 assets/build/cnp_build_support.py 不一致',
      );
    });

    test('资源编译器只按显式 CNP_RC_COMPILER 透传且不自动探测', () {
      final Map<String, String> documents = _readProjectDocuments();
      expect(documents['AGENTS.md'], contains('CNP_RC_COMPILER'));
      expect(documents['AGENTS.md'], contains('显式'));
      expect(documents['assets/build/SKILL.md'], contains('CNP_RC_COMPILER'));
      expect(documents['assets/build/SKILL.md'], contains('不自动探测'));
    });

    test('.a 作为通用归档并按 Release/Debug 归入 lib 目录', () {
      final Map<String, String> documents = _readProjectDocuments();
      expect(documents['AGENTS.md'], contains('FileType.lib'));
      expect(documents['README.md'], contains('.a'));
      expect(documents['assets/build/SKILL.md'], contains('release/lib'));
      expect(documents['assets/build/SKILL.md'], contains('debug/lib'));
    });

    test('AGENTS.md 记录 .a 的构建器落点与 NuGet 不自动派生附加库', () {
      final String agents = _readProjectDocuments()['AGENTS.md']!;
      expect(
        agents,
        contains('lib/dll/pdb（`.a` 通用归档同样归此类）→ `build/native/lib/`'),
        reason: 'NuGet 布局未记录 .a 通用归档同样归入 build/native/lib/',
      );
      expect(
        agents,
        contains(
          '`.a` 不触发 `AdditionalLibraryDirectories`/`AdditionalDependencies` 自动派生',
        ),
        reason: 'NuGet 布局未记录 .a 不参与附加库目录/库名的自动派生',
      );
      expect(
        agents,
        contains('lib/dll/pdb（`.a` 通用归档同样归此类）→ `lib/`'),
        reason: 'CMake 布局未记录 .a 通用归档同样归入 lib/',
      );
      expect(
        agents,
        contains('`.lib`/`.a` 按路径推断 D/R 分组'),
        reason: 'CMake 链接列表未记录 .a 与 .lib 一同参与 Release/Debug 分组',
      );
    });

    test('CNP_RUNTIME_LIBRARY 的 md/mt 说明仍然保留', () {
      final Map<String, String> documents = _readProjectDocuments();
      for (final String path in <String>[
        'AGENTS.md',
        'assets/build/SKILL.md',
      ]) {
        final String text = documents[path]!;
        expect(
          text,
          contains('CNP_RUNTIME_LIBRARY'),
          reason: '$path 缺少运行库家族说明',
        );
        expect(text, contains('`md`'), reason: '$path 缺少 md 说明');
        expect(text, contains('`mt`'), reason: '$path 缺少 mt 说明');
      }
    });
  });
}
