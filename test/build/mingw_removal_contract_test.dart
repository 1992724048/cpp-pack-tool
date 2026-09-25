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
const List<String> _retiredToolchainTerms = <String>[
  'MinGW',
  'MSYS2',
  'msys64',
  'MSYS2_ROOT',
  'UCRT64',
  'CLANG64',
  'MINGW64',
  'windres',
];

/// 已删除的 GNU 编译旗标与 GNU 驱动探测口径。
const List<String> _retiredGnuTerms = <String>[
  '-mavx2',
  '-static-libgcc',
  '-static-libstdc++',
  '-ffunction-sections',
  '-fdata-sections',
  '-dumpmachine',
];

/// 构建 Profile 契约由独立计划接手，本批文档不得提前声明。
const List<String> _profileTerms = <String>['# profile:', 'CNP_BUILD_PROFILE'];

void main() {
  test('删除 MinGW 后只保留 icx、clang-cl、msvc 三种编译器种类', () {
    expect(
      CompilerKind.values,
      <CompilerKind>[
        CompilerKind.icx,
        CompilerKind.clangCl,
        CompilerKind.msvc,
      ],
    );
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
    final Map<String, String> documents = <String, String>{
      for (final String path in _projectDocuments)
        path: File(path).readAsStringSync(),
    };

    test('三份项目文档均被真实读取且内容非空', () {
      expect(documents.keys.toSet(), _projectDocuments.toSet());
      for (final MapEntry<String, String> document in documents.entries) {
        expect(
          document.value.length,
          greaterThan(200),
          reason: '${document.key} 内容过短，负向断言可能对空文本恒真',
        );
      }
    });

    test('项目文档不再出现已删除的 MinGW 工具链术语', () {
      for (final MapEntry<String, String> document in documents.entries) {
        for (final String token in _retiredToolchainTerms) {
          expect(
            document.value,
            isNot(contains(token)),
            reason: '${document.key} 仍含已删除术语 $token',
          );
        }
      }
    });

    test('项目文档不再出现 GNU 编译旗标与 GNU 驱动探测口径', () {
      for (final MapEntry<String, String> document in documents.entries) {
        for (final String token in _retiredGnuTerms) {
          expect(
            document.value,
            isNot(contains(token)),
            reason: '${document.key} 仍含已删除的 GNU 口径 $token',
          );
        }
      }
    });

    test('项目文档不提前声明构建 Profile 契约', () {
      for (final MapEntry<String, String> document in documents.entries) {
        for (final String token in _profileTerms) {
          expect(
            document.value,
            isNot(contains(token)),
            reason: '${document.key} 提前写入 Profile 口径 $token',
          );
        }
      }
    });

    test('README 与 SKILL.md 的编译器优先级为 ICX > clang-cl > MSVC', () {
      expect(documents['README.md'], contains('ICX > clang-cl > MSVC'));
      expect(
        documents['assets/build/SKILL.md'],
        contains('ICX > clang-cl > MSVC'),
      );
    });

    test('SKILL.md 的 CNP_COMPILER_KIND 覆盖当前全部编译器标识', () {
      final String skill = documents['assets/build/SKILL.md']!;
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
        documents['AGENTS.md'],
        contains('VERSION ${version!.group(1)}'),
        reason: 'AGENTS.md 的 helper 版本与 assets/build/cnp_build_support.py 不一致',
      );
    });

    test('资源编译器只按显式 CNP_RC_COMPILER 透传且不自动探测', () {
      expect(documents['AGENTS.md'], contains('CNP_RC_COMPILER'));
      expect(documents['AGENTS.md'], contains('显式'));
      expect(documents['assets/build/SKILL.md'], contains('CNP_RC_COMPILER'));
      expect(documents['assets/build/SKILL.md'], contains('不自动探测'));
    });

    test('.a 作为通用归档并按 Release/Debug 归入 lib 目录', () {
      expect(documents['AGENTS.md'], contains('FileType.lib'));
      expect(documents['README.md'], contains('.a'));
      expect(documents['assets/build/SKILL.md'], contains('release/lib'));
      expect(documents['assets/build/SKILL.md'], contains('debug/lib'));
    });

    test('CNP_RUNTIME_LIBRARY 的 md/mt 说明仍然保留', () {
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
