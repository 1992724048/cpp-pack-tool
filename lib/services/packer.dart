/// 打包执行服务：定位 `nuget.exe` 并调用 `nuget pack` 生成 `.nupkg`。
///
/// - [findNuGetExe]：按「显式路径 > PATH > 常见安装位置」优先级定位。
/// - [pack]：执行 `nuget pack`，返回 [PackResult]（含 stdout/stderr/exitCode）。
/// - [buildPackArgs]：构造 `nuget pack` 命令行参数（便于单测，不真正打包）。
///
/// `resolveNuGetExe` 为可注入探测器（NuGetProbe）的纯决策逻辑，便于单测
/// 而无需真实运行 `where` 或访问文件系统。
library;

import 'dart:io';

import 'path_utils.dart';

/// 探测环境抽象：把文件系统/命令访问封装为可注入的回调，避免单测真实 IO。
class NuGetProbe {
  NuGetProbe({
    required this.fileExists,
    required this.whichOnPath,
    required this.searchNugetIn,
    required this.typicalRoots,
  });

  /// 判断指定路径是否已存在。
  final bool Function(String path) fileExists;

  /// 在 PATH 中查找 `nuget.exe`，返回其路径；找不到返回 null。
  final String? Function() whichOnPath;

  /// 在候选根目录列表中递归搜索 `nuget.exe`，返回首个；找不到返回 null。
  final String? Function(List<String> roots) searchNugetIn;

  /// 常见安装位置根目录。
  final List<String> typicalRoots;
}

/// 纯决策逻辑：按优先级解析出 `nuget.exe` 路径；找不到返回 null。
///
/// 优先级：显式路径（存在者）→ PATH → 常见安装位置。
String? resolveNuGetExe({
  required List<String> explicitCandidates,
  required NuGetProbe probe,
}) {
  for (final candidate in explicitCandidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) continue;
    if (probe.fileExists(trimmed)) {
      return Directory(trimmed).absolute.path;
    }
  }

  final onPath = probe.whichOnPath();
  if (onPath != null) return onPath;

  if (probe.typicalRoots.isNotEmpty) {
    return probe.searchNugetIn(probe.typicalRoots);
  }
  return null;
}

/// 定位 `nuget.exe`。
///
/// [candidatesFromSettings] 为设置中保存的显式候选路径（按优先级排列）。
String? findNuGetExe(List<String> candidatesFromSettings) {
  final probe = NuGetProbe(
    fileExists: (path) => File(path).existsSync(),
    whichOnPath: _whichNugetOnPath,
    searchNugetIn: _searchNugetInDirs,
    typicalRoots: _typicalNugetRoots(),
  );
  return resolveNuGetExe(
    explicitCandidates: candidatesFromSettings,
    probe: probe,
  );
}

/// 构造 `nuget pack` 命令行参数。
List<String> buildPackArgs({
  required String nuspecPath,
  required String outputDir,
}) {
  return ['pack', nuspecPath, '-OutputDirectory', outputDir, '-NonInteractive'];
}

/// 执行打包：调用 `nuget.exe pack`，工作目录切换为 nuspec 所在目录，
/// 以保证 nuspec 中的相对 `src` 路径解析正确。
Future<PackResult> pack({
  required String nuspecPath,
  required String outputDir,
  required String nugetExe,
}) async {
  try {
    Directory(outputDir).createSync(recursive: true);
  } on FileSystemException catch (e) {
    return PackResult.failure('无法创建输出目录 "$outputDir": ${e.message}');
  }

  final workingDir = dirnameOf(nuspecPath);
  final args = buildPackArgs(nuspecPath: nuspecPath, outputDir: outputDir);

  ProcessResult result;
  try {
    result = await Process.run(
      nugetExe,
      args,
      workingDirectory: workingDir.isEmpty ? null : workingDir,
    );
  } on ProcessException catch (e) {
    return PackResult.failure('无法启动 nuget.exe "$nugetExe": ${e.message}');
  }

  final stdoutText = _asText(result.stdout);
  final stderrText = _asText(result.stderr);
  final exitCode = result.exitCode;

  if (exitCode != 0) {
    return PackResult.failure(
      'nuget pack 退出码 $exitCode${stderrText.isEmpty ? '' : ':\n$stderrText'}',
    );
  }

  return PackResult.success(
    message: stdoutText,
    outputPath: parseNupkgOutputPath(stdoutText),
  );
}

/// 从 `nuget pack` 的 stdout 解析生成的 `.nupkg` 完整路径；无法解析返回 null。
String? parseNupkgOutputPath(String stdout) {
  final lines = stdout.split('\n');
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // NuGet 输出形如：Successfully created package 'C:\...\Foo.1.0.0.nupkg'.
    final quoted = RegExp(r"'([^']+\.nupkg)'").firstMatch(trimmed);
    if (quoted != null) return quoted.group(1);
    final bare = RegExp(r'([A-Za-z]:[^\r\n]*?\.nupkg)').firstMatch(trimmed);
    if (bare != null) return bare.group(1);
  }
  return null;
}

/// 在 PATH 环境变量目录中探测 `nuget.exe`。
String? _whichNugetOnPath() {
  final pathEnv = Platform.environment['PATH'] ?? '';
  final dirs = pathEnv
      .split(';')
      .map((d) => d.trim())
      .where((d) => d.isNotEmpty);
  for (final dir in dirs) {
    for (final name in const ['nuget.exe', 'nuget']) {
      final candidate = File(joinPath([dir, name]));
      if (candidate.existsSync()) {
        return candidate.absolute.path;
      }
    }
  }
  return null;
}

/// 常见安装位置根目录。
List<String> _typicalNugetRoots() {
  final env = Platform.environment;
  final roots = <String>[];
  void addFrom(String base, List<String> sub) {
    if (base.isEmpty) return;
    roots.add(joinPath([base, ...sub]));
  }

  addFrom(env['LOCALAPPDATA'] ?? '', ['Microsoft', 'WinGet', 'Packages']);
  addFrom(env['USERPROFILE'] ?? '', ['.dotnet', 'tools']);
  addFrom(env['ProgramFiles'] ?? '', ['NuGet']);
  addFrom(env['USERPROFILE'] ?? '', [
    '.nuget',
    'packages',
    'nuget.commandline',
  ]);
  return roots;
}

/// 在候选根目录中递归搜索 `nuget.exe`。
String? _searchNugetInDirs(List<String> roots) {
  for (final root in roots) {
    if (!Directory(root).existsSync()) continue;
    final found = _findNugetExeRecursive(root);
    if (found != null) return found;
  }
  return null;
}

/// 迭代式 DFS 搜索 `nuget.exe`（避免深递归栈溢出）。
String? _findNugetExeRecursive(String root) {
  final found = <String>[];
  final stack = <String>[root];
  final visited = <String>{};
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final canonical = _canonicalPath(dir);
    if (!visited.add(canonical)) continue;

    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }

    for (final entry in entries) {
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        stack.add(entry.path);
      } else if (basenameOf(entry.path).toLowerCase() == 'nuget.exe') {
        found.add(entry.path);
      }
    }
  }

  if (found.isEmpty) return null;
  // 参考实现按 FullName 降序取首个（winget 版本目录通常路径更长/更深）。
  found.sort((a, b) => b.compareTo(a));
  return found.first;
}

/// 解析规范（含符号链接）路径；失败时回退原路径。
String _canonicalPath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return path;
  }
}

/// 将进程输出统一为字符串。
String _asText(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

/// 打包结果。
class PackResult {
  const PackResult({
    required this.success,
    required this.message,
    this.outputPath,
  });

  /// 是否成功。
  final bool success;

  /// 若成功为 stdout 文本；若失败为「退出码 + stderr」的说明。
  final String message;

  /// 生成的 `.nupkg` 完整路径（成功时可为 null，表示 stdout 未能解析路径）。
  final String? outputPath;

  factory PackResult.failure(String message) =>
      PackResult(success: false, message: message);

  factory PackResult.success({required String message, String? outputPath}) =>
      PackResult(success: true, message: message, outputPath: outputPath);
}
