import 'dart:io';

import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 随代码同步维护的项目文档：MinGW 删除后它们不得再教用户使用旧工具链。
const List<String> _projectDocuments = <String>[
  'AGENTS.md',
  'README.md',
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

/// 全仓扫描覆盖的文本扩展名：Dart 源码与 Markdown 文档；`.py` 保留以防今后新增的
/// 脚本绕过负向扫描。
const List<String> _scannedExtensions = <String>['.dart', '.md', '.py'];

/// 全仓扫描的目录根（相对包根），确保生产代码、测试与资产脚本三类都在扫描面内。
const List<String> _scanRoots = <String>['assets', 'lib', 'test'];

/// 全部已删除口径（工具链术语 + GNU 编译旗标），供全仓扫描逐 token 比对。
const List<String> _allRetiredTokens = <String>[
  ..._retiredToolchainTerms,
  ..._retiredGnuTerms,
];

/// 允许保留已删除口径的文件：`相对路径 → (允许的 token, 保留理由)`。
///
/// 登记理由只有两类：保护性负向夹具（含负向断言）与旧配置迁移识别；
/// 生产代码的活跃链路与用户文档一律不得登记。
const Map<String, ({List<String> tokens, String reason})> _allowedResidues =
    <String, ({List<String> tokens, String reason})>{
      'lib/models/settings_model.dart': (
        tokens: <String>['mingw'],
        reason: '生产代码唯一例外：检测缓存与优先级的旧种类迁移识别（整表作废并等待重检）',
      ),
      'test/build/build_environment_test.dart': (
        tokens: <String>['windres'],
        reason: '负向夹具：断言不推导资源编译器、同目录存在该工具也不下发',
      ),
      'test/build/build_environment_real_smoke_test.dart': (
        tokens: <String>['mingw'],
        reason: '负向断言：真实环境准备仅覆盖受支持的三种编译器种类',
      ),
      'test/build/toolchain_test.dart': (
        tokens: <String>[
          'msys2',
          'msys2_root',
          'msys64',
          'ucrt64',
          'mingw',
          '-dumpmachine',
        ],
        reason: '负向夹具：断言不读取旧安装根（含其环境变量）、不启动已删除的 GNU 驱动探测子进程',
      ),
      'test/util/format_test.dart': (
        tokens: <String>['msys64', 'ucrt64'],
        reason: '负向无关夹具：仅作为多级目录的父目录解析路径样本，不表达工具链语义',
      ),
      'test/models/settings_model_test.dart': (
        tokens: <String>['mingw', 'mingw64', 'msys64', 'ucrt64'],
        reason: '迁移测试：旧检测缓存与旧优先级读回时被丢弃并等待重检',
      ),
      'test/config/pack_store_test.dart': (
        tokens: <String>['mingw', 'msys64', 'ucrt64'],
        reason: '迁移测试：旧配置文件加载后相关条目被丢弃',
      ),
      'test/build/mingw_removal_contract_test.dart': (
        tokens: _allRetiredTokens,
        reason: '本文件即负向 token 的载体：表格与用例名必须写出字面量才能断言',
      ),
    };

/// 读取全仓扫描范围内的文本文件，返回 `相对路径（正斜杠） → 小写归一正文`
/// 与实际枚举到文件的扫描根集合。
///
/// 目录根缺失即以具名断言失败，避免递归枚举为空时扫描静默恒真。枚举口径取
/// 「枚举到任意文件」而非「枚举到受扫描扩展名的文件」：`assets` 只有字体与图标
/// 等二进制资源，本就不贡献受扫描文本，若按后者判定会把「路径写错导致枚举为空」
/// 与「该根确实没有受扫描文本」混为一谈。
({Map<String, String> texts, Set<String> rootsWithFiles}) _scanRepositoryText() {
  final Map<String, String> texts = <String, String>{};
  final Set<String> rootsWithFiles = <String>{};
  for (final String root in _scanRoots) {
    final Directory directory = Directory(root);
    expect(
      directory.existsSync(),
      isTrue,
      reason: '扫描根 $root 不存在，全仓扫描会静默漏扫该目录',
    );
    for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      rootsWithFiles.add(root);
      final String path = entity.path.replaceAll('\\', '/');
      if (!_scannedExtensions.any(path.endsWith)) {
        continue;
      }
      texts[path] = File(entity.path).readAsStringSync().toLowerCase();
    }
  }
  for (final String path in _projectDocuments) {
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '项目文档 $path 不存在，全仓扫描会静默漏扫');
    texts[path] = file.readAsStringSync().toLowerCase();
  }
  return (texts: texts, rootsWithFiles: rootsWithFiles);
}

/// 汇总每个文件实际命中的已删除口径 token。
Map<String, List<String>> _collectResidues(Map<String, String> texts) {
  final Map<String, List<String>> residues = <String, List<String>>{};
  for (final MapEntry<String, String> file in texts.entries) {
    final List<String> hits = <String>[
      for (final String token in _allRetiredTokens)
        if (file.value.contains(token)) token,
    ];
    if (hits.isNotEmpty) {
      residues[file.key] = hits;
    }
  }
  return residues;
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
    test('两份项目文档均被真实读取且内容非空', () {
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
  });

  group('全仓残留扫描', () {
    test('扫描面覆盖三个目录根与全部项目文档', () {
      final ({Map<String, String> texts, Set<String> rootsWithFiles}) scan =
          _scanRepositoryText();
      final Map<String, String> texts = scan.texts;
      for (final String root in _scanRoots) {
        expect(
          scan.rootsWithFiles,
          contains(root),
          reason: '扫描根 $root 未枚举到任何文件，扫描面存在缺口',
        );
      }
      for (final String path in _projectDocuments) {
        expect(texts.keys, contains(path), reason: '项目文档 $path 未被扫描');
      }
      expect(
        texts.length,
        greaterThan(100),
        reason: '扫描到的文本文件过少，全仓扫描可能因路径口径错误而空转',
      );
    });

    test('全仓仅在显式登记处保留已删除口径', () {
      final Map<String, List<String>> residues = _collectResidues(
        _scanRepositoryText().texts,
      );
      expect(residues, isNotEmpty, reason: '允许残留表无实际命中，扫描或 token 表可能已失效');
      for (final MapEntry<String, List<String>> entry in residues.entries) {
        final ({List<String> tokens, String reason})? allowed =
            _allowedResidues[entry.key];
        expect(
          allowed,
          isNotNull,
          reason: '${entry.key} 残留已删除口径 ${entry.value.join('、')}，'
              '但未登记保留理由；生产代码与用户文档一律禁止，'
              '仅负向夹具与旧配置迁移测试可登记',
        );
        final Set<String> undeclared = entry.value.toSet().difference(
          allowed!.tokens.toSet(),
        );
        expect(
          undeclared,
          isEmpty,
          reason: '${entry.key} 出现未登记的已删除口径 ${undeclared.join('、')}',
        );
      }
    });

    test('允许残留表无过期或空理由条目', () {
      expect(_allowedResidues, isNotEmpty, reason: '允许残留表为空，登记机制形同虚设');
      final Map<String, String> texts = _scanRepositoryText().texts;
      for (final MapEntry<String, ({List<String> tokens, String reason})> entry
          in _allowedResidues.entries) {
        expect(
          entry.value.reason.trim(),
          isNotEmpty,
          reason: '${entry.key} 的保留理由为空，登记失去意义',
        );
        final String? text = texts[entry.key];
        expect(
          text,
          isNotNull,
          reason: '允许残留表登记的 ${entry.key} 已不在扫描范围内，请移除该条目',
        );
        for (final String token in entry.value.tokens) {
          expect(
            text,
            contains(token),
            reason: '允许残留表已过期：${entry.key} 不再含 $token，请移除该登记',
          );
        }
      }
    });
  });
}
