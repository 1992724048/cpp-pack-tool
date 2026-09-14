import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';

const String _tagRefPrefix = 'refs/tags/';
const String _gitPromptEnvironmentKey = 'GIT_TERMINAL_PROMPT';
const Duration _remoteTagsTimeout = Duration(seconds: 15);

final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _digitsPattern = RegExp(r'^\d+$');
final RegExp _versionSegmentPattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9]*[-_]([0-9]+(?:\.[0-9]+)*)$',
);

/// 查询远端仓库的全部 tag 名称（`git ls-remote --tags --refs`）。
///
/// 离线、超时、非零退出或 runner 异常时返回 null（静默失败，不抛出）；
/// 仓库无 tag 时返回空列表。测试可注入 [runner] 与 [timeout]；
/// [workingDirectory] 供本地仓库场景（远端名 `origin`）指定工作目录。
Future<List<String>?> listRemoteTags(
  String repoUrl, {
  PackProcessRunner runner = Process.run,
  Duration timeout = _remoteTagsTimeout,
  String? workingDirectory,
}) async {
  final ProcessResult result;
  try {
    result = await runner(
      'git',
      <String>['ls-remote', '--tags', '--refs', repoUrl],
      workingDirectory: workingDirectory,
      environment: <String, String>{_gitPromptEnvironmentKey: '0'},
    ).timeout(timeout);
  } on ProcessException {
    return null;
  } on TimeoutException {
    return null;
  }
  if (result.exitCode != 0) {
    return null;
  }
  return _parseRemoteTags('${result.stdout}');
}

/// 解析 `git ls-remote` 输出中的 tag 名称（`<哈希>\trefs/tags/<名称>` 行）。
List<String> _parseRemoteTags(String stdout) {
  final List<String> tags = <String>[];
  for (final String rawLine in stdout.split('\n')) {
    final List<String> tokens = rawLine.trim().split(_whitespacePattern);
    if (tokens.length < 2) {
      continue;
    }
    final String ref = tokens.last;
    if (!ref.startsWith(_tagRefPrefix)) {
      continue;
    }
    final String name = ref.substring(_tagRefPrefix.length);
    if (name.isNotEmpty) {
      tags.add(name);
    }
  }
  return tags;
}

/// 本地缓存仓库的最新稳定 tag：查询远端（`ls-remote` 走仓库内 `origin`）。
///
/// 与 UI「最新版本」同一口径：同一 [latestTag] 解析与数值比较、同一
/// `ls-remote --tags --refs` 数据面；查询失败（离线/超时/无 origin）或
/// 无可用 tag 时返回 null，由调用方回退默认分支行为。
Future<String?> resolveLatestStableTag(
  Directory repository, {
  PackProcessRunner runner = Process.run,
  Duration timeout = _remoteTagsTimeout,
}) async {
  final ProcessResult result;
  try {
    result = await runner(
      'git',
      <String>['ls-remote', '--tags', '--refs', 'origin'],
      workingDirectory: repository.path,
      environment: <String, String>{_gitPromptEnvironmentKey: '0'},
    ).timeout(timeout);
  } on ProcessException {
    return null;
  } on TimeoutException {
    return null;
  }
  if (result.exitCode != 0) {
    return null;
  }
  return latestTag(_parseRemoteTags('${result.stdout}'));
}

/// tag 中最高版本；无可用（可解析）tag 时返回 null，不可解析的 tag 忽略。
String? latestTag(List<String> tags) {
  String? latest;
  for (final String tag in tags) {
    if (_parseTagVersion(tag) == null) {
      continue;
    }
    if (latest == null || compareTagVersions(tag, latest) > 0) {
      latest = tag;
    }
  }
  return latest;
}

/// 比较两个 tag 的版本号：a > b 返回正数，a < b 返回负数，相等或无法比较返回 0。
///
/// 去除前导 `v`/`V` 或单段前缀（`openssl-4.0.2` 的 `openssl-`）后按 `.` 分段做
/// 数值比较，段数不同按缺省段 0 补足（`1.2` 与 `1.2.0` 相等）；任一侧无法解析为
/// 纯数字分段（含 `-alpha1` 等预发布后缀）时视为不可比较。
int compareTagVersions(String a, String b) {
  final List<int>? left = _parseTagVersion(a);
  final List<int>? right = _parseTagVersion(b);
  if (left == null || right == null) {
    return 0;
  }
  final int length = left.length > right.length ? left.length : right.length;
  for (int index = 0; index < length; index++) {
    final int leftPart = index < left.length ? left[index] : 0;
    final int rightPart = index < right.length ? right[index] : 0;
    if (leftPart != rightPart) {
      return leftPart.compareTo(rightPart);
    }
  }
  return 0;
}

/// 解析 tag 的版本分段：`v?<数字点分>` 或单段字母前缀 + `-`/`_` + 数字点分
/// （如 `openssl-4.0.2`）；解析失败（含预发布后缀、日期式等）返回 null。
List<int>? _parseTagVersion(String tag) {
  final String trimmed = tag.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  String body = trimmed;
  if (body.startsWith('v') || body.startsWith('V')) {
    body = body.substring(1);
  }
  if (body.isEmpty) {
    return null;
  }
  final RegExpMatch? prefixed = _versionSegmentPattern.firstMatch(body);
  if (prefixed != null) {
    body = prefixed.group(1)!;
  }
  final List<int> segments = <int>[];
  for (final String part in body.split('.')) {
    if (!_digitsPattern.hasMatch(part)) {
      return null;
    }
    final int? value = int.tryParse(part);
    if (value == null) {
      return null;
    }
    segments.add(value);
  }
  return segments;
}
