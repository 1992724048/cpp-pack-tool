import 'dart:async';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/repo_version.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _ProcessCall = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
});

void main() {
  group('listRemoteTags', () {
    test('解析 ls-remote 输出中的 tag 名称并透传调用参数', () async {
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final List<String>? tags = await listRemoteTags(
        'https://github.com/foo/bar.git',
        runner: _runner(
          calls,
          (_) async => ProcessResult(
            1,
            0,
            'aaa\trefs/tags/v1.0.0\n'
                'bbb\trefs/tags/1.1.0\n'
                'ccc\tHEAD\n'
                'ddd\trefs/heads/main\n',
            '',
          ),
        ),
      );

      expect(tags, <String>['v1.0.0', '1.1.0']);
      expect(calls, hasLength(1));
      expect(calls.single.executable, 'git');
      expect(calls.single.arguments, <String>[
        'ls-remote',
        '--tags',
        '--refs',
        'https://github.com/foo/bar.git',
      ]);
      expect(calls.single.workingDirectory, isNull);
      expect(calls.single.environment, <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
      });
    });

    test('仓库无 tag 时返回空列表', () async {
      final List<String>? tags = await listRemoteTags(
        'https://example.com/repo.git',
        runner: _runner(
          <_ProcessCall>[],
          (_) async => ProcessResult(1, 0, 'aaa\tHEAD\n', ''),
        ),
      );

      expect(tags, isEmpty);
    });

    test('非零退出返回 null', () async {
      final List<String>? tags = await listRemoteTags(
        'https://example.com/repo.git',
        runner: _runner(
          <_ProcessCall>[],
          (_) async => ProcessResult(1, 128, '', 'fatal: not found\n'),
        ),
      );

      expect(tags, isNull);
    });

    test('runner 抛 ProcessException 返回 null', () async {
      final List<String>? tags = await listRemoteTags(
        'https://example.com/repo.git',
        runner: _runner(
          <_ProcessCall>[],
          (_) async => throw ProcessException('git', <String>[], 'not found'),
        ),
      );

      expect(tags, isNull);
    });

    test('超时返回 null', () async {
      final Completer<ProcessResult> pending = Completer<ProcessResult>();

      final List<String>? tags = await listRemoteTags(
        'https://example.com/repo.git',
        runner: _runner(<_ProcessCall>[], (_) => pending.future),
        timeout: const Duration(milliseconds: 20),
      );

      expect(tags, isNull);
    });
  });

  group('latestTag', () {
    test('忽略不可解析 tag 并取最高版本', () {
      expect(
        latestTag(<String>['nightly', 'v1.0.0', '1.10.0', '1.9.0', 'release-x']),
        '1.10.0',
      );
    });

    test('全部不可解析时返回 null', () {
      expect(latestTag(<String>['nightly', 'release-x', '']), isNull);
    });

    test('空列表返回 null', () {
      expect(latestTag(const <String>[]), isNull);
    });
  });

  group('compareTagVersions', () {
    test('去除 v 前缀并按数字分段比较', () {
      expect(compareTagVersions('v1.2.0', '1.1.9'), greaterThan(0));
      expect(compareTagVersions('1.1.9', 'v1.2.0'), lessThan(0));
      expect(compareTagVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(compareTagVersions('1.0.0', '1.0.0'), 0);
    });

    test('段数不同按缺省 0 补足', () {
      expect(compareTagVersions('1.2', '1.2.0'), 0);
      expect(compareTagVersions('1.2.3.4', '1.2.3'), greaterThan(0));
      expect(compareTagVersions('v1.0', 'v1'), 0);
    });

    test('任一侧不可解析时视为不可比较', () {
      expect(compareTagVersions('latest', '1.0.0'), 0);
      expect(compareTagVersions('1.0.0', 'beta'), 0);
      expect(compareTagVersions('', '1.0.0'), 0);
    });
  });
}

PackProcessRunner _runner(
  List<_ProcessCall> calls,
  Future<ProcessResult> Function(_ProcessCall call) handler,
) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    final _ProcessCall call = (
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    calls.add(call);
    return handler(call);
  };
}
