/// 共享项目映射文件解析器：从 `.vcxitems`/`.vcxproj`/`.props`/`.targets` 提取
/// 头文件/源码 glob 与编译配置（附加依赖、包含目录、预处理宏）。
///
/// 纯 `dart:io` + 手写正则/字符串解析，**不引入第三方 XML 库**。生成的
/// [SharedProjectInfo] 供「添加源目录」流程合并进映射建议与编译配置。
///
/// 解析采用启发式：提取 `<ClInclude Include="..."/>`、`<ClCompile Include="...">`
/// 以及 `<AdditionalDependencies>`/`<AdditionalIncludeDirectories>`/
/// `<PreprocessorDefinitions>` 的元素文本；损坏/无法读取时抛 [FormatException]。
library;

import 'dart:io';

import '../models/pack_project.dart';
import 'path_utils.dart';

/// 共享项目配置文件扩展名（按优先级排序：vcxitems > vcxproj > props > targets）。
const List<String> kSharedProjectExtensions = <String>[
  '.vcxitems',
  '.vcxproj',
  '.props',
  '.targets',
];

/// 解析结果：头/源 glob 与编译配置项（分号字符串已拆分为列表）。
class SharedProjectInfo {
  const SharedProjectInfo({
    this.headerGlobs = const [],
    this.sourceGlobs = const [],
    this.additionalDependencies = const [],
    this.additionalIncludeDirectories = const [],
    this.preprocessorDefinitions = const [],
  });

  /// 头文件相对路径（`<ClInclude Include="..."/>`，相对项目文件所在目录）。
  final List<String> headerGlobs;

  /// 源码文件相对路径（`<ClCompile Include="...">`）。
  final List<String> sourceGlobs;

  /// 附加依赖（分号分隔字符串已拆分为非空列表）。
  final List<String> additionalDependencies;

  /// 附加包含目录。
  final List<String> additionalIncludeDirectories;

  /// 预处理宏。
  final List<String> preprocessorDefinitions;
}

/// 在 [sourceDir] 顶层按优先级查找共享项目配置文件（大小写不敏感）。
///
/// 按 `.vcxitems` > `.vcxproj` > `.props` > `.targets` 返回第一个存在的完整路径；
/// 目录不存在或未找到时返回 null。仅查顶层（不递归）。
String? detectSharedProjectFile(String sourceDir) {
  final dir = sourceDir.trim();
  if (dir.isEmpty) return null;
  final directory = Directory(dir);
  if (!directory.existsSync()) return null;

  List<FileSystemEntity> entries;
  try {
    entries = directory.listSync(followLinks: false);
  } on FileSystemException {
    return null;
  }
  final files = <File>[];
  for (final entry in entries) {
    if (entry is File) files.add(entry);
  }
  for (final ext in kSharedProjectExtensions) {
    for (final file in files) {
      if (basenameOf(file.path).toLowerCase().endsWith(ext)) {
        return file.path;
      }
    }
  }
  return null;
}

/// 解析共享项目文件为 [SharedProjectInfo]。
///
/// 文件不存在/为空/解析异常时抛出 [FormatException]（携带可读原因）。
SharedProjectInfo parseSharedProject(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FormatException('共享项目文件不存在：$filePath');
  }
  final content = file.readAsStringSync();
  if (content.trim().isEmpty) {
    throw FormatException('共享项目文件为空：$filePath');
  }
  try {
    return SharedProjectInfo(
      headerGlobs: _collectIncludeValues(content, 'ClInclude'),
      sourceGlobs: _collectIncludeValues(content, 'ClCompile'),
      additionalDependencies: _collectElementSemis(
        content,
        'AdditionalDependencies',
      ),
      additionalIncludeDirectories: _collectElementSemis(
        content,
        'AdditionalIncludeDirectories',
      ),
      preprocessorDefinitions: _collectElementSemis(
        content,
        'PreprocessorDefinitions',
      ),
    );
  } on Object catch (e) {
    throw FormatException('解析共享项目文件失败：$e');
  }
}

/// 由 [info] 派生文件映射（目标按现有规则：头文件 include 取相对目录、源码 src 路径）。
///
/// [sourceDirName] 为源目录名（目标簇名前缀，头文件在根目录时作为 include 路径标签）。
List<FileMapping> buildMappingsFromSharedProject(
  SharedProjectInfo info,
  String sourceDirName,
) {
  final cluster = sourceDirName.trim().isEmpty
      ? 'shared'
      : sourceDirName.trim();
  final mappings = <FileMapping>[];
  for (final header in info.headerGlobs) {
    final dir = dirnameOf(header);
    final target = dir.isEmpty ? cluster : dir;
    mappings.add(FileMapping(srcGlob: _relGlob(header), target: target));
  }
  for (final source in info.sourceGlobs) {
    final dir = dirnameOf(source);
    final target = joinPath([
      'build',
      'native',
      'src',
      cluster,
      ...(dir.isEmpty ? const <String>[] : dir.split(pathSeparator)),
    ]);
    mappings.add(FileMapping(srcGlob: _relGlob(source), target: target));
  }
  return mappings;
}

/// 合并共享项目的编译配置到 [base]（去重追加，不覆盖既有配置）。
CompileConfig mergeCompileConfigFromSharedProject(
  CompileConfig base,
  SharedProjectInfo info,
) {
  return base.copyWith(
    additionalDependencies: _mergeSemicolon(
      base.additionalDependencies,
      info.additionalDependencies,
    ),
    additionalIncludeDirectories: _mergeSemicolon(
      base.additionalIncludeDirectories,
      info.additionalIncludeDirectories,
    ),
    preprocessorDefines: _mergeSemicolon(
      base.preprocessorDefines,
      info.preprocessorDefinitions,
    ),
  );
}

/// 提取 `<tagName Include="..." .../>` 或 `<tagName Include="...">` 的值列表。
List<String> _collectIncludeValues(String content, String tagName) {
  final open = RegExp(
    r'<\s*' + RegExp.escape(tagName) + r'\b([^>]*)>',
    caseSensitive: false,
  );
  final result = <String>[];
  for (final match in open.allMatches(content)) {
    final include = _attrValue(match.group(1)!, 'Include');
    if (include != null && include.isNotEmpty) result.add(include);
  }
  return result;
}

/// 提取所有 `<tagName>...</tagName>` 元素文本并按 `;` 拆分去重。
List<String> _collectElementSemis(String content, String tagName) {
  final seen = <String>{};
  final result = <String>[];
  for (final text in _elementTexts(content, tagName)) {
    for (final item in text.split(';')) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) result.add(trimmed);
    }
  }
  return result;
}

/// 提取所有 `<tagName>...</tagName>` 的元素文本（已 trim）。
List<String> _elementTexts(String content, String tagName) {
  final re = RegExp(
    r'<\s*' +
        RegExp.escape(tagName) +
        r'\b[^>]*>(.*?)</\s*' +
        RegExp.escape(tagName) +
        r'\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  return [for (final match in re.allMatches(content)) match.group(1)!.trim()];
}

/// 从属性串中提取命名属性的引号值；缺失时返回 null。
String? _attrValue(String attrs, String name) {
  final re = RegExp(
    RegExp.escape(name) + r'\s*=\s*"([^"]*)"',
    caseSensitive: false,
  );
  final match = re.firstMatch(attrs);
  return match?.group(1);
}

/// 规范化相对 glob：统一分隔符、去掉前导 `.\`。
String _relGlob(String path) {
  var normalized = normalizeSeparators(path.trim());
  while (normalized.startsWith('.\\')) {
    normalized = normalized.substring(2);
  }
  return normalized;
}

/// 合并分号分隔字符串：既有项（去重）+ 追加项（按出现去重）。
String _mergeSemicolon(String existing, List<String> added) {
  final seen = <String>{};
  final parts = <String>[];
  for (final item in existing.split(';')) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) parts.add(trimmed);
  }
  for (final item in added) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) parts.add(trimmed);
  }
  return parts.join(';');
}
