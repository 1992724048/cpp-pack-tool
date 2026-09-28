import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/scanner/file_scan.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 参与 include 检查的文本源码扩展名（头 + 源；大小写不敏感）。
///
/// 失效引用实测集中在 `.cc`（gtest 的 `gtest-all.cc` 融合式 include），
/// 因此扫描范围从「头文件」扩大到全部文本源码。
const Set<String> headerIncludeSourceExtensions = <String>{
  'h',
  'hpp',
  'hh',
  'hxx',
  'inl',
  'ipp',
  'c',
  'cc',
  'cpp',
  'cxx',
};

/// 未自动修复的 include 问题分类（报告级）。
enum HeaderIncludeIssueKind {
  /// 包内没有任何同名文件候选。
  noCandidate,

  /// 包内存在多个同名候选，无法确定目标。
  multipleCandidates,

  /// 有唯一候选但其打包落点不在 include 根之下（如 `.cc` 落 `files/`、`.lib`
  /// 落 `lib/`，include 根搜不到），没有「相对 include 根的包内路径」可作改写目标。
  crossTree,

  /// 尖括号自引用（首段命中包内 include 根）但目标缺失；仅报告不修改。
  missingAngle,
}

/// 一处已自动修复的引号 include。
class HeaderIncludeFix {
  const HeaderIncludeFix({
    required this.filePath,
    required this.line,
    required this.from,
    required this.to,
  });

  /// 相对包源目录的路径（`/` 分隔）。
  final String filePath;

  /// 1 起始的行号。
  final int line;

  /// 原 include 字面量（不含引号）。
  final String from;

  /// 修复后的 include 字面量：目标文件相对包内 include 根的包内路径。
  final String to;
}

/// 一处待处理的 include 问题。
class HeaderIncludeIssue {
  const HeaderIncludeIssue({
    required this.filePath,
    required this.line,
    required this.include,
    required this.kind,
    this.candidates = const <String>[],
  });

  final String filePath;
  final int line;

  /// 原 include 字面量（不含引号/尖括号）。
  final String include;
  final HeaderIncludeIssueKind kind;

  /// 同名候选（相对包源目录路径；无候选时为空，多候选时列出全部）。
  final List<String> candidates;

  String get description => switch (kind) {
    HeaderIncludeIssueKind.noCandidate => '包内未找到同名文件',
    HeaderIncludeIssueKind.multipleCandidates =>
      '存在多个同名候选：${candidates.join('、')}',
    HeaderIncludeIssueKind.crossTree => '唯一候选打包后不在 include 根之下：${candidates.join('、')}',
    HeaderIncludeIssueKind.missingAngle => '尖括号自引用缺失（不自动修改）',
  };
}

/// include 检查与自动修复的结果。
class HeaderIncludeFixReport {
  const HeaderIncludeFixReport({
    this.fixed = const <HeaderIncludeFix>[],
    this.issues = const <HeaderIncludeIssue>[],
  });

  static const HeaderIncludeFixReport empty = HeaderIncludeFixReport();

  final List<HeaderIncludeFix> fixed;
  final List<HeaderIncludeIssue> issues;

  int get fixedCount => fixed.length;
  bool get hasIssues => issues.isNotEmpty;
  bool get isEmpty => fixed.isEmpty && issues.isEmpty;
}

/// 读取文件字节（绝对路径）。
typedef HeaderIncludeFileReader = Future<List<int>> Function(
  String absolutePath,
);

/// 写回文件字节（绝对路径）。
typedef HeaderIncludeFileWriter = Future<void> Function(
  String absolutePath,
  List<int> bytes,
);

/// include 检查/修复入口的回调形态（构建流程接线用，便于测试注入替代实现）。
typedef PackHeaderIncludeFixer = Future<HeaderIncludeFixReport> Function(
  String sourcePath, {
  required String packageName,
});

/// 扫描 [sourcePath] 下全部文本源码的 `#include` 引用并做保守自动修复：
///
/// - 引号引用先按**源码布局**解析（当前文件目录 → 每个 `includeRoots` → 包根），
///   命中即视为正常、不动；未命中再按**包内布局**判一次（`.targets` 恒定只下发
///   `build/native/include` 一个搜索根），已能解析的同样原样保留——否则会产出一次
///   内容不变的「修复」而虚增 fixedCount；
/// - 仍未解析的引用找**唯一同名候选**（basename 大小写不敏感全包搜索），候选落在
///   include 根之下时改写为**目标相对 include 根的包内路径**——include 根恒定下发，
///   该形式在任何引用位置都必然解析得到；改写后再自检一次可解析性，不能则回落报告；
/// - 其余未解析引用收集为待处理问题（无候选 / 多候选 / 候选不在 include 根之下），
///   外部依赖（首段目录不落在包内，如 `absl/...`）与条件编译外部引用不报告；
/// - 尖括号引用仅检查首段命中包内 include 根的自引用存在性，缺失仅报告。
///
/// [packageName] 与打包器同一命名空间口径（见 [includeNamespaceOf]）；
/// [readFile]/[writeFile] 可注入以配合测试。保留文件编码/BOM/行尾，仅替换
/// include 字面量；重复执行幂等。
Future<HeaderIncludeFixReport> fixHeaderIncludes(
  String sourcePath, {
  required String packageName,
  HeaderIncludeFileReader? readFile,
  HeaderIncludeFileWriter? writeFile,
}) {
  return HeaderIncludeFixer(
    sourcePath: sourcePath,
    packageName: packageName,
    readFile: readFile,
    writeFile: writeFile,
  ).run();
}

class HeaderIncludeFixer {
  HeaderIncludeFixer({
    required this.sourcePath,
    required this.packageName,
    HeaderIncludeFileReader? readFile,
    HeaderIncludeFileWriter? writeFile,
  }) : _readFile = readFile ?? _readFileBytes,
       _writeFile = writeFile ?? _writeFileBytes;

  final String sourcePath;
  final String packageName;
  final HeaderIncludeFileReader _readFile;
  final HeaderIncludeFileWriter _writeFile;

  Future<HeaderIncludeFixReport> run() async {
    final _IncludeIndex index = await _buildIndex();
    final List<String> textFiles = <String>[
      for (final String file in index.files)
        if (_isTextSource(file)) file,
    ]..sort(_comparePaths);

    final List<HeaderIncludeFix> fixes = <HeaderIncludeFix>[];
    final List<HeaderIncludeIssue> issues = <HeaderIncludeIssue>[];

    for (final String file in textFiles) {
      final List<int> bytes = await _readFile(joinPath(sourcePath, file));
      final _DecodedText decoded = _decodeText(bytes);
      final _FileFixOutcome outcome = _fixText(decoded.text, file, index);
      fixes.addAll(outcome.fixes);
      issues.addAll(outcome.issues);
      if (outcome.fixes.isNotEmpty) {
        await _writeFile(joinPath(sourcePath, file), decoded.encode(outcome.text));
      }
    }
    return HeaderIncludeFixReport(
      fixed: List<HeaderIncludeFix>.unmodifiable(fixes),
      issues: List<HeaderIncludeIssue>.unmodifiable(issues),
    );
  }

  Future<_IncludeIndex> _buildIndex() async {
    final _IncludeIndex index = _IncludeIndex(
      namespace: includeNamespaceOf(sourcePath, packageName),
    );
    await _collectDirectory(Directory(sourcePath), '', index);
    return index;
  }

  Future<void> _collectDirectory(
    Directory directory,
    String prefix,
    _IncludeIndex index,
  ) async {
    final List<FileSystemEntity> entities = await directory.list(
      followLinks: false,
    ).toList();
    for (final FileSystemEntity entity in entities) {
      final String name = baseName(entity.path);
      final String relative = prefix.isEmpty ? name : '$prefix/$name';
      if (entity is File) {
        index.addFile(relative);
      } else if (entity is Directory && !FileScan.shouldSkipDirectory(name)) {
        index.addDirectory(relative, name);
        await _collectDirectory(entity, relative, index);
      }
    }
  }

  ({String text, List<HeaderIncludeFix> fixes, List<HeaderIncludeIssue> issues})
  _fixText(String text, String filePath, _IncludeIndex index) {
    final _FileScanner scanner = _FileScanner(filePath: filePath, index: index);
    final StringBuffer buffer = StringBuffer();
    int lineNumber = 0;
    int last = 0;
    for (final RegExpMatch separator in _lineSeparatorPattern.allMatches(text)) {
      lineNumber++;
      buffer
        ..write(scanner.fixLine(text.substring(last, separator.start), lineNumber))
        ..write(text.substring(separator.start, separator.end));
      last = separator.end;
    }
    buffer.write(scanner.fixLine(text.substring(last), lineNumber + 1));
    return (text: buffer.toString(), fixes: scanner.fixes, issues: scanner.issues);
  }
}

final RegExp _lineSeparatorPattern = RegExp(r'\r\n|\n|\r');
final RegExp _pathSeparatorPattern = RegExp(r'[/\\]');
final RegExp _quotedIncludePattern = RegExp(
  r'^[ \t]*#[ \t]*include[ \t]*"([^"]*)"',
);
final RegExp _angleIncludePattern = RegExp(
  r'^[ \t]*#[ \t]*include[ \t]*<([^<>]*)>',
);

/// 单文件处理结果：修复后的文本 + 已修复清单 + 待处理问题清单。
typedef _FileFixOutcome = ({
  String text,
  List<HeaderIncludeFix> fixes,
  List<HeaderIncludeIssue> issues,
});

const List<int> _utf8BomBytes = <int>[0xEF, 0xBB, 0xBF];

bool _isTextSource(String path) {
  final String name = baseName(path);
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return false;
  }
  return headerIncludeSourceExtensions.contains(
    name.substring(dot + 1).toLowerCase(),
  );
}

int _comparePaths(String first, String second) {
  final int insensitive = first.toLowerCase().compareTo(second.toLowerCase());
  return insensitive != 0 ? insensitive : first.compareTo(second);
}

String _directoryOf(String path) {
  final int separator = path.lastIndexOf('/');
  return separator <= 0 ? '' : path.substring(0, separator);
}

List<String> _rawSegments(String path) => <String>[
  for (final String segment in path.split(_pathSeparatorPattern))
    if (segment.isNotEmpty) segment,
];

/// 以 [baseDirectory]（`/` 分隔，可为空 = 包根）为基准归一化相对路径；
/// `..` 越出包根时返回 null。
String? _normalizeRelativePath(String baseDirectory, String path) {
  final List<String> stack = baseDirectory.isEmpty
      ? <String>[]
      : baseDirectory.split('/');
  for (final String segment in _rawSegments(path)) {
    if (segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (stack.isEmpty) {
        return null;
      }
      stack.removeLast();
      continue;
    }
    stack.add(segment);
  }
  return stack.isEmpty ? null : stack.join('/');
}

/// 打包落点是否落在包内 include 根（`build/native/include`）之下：只有头文件与
/// 模块会被打包器搬进 include 命名空间树，其余文件留在 `files/`/`lib/`，而
/// `.targets` 不为它们下发任何搜索根。
bool _landsUnderIncludeRoot(String path) {
  final String normalized = path.replaceAll('\\', '/');
  final FileType type = FileModel(
    name: baseName(normalized),
    path: normalized,
  ).type;
  return type == FileType.header || type == FileType.module;
}

/// 打包落点路径（与 `nuget_builder` 同一口径：头文件/模块进 include 命名空间树，
/// 其余文件保持原相对路径）。返回值统一以包内 include 根为基准。
String _packageDestination(String path, String namespace) {
  final String normalized = path.replaceAll('\\', '/');
  if (!_landsUnderIncludeRoot(normalized)) {
    return normalized;
  }
  return includePackageRelativePath(normalized, namespace);
}

/// 单个文本文件的 include 扫描状态机（块注释与 raw string 跨行跟踪）。
class _FileScanner {
  _FileScanner({required this.filePath, required this.index});

  final String filePath;
  final _IncludeIndex index;
  final List<HeaderIncludeFix> fixes = <HeaderIncludeFix>[];
  final List<HeaderIncludeIssue> issues = <HeaderIncludeIssue>[];

  bool _inBlockComment = false;

  /// 当前所在 raw string 的定界符（`R"delim(` 中 `delim`）；不在其中时为 null。
  String? _rawStringDelimiter;

  String fixLine(String line, int lineNumber) {
    final String masked = _maskCommentsAndRawStrings(line);
    final RegExpMatch? quoted = _quotedIncludePattern.firstMatch(masked);
    if (quoted != null) {
      return _handleQuoted(line, quoted, lineNumber);
    }
    final RegExpMatch? angle = _angleIncludePattern.firstMatch(masked);
    if (angle != null) {
      _handleAngle(line, angle, lineNumber);
    }
    return line;
  }

  /// 注释与 raw string 内的字符替换为等长空格（偏移不变），供 include
  /// 匹配使用；普通字符串原样保留（include 指令自身的字面量即普通字符串），
  /// 扫描时跳过其内容以免其中的 `/*` 误入注释态。块注释与 raw string 跨行
  /// 跟踪；普通字符串仅行内跟踪，行尾未闭合按行尾丢弃，避免注释中未配对
  /// 引号蚕食后续行。
  String _maskCommentsAndRawStrings(String line) {
    final StringBuffer masked = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_inBlockComment) {
        final int close = line.indexOf('*/', index);
        if (close < 0) {
          masked.write(' ' * (line.length - index));
          index = line.length;
        } else {
          masked.write(' ' * (close + 2 - index));
          index = close + 2;
          _inBlockComment = false;
        }
        continue;
      }
      final String? rawDelimiter = _rawStringDelimiter;
      if (rawDelimiter != null) {
        final String terminator = ')$rawDelimiter"';
        final int close = line.indexOf(terminator, index);
        if (close < 0) {
          masked.write(' ' * (line.length - index));
          index = line.length;
        } else {
          final int end = close + terminator.length;
          masked.write(' ' * (end - index));
          index = end;
          _rawStringDelimiter = null;
        }
        continue;
      }
      final int commentOpen = line.indexOf('/*', index);
      final int quote = line.indexOf('"', index);
      if (quote >= 0 && (commentOpen < 0 || quote < commentOpen)) {
        masked.write(line.substring(index, quote));
        index = _scanString(line, quote, masked);
        continue;
      }
      if (commentOpen >= 0) {
        masked
          ..write(line.substring(index, commentOpen))
          ..write('  ');
        index = commentOpen + 2;
        _inBlockComment = true;
        continue;
      }
      masked.write(line.substring(index));
      index = line.length;
    }
    return masked.toString();
  }

  /// 扫描自 [quote]（`"`）起的字符串字面量并返回其后的扫描下标。普通字符串
  /// 连同转义序列原样写入 [masked]；`R"delim(` 起始的 raw string 整体掩码并
  /// 记录跨行状态；行内未闭合时按行尾结束。
  int _scanString(String line, int quote, StringBuffer masked) {
    final int? delimiterEnd = _rawStringDelimiterEnd(line, quote);
    if (delimiterEnd != null) {
      masked.write(' ' * (delimiterEnd + 1 - quote));
      _rawStringDelimiter = line.substring(quote + 1, delimiterEnd);
      return delimiterEnd + 1;
    }
    int cursor = quote + 1;
    while (cursor < line.length) {
      final int code = line.codeUnitAt(cursor);
      if (code == 0x5C /* \ */) {
        cursor += 2;
        continue;
      }
      cursor++;
      if (code == 0x22 /* " */) {
        break;
      }
    }
    final int end = cursor > line.length ? line.length : cursor;
    masked.write(line.substring(quote, end));
    return end;
  }

  /// `"` 处属于 raw string 起始（`R"delim(`）时返回定界符后 `(` 的下标；
  /// 非 `R"` 起始或定界符非法/超长（>16）返回 null，按普通字符串处理。
  int? _rawStringDelimiterEnd(String line, int quote) {
    if (quote < 1 || line.codeUnitAt(quote - 1) != 0x52 /* R */) {
      return null;
    }
    final int delimiterStart = quote + 1;
    int cursor = delimiterStart;
    while (cursor < line.length && cursor - delimiterStart <= 16) {
      final int code = line.codeUnitAt(cursor);
      if (code == 0x28 /* ( */) {
        return cursor;
      }
      if (code == 0x22 /* " */ ||
          code == 0x29 /* ) */ ||
          code == 0x5C /* \ */ ||
          code <= 0x20) {
        return null;
      }
      cursor++;
    }
    return null;
  }

  /// 捕获组字面量的行内范围：两个 include 模式都在捕获组后紧跟一个结束字符
  /// （引号/尖括号），故结束位置 = 整体匹配结束 - 1，起始位置再左移字面量长度。
  ({int start, int end}) _captureSpan(RegExpMatch match) {
    final int end = match.end - 1;
    return (start: end - match.group(1)!.length, end: end);
  }

  String _handleQuoted(String line, RegExpMatch match, int lineNumber) {
    final String includePath = match.group(1)!;
    final ({int start, int end}) span = _captureSpan(match);
    if (includePath.trim().isEmpty ||
        _resolvesQuotedInclude(includePath)) {
      return line;
    }

    // 第 1 步：包布局下已能解析的引用不是问题，原样保留。源码层解析不了但经
    // include 根能在包内解析的引用（如 `ns/sub/include/ns/other.h`）正落此处，
    // 少了这道判定会对它做一次内容不变的改写，虚增 fixedCount。
    if (_resolvesInPackageLayout(includePath)) {
      return line;
    }

    // 排除引用文件自身：同名自引用（如 `foo/bar.h` 引用 `baz/bar.h`）不代表
    // 存在可改写目标，应归入报告而非自包含改写。
    final String lowerSelfPath = filePath.toLowerCase();
    final List<String> candidates = <String>[
      for (final String candidate
          in index.candidatesFor(baseName(includePath).toLowerCase()))
        if (candidate.toLowerCase() != lowerSelfPath) candidate,
    ]..sort(_comparePaths);

    if (candidates.isEmpty) {
      if (!_isForeignQuotedReference(includePath)) {
        issues.add(
          HeaderIncludeIssue(
            filePath: filePath,
            line: lineNumber,
            include: includePath,
            kind: HeaderIncludeIssueKind.noCandidate,
          ),
        );
      }
      return line;
    }
    if (candidates.length > 1) {
      issues.add(
        HeaderIncludeIssue(
          filePath: filePath,
          line: lineNumber,
          include: includePath,
          kind: HeaderIncludeIssueKind.multipleCandidates,
          candidates: candidates,
        ),
      );
      return line;
    }

    // 第 2 步：唯一候选落在 include 根之下时，改写为它相对 include 根的包内
    // 路径。引号/尖括号形态不变，只换字面量。
    final String candidate = candidates.single;
    final String? replacement = _includeRootRelativeTarget(candidate);

    // 第 3 步：自检改写结果在包布局下确实能解析，不能则不写、回落到报告分支。
    if (replacement != null && _resolvesInPackageLayout(replacement)) {
      fixes.add(
        HeaderIncludeFix(
          filePath: filePath,
          line: lineNumber,
          from: includePath,
          to: replacement,
        ),
      );
      return line.replaceRange(span.start, span.end, replacement);
    }
    issues.add(
      HeaderIncludeIssue(
        filePath: filePath,
        line: lineNumber,
        include: includePath,
        kind: HeaderIncludeIssueKind.crossTree,
        candidates: candidates,
      ),
    );
    return line;
  }

  void _handleAngle(String line, RegExpMatch match, int lineNumber) {
    final String includePath = match.group(1)!;
    if (includePath.trim().isEmpty || _resolvesAngleInclude(includePath)) {
      return;
    }
    if (!_isAngleSelfReference(includePath)) {
      return;
    }
    issues.add(
      HeaderIncludeIssue(
        filePath: filePath,
        line: lineNumber,
        include: includePath,
        kind: HeaderIncludeIssueKind.missingAngle,
      ),
    );
  }

  bool _resolvesQuotedInclude(String includePath) {
    if (_exists(_normalizeRelativePath(_directoryOf(filePath), includePath))) {
      return true;
    }
    for (final String root in index.includeRoots) {
      if (_exists(_normalizeRelativePath(root, includePath))) {
        return true;
      }
    }
    return _exists(_normalizeRelativePath('', includePath));
  }

  bool _resolvesAngleInclude(String includePath) {
    for (final String root in index.includeRoots) {
      if (_exists(_normalizeRelativePath(root, includePath))) {
        return true;
      }
    }
    return false;
  }

  /// 包布局下的可解析性。`.targets` 恒定只下发 `build/native/include` 一个搜索
  /// 根，故只需两条路径：引用文件自身的包内目录（仅当它也落在 include 根之下
  /// 才有意义）与 include 根本身；`files/`、`lib/` 下的源文件没有对应搜索根。
  bool _resolvesInPackageLayout(String includePath) {
    if (_landsUnderIncludeRoot(filePath)) {
      final String? sibling = _normalizeRelativePath(
        _directoryOf(_packageDestination(filePath, index.namespace)),
        includePath,
      );
      if (_existsInIncludeRoot(sibling)) {
        return true;
      }
    }
    return _existsInIncludeRoot(_normalizeRelativePath('', includePath));
  }

  /// 改写目标：候选落在 include 根之下时取其相对 include 根的包内路径；否则无
  /// 目标（非头文件落 `files/`/`lib/`，include 根搜不到任何改写形态）。
  String? _includeRootRelativeTarget(String candidate) =>
      _landsUnderIncludeRoot(candidate)
          ? _packageDestination(candidate, index.namespace)
          : null;

  /// 尖括号自引用：首段命中包内 include 根下的子目录（如 `<gtest/...>`）。
  bool _isAngleSelfReference(String includePath) {
    final List<String> segments = _rawSegments(includePath);
    if (segments.length < 2) {
      return false;
    }
    final String first = segments.first.toLowerCase();
    return index.includeRoots.any(
      (String root) => index.isIncludeRootChild(root.toLowerCase(), first),
    );
  }

  /// 外部依赖：多段路径且首段目录不落在包内（如 `absl/strings/...`）；
  /// 裸文件名与 `.`/`..` 开头视为包内引用风格。
  bool _isForeignQuotedReference(String includePath) {
    final List<String> segments = _rawSegments(includePath);
    if (segments.length <= 1) {
      return false;
    }
    final String first = segments.first;
    if (first == '.' || first == '..') {
      return false;
    }
    return !index.directoryNames.contains(first.toLowerCase());
  }

  bool _exists(String? normalizedRelativePath) =>
      normalizedRelativePath != null &&
      index.contains(normalizedRelativePath.toLowerCase());

  bool _existsInIncludeRoot(String? normalizedRelativePath) =>
      normalizedRelativePath != null &&
      index.includeRootPaths.contains(normalizedRelativePath.toLowerCase());
}

class _IncludeIndex {
  _IncludeIndex({required this.namespace});

  final String namespace;
  final List<String> files = <String>[];
  final Set<String> directoryNames = <String>{};
  final List<String> includeRoots = <String>[];

  /// 包内 include 根下的路径（相对该根、小写）。只收录真正落进该根的文件
  /// （头文件/模块）——`files/`、`lib/` 下的文件与 include 根同名也不可搜到。
  final Set<String> includeRootPaths = <String>{};

  final Map<String, String> _actualPathsByLowerPath = <String, String>{};
  final Map<String, List<String>> _pathsByLowerName = <String, List<String>>{};
  final Set<String> _includeRootLowerPaths = <String>{};
  final Map<String, Set<String>> _includeRootChildDirs =
      <String, Set<String>>{};

  bool contains(String lowerPath) => _actualPathsByLowerPath.containsKey(lowerPath);

  List<String> candidatesFor(String lowerBaseName) =>
      _pathsByLowerName[lowerBaseName] ?? const <String>[];

  bool isIncludeRootChild(String includeRootLowerPath, String childLowerName) =>
      _includeRootChildDirs[includeRootLowerPath]?.contains(childLowerName) ??
      false;

  void addFile(String path) {
    files.add(path);
    _actualPathsByLowerPath[path.toLowerCase()] = path;
    _pathsByLowerName
        .putIfAbsent(baseName(path).toLowerCase(), () => <String>[])
        .add(path);
    if (_landsUnderIncludeRoot(path)) {
      includeRootPaths.add(
        _packageDestination(path, namespace).toLowerCase(),
      );
    }
  }

  void addDirectory(String path, String name) {
    directoryNames.add(name.toLowerCase());
    final String lower = path.toLowerCase();
    if (name.toLowerCase() == 'include') {
      includeRoots.add(path);
      _includeRootLowerPaths.add(lower);
    }
    final String parentLower = lower.contains('/')
        ? lower.substring(0, lower.lastIndexOf('/'))
        : '';
    if (_includeRootLowerPaths.contains(parentLower)) {
      _includeRootChildDirs
          .putIfAbsent(parentLower, () => <String>{})
          .add(name.toLowerCase());
    }
  }
}

class _DecodedText {
  const _DecodedText({
    required this.text,
    required this.encoding,
    required this.hasBom,
  });

  final String text;
  final Encoding encoding;
  final bool hasBom;

  List<int> encode(String value) => <int>[
    if (hasBom) ..._utf8BomBytes,
    ...encoding.encode(value),
  ];
}

/// UTF-8（含 BOM）优先，失败回退 Latin-1 全字节保真；仅替换 ASCII include
/// 字面量，写回不改变其余字节。
_DecodedText _decodeText(List<int> bytes) {
  final bool hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final List<int> body = hasBom ? bytes.sublist(3) : bytes;
  try {
    return _DecodedText(
      text: utf8.decode(body),
      encoding: utf8,
      hasBom: hasBom,
    );
  } on FormatException {
    return _DecodedText(
      text: latin1.decode(body),
      encoding: latin1,
      hasBom: hasBom,
    );
  }
}

Future<List<int>> _readFileBytes(String path) async =>
    File(path).readAsBytes();

Future<void> _writeFileBytes(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}
