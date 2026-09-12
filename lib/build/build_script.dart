import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

const String _buildScriptName = 'build.py';
const String _toolDirectivePrefix = '# tool:';
const String _optionDirectivePrefix = '# option:';

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

/// `# option:` 声明的构建选项。
class BuildScriptOption {
  const BuildScriptOption({required this.name, required this.values});

  final String name;

  /// 候选值，首值为默认值。
  final List<String> values;

  String get defaultValue => values.first;
}

/// build.py 头部解析结果。
class BuildScriptHeader {
  const BuildScriptHeader({
    required this.repo,
    this.tools = const <BuildScriptTool>[],
    this.options = const <BuildScriptOption>[],
  });

  final String repo;
  final List<BuildScriptTool> tools;
  final List<BuildScriptOption> options;
}

/// 解析 build.py 头部：首行仓库地址 + 其后连续 `#` 行中的 `# tool:` / `# option:` 指令。
///
/// 首行不合法返回 null；非法或未知指令行按注释忽略，同名声明以首次为准；
/// 遇到首个非 `#` 行（含空行）即终止头部连续段。
BuildScriptHeader? parseBuildScriptHeader(String content) {
  final List<String> lines = content.split('\n');
  final String? repository = _parseRepoLine(lines.first);
  if (repository == null) {
    return null;
  }
  final List<BuildScriptTool> tools = <BuildScriptTool>[];
  final List<BuildScriptOption> options = <BuildScriptOption>[];
  final Set<String> toolNames = <String>{};
  final Set<String> optionNames = <String>{};
  for (final String rawLine in lines.skip(1)) {
    final String line = rawLine.trim();
    if (!line.startsWith('#')) {
      break;
    }
    final BuildScriptTool? tool = _parseToolLine(line);
    if (tool != null) {
      if (toolNames.add(tool.name)) {
        tools.add(tool);
      }
      continue;
    }
    final BuildScriptOption? option = _parseOptionLine(line);
    if (option != null && optionNames.add(option.name)) {
      options.add(option);
    }
  }
  return BuildScriptHeader(repo: repository, tools: tools, options: options);
}

String? _parseRepoLine(String rawLine) {
  final String line = rawLine.trim();
  if (!line.startsWith('#')) {
    return null;
  }
  final String repository = line.substring(1).trim();
  return repository.isEmpty ? null : repository;
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
  final String rest = line.substring(_optionDirectivePrefix.length).trim();
  final int equalsIndex = rest.indexOf('=');
  if (equalsIndex < 0) {
    return null;
  }
  final String name = rest.substring(0, equalsIndex).trim();
  if (!_optionNamePattern.hasMatch(name)) {
    return null;
  }
  final List<String> values = <String>[
    for (final String part in rest.substring(equalsIndex + 1).split('|'))
      part.trim(),
  ];
  if (values.any((String value) => value.isEmpty)) {
    return null;
  }
  if (values.toSet().length != values.length) {
    return null;
  }
  return BuildScriptOption(name: name, values: values);
}

/// 解析 build.py 首行的 git 仓库地址（`# <仓库地址>`）。
///
/// 首行 trim 后必须以 `#` 开头且 `#` 之后仍有非空内容，否则返回 null。
String? parseBuildScriptRepo(String content) =>
    parseBuildScriptHeader(content)?.repo;

/// 依据声明集合解析最终选项值：合法保存值优先，非法或缺失取默认值，未声明键剔除。
Map<String, String> resolveBuildOptions(
  List<BuildScriptOption> options,
  Map<String, String> savedValues,
) {
  return <String, String>{
    for (final BuildScriptOption option in options)
      option.name: option.values.contains(savedValues[option.name])
          ? savedValues[option.name]!
          : option.defaultValue,
  };
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
