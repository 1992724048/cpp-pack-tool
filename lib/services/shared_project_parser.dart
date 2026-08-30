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

/// MSBuild 属性引用模式（如 `$(MSBuildThisFileDirectory)`）。
final RegExp _msBuildPropertyRef = RegExp(r'\$\([^)]*\)');

/// MSBuild 项元数据引用模式（如 `%(AdditionalIncludeDirectories)`）。
final RegExp _msBuildMetadataRef = RegExp(r'%\([^)]*\)');

/// 共享项目配置文件扩展名（按优先级排序：vcxitems > vcxproj > props > targets）。
const List<String> kSharedProjectExtensions = <String>[
  '.vcxitems',
  '.vcxproj',
  '.props',
  '.targets',
];

/// 解析结果：头/源 glob 与编译配置项（分号字符串已拆分为列表）。
///
/// 含 MSBuild 属性/元数据引用（`$(...)`/`%(...)`）的路径与定义会被「原样保留」，
/// 同时列入对应的 `macro*` 列表供生成器识别为「需原样输出」的值（不做路径
/// 归一化/前缀拼接）。头/源 glob 已剥离开头的 `$(MSBuildThisFileDirectory)` 前缀
/// （见 [_relativizeInclude]），得到相对共享项目目录的路径。
class SharedProjectInfo {
  const SharedProjectInfo({
    this.headerGlobs = const [],
    this.sourceGlobs = const [],
    this.additionalDependencies = const [],
    this.additionalIncludeDirectories = const [],
    this.preprocessorDefinitions = const [],
    this.macroDependencies = const [],
    this.macroIncludeDirectories = const [],
    this.macroPreprocessorDefinitions = const [],
    this.preBuildCommands = const [],
    this.postBuildCommands = const [],
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

  /// 附加依赖中含 MSBuild 引用（`$(...)`/`%(...)`）的条目（原样保留）。
  final List<String> macroDependencies;

  /// 附加包含目录中含 MSBuild 引用的条目（原样保留）。
  final List<String> macroIncludeDirectories;

  /// 预处理宏中含 MSBuild 引用的条目（原样保留）。
  final List<String> macroPreprocessorDefinitions;

  /// 编译前命令（`<PreBuildEvent><Command>`，多行按行拆分、去空、去重）。
  final List<String> preBuildCommands;

  /// 编译后命令（`<PostBuildEvent><Command>`，多行按行拆分、去空、去重）。
  final List<String> postBuildCommands;
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
    final includeDirs = <String>[];
    final includeDirsMacro = <String>[];
    final deps = <String>[];
    final depsMacro = <String>[];
    final defines = <String>[];
    final definesMacro = <String>[];
    _collectElementSemicolon(
      content,
      'AdditionalIncludeDirectories',
      includeDirs,
      includeDirsMacro,
    );
    _collectElementSemicolon(
      content,
      'AdditionalDependencies',
      deps,
      depsMacro,
    );
    _collectElementSemicolon(
      content,
      'PreprocessorDefinitions',
      defines,
      definesMacro,
    );
    return SharedProjectInfo(
      headerGlobs: _collectIncludeValues(content, 'ClInclude'),
      sourceGlobs: _collectIncludeValues(content, 'ClCompile'),
      additionalDependencies: deps,
      additionalIncludeDirectories: includeDirs,
      preprocessorDefinitions: defines,
      macroDependencies: depsMacro,
      macroIncludeDirectories: includeDirsMacro,
      macroPreprocessorDefinitions: definesMacro,
      preBuildCommands: _collectCommandLines(content, 'PreBuildEvent'),
      postBuildCommands: _collectCommandLines(content, 'PostBuildEvent'),
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

/// 合并共享项目的编译配置与命令序列到 [base]（去重追加，不覆盖既有配置）。
///
/// - 附加依赖/包含目录/预处理宏：分号字符串去重追加。
/// - 编译前/后命令：共享项目 `<PreBuildEvent>`/`<PostBuildEvent>` 的命令去重追加。
///   CompileConfig 顶层命令（打包页脚本）与消费方 targets 命令（此列表）职责
///   不同，详见 `msbuild_generator`。
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
    preBuildCommands: _mergeStringLists(
      base.preBuildCommands,
      info.preBuildCommands,
    ),
    postBuildCommands: _mergeStringLists(
      base.postBuildCommands,
      info.postBuildCommands,
    ),
  );
}

/// 提取 `<tagName Include="..." .../>` 或 `<tagName Include="...">` 的值列表。
///
/// 值中开头的 `$(MSBuildThisFileDirectory)` 宏段会被剥离（见 [_relativizeInclude]），
/// 使返回的路径相对共享项目文件所在目录。
List<String> _collectIncludeValues(String content, String tagName) {
  final open = RegExp(
    r'<\s*' + RegExp.escape(tagName) + r'\b([^>]*)>',
    caseSensitive: false,
  );
  final result = <String>[];
  for (final match in open.allMatches(content)) {
    final include = _attrValue(match.group(1)!, 'Include');
    if (include != null && include.isNotEmpty) {
      final rel = _relativizeInclude(include);
      if (rel.isNotEmpty) result.add(rel);
    }
  }
  return result;
}

/// 剥离路径开头的 `$(MSBuildThisFileDirectory)` 宏段，得到相对共享项目目录的路径。
///
/// 共享项目中使用 `$(MSBuildThisFileDirectory)` 前缀的 Include（如
/// `$(MSBuildThisFileDirectory)include\foo.h`）在 MSBuild 中解析为 vcxitems 所在
/// 目录（即用户添加的源目录）。为得到相对该目录的 srcGlob，必须剥掉宏前缀（连同
/// 其后的分隔符）；否则字面 `$(...)` 会被当作路径段拼进实际路径（如
/// `...\$(MSBuildThisFileDirectory)foo`），导致「找不到路径」错误。其它形式的宏
/// （如 `$(SolutionDir)`）相对的不是 vcxitems 目录，保留原样交由生成器原样输出。
String _relativizeInclude(String path) {
  var p = path.trim();
  if (p.isEmpty) return p;
  const prefix = r'$(MSBuildThisFileDirectory)';
  if (p.startsWith(prefix)) {
    p = p.substring(prefix.length);
  }
  while (p.startsWith('\\') || p.startsWith('/')) {
    p = p.substring(1);
  }
  return p;
}

/// 提取所有 `<tagName>...</tagName>` 元素文本并按 `;` 拆分。
///
/// 去重后的非空条目写入 [plain]；其中含 MSBuild 引用（`$(...)`/`%(...)`）的条目
/// 同时写入 [macros]，供生成器识别为「需原样输出」的值。
void _collectElementSemicolon(
  String content,
  String tagName,
  List<String> plain,
  List<String> macros,
) {
  final seen = <String>{};
  for (final text in _elementTexts(content, tagName)) {
    for (final item in text.split(';')) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(trimmed)) continue;
      plain.add(trimmed);
      if (_isMsBuildReference(trimmed)) macros.add(trimmed);
    }
  }
}

/// 提取 `<tagName><Command>...</Command></tagName>` 的命令文本，按行拆分去空去重。
///
/// 用于 `<PreBuildEvent>`/`<PostBuildEvent>` 等事件的命令序列；多行命令逐行拆分，
/// 每行 trim 后非空才保留，并按出现序去重。
List<String> _collectCommandLines(String content, String tagName) {
  final eventRe = RegExp(
    r'<\s*' +
        RegExp.escape(tagName) +
        r'\b[^>]*>(.*?)</\s*' +
        RegExp.escape(tagName) +
        r'\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  final commandRe = RegExp(
    r'<\s*Command\b[^>]*>(.*?)</\s*Command\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  final seen = <String>{};
  final result = <String>[];
  for (final event in eventRe.allMatches(content)) {
    for (final cmd in commandRe.allMatches(event.group(1)!)) {
      for (final line in cmd.group(1)!.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!seen.add(trimmed)) continue;
        result.add(trimmed);
      }
    }
  }
  return result;
}

/// 是否含 MSBuild 引用（属性引用 `$(...)` 或项元数据引用 `%(...)`）。
bool _isMsBuildReference(String value) =>
    _msBuildPropertyRef.hasMatch(value) || _msBuildMetadataRef.hasMatch(value);

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

/// 合并字符串列表：既有项（去重）+ 追加项（去重），保持原顺序。
List<String> _mergeStringLists(List<String> existing, List<String> added) {
  final seen = <String>{};
  final result = <String>[];
  for (final item in existing) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) result.add(trimmed);
  }
  for (final item in added) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) result.add(trimmed);
  }
  return result;
}
