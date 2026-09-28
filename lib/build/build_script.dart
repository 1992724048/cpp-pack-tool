import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/version_range.dart';

const String _buildScriptName = 'build.py';
const String _toolDirectivePrefix = '# tool:';
const String _optionDirectivePrefix = '# option:';
const String _checkboxDirectivePrefix = '# checkbox:';
const String _multiSelectDirectivePrefix = '# multiselect:';
const String _sourceDirectivePrefix = '# source:';
const String _dependsDirectivePrefix = '# depends:';
const String _runtimeDirectivePrefix = '# runtime:';

/// `# profile:` 指令前缀（头部连续注释段内的构建管线 Profile 声明）。
const String profileDirectivePrefix = '# profile:';

/// 当前受支持的构建管线 Profile 版本。
const String supportedBuildProfile = 'v1';

/// 运行库选项在 `PackModel.buildOptions` 中的保留键。
///
/// 键不存在 = 跟随配方默认（`# runtime:` 或 `md`）；值域 `MD` / `MT`（保存口径），
/// 解析时大小写不敏感。该名称为保留名：build.py 以 `# option` / `# checkbox` /
/// `# multiselect` 声明同名选项（大小写 / 空白不敏感）时整行忽略，防止
/// `CNP_OPTION_RUNTIME` 与 [runtimeLibraryEnvName] 取值矛盾。
const String runtimeOptionName = 'runtime';

/// 旧子进程运行库环境变量名（Profile 接管后不再下发）。
///
/// 仅作只读清理标识：装配子进程环境时按大小写不敏感移除父环境残留
/// （见 `legacyNoIpoEnvName` 同批处理），待计划 C 移除最后的 UI 引用后再删。
const String runtimeLibraryEnvName = 'CNP_RUNTIME_LIBRARY';

final RegExp _toolNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');
final RegExp _optionNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final RegExp _driveLetterPattern = RegExp(r'^[A-Za-z]:');
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _pathSeparatorPattern = RegExp(r'[/\\]');
final RegExp _envNameForbiddenPattern = RegExp(r'[^A-Z0-9_]');

/// 是否为根级 `build.py`：不含任何路径分隔符且文件名大小写不敏感。
bool isBuildScriptPath(String relativePath) {
  if (relativePath.contains('/') || relativePath.contains('\\')) {
    return false;
  }
  return relativePath.toLowerCase() == _buildScriptName;
}

/// 根级 `build.py` 的字典序首个候选；无候选返回 null。
FileModel? findBuildScript(List<FileModel> files) {
  final List<FileModel> candidates =
      files.where((FileModel file) => isBuildScriptPath(file.path)).toList()
        ..sort(
          (FileModel first, FileModel second) =>
              first.path.compareTo(second.path),
        );
  return candidates.isEmpty ? null : candidates.first;
}

/// `# tool:` 声明的环境工具。
class BuildScriptTool {
  const BuildScriptTool({
    required this.name,
    required this.url,
    this.binSubdir,
  });

  final String name;
  final String url;

  /// 追加到 PATH 的相对子目录（如 `perl/bin`）。
  final String? binSubdir;
}

/// 构建选项控件类型：`# option` 下拉 / `# checkbox` 复选 / `# multiselect` 多选。
enum BuildOptionControl { dropdown, checkbox, multiselect }

/// `# option:` / `# checkbox:` / `# multiselect:` 声明的构建选项。
class BuildScriptOption {
  const BuildScriptOption({
    required this.name,
    required this.values,
    this.control = BuildOptionControl.dropdown,
  });

  final String name;

  /// 候选值：下拉为可选值列表（首值为默认）；复选框为「勾选态值 | 未勾选态值」
  /// （首值为勾选态也是默认）；多选为声明序即保存序的候选值列表。
  final List<String> values;

  /// 控件类型，缺省下拉（`# option:`，向后兼容）。
  final BuildOptionControl control;

  String get defaultValue => values.first;
}

/// `# depends:` 声明的包依赖。
class BuildScriptDependency {
  const BuildScriptDependency({required this.name, this.version});

  final String name;

  /// 声明的 NuGet 版本范围；null 表示未声明，由打包侧按本地包版本推断。
  final String? version;
}

/// build.py 头部解析结果。
class BuildScriptHeader {
  const BuildScriptHeader({
    this.sourceDir,
    this.tools = const <BuildScriptTool>[],
    this.options = const <BuildScriptOption>[],
    this.dependencies = const <BuildScriptDependency>[],
    this.runtime,
    this.profileVersion,
  });

  /// 首行 `# source:` 声明的包源目录下相对目录（如 `.cnp-src`）；声明
  /// `# source: none` 时为 null。路径合法性由 [requireValidSourceDirective]
  /// 判定，解析期原样保留声明值以便报错文案引用用户写法。
  final String? sourceDir;

  /// 无预置源码（`# source: none`）：`SRC_PATH` 仅作为脚本自行下载/解压的
  /// 工作区，跨构建保留。
  bool get sourceNone => sourceDir == null;

  final List<BuildScriptTool> tools;
  final List<BuildScriptOption> options;
  final List<BuildScriptDependency> dependencies;

  /// `# runtime:` 声明的默认运行库家族（`md` / `mt`，小写规范化）；未声明为 null。
  final String? runtime;

  /// `# profile:` 声明的构建管线 Profile 版本（原始书写形式，允许两侧空白与
  /// 大小写差异，由 [requireSupportedBuildProfile] 归一比较）；未声明为 null。
  final String? profileVersion;
}

/// 解析 build.py 头部：首行源码来源声明 + 其后连续 `#` 行中的
/// `# tool:` / `# option:` / `# checkbox:` / `# multiselect:` /
/// `# runtime:` / `# profile:` / `# depends:` 指令。
///
/// 首行必须命中源码来源声明锚点（[_sourceDirectivePrefix]，即严格锚点），
/// 否则返回 null；第 2 行起的非法或未知指令行按注释忽略，选项名称为保留名
/// （`runtime`，见 [runtimeOptionName]）的选项声明同样忽略；同名声明以首次为准；
/// 遇到首个非 `#` 行（含空行）即终止头部连续段。
BuildScriptHeader? parseBuildScriptHeader(String content) {
  final List<String> lines = content.split('\n');
  final ({String? sourceDir, bool anchored}) firstLine = _parseSourceDirLine(
    lines.first,
  );
  if (!firstLine.anchored) {
    return null;
  }
  final List<BuildScriptTool> tools = <BuildScriptTool>[];
  final List<BuildScriptOption> options = <BuildScriptOption>[];
  final List<BuildScriptDependency> dependencies = <BuildScriptDependency>[];
  final Set<String> toolNames = <String>{};
  final Set<String> optionNames = <String>{};
  final Set<String> dependencyNames = <String>{};
  String? runtime;
  String? profileVersion;
  for (final String rawLine in lines.skip(1)) {
    final String line = rawLine.trim();
    if (!line.startsWith('#')) {
      break;
    }
    if (line.startsWith(_runtimeDirectivePrefix)) {
      runtime ??= normalizeRuntimeLibrary(
        line.substring(_runtimeDirectivePrefix.length),
      );
      continue;
    }
    if (line.startsWith(profileDirectivePrefix)) {
      profileVersion ??= profileVersionFromLine(line);
      continue;
    }
    final BuildScriptTool? tool = _parseToolLine(line);
    if (tool != null) {
      if (toolNames.add(tool.name)) {
        tools.add(tool);
      }
      continue;
    }
    final BuildScriptOption? option =
        _parseOptionLine(line) ??
        _parseCheckboxLine(line) ??
        _parseMultiSelectLine(line);
    if (option != null && optionNames.add(option.name)) {
      options.add(option);
    }
    final BuildScriptDependency? dependency = _parseDependsLine(line);
    if (dependency != null &&
        dependencyNames.add(dependency.name.toLowerCase())) {
      dependencies.add(dependency);
    }
  }
  return BuildScriptHeader(
    sourceDir: firstLine.sourceDir,
    tools: tools,
    options: options,
    dependencies: dependencies,
    runtime: runtime,
    profileVersion: profileVersion,
  );
}

/// 提取 `# profile:` 指令行的版本值：前缀之后的内容去两侧空白。
///
/// 行不含 [profileDirectivePrefix] 时返回 null；值为空串时由
/// [requireSupportedBuildProfile] 按缺失声明处理。
String? profileVersionFromLine(String line) {
  final String trimmed = line.trim();
  if (!trimmed.startsWith(profileDirectivePrefix)) {
    return null;
  }
  return trimmed.substring(profileDirectivePrefix.length).trim();
}

/// 校验 [header] 声明的 Profile 版本；缺失（未声明或值为空）或不是
/// [supportedBuildProfile] 时抛出 `FormatException`。
///
/// 调用方在任何副作用之前调用（源码准备：`onStage(downloading)`/缓存目录/git/
/// 源目录清理之前；构建环境准备：编译器检测与工具供给之前），并把异常映射为
/// 各自的用户可见异常类型；消息含脚本路径与期望的 `# profile: v1` 字面量。
void requireSupportedBuildProfile(BuildScriptHeader header, String scriptPath) {
  final String version = (header.profileVersion ?? '').trim();
  if (version.isEmpty) {
    throw FormatException(
      'build.py 缺少 Profile 声明：$scriptPath 需要在头部连续注释段包含 '
      '"$profileDirectivePrefix $supportedBuildProfile"',
    );
  }
  if (version.toLowerCase() != supportedBuildProfile) {
    throw FormatException(
      'build.py Profile 版本 "$version" 不受支持：$scriptPath 仅支持 '
      '$supportedBuildProfile（需写 "$profileDirectivePrefix $supportedBuildProfile"）',
    );
  }
}

/// 校验 [header] 的源码来源声明；`# source: none`（[BuildScriptHeader.sourceDir]
/// 为 null）直接通过，声明了目录但值非法（空串、绝对路径、含盘符、含 `..`）
/// 时抛出 `FormatException`。
///
/// 路径判据复用 `_isRelativeSubdir`（与 `# tool` 的 `bin=` 同一口径），调用方在
/// 任何副作用之前调用（与 [requireSupportedBuildProfile] 同一 try 块）并把异常
/// 映射为用户可见异常类型。
void requireValidSourceDirective(BuildScriptHeader header, String scriptPath) {
  final String? sourceDir = header.sourceDir;
  if (sourceDir == null) {
    return;
  }
  if (!_isRelativeSubdir(sourceDir)) {
    throw FormatException(
      'build.py 源码目录声明非法：$scriptPath 的 "$_sourceDirectivePrefix '
      '$sourceDir" 必须是包源目录下的相对路径（不得含盘符 或 ..）',
    );
  }
}

/// 首行「缺少源码声明」的用户可见文案（单一事实来源，供构建入口复用）。
String buildScriptSourceDeclarationMissingMessage(String scriptPath) =>
    'build.py 首行缺少源码声明：$scriptPath 需要 '
    '"$_sourceDirectivePrefix <包内相对目录>"，'
    '仅提供预构建归档的配方写 "$_sourceDirectivePrefix none"';

/// 解析 build.py 首行的源码来源声明（严格锚点 [_sourceDirectivePrefix]）。
///
/// [anchored] 为 false 表示首行 trim 后不以该前缀开头，调用方据此让整个头部
/// 解析返回 null（fail-closed，不做旧写法兼容）；命中前缀时把剩余值 trim 后
/// 原样存入 [sourceDir]（路径合法性留给 [requireValidSourceDirective]），
/// 值为 `none`（大小写不敏感）时 [sourceDir] 为 null。
({String? sourceDir, bool anchored}) _parseSourceDirLine(String rawLine) {
  final String line = rawLine.trim();
  if (!line.startsWith(_sourceDirectivePrefix)) {
    return (sourceDir: null, anchored: false);
  }
  final String value = line.substring(_sourceDirectivePrefix.length).trim();
  return (
    sourceDir: value.toLowerCase() == 'none' ? null : value,
    anchored: true,
  );
}

BuildScriptTool? _parseToolLine(String line) {
  if (!line.startsWith(_toolDirectivePrefix)) {
    return null;
  }
  final String rest = line.substring(_toolDirectivePrefix.length).trim();
  if (rest.isEmpty) {
    return null;
  }
  final List<String> tokens = rest.split(_whitespacePattern);
  if (tokens.length < 2 || tokens.length > 3) {
    return null;
  }
  final String name = tokens[0];
  final String url = tokens[1];
  if (!_toolNamePattern.hasMatch(name) || !_isHttpUrl(url)) {
    return null;
  }
  String? binSubdir;
  if (tokens.length == 3) {
    final String binToken = tokens[2];
    if (!binToken.startsWith('bin=')) {
      return null;
    }
    binSubdir = binToken.substring('bin='.length);
    if (!_isRelativeSubdir(binSubdir)) {
      return null;
    }
  }
  return BuildScriptTool(name: name, url: url, binSubdir: binSubdir);
}

bool _isHttpUrl(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) {
    return false;
  }
  final String scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
}

bool _isRelativeSubdir(String subdir) {
  if (subdir.isEmpty || subdir.startsWith('/') || subdir.startsWith('\\')) {
    return false;
  }
  if (_driveLetterPattern.hasMatch(subdir)) {
    return false;
  }
  return !subdir.split(_pathSeparatorPattern).contains('..');
}

BuildScriptOption? _parseOptionLine(String line) {
  if (!line.startsWith(_optionDirectivePrefix)) {
    return null;
  }
  return _parseValuedOption(
    line.substring(_optionDirectivePrefix.length),
    BuildOptionControl.dropdown,
    minValues: 1,
  );
}

BuildScriptOption? _parseCheckboxLine(String line) {
  if (!line.startsWith(_checkboxDirectivePrefix)) {
    return null;
  }
  return _parseValuedOption(
    line.substring(_checkboxDirectivePrefix.length),
    BuildOptionControl.checkbox,
    minValues: 2,
    maxValues: 2,
  );
}

BuildScriptOption? _parseMultiSelectLine(String line) {
  if (!line.startsWith(_multiSelectDirectivePrefix)) {
    return null;
  }
  final BuildScriptOption? option = _parseValuedOption(
    line.substring(_multiSelectDirectivePrefix.length),
    BuildOptionControl.multiselect,
    minValues: 1,
  );
  if (option == null ||
      option.values.any((String value) => value.contains(';'))) {
    return null;
  }
  return option;
}

/// 解析 `<名称> = <值> | <值> …` 形式：名称须匹配选项名正则且非保留名
/// （`runtime`，见 [runtimeOptionName]），值去空白后不得为空、不得重复，
/// 数量须落在 [minValues]/[maxValues] 范围内。
BuildScriptOption? _parseValuedOption(
  String rest,
  BuildOptionControl control, {
  required int minValues,
  int? maxValues,
}) {
  final int equalsIndex = rest.indexOf('=');
  if (equalsIndex < 0) {
    return null;
  }
  final String name = rest.substring(0, equalsIndex).trim();
  if (!_optionNamePattern.hasMatch(name)) {
    return null;
  }
  if (_isReservedOptionName(name)) {
    return null;
  }
  final List<String> values = <String>[
    for (final String part in rest.substring(equalsIndex + 1).split('|'))
      part.trim(),
  ];
  if (values.length < minValues ||
      (maxValues != null && values.length > maxValues)) {
    return null;
  }
  if (values.any((String value) => value.isEmpty)) {
    return null;
  }
  if (values.toSet().length != values.length) {
    return null;
  }
  return BuildScriptOption(name: name, values: values, control: control);
}

/// 选项名是否为保留名（[runtimeOptionName]，大小写 / 空白不敏感）：
/// 保留名声明按非法行忽略，不报错。
bool _isReservedOptionName(String name) =>
    name.trim().toLowerCase() == runtimeOptionName;

/// 解析 `# depends: <包名> [<版本范围>]`：包名为单个非空白 token，
/// 版本范围可选且必须通过 [isValidVersionRange]；非法行返回 null（整行忽略）。
BuildScriptDependency? _parseDependsLine(String line) {
  if (!line.startsWith(_dependsDirectivePrefix)) {
    return null;
  }
  final String rest = line.substring(_dependsDirectivePrefix.length).trim();
  if (rest.isEmpty) {
    return null;
  }
  final List<String> tokens = rest.split(_whitespacePattern);
  if (tokens.length > 2) {
    return null;
  }
  if (tokens.length == 2) {
    if (!isValidVersionRange(tokens[1])) {
      return null;
    }
    return BuildScriptDependency(name: tokens[0], version: tokens[1]);
  }
  return BuildScriptDependency(name: tokens[0]);
}

/// 运行库家族声明值规范化：接受 `md` / `mt`（大小写不敏感、允许两侧空白），
/// 其余值（含 null/空串）返回 null。
String? normalizeRuntimeLibrary(String? value) {
  final String normalized = (value ?? '').trim().toLowerCase();
  if (normalized == 'md' || normalized == 'mt') {
    return normalized;
  }
  return null;
}

/// 依据声明集合解析最终选项值：合法保存值优先，非法或缺失取默认值，未声明键剔除。
///
/// 多选项归一化为声明序 `;` 连接（可全不选的空串）。
Map<String, String> resolveBuildOptions(
  List<BuildScriptOption> options,
  Map<String, String> savedValues,
) {
  return <String, String>{
    for (final BuildScriptOption option in options)
      option.name: effectiveBuildOptionValue(option, savedValues),
  };
}

/// 单个选项的生效值（UI 显示与构建下发共用同一口径）：
///
/// - 下拉 / 复选框：合法保存值优先（含默认值），非法或缺失取 [BuildScriptOption.defaultValue]；
/// - 多选：保存值按 `;` 拆分、去空并与声明值求交，按声明序重新连接（可空串）。
String effectiveBuildOptionValue(
  BuildScriptOption option,
  Map<String, String> savedValues,
) {
  final String? saved = savedValues[option.name];
  switch (option.control) {
    case BuildOptionControl.dropdown:
    case BuildOptionControl.checkbox:
      return saved != null && option.values.contains(saved)
          ? saved
          : option.defaultValue;
    case BuildOptionControl.multiselect:
      return normalizedMultiSelectValue(option.values, saved);
  }
}

/// 多选选项的已选值集合：按 `;` 拆分保存值、去空并与声明值精确求交。
Set<String> multiSelectSelection(List<String> values, String? saved) {
  if (saved == null || saved.isEmpty) {
    return const <String>{};
  }
  final Set<String> present = <String>{
    for (final String part in saved.split(';'))
      if (part.trim().isNotEmpty) part.trim(),
  };
  return <String>{
    for (final String value in values)
      if (present.contains(value)) value,
  };
}

/// 多选选项的归一化保存值：已选值按声明序以 `;` 连接（全不选为空串）。
String normalizedMultiSelectValue(List<String> values, String? saved) {
  final Set<String> selected = multiSelectSelection(values, saved);
  return values.where(selected.contains).join(';');
}

/// 选项名的子进程环境变量名（`tbb` → `CNP_OPTION_TBB`）。
String optionEnvName(String optionName) {
  final String upper = optionName.toUpperCase();
  return 'CNP_OPTION_${upper.replaceAll(_envNameForbiddenPattern, '_')}';
}

/// 读取包内根级 build.py 并解析头部。
///
/// 无根级脚本或包无源目录时返回 null；读取失败抛出原始 IO 异常（由调用方包装）。
Future<BuildScriptHeader?> loadBuildScriptHeader(
  PackModel pack, {
  Future<String> Function(String path)? readFile,
}) async {
  final FileModel? script = findBuildScript(pack.files);
  final String? sourcePath = pack.sourcePath;
  if (script == null || sourcePath == null || sourcePath.isEmpty) {
    return null;
  }
  final Future<String> Function(String path) reader =
      readFile ?? _readFileAsString;
  final String content = await reader(joinPath(sourcePath, script.path));
  return parseBuildScriptHeader(content);
}

Future<String> _readFileAsString(String path) => File(path).readAsString();
