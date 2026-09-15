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

  /// 有唯一候选但不在同一打包落点目录（跨树：如 `.cc` 引用被搬进 include
  /// 树的 `.h`），改写为裸文件名后打包层仍会失效。
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

  /// 修复后的裸文件名（取自候选文件的实际名称）。
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
    HeaderIncludeIssueKind.crossTree => '唯一候选不在同一目录：${candidates.join('、')}',
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
/// - 引号引用依次按「当前文件目录 → 包内 include 根 → 包根」解析，命中即视为正常；
/// - 未解析的引号引用若存在**唯一同名候选**（basename 大小写不敏感全包搜索）且
///   候选与引用文件**同目录**、打包落点目录一致，则改写为裸文件名——该形态在
///   staged 源目录与打包产物两层都有效；
/// - 其余未解析引用收集为待处理问题（无候选 / 多候选 / 跨树残留），
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

/// 打包落点路径（与 `nuget_builder` 同一口径：头文件/模块进 include 命名空间树，
/// 其余文件保持原相对路径）。
String _packageDestination(String path, String namespace) {
  final String normalized = path.replaceAll('\\', '/');
  final FileType type = FileModel(
    name: baseName(normalized),
    path: normalized,
  ).type;
  return switch (type) {
    FileType.header || FileType.module => includePackageRelativePath(
      normalized,
      namespace,
    ),
    _ => normalized,
  };
}

/// 单个文本文件的 include 扫描状态机（块注释跨行跟踪）。
class _FileScanner {
  _FileScanner({required this.filePath, required this.index});

  final String filePath;
  final _IncludeIndex index;
  final List<HeaderIncludeFix> fixes = <HeaderIncludeFix>[];
  final List<HeaderIncludeIssue> issues = <HeaderIncludeIssue>[];

  bool _inBlockComment = false;

  String fixLine(String line, int lineNumber) {
    final String masked = _maskBlockComments(line);
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

  /// 块注释内的字符替换为等长空格（偏移不变），供 include 匹配使用。
  String _maskBlockComments(String line) {
    final StringBuffer masked = StringBuffer();
    int index = 0;
    bool inComment = _inBlockComment;
    while (index < line.length) {
      if (inComment) {
        final int close = line.indexOf('*/', index);
        if (close < 0) {
          masked.write(' ' * (line.length - index));
          index = line.length;
        } else {
          masked.write(' ' * (close + 2 - index));
          index = close + 2;
          inComment = false;
        }
      } else {
        final int open = line.indexOf('/*', index);
        if (open < 0) {
          masked.write(line.substring(index));
          index = line.length;
        } else {
          masked
            ..write(line.substring(index, open))
            ..write('  ');
          index = open + 2;
          inComment = true;
        }
      }
    }
    _inBlockComment = inComment;
    return masked.toString();
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

    final List<String> candidates = List<String>.of(
      index.candidatesFor(baseName(includePath).toLowerCase()),
    )..sort(_comparePaths);

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

    final String candidate = candidates.single;
    if (_isSafeAutoFixTarget(candidate)) {
      final String replacement = baseName(candidate);
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

  /// 裸文件名形态在 staged 源目录与打包产物两层都成立的条件：候选与引用文件
  /// 同目录，且打包落点目录一致（头文件会被搬进 include 命名空间树）。
  bool _isSafeAutoFixTarget(String candidate) {
    if (_directoryOf(candidate).toLowerCase() !=
        _directoryOf(filePath).toLowerCase()) {
      return false;
    }
    return _directoryOf(_packageDestination(candidate, index.namespace))
            .toLowerCase() ==
        _directoryOf(_packageDestination(filePath, index.namespace))
            .toLowerCase();
  }
}

class _IncludeIndex {
  _IncludeIndex({required this.namespace});

  final String namespace;
  final List<String> files = <String>[];
  final Set<String> directoryNames = <String>{};
  final List<String> includeRoots = <String>[];

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
