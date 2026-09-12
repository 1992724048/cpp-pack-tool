import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';

const String _tagRefPrefix = 'refs/tags/';
const String _gitPromptEnvironmentKey = 'GIT_TERMINAL_PROMPT';
const Duration _remoteTagsTimeout = Duration(seconds: 15);

final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _digitsPattern = RegExp(r'^\d+$');

/// 查询远端仓库的全部 tag 名称（`git ls-remote --tags --refs`）。
///
/// 离线、超时、非零退出或 runner 异常时返回 null（静默失败，不抛出）；
/// 仓库无 tag 时返回空列表。测试可注入 [runner] 与 [timeout]。
Future<List<String>?> listRemoteTags(
  String repoUrl, {
  PackProcessRunner runner = Process.run,
  Duration timeout = _remoteTagsTimeout,
}) async {
  final ProcessResult result;
  try {
    result = await runner(
      'git',
      <String>['ls-remote', '--tags', '--refs', repoUrl],
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
  final List<String> tags = <String>[];
  for (final String rawLine in '${result.stdout}'.split('\n')) {
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
/// 去除前导 `v`/`V` 后按 `.` 分段做数值比较，段数不同按缺省段 0 补足
/// （`1.2` 与 `1.2.0` 相等）；任一侧无法解析为纯数字分段时视为不可比较。
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

List<int>? _parseTagVersion(String tag) {
  final String trimmed = tag.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final String body = trimmed.startsWith('v') || trimmed.startsWith('V')
      ? trimmed.substring(1)
      : trimmed;
  if (body.isEmpty) {
    return null;
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
