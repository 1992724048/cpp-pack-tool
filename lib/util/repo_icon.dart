import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 可辨识的远程仓库平台（仅公共托管；自建实例按不可辨识处理）。
enum RepoPlatform { github, gitlab }

/// 仓库解析结果：平台 / 属主或完整项目路径 / 规范化网页地址。
class RepoLocation {
  const RepoLocation({
    required this.platform,
    required this.owner,
    required this.webUrl,
  });

  final RepoPlatform platform;

  /// GitHub：属主；GitLab：`group/subgroup/project` 完整路径。
  final String owner;

  /// 规范化后的网页地址（去 `.git`、去尾斜杠、去查询与片段）。
  final String webUrl;
}

/// 侧栏条目数据源：平台（未解析出远程平台时为 null）与头像文件绝对路径。
typedef RepoIconSource = ({RepoPlatform? platform, String? avatarPath});

/// 单次头像请求结果（测试注入 [RepoIconFetcher] 时构造）。
typedef RepoIconResponse = ({
  int statusCode,
  String? contentType,
  List<int> bytes,
});

/// 单次 HTTP 获取；[timeout] 为单次请求超时，测试可注入替代实现。
typedef RepoIconFetcher =
    Future<RepoIconResponse> Function(Uri uri, {required Duration timeout});

const String _githubHost = 'github.com';
const String _gitlabHost = 'gitlab.com';
const String _gitlabApiBase = 'https://gitlab.com/api/v4/projects';
const String _gitSuffix = '.git';
const String _userAgent = 'cpp_nuget_pack';

final RegExp _scpRepoPattern = RegExp(r'^[^@/\s]+@([^:/\s]+):(.+)$');

/// 解析仓库地址；非 github.com / gitlab.com（自建托管、本地路径等）返回 null。
RepoLocation? parseRepoLocation(String repo) {
  final String? webUrl = openableRepoWebUrl(repo);
  if (webUrl == null) {
    return null;
  }
  final Uri? uri = Uri.tryParse(webUrl);
  if (uri == null) {
    return null;
  }
  final List<String> segments = _pathSegments(uri);
  if (segments.isEmpty) {
    return null;
  }
  return switch (uri.host.toLowerCase()) {
    _githubHost => RepoLocation(
      platform: RepoPlatform.github,
      owner: segments.first,
      webUrl: webUrl,
    ),
    _gitlabHost => RepoLocation(
      platform: RepoPlatform.gitlab,
      owner: segments.join('/'),
      webUrl: webUrl,
    ),
    _ => null,
  };
}

/// 可打开的网页地址：http/https 原样规范化；`git@host:path` 转 `https://host/path`
/// （去 `.git`）；其余（本地路径、空串等）返回 null。
String? openableRepoWebUrl(String repo) {
  final String trimmed = repo.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return _normalizeWebUrl(uri);
  }
  return _parseScpRepo(trimmed);
}

List<String> _pathSegments(Uri uri) =>
    uri.pathSegments.where((String segment) => segment.isNotEmpty).toList();

/// 去 `.git`、去尾斜杠、去查询与片段（保留显式端口）。
String _normalizeWebUrl(Uri uri) {
  final List<String> segments = _pathSegments(uri);
  if (segments.isNotEmpty) {
    final String last = segments.last;
    if (last.toLowerCase().endsWith(_gitSuffix)) {
      final String stripped = last.substring(0, last.length - _gitSuffix.length);
      if (stripped.isEmpty) {
        segments.removeLast();
      } else {
        segments[segments.length - 1] = stripped;
      }
    }
  }
  final String authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  final String path = segments.isEmpty ? '' : '/${segments.join('/')}';
  return '${uri.scheme}://$authority$path';
}

String? _parseScpRepo(String value) {
  final RegExpMatch? match = _scpRepoPattern.firstMatch(value);
  if (match == null) {
    return null;
  }
  final String host = match.group(1)!;
  final String path = match.group(2)!.trim();
  if (path.isEmpty || path.startsWith(r'\')) {
    return null;
  }
  final Uri? uri = Uri.tryParse('https://$host/$path');
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  return _normalizeWebUrl(uri);
}

/// GitHub 属主头像地址（头像 CDN；匿名访问，建议 128 尺寸）。
String githubAvatarUrl(String owner, {int size = 128}) =>
    'https://avatars.githubusercontent.com/$owner?s=$size';

/// 响应 Content-Type → 落盘扩展名；无法识别或缺失按 `png`
/// （内容非法由渲染层 errorBuilder 兜底）。
String extensionForContentType(String? contentType) {
  final String value = (contentType ?? '').toLowerCase().split(';').first.trim();
  return switch (value) {
    'image/png' => 'png',
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/svg+xml' => 'svg',
    _ => 'png',
  };
}

/// 确保头像可用：命中磁盘缓存直接返回绝对路径；否则网络获取并落盘；
/// 失败（含超时、无头像）静默返回 null，不做负缓存与 TTL。
///
/// [cacheRoot] 默认与构建缓存同根（`cache/icons/<平台>/`）；[fetch] 可注入。
Future<String?> ensureRepoAvatar(
  String repo, {
  String cacheRoot = 'cache',
  Duration timeout = const Duration(seconds: 15),
  RepoIconFetcher? fetch,
}) async {
  final RepoLocation? location = parseRepoLocation(repo);
  if (location == null) {
    return null;
  }
  final Directory cacheDirectory = Directory(
    '${Directory(cacheRoot).absolute.path}/icons/${location.platform.name}',
  );
  final String cacheKey = _cacheKeyFor(location);
  final String? cached = _findCachedAvatar(cacheDirectory, cacheKey);
  if (cached != null) {
    return cached;
  }
  final RepoIconFetcher fetcher = fetch ?? _fetchOverHttp;
  try {
    final String? avatarUrl = await _resolveAvatarUrl(
      location,
      fetcher,
      timeout,
    );
    if (avatarUrl == null) {
      return null;
    }
    final RepoIconResponse response = await fetcher(
      Uri.parse(avatarUrl),
      timeout: timeout,
    );
    if (response.statusCode != 200 || response.bytes.isEmpty) {
      return null;
    }
    return await _writeAvatarCache(
      cacheDirectory,
      cacheKey,
      extensionForContentType(response.contentType),
      response.bytes,
    );
  } catch (_) {
    return null;
  }
}

String _cacheKeyFor(RepoLocation location) {
  if (location.platform == RepoPlatform.github) {
    return PackStore.sanitizeFileName(location.owner.toLowerCase());
  }
  final String flattened = location.owner.toLowerCase().replaceAll('/', '_');
  return PackStore.sanitizeFileName(flattened);
}

String? _findCachedAvatar(Directory directory, String cacheKey) {
  if (!directory.existsSync()) {
    return null;
  }
  final List<String> matches = <String>[];
  try {
    for (final FileSystemEntity entity in directory.listSync(
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      if (baseName(entity.path).startsWith('$cacheKey.')) {
        matches.add(entity.absolute.path);
      }
    }
  } on FileSystemException {
    return null;
  }
  if (matches.isEmpty) {
    return null;
  }
  matches.sort();
  return matches.first;
}

/// GitHub 直接构造头像地址；GitLab 先经 API 解析 `avatar_url`（可能为 null）。
Future<String?> _resolveAvatarUrl(
  RepoLocation location,
  RepoIconFetcher fetcher,
  Duration timeout,
) async {
  if (location.platform == RepoPlatform.github) {
    return githubAvatarUrl(location.owner);
  }
  final Uri apiUri = Uri.parse(
    '$_gitlabApiBase/${Uri.encodeComponent(location.owner)}',
  );
  final RepoIconResponse response = await fetcher(apiUri, timeout: timeout);
  if (response.statusCode != 200 || response.bytes.isEmpty) {
    return null;
  }
  final Object? decoded = jsonDecode(
    utf8.decode(response.bytes, allowMalformed: true),
  );
  if (decoded is! Map) {
    return null;
  }
  final Object? avatarUrl = decoded['avatar_url'];
  if (avatarUrl is! String || avatarUrl.trim().isEmpty) {
    return null;
  }
  if (avatarUrl.startsWith('//')) {
    return 'https:$avatarUrl';
  }
  return avatarUrl.startsWith('/') ? 'https://$_gitlabHost$avatarUrl' : avatarUrl;
}

/// 先写 `.tmp` 再改名（原子替换思路）；写入失败返回 null（下次启动重试）。
Future<String?> _writeAvatarCache(
  Directory directory,
  String cacheKey,
  String extension,
  List<int> bytes,
) async {
  await directory.create(recursive: true);
  final File target = File('${directory.path}/$cacheKey.$extension');
  final File temporary = File('${target.path}.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  try {
    if (await target.exists()) {
      await target.delete();
    }
    final File result = await temporary.rename(target.path);
    return result.absolute.path;
  } catch (_) {
    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    } catch (_) {
      // 临时文件清理失败不追加处理：缓存目录内容非关键数据
    }
    return null;
  }
}

/// 默认 HTTP 获取：跟随重定向（HttpClient 默认行为），全流程受 [timeout] 约束。
Future<RepoIconResponse> _fetchOverHttp(
  Uri uri, {
  required Duration timeout,
}) async {
  final HttpClient client = HttpClient();
  client.connectionTimeout = timeout;
  try {
    final HttpClientRequest request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final HttpClientResponse response = await request.close().timeout(timeout);
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
    }
    return (
      statusCode: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      bytes: bytes,
    );
  } finally {
    client.close(force: true);
  }
}
