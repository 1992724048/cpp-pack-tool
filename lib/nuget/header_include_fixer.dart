import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:cpp_nuget_pack/scanner/file_scan.dart';
import 'package:cpp_nuget_pack/shared/format.dart';

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

enum HeaderIncludeIssueKind { noCandidate, multipleCandidates, crossTree, missingAngle }

class HeaderIncludeFix {
  const HeaderIncludeFix({required this.filePath, required this.line, required this.from, required this.to});

  final String filePath;
  final int line;
  final String from;
  final String to;
}

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

  /// 同名候选（相对包源目录路径，同一包内落点只列一个代表；无候选时为空，多候选
  /// 时列出全部）。
  final List<String> candidates;

  String get description => switch (kind) {
    HeaderIncludeIssueKind.noCandidate => '包内未找到同名文件',
    HeaderIncludeIssueKind.multipleCandidates => '存在多个同名候选：${candidates.join('、')}',
    HeaderIncludeIssueKind.crossTree => '唯一候选无适用改写形态：${candidates.join('、')}',
    HeaderIncludeIssueKind.missingAngle => '尖括号自引用缺失（不自动修改）',
  };
}

/// include 检查与自动修复的结果。
class HeaderIncludeFixReport {
  const HeaderIncludeFixReport({this.fixed = const <HeaderIncludeFix>[], this.issues = const <HeaderIncludeIssue>[]});

  static const HeaderIncludeFixReport empty = HeaderIncludeFixReport();

  final List<HeaderIncludeFix> fixed;
  final List<HeaderIncludeIssue> issues;

  int get fixedCount => fixed.length;

  bool get hasIssues => issues.isNotEmpty;

  bool get isEmpty => fixed.isEmpty && issues.isEmpty;
}

/// 读取文件字节（绝对路径）。
typedef HeaderIncludeFileReader = Future<List<int>> Function(String absolutePath);

/// 写回文件字节（绝对路径）。
typedef HeaderIncludeFileWriter = Future<void> Function(String absolutePath, List<int> bytes);

/// include 检查/修复入口的回调形态（构建流程接线用，便于测试注入替代实现）。
typedef PackHeaderIncludeFixer = Future<HeaderIncludeFixReport> Function(
  String sourcePath, {
  required String packageName,
});

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
    final _IncludeIndex index = _IncludeIndex(namespace: includeNamespaceOf(sourcePath, packageName));
    await _collectDirectory(Directory(sourcePath), '', index);
    return index;
  }

  Future<void> _collectDirectory(Directory directory, String prefix, _IncludeIndex index) async {
    final List<FileSystemEntity> entities = await directory.list(followLinks: false).toList();
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

  ({String text, List<HeaderIncludeFix> fixes, List<HeaderIncludeIssue> issues}) _fixText(
    String text,
    String filePath,
    _IncludeIndex index,
  ) {
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
final RegExp _quotedIncludePattern = RegExp(r'^[ \t]*#[ \t]*include[ \t]*"([^"]*)"');
final RegExp _angleIncludePattern = RegExp(r'^[ \t]*#[ \t]*include[ \t]*<([^<>]*)>');

/// 单文件处理结果：修复后的文本 + 已修复清单 + 待处理问题清单。
typedef _FileFixOutcome = ({String text, List<HeaderIncludeFix> fixes, List<HeaderIncludeIssue> issues});

const List<int> _utf8BomBytes = <int>[0xEF, 0xBB, 0xBF];

bool _isTextSource(String path) {
  final String name = baseName(path);
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return false;
  }
  return headerIncludeSourceExtensions.contains(name.substring(dot + 1).toLowerCase());
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
  final List<String> stack = baseDirectory.isEmpty ? <String>[] : baseDirectory.split('/');
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

FileType _fileTypeOf(String path) {
  final String normalized = path.replaceAll('\\', '/');
  return FileModel(name: baseName(normalized), path: normalized).type;
}

bool _landsUnderIncludeRoot(String path) {
  final FileType type = _fileTypeOf(path);
  return type == FileType.header || type == FileType.module;
}

bool _landsUnderFilesRoot(String path) {
  return switch (_fileTypeOf(path)) {
    FileType.header || FileType.module || FileType.lib || FileType.dll || FileType.pdb => false,
    _ => true,
  };
}

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
      if (code == 0x5C /* \ */ ) {
        cursor += 2;
        continue;
      }
      cursor++;
      if (code == 0x22 /* " */ ) {
        break;
      }
    }
    final int end = cursor > line.length ? line.length : cursor;
    masked.write(line.substring(quote, end));
    return end;
  }

  int? _rawStringDelimiterEnd(String line, int quote) {
    if (quote < 1 || line.codeUnitAt(quote - 1) != 0x52 /* R */ ) {
      return null;
    }
    final int delimiterStart = quote + 1;
    int cursor = delimiterStart;
    while (cursor < line.length && cursor - delimiterStart <= 16) {
      final int code = line.codeUnitAt(cursor);
      if (code == 0x28 /* ( */ ) {
        return cursor;
      }
      if (code == 0x22 /* " */ || code == 0x29 /* ) */ || code == 0x5C /* \ */ || code <= 0x20) {
        return null;
      }
      cursor++;
    }
    return null;
  }

  ({int start, int end}) _captureSpan(RegExpMatch match) {
    final int end = match.end - 1;
    return (start: end - match.group(1)!.length, end: end);
  }

  String _handleQuoted(String line, RegExpMatch match, int lineNumber) {
    final String includePath = match.group(1)!;
    final ({int start, int end}) span = _captureSpan(match);
    if (includePath.trim().isEmpty || _resolvesInPackageLayout(includePath, searchOwnDirectory: true)) {
      return line;
    }

    final String lowerSelfPath = filePath.toLowerCase();
    final List<String> candidates = <String>[
      for (final String candidate in index.candidatesFor(baseName(includePath).toLowerCase()))
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

    final String candidate = candidates.single;
    final String? replacement = _includeRootRelativeTarget(candidate) ?? _siblingBareNameTarget(candidate);
    if (replacement != null) {
      fixes.add(HeaderIncludeFix(filePath: filePath, line: lineNumber, from: includePath, to: replacement));
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
    if (includePath.trim().isEmpty || _resolvesInPackageLayout(includePath, searchOwnDirectory: false)) {
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

  bool _resolvesInPackageLayout(String includePath, {required bool searchOwnDirectory}) {
    if (searchOwnDirectory) {
      final String selfLanding = _packageDestination(filePath, index.namespace);
      final String? sibling = _normalizeRelativePath(_directoryOf(selfLanding), includePath);
      if (_landsUnderIncludeRoot(filePath) && _existsInIncludeRoot(sibling)) {
        return true;
      }
      if (_landsUnderFilesRoot(filePath) && _existsInFilesRoot(sibling)) {
        return true;
      }
    }
    return _existsInIncludeRoot(_normalizeRelativePath('', includePath));
  }

  String? _includeRootRelativeTarget(String candidate) =>
      _landsUnderIncludeRoot(candidate) ? _packageDestination(candidate, index.namespace) : null;

  String? _siblingBareNameTarget(String candidate) {
    if (!_landsUnderFilesRoot(candidate) ||
        _directoryOf(candidate).toLowerCase() != _directoryOf(filePath).toLowerCase()) {
      return null;
    }
    final String candidateDir = _directoryOf(_packageDestination(candidate, index.namespace)).toLowerCase();
    final String selfDir = _directoryOf(_packageDestination(filePath, index.namespace)).toLowerCase();
    return candidateDir == selfDir ? baseName(candidate) : null;
  }

  bool _isAngleSelfReference(String includePath) {
    final List<String> segments = _rawSegments(includePath);
    if (segments.length < 2) {
      return false;
    }
    final String first = segments.first.toLowerCase();
    return index.includeRoots.any((String root) => index.isIncludeRootChild(root.toLowerCase(), first));
  }

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

  bool _existsInIncludeRoot(String? normalizedRelativePath) =>
      normalizedRelativePath != null && index.includeRootPaths.contains(normalizedRelativePath.toLowerCase());

  bool _existsInFilesRoot(String? normalizedRelativePath) =>
      normalizedRelativePath != null && index.filesRootPaths.contains(normalizedRelativePath.toLowerCase());
}

class _IncludeIndex {
  _IncludeIndex({required this.namespace});

  final String namespace;
  final List<String> files = <String>[];
  final Set<String> directoryNames = <String>{};
  final List<String> includeRoots = <String>[];

  final Set<String> includeRootPaths = <String>{};
  final Set<String> filesRootPaths = <String>{};
  final Map<String, Map<String, String>> _candidateByLanding = <String, Map<String, String>>{};
  final Set<String> _includeRootLowerPaths = <String>{};
  final Map<String, Set<String>> _includeRootChildDirs = <String, Set<String>>{};

  List<String> candidatesFor(String lowerBaseName) =>
      _candidateByLanding[lowerBaseName]?.values.toList() ?? const <String>[];

  bool isIncludeRootChild(String includeRootLowerPath, String childLowerName) =>
      _includeRootChildDirs[includeRootLowerPath]?.contains(childLowerName) ?? false;

  void addFile(String path) {
    files.add(path);
    final Map<String, String> byLanding = _candidateByLanding.putIfAbsent(
      baseName(path).toLowerCase(),
      () => <String, String>{},
    );
    final String destination = _packageDestination(path, namespace);
    final String landing = destination.toLowerCase();
    final String? representative = byLanding[landing];
    if (representative == null || _comparePaths(path, representative) < 0) {
      byLanding[landing] = path;
    }
    if (_landsUnderIncludeRoot(path)) {
      includeRootPaths.add(landing);
    } else if (_landsUnderFilesRoot(path)) {
      filesRootPaths.add(path.toLowerCase());
    }
  }

  void addDirectory(String path, String name) {
    directoryNames.add(name.toLowerCase());
    final String lower = path.toLowerCase();
    if (name.toLowerCase() == 'include') {
      includeRoots.add(path);
      _includeRootLowerPaths.add(lower);
    }
    final String parentLower = lower.contains('/') ? lower.substring(0, lower.lastIndexOf('/')) : '';
    if (_includeRootLowerPaths.contains(parentLower)) {
      _includeRootChildDirs.putIfAbsent(parentLower, () => <String>{}).add(name.toLowerCase());
    }
  }
}

class _DecodedText {
  const _DecodedText({required this.text, required this.encoding, required this.hasBom});

  final String text;
  final Encoding encoding;
  final bool hasBom;

  List<int> encode(String value) => <int>[if (hasBom) ..._utf8BomBytes, ...encoding.encode(value)];
}

_DecodedText _decodeText(List<int> bytes) {
  final bool hasBom = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
  final List<int> body = hasBom ? bytes.sublist(3) : bytes;
  try {
    return _DecodedText(text: utf8.decode(body), encoding: utf8, hasBom: hasBom);
  } on FormatException {
    return _DecodedText(text: latin1.decode(body), encoding: latin1, hasBom: hasBom);
  }
}

Future<List<int>> _readFileBytes(String path) async => File(path).readAsBytes();

Future<void> _writeFileBytes(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}
