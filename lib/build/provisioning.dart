import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 工具包下载器：返回 zip 字节，失败时抛异常。
typedef ToolFetcher = Future<Uint8List> Function(Uri uri);

/// CMake 官方便携版下载地址（Kitware/CMake release，2026-09-13 核验可达）。
const String cmakeDownloadUrl =
    'https://github.com/Kitware/CMake/releases/download/v4.4.3/cmake-4.4.3-windows-x86_64.zip';

/// Ninja 官方 Windows 版下载地址（ninja-build/ninja release，2026-09-13 核验可达）。
const String ninjaDownloadUrl =
    'https://github.com/ninja-build/ninja/releases/download/v1.13.1/ninja-win.zip';

const String _minimumCmakeVersion = '3.25.0';
const int _defaultReplaceAttempts = 3;
const Duration _defaultReplaceRetryDelay = Duration(milliseconds: 250);
const String _markerFileName = '.source';
const String _tempDirectoryName = '.tmp';
const String _binDirectoryName = 'bin';
final RegExp _invalidNamePattern = RegExp(r'[^A-Za-z0-9._-]');
final RegExp _alphanumericPattern = RegExp(r'[A-Za-z0-9]');
final RegExp _cmakeVersionPattern = RegExp(r'cmake version (\d+\.\d+\.\d+)');

/// 已供给到 `tools/` 的工具。
class ProvisionedTool {
  const ProvisionedTool({
    required this.name,
    required this.directory,
    required this.pathEntries,
  });

  /// 工具名（已按目录安全规则清洗）。
  final String name;

  /// 工具目录（`tools/<name>`）。
  final String directory;

  /// 应加入 PATH 的目录：工具目录本身、存在的 `bin/` 与声明的子目录。
  final List<String> pathEntries;
}

/// CMake/Ninja 供给结果。
class CmakeNinja {
  const CmakeNinja({
    required this.cmakeExecutable,
    required this.ninjaExecutable,
    required this.pathEntries,
  });

  /// cmake 可执行文件路径；本地在 PATH 时为命令名 `cmake`。
  final String cmakeExecutable;

  /// ninja 可执行文件路径；本地在 PATH 时为命令名 `ninja`。
  final String ninjaExecutable;

  /// 需补充进 PATH 的目录；全部本地可用时为空。
  final List<String> pathEntries;
}

/// 工具供给器：本地优先，缺失时下载 zip 解压到 `tools/<name>/`。
///
/// 来源 URL 记入 `tools/<name>/.source`，标记匹配即复用；下载先解压到
/// `tools/.tmp/` 再原子替换，失败不留半成品目录。zip 的单层根目录自动剥离。
/// 替换遇杀软/句柄锁导致的瞬时文件占用时短延迟重试（默认 3 次、间隔 250ms）。
class ToolProvisioner {
  ToolProvisioner({
    String toolsRoot = 'tools',
    ToolFetcher? fetch,
    PackProcessRunner? runner,
    Map<String, String>? environment,
    int replaceAttempts = _defaultReplaceAttempts,
    Duration replaceRetryDelay = _defaultReplaceRetryDelay,
  }) : assert(replaceAttempts >= 1),
       assert(replaceRetryDelay >= Duration.zero),
       _toolsRoot = Directory(toolsRoot).absolute.path,
       _fetch = fetch ?? _fetchBytesOverHttp,
       _runner = runner ?? Process.run,
       _environment = environment ?? Platform.environment,
       _replaceAttempts = replaceAttempts,
       _replaceRetryDelay = replaceRetryDelay;

  final String _toolsRoot;
  final ToolFetcher _fetch;
  final PackProcessRunner _runner;
  final Map<String, String> _environment;
  final int _replaceAttempts;
  final Duration _replaceRetryDelay;

  /// 确保 [name] 工具就绪：来源标记匹配 [url] 时直接复用，否则重新下载替换。
  ///
  /// [binSubdir] 为需额外加入 PATH 的工具内子目录（以 `/` 分隔，如 `perl/bin`）。
  Future<ProvisionedTool> ensureTool({
    required String name,
    required String url,
    String? binSubdir,
  }) async {
    final String safeName = _sanitizeToolName(name);
    final List<String>? subSegments = _validatedSubdir(safeName, binSubdir);
    final String toolPath = joinPath(_toolsRoot, safeName);
    final File marker = File(joinPath(toolPath, _markerFileName));
    if (await _markerMatches(marker, url)) {
      return _describeTool(safeName, toolPath, subSegments);
    }

    final Uint8List bytes = await _download(safeName, url);
    final Archive archive = _decodeArchive(safeName, url, bytes);

    final Directory tempRoot = Directory(
      joinPath(_toolsRoot, _tempDirectoryName),
    );
    await tempRoot.create(recursive: true);
    final Directory staging = await tempRoot.createTemp('$safeName-');
    try {
      _extractArchive(archive, staging, safeName, url);
      File(joinPath(staging.path, _markerFileName)).writeAsStringSync(url);
      await _replaceDirectory(staging, Directory(toolPath), safeName);
    } finally {
      await _deleteQuietly(staging);
    }
    return _describeTool(safeName, toolPath, subSegments);
  }

  /// 确保 CMake（≥ 3.25）与 Ninja 可用：优先本机 PATH 与
  /// `%ProgramFiles%\CMake\bin`，否则下载到 `tools/`。
  Future<CmakeNinja> ensureCmakeNinja() async {
    final List<String> pathEntries = <String>[];
    String? cmake = await _probeCmake('cmake');
    final String? fallback = _programFilesCmakePath();
    if (cmake == null && fallback != null) {
      cmake = await _probeCmake(fallback);
    }
    if (cmake == null) {
      final ProvisionedTool tool = await ensureTool(
        name: 'cmake',
        url: cmakeDownloadUrl,
      );
      cmake = joinPath(tool.directory, 'bin/cmake.exe');
      pathEntries.addAll(tool.pathEntries);
    }

    final bool ninjaAvailable = await _commandAvailable('ninja', const <String>[
      '--version',
    ]);
    String? ninja = ninjaAvailable ? 'ninja' : null;
    if (ninja == null) {
      final ProvisionedTool tool = await ensureTool(
        name: 'ninja',
        url: ninjaDownloadUrl,
      );
      ninja = joinPath(tool.directory, 'ninja.exe');
      pathEntries.addAll(tool.pathEntries);
    }

    return CmakeNinja(
      cmakeExecutable: cmake,
      ninjaExecutable: ninja,
      pathEntries: pathEntries,
    );
  }

  Future<Uint8List> _download(String name, String url) async {
    try {
      return await _fetch(Uri.parse(url));
    } on BuildPreparationException {
      rethrow;
    } catch (error) {
      throw BuildPreparationException('工具 $name 下载失败：$url（$error）');
    }
  }

  Archive _decodeArchive(String name, String url, Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      throw BuildPreparationException('工具 $name 的压缩包无效：$url（$error）');
    }
    if (!archive.any((ArchiveFile file) => file.isFile)) {
      throw BuildPreparationException('工具 $name 的压缩包为空：$url');
    }
    return archive;
  }

  void _extractArchive(
    Archive archive,
    Directory destination,
    String name,
    String url,
  ) {
    final String? stripRoot = _singleRootDirectory(archive);
    for (final ArchiveFile file in archive.files) {
      final List<String>? segments = _safeSegments(file.name);
      if (segments == null) {
        throw BuildPreparationException(
          '工具 $name 的压缩包包含不安全的路径：${file.name}（$url）',
        );
      }
      final List<String>? relative = _stripRoot(segments, stripRoot);
      if (relative == null || relative.isEmpty) {
        continue;
      }
      final String path = joinPath(destination.path, relative.join('/'));
      if (file.isDirectory) {
        Directory(path).createSync(recursive: true);
        continue;
      }
      final File target = File(path);
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(file.content);
    }
  }

  Future<String?> _probeCmake(String executable) async {
    final ProcessResult result;
    try {
      result = await _runner(executable, const <String>['--version']);
    } on ProcessException {
      return null;
    }
    if (result.exitCode != 0) {
      return null;
    }
    final Match? match = _cmakeVersionPattern.firstMatch('${result.stdout}');
    if (match == null || !_meetsMinimumVersion(match.group(1)!)) {
      return null;
    }
    return executable;
  }

  Future<bool> _commandAvailable(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final ProcessResult result = await _runner(executable, arguments);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  String? _programFilesCmakePath() {
    final String? programFiles = _environment['ProgramFiles'];
    if (programFiles == null || programFiles.isEmpty) {
      return null;
    }
    return joinPath(programFiles, 'CMake/bin/cmake.exe');
  }

  ProvisionedTool _describeTool(
    String name,
    String directory,
    List<String>? subSegments,
  ) {
    final List<String> entries = <String>[directory];
    _addExistingPath(entries, joinPath(directory, _binDirectoryName));
    if (subSegments != null) {
      _addExistingPath(entries, joinPath(directory, subSegments.join('/')));
    }
    return ProvisionedTool(
      name: name,
      directory: directory,
      pathEntries: entries,
    );
  }

  /// 目录替换在杀软/句柄锁下可能瞬时 `PathAccessException`；仅对
  /// [FileSystemException] 短延迟重试，末次仍失败则抛出。
  Future<void> _replaceDirectory(
    Directory staging,
    Directory target,
    String name,
  ) async {
    var attempt = 1;
    while (true) {
      try {
        if (target.existsSync()) {
          target.deleteSync(recursive: true);
        }
        staging.renameSync(target.path);
        return;
      } catch (error) {
        if (error is! FileSystemException || attempt >= _replaceAttempts) {
          throw BuildPreparationException(
            '工具 $name 安装失败：${target.path}（$error）',
          );
        }
        attempt++;
        await Future<void>.delayed(_replaceRetryDelay);
      }
    }
  }
}

String _sanitizeToolName(String name) {
  final String sanitized = name.replaceAll(_invalidNamePattern, '_');
  if (sanitized.isEmpty ||
      sanitized == '.' ||
      sanitized == '..' ||
      !_alphanumericPattern.hasMatch(sanitized)) {
    throw BuildPreparationException('工具名称非法：$name');
  }
  return sanitized;
}

List<String>? _validatedSubdir(String name, String? binSubdir) {
  if (binSubdir == null) {
    return null;
  }
  final List<String>? segments = _safeSegments(binSubdir);
  if (segments == null || segments.isEmpty) {
    throw BuildPreparationException('工具 $name 的子目录不合法：$binSubdir');
  }
  return segments;
}

Future<bool> _markerMatches(File marker, String url) async {
  if (!await marker.exists()) {
    return false;
  }
  try {
    return (await marker.readAsString()).trim() == url;
  } on FileSystemException {
    return false;
  }
}

Future<void> _deleteQuietly(FileSystemEntity entity) async {
  try {
    if (await entity.exists()) {
      await entity.delete(recursive: true);
    }
  } on FileSystemException {
    // 临时残留清理失败不影响本次结果，下次供给会重新创建。
  }
}

void _addExistingPath(List<String> entries, String path) {
  if (entries.contains(path) || !Directory(path).existsSync()) {
    return;
  }
  entries.add(path);
}

String? _singleRootDirectory(Archive archive) {
  String? root;
  for (final ArchiveFile file in archive.files) {
    if (!file.isFile) {
      continue;
    }
    final List<String>? segments = _safeSegments(file.name);
    if (segments == null || segments.length < 2) {
      return null;
    }
    if (root == null) {
      root = segments.first;
    } else if (root != segments.first) {
      return null;
    }
  }
  return root;
}

/// 剥离单层根目录；不在根下的目录条目返回 null（跳过）。
List<String>? _stripRoot(List<String> segments, String? stripRoot) {
  if (stripRoot == null) {
    return segments;
  }
  if (segments.length < 2 || segments.first != stripRoot) {
    return null;
  }
  return segments.sublist(1);
}

List<String>? _safeSegments(String path) {
  final List<String> segments = path
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .toList();
  for (final String segment in segments) {
    if (segment == '.' ||
        segment == '..' ||
        segment.contains(r'\') ||
        segment.contains(':')) {
      return null;
    }
  }
  return segments;
}

bool _meetsMinimumVersion(String version) {
  final List<int> actual = _versionParts(version);
  final List<int> required = _versionParts(_minimumCmakeVersion);
  for (int index = 0; index < required.length; index++) {
    if (actual[index] != required[index]) {
      return actual[index] > required[index];
    }
  }
  return true;
}

List<int> _versionParts(String version) =>
    version.split('.').map(int.parse).toList();

Future<Uint8List> _fetchBytesOverHttp(Uri uri) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw BuildPreparationException('下载失败（HTTP ${response.statusCode}）：$uri');
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}
