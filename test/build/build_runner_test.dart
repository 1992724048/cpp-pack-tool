import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _ProcessCall = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
});

typedef _StreamCall = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
});

/// 流式执行器替身的行为：记录调用并返回一个假进程。
typedef _FakeProcessHandler = Future<_FakeProcess> Function(_StreamCall call);

/// 与 `Process` 同形的最小子集：stdout/stderr 为可订阅的字节流，
/// [pid]/[exitCode] 供 `runPackBuild` 组装 `ProcessResult` 使用。
class _FakeProcess implements Process {
  _FakeProcess({
    required String stdout,
    required String stderr,
    this._exitCode = 0,
  }) : stdout = _FakeStream(stdout),
       stderr = _FakeStream(stderr);

  @override
  final int pid = 1;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  final int _exitCode;

  @override
  Future<int> get exitCode => Future<int>.value(_exitCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStream extends Stream<List<int>> {
  _FakeStream(this.text);

  final String text;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(text)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

void main() {
  setUp(_streamCalls.clear);

  group('前置校验', () {
    test('缺少源目录信息时抛错且不执行进程', () async {
      final Directory root = _tempDirectory();
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(),
          stages.add,
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(_buildException('该包缺少源目录信息')),
      );

      expect(stages, isEmpty);
      expect(calls, isEmpty);
    });

    test('包内无 build.py 时抛错', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath, files: <FileModel>[]),
          (_) {},
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(_buildException('未找到 build.py')),
      );

      expect(calls, isEmpty);
    });

    test('源目录中 build.py 缺失时抛错', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = joinPath(root.path, 'src');
      Directory(sourcePath).createSync(recursive: true);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(_buildException('源目录中找不到 build.py（可能已被移动）')),
      );

      expect(calls, isEmpty);
    });

    test('build.py 首行缺少仓库地址时抛错', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, 'print(1)\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(_buildException('build.py 首行缺少 git 仓库地址（格式：# <仓库地址>）')),
      );

      expect(stages, isEmpty);
      expect(calls, isEmpty);
    });

    test('首行只有 # 时同样抛错', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '#   \nprint(1)\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(_buildException('build.py 首行缺少 git 仓库地址（格式：# <仓库地址>）')),
      );

      expect(calls, isEmpty);
    });
  });

  group('下载源码', () {
    test('首次构建克隆仓库并执行构建：参数、工作目录与环境变量', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\nprint(1)\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        stages.add,
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(stages, <PackBuildStage>[
        PackBuildStage.downloading,
        PackBuildStage.building,
      ]);
      expect(Directory(joinPath(cacheRoot, 'build')).existsSync(), isTrue);
      expect(calls, hasLength(2));

      final _ProcessCall clone = calls[0];
      expect(clone.executable, 'git');
      expect(clone.arguments, <String>[
        'clone',
        '--progress',
        'https://github.com/foo/bar.git',
        targetPath,
      ]);
      expect(clone.workingDirectory, isNull);
      expect(clone.environment, <String, String>{'GIT_TERMINAL_PROMPT': '0'});

      final _ProcessCall python = calls[1];
      expect(python.executable, 'python');
      expect(python.arguments, <String>['-u', 'build.py']);
      expect(python.workingDirectory, sourcePath);
      expect(python.environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });

    test('已有 .git 时原位硬重置：fetch → reset @{u} → clean -ffdx 且保留 .git', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      Directory(joinPath(targetPath, '.git')).createSync(recursive: true);
      File(joinPath(targetPath, 'keep.txt')).writeAsStringSync('keep');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      final List<_ProcessCall> gitCalls = calls
          .where((_ProcessCall call) => call.executable == 'git')
          .toList();
      expect(gitCalls, hasLength(3));
      expect(gitCalls[0].arguments, <String>['fetch', '--progress']);
      expect(gitCalls[0].workingDirectory, targetPath);
      expect(gitCalls[0].environment, <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
      });
      expect(gitCalls[1].arguments, <String>['reset', '--hard', '@{u}']);
      expect(gitCalls[1].workingDirectory, targetPath);
      expect(gitCalls[2].arguments, <String>['clean', '-ffdx']);
      expect(gitCalls[2].workingDirectory, targetPath);
      expect(calls[3].executable, 'python');
      expect(
        Directory(joinPath(targetPath, '.git')).existsSync(),
        isTrue,
        reason: '硬重置保留 .git 仓库目录',
      );
      expect(
        File(joinPath(targetPath, 'keep.txt')).existsSync(),
        isTrue,
        reason: '桩 git 不清文件：该断言只锁命令序列，真实清理由 git 自身完成',
      );
    });

    test('无上游引用时 reset 回退到 FETCH_HEAD', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      Directory(joinPath(targetPath, '.git')).createSync(recursive: true);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (call) async {
          if (call.arguments.length >= 3 &&
              call.arguments[0] == 'reset' &&
              call.arguments[2] == '@{u}') {
            return ProcessResult(1, 128, '', 'fatal: no upstream configured\n');
          }
          return _success();
        }),
        cacheRoot: cacheRoot,
      );

      final List<_ProcessCall> resets = calls
          .where(
            (_ProcessCall call) =>
                call.arguments.isNotEmpty && call.arguments.first == 'reset',
          )
          .toList();
      expect(resets, hasLength(2));
      expect(resets[1].arguments, <String>['reset', '--hard', 'FETCH_HEAD']);
      expect(
        calls.where(
          (_ProcessCall call) =>
              call.arguments.isNotEmpty && call.arguments.first == 'clean',
        ),
        hasLength(1),
      );
    });

    test('目标目录存在但不是 git 仓库时先清理再克隆', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      Directory(targetPath).createSync(recursive: true);
      File(joinPath(targetPath, 'stale.txt')).writeAsStringSync('stale');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      bool existedAtClone = true;

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (call) async {
          if (call.executable == 'git' && call.arguments.first == 'clone') {
            existedAtClone = Directory(targetPath).existsSync();
          }
          return _success();
        }),
        cacheRoot: cacheRoot,
      );

      expect(existedAtClone, isFalse);
      expect(
        calls.where((_ProcessCall call) => call.arguments.first == 'clone'),
        hasLength(1),
      );
    });

    test('克隆失败时删除残留并抛出含输出尾部的异常', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(calls, (_) async {
            Directory(targetPath).createSync(recursive: true);
            File(joinPath(targetPath, 'partial.txt')).writeAsStringSync('x');
            return ProcessResult(1, 128, '', 'fatal: repository not found\n');
          }),
          cacheRoot: cacheRoot,
        ),
        throwsA(
          _buildException(
            '克隆源码失败（退出码 128）',
            outputTail: contains('fatal: repository not found'),
          ),
        ),
      );

      expect(stages, <PackBuildStage>[PackBuildStage.downloading]);
      expect(calls, hasLength(1));
      expect(Directory(targetPath).existsSync(), isFalse);
    });

    test('拉取失败时抛出异常、不清理源目录且不执行构建', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      File(joinPath(sourcePath, 'stale.txt')).writeAsStringSync('stale');
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      Directory(joinPath(targetPath, '.git')).createSync(recursive: true);
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(
            calls,
            (_) async => ProcessResult(1, 1, '', 'fatal: unable to access\n'),
          ),
          cacheRoot: cacheRoot,
        ),
        throwsA(
          _buildException(
            '拉取源码失败（退出码 1）',
            outputTail: contains('unable to access'),
          ),
        ),
      );

      expect(stages, <PackBuildStage>[PackBuildStage.downloading]);
      expect(calls, hasLength(1));
      expect(
        File(joinPath(sourcePath, 'stale.txt')).existsSync(),
        isTrue,
        reason: '拉取失败不得触碰包源目录',
      );
    });

    test('clean 失败同样按拉取失败报错且不执行构建', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      Directory(joinPath(targetPath, '.git')).createSync(recursive: true);
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(calls, (call) async {
            if (call.arguments.isNotEmpty && call.arguments.first == 'clean') {
              return ProcessResult(1, 1, '', 'fatal: cannot clean\n');
            }
            return _success();
          }),
          cacheRoot: cacheRoot,
        ),
        throwsA(
          _buildException(
            '拉取源码失败（退出码 1）',
            outputTail: contains('cannot clean'),
          ),
        ),
      );

      expect(stages, <PackBuildStage>[PackBuildStage.downloading]);
      expect(
        File(joinPath(sourcePath, 'build.py')).existsSync(),
        isTrue,
        reason: 'git 失败时不进入源目录清理',
      );
    });
  });

  group('构建前清理', () {
    test('清理先于 build.py 执行：白名单保留、其余文件删除', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      File(joinPath(sourcePath, 'stale.txt')).writeAsStringSync('stale');
      Directory(joinPath(sourcePath, 'build-release')).createSync(
        recursive: true,
      );
      File(
        joinPath(sourcePath, 'build-release/CMakeCache.txt'),
      ).writeAsStringSync('x');
      final Set<String> visibleAtBuild = <String>{};
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (call) async {
          if (call.executable == 'python') {
            visibleAtBuild.addAll(
              Directory(sourcePath)
                  .listSync()
                  .map((FileSystemEntity entity) => baseName(entity.path)),
            );
          }
          return _success();
        }),
        cacheRoot: joinPath(root.path, 'cache'),
      );

      expect(calls, hasLength(2));
      expect(
        visibleAtBuild,
        containsAll(<String>['build.py', 'icon.png', 'LICENSE']),
      );
      expect(visibleAtBuild, isNot(contains('stale.txt')));
      expect(visibleAtBuild, isNot(contains('build-release')));
    });

    test('清理失败时抛错且不执行构建脚本', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final File locked = File(joinPath(sourcePath, 'locked.dat'))
        ..writeAsStringSync('busy');
      final RandomAccessFile handle = locked.openSync(mode: FileMode.append);
      addTearDown(handle.closeSync);
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(
          isA<PackBuildException>().having(
            (PackBuildException error) => error.message,
            'message',
            contains('清理构建输出目录失败'),
          ),
        ),
      );

      expect(stages, <PackBuildStage>[PackBuildStage.downloading]);
      expect(
        calls.where((_ProcessCall call) => call.executable == 'python'),
        isEmpty,
        reason: '清理失败不得执行构建脚本',
      );
    });

    test('相对 cacheRoot 解析为稳定的绝对缓存目录', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String scriptPath = joinPath(sourcePath, 'build.py');
      final String scriptBackup = File(scriptPath).readAsStringSync();
      final List<_ProcessCall> calls = <_ProcessCall>[];

      Future<void> runOnce() async {
        final String previous = Directory.current.path;
        Directory.current = root.path;
        try {
          await runPackBuild(
            _pack(sourcePath: sourcePath),
            (_) {},
            processRunner: _runner(calls, (_) async => _success()),
            cacheRoot: 'cache',
          );
        } finally {
          Directory.current = previous;
        }
        File(scriptPath).writeAsStringSync(scriptBackup);
      }

      await runOnce();
      await runOnce();

      final String resolved =
          calls.last.environment!['SRC_PATH'] ?? '';
      expect(
        resolved.replaceAll('/', r'\'),
        joinPath(root.path, 'cache/build/demo').replaceAll('/', r'\'),
        reason: '相对 cacheRoot 以工作目录为基准解析为同一绝对路径',
      );
      expect(calls, hasLength(4), reason: '两次构建各含 git + python');
    });
  });

  group('预构建（# source: none）', () {
    test('跳过 git：仅创建缓存目录并注入 SRC_PATH 执行构建', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/openvinotoolkit/openvino.git\n'
        '# source: none\n'
        'print(1)\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        stages.add,
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(stages, <PackBuildStage>[
        PackBuildStage.downloading,
        PackBuildStage.building,
      ]);
      expect(
        calls.where((_ProcessCall call) => call.executable == 'git'),
        isEmpty,
        reason: 'source: none 不应调用 git',
      );
      expect(calls, hasLength(1));

      final _ProcessCall python = calls.single;
      expect(python.executable, 'python');
      expect(python.arguments, <String>['-u', 'build.py']);
      expect(python.workingDirectory, sourcePath);
      expect(python.environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
      expect(
        Directory(targetPath).existsSync(),
        isTrue,
        reason: 'SRC_PATH 工作区目录应被创建',
      );
    });

    test('缓存目录已存在（二次构建）时保留内容且不调用 git', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/openvinotoolkit/openvino.git\n'
        '# source: none\n',
      );
      File(joinPath(sourcePath, 'stale.txt')).writeAsStringSync('stale');
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      File(
        joinPath(targetPath, 'downloads/openvino.zip'),
      ).createSync(recursive: true);
      File(
        joinPath(targetPath, 'unpacked/.complete'),
      ).createSync(recursive: true);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(calls, hasLength(1));
      expect(calls.single.executable, 'python');
      expect(
        File(joinPath(targetPath, 'downloads/openvino.zip')).existsSync(),
        isTrue,
        reason: 'source: none 缓存目录（downloads）不得清理',
      );
      expect(
        File(joinPath(targetPath, 'unpacked/.complete')).existsSync(),
        isTrue,
        reason: 'source: none 缓存目录（unpacked）不得清理',
      );
      expect(
        File(joinPath(sourcePath, 'stale.txt')).existsSync(),
        isFalse,
        reason: 'BUILD_OUT 照常清理',
      );
      expect(
        File(joinPath(sourcePath, 'build.py')).existsSync(),
        isTrue,
        reason: '白名单保留',
      );
    });

    test('source: none 时注入环境仍透传到构建进程', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/openvinotoolkit/openvino.git\n'
        '# source: none\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final Map<String, String> injected = <String, String>{
        'CNP_OPTION_TBB': 'on',
        'CNP_TOOLS_DIR': r'D:\tools',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
        environment: injected,
      );

      expect(calls, hasLength(1));
      expect(calls.single.environment, <String, String>{
        ...injected,
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });
  });

  group('执行构建', () {
    test('python 不可用时回退 py -3', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        stages.add,
        processRunner: _runner(calls, (call) async {
          if (call.executable == 'python') {
            throw ProcessException('python', <String>['build.py'], 'not found');
          }
          return _success();
        }),
        cacheRoot: cacheRoot,
      );

      expect(stages, <PackBuildStage>[
        PackBuildStage.downloading,
        PackBuildStage.building,
      ]);
      expect(calls, hasLength(3));
      expect(calls[1].executable, 'python');
      expect(calls[2].executable, 'py');
      expect(calls[2].arguments, <String>['-3', '-u', 'build.py']);
      expect(calls[2].workingDirectory, sourcePath);
      expect(calls[2].environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });

    test('python 与 py 均不可用时抛出未找到 Python', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(calls, (call) async {
            if (call.executable == 'git') {
              return _success();
            }
            throw ProcessException(
              call.executable,
              call.arguments,
              'not found',
            );
          }),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(_buildException('未找到 Python（python / py），无法执行构建')),
      );

      expect(calls, hasLength(3));
    });

    test('构建非零退出时异常携带合并输出末尾 20 行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final String stdout = <String>[
        for (int index = 1; index <= 25; index++)
          'line${index.toString().padLeft(2, '0')}',
      ].join('\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(
            calls,
            (call) async => call.executable == 'git'
                ? _success()
                : ProcessResult(1, 3, stdout, 'err-line'),
          ),
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(
          _buildException(
            '构建失败（退出码 3）',
            outputTail: allOf(
              contains('line25'),
              contains('err-line'),
              isNot(contains('line01')),
              predicate<String>(
                (String text) => text.split('\n').length == 20,
                '输出末尾 20 行',
              ),
            ),
          ),
        ),
      );
    });
  });

  group('环境注入', () {
    test('注入的子进程环境透传到 git 与 python 调用', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final Map<String, String> injected = <String, String>{
        'CNP_COMPILER_KIND': 'icx',
        'CNP_TOOLS_DIR': r'D:\tools',
        'PATH': r'D:\tools\ninja;D:\tools\cmake\bin',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
        environment: injected,
      );

      expect(calls, hasLength(2));
      expect(calls[0].environment, <String, String>{
        ...injected,
        'GIT_TERMINAL_PROMPT': '0',
      });
      expect(calls[1].environment, <String, String>{
        ...injected,
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });

    test('未注入环境（null）时沿用既有内建变量', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(calls, hasLength(2));
      expect(calls[0].environment, <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
      });
      expect(calls[1].environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });

    test('注入的同名变量不覆盖必需变量', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
        environment: <String, String>{
          'GIT_TERMINAL_PROMPT': '1',
          'SRC_PATH': r'D:\bogus',
          'BUILD_OUT': r'D:\bogus',
        },
      );

      expect(calls, hasLength(2));
      expect(calls[0].environment, <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
        'SRC_PATH': r'D:\bogus',
        'BUILD_OUT': r'D:\bogus',
      });
      expect(calls[1].environment, <String, String>{
        'GIT_TERMINAL_PROMPT': '1',
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });

    test('python 回退 py 时同样携带注入环境', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final Map<String, String> injected = <String, String>{
        'CNP_CMAKE': r'D:\tools\cmake\bin\cmake.exe',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (call) async {
          if (call.executable == 'python') {
            throw ProcessException('python', <String>['build.py'], 'not found');
          }
          return _success();
        }),
        cacheRoot: cacheRoot,
        environment: injected,
      );

      expect(calls, hasLength(3));
      expect(calls[2].executable, 'py');
      expect(calls[2].environment, <String, String>{
        ...injected,
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });
  });

  group('流式输出', () {
    test('注入流式执行器且回调非空时 git 与 python 逐行转发并转发环境', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<String> lines = <String>[];
      final Map<String, String> injected = <String, String>{
        'CNP_TOOLS_DIR': r'D:\tools',
      };

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        streamRunner: _streamingRunner((_StreamCall call) async {
          if (call.executable == 'git') {
            return _fakeProcess(
              stdout:
                  'Receiving objects:  12% (1/8)\r'
                  'Receiving objects:  34% (3/8)\r',
            );
          }
          return _fakeProcess(stdout: 'line1\nline2\n', stderr: 'warn1\n');
        }),
        onOutput: lines.add,
        cacheRoot: cacheRoot,
        environment: injected,
      );

      expect(lines, <String>[
        'Receiving objects:  12% (1/8)',
        'Receiving objects:  34% (3/8)',
        'line1',
        'line2',
        'warn1',
      ]);
      expect(calls, isEmpty, reason: '注入流式执行器时 git 与 python 均走流式');

      expect(_streamCalls, hasLength(2));
      final _StreamCall git = _streamCalls.first;
      expect(git.executable, 'git');
      expect(git.arguments, <String>[
        'clone',
        '--progress',
        'https://github.com/foo/bar.git',
        targetPath,
      ]);
      expect(git.workingDirectory, isNull);
      expect(git.environment, <String, String>{
        ...injected,
        'GIT_TERMINAL_PROMPT': '0',
      });

      final _StreamCall stream = _streamCalls.last;
      expect(stream.executable, 'python');
      expect(stream.arguments, <String>['-u', 'build.py']);
      expect(stream.workingDirectory, sourcePath);
      expect(stream.environment, <String, String>{
        ...injected,
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });

    test('流式构建非零退出时异常携带合并输出末尾 20 行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final String stdout = <String>[
        for (int index = 1; index <= 25; index++)
          'line${index.toString().padLeft(2, '0')}',
      ].join('\n');
      final List<String> lines = <String>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
          streamRunner: _streamingRunner((_StreamCall call) async {
            if (call.executable == 'git') {
              return _fakeProcess(stdout: 'clone ok\n');
            }
            return _fakeProcess(
              stdout: '$stdout\n',
              stderr: 'err-line\n',
              exitCode: 3,
            );
          }),
          onOutput: lines.add,
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(
          _buildException(
            '构建失败（退出码 3）',
            outputTail: allOf(
              contains('line25'),
              contains('err-line'),
              isNot(contains('line01')),
              predicate<String>(
                (String text) => text.split('\n').length == 20,
                '输出末尾 20 行',
              ),
            ),
          ),
        ),
      );

      expect(
        lines,
        hasLength(27),
        reason: '1 行 clone 输出 + 25 行 stdout + 1 行 stderr 都经回调转发',
      );
    });

    test('未提供流式执行器时 onOutput 静默降级为一次性捕获', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final List<String> lines = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(
          <_ProcessCall>[],
          (_) async => ProcessResult(1, 0, 'done\n', ''),
        ),
        onOutput: lines.add,
        cacheRoot: joinPath(root.path, 'cache'),
      );

      expect(lines, isEmpty);
    });

    test('流式 python 不可用时回退 py -3 并同样转发输出', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<String> lines = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
        streamRunner: _streamingRunner((_StreamCall call) async {
          if (call.executable == 'python') {
            throw ProcessException('python', <String>['build.py'], 'not found');
          }
          return _fakeProcess(
            stdout: call.executable == 'git' ? 'clone ok\n' : 'fallback done\n',
          );
        }),
        onOutput: lines.add,
        cacheRoot: cacheRoot,
      );

      expect(lines, <String>['clone ok', 'fallback done']);
      expect(_streamCalls.map((_StreamCall call) => call.executable), <String>[
        'git',
        'python',
        'py',
      ]);
      expect(_streamCalls.last.arguments, <String>['-3', '-u', 'build.py']);
    });

    test('流式 fetch：--progress 逐行转发且失败异常携带 \\r 分隔后的尾部', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      Directory(joinPath(targetPath, '.git')).createSync(recursive: true);
      final List<String> lines = <String>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
          streamRunner: _streamingRunner((_StreamCall call) async {
            expect(call.executable, 'git');
            return _fakeProcess(
              stdout: 'remote: Total 8 (delta 0)\r',
              stderr:
                  'Receiving objects:  50% (4/8)\r'
                  'fatal: unable to access repository\n',
              exitCode: 1,
            );
          }),
          onOutput: lines.add,
          cacheRoot: cacheRoot,
        ),
        throwsA(
          _buildException(
            '拉取源码失败（退出码 1）',
            outputTail: allOf(
              contains('Receiving objects:  50% (4/8)'),
              contains('fatal: unable to access repository'),
            ),
          ),
        ),
      );

      expect(_streamCalls, hasLength(1));
      expect(_streamCalls.single.arguments, <String>['fetch', '--progress']);
      expect(lines, <String>[
        'remote: Total 8 (delta 0)',
        'Receiving objects:  50% (4/8)',
        'fatal: unable to access repository',
      ]);
    });

    test('runPackBuildStreaming 默认流式转发 git 与 python 输出', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# url\n');
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<String> lines = <String>[];

      await runPackBuildStreaming(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(
          <_ProcessCall>[],
          (_) async => fail('不应调用收集式执行器'),
        ),
        streamRunner: _streamingRunner(
          (_StreamCall call) async => _fakeProcess(stdout: 'streamed\n'),
        ),
        onOutput: lines.add,
        cacheRoot: cacheRoot,
      );

      expect(lines, <String>['streamed', 'streamed']);
      expect(_streamCalls.map((_StreamCall call) => call.executable), <String>[
        'git',
        'python',
      ]);
      expect(_streamCalls.last.arguments, <String>['-u', 'build.py']);
    });
  });

  group('源码版本记录', () {
    test('describe 命中最近 tag 时回调版本', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<String> versions = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (call) async {
          if (call.arguments.first == 'describe') {
            return ProcessResult(1, 0, 'v1.2.3\n', '');
          }
          return _success();
        }),
        onSourceVersion: versions.add,
        cacheRoot: cacheRoot,
      );

      expect(versions, <String>['v1.2.3']);
      final _ProcessCall describe = calls.firstWhere(
        (_ProcessCall call) => call.arguments.first == 'describe',
      );
      expect(describe.arguments, <String>['describe', '--tags', '--abbrev=0']);
      expect(describe.workingDirectory, targetPath);
      expect(describe.environment, <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
      });
      expect(
        calls.where((_ProcessCall call) => call.arguments.first == 'rev-parse'),
        isEmpty,
      );
    });

    test('describe 失败时回退短哈希', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<String> versions = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (call) async {
          if (call.arguments.first == 'describe') {
            return ProcessResult(1, 128, '', 'fatal: no names found\n');
          }
          if (call.arguments.first == 'rev-parse') {
            return ProcessResult(1, 0, 'abc1234\n', '');
          }
          return _success();
        }),
        onSourceVersion: versions.add,
        cacheRoot: cacheRoot,
      );

      expect(versions, <String>['abc1234']);
      final _ProcessCall head = calls.firstWhere(
        (_ProcessCall call) => call.arguments.first == 'rev-parse',
      );
      expect(head.arguments, <String>['rev-parse', '--short', 'HEAD']);
    });

    test('describe 抛异常时回退短哈希', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<String> versions = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(<_ProcessCall>[], (call) async {
          if (call.arguments.first == 'describe') {
            throw ProcessException('git', call.arguments, 'not found');
          }
          if (call.arguments.first == 'rev-parse') {
            return ProcessResult(1, 0, 'deadbee', '');
          }
          return _success();
        }),
        onSourceVersion: versions.add,
        cacheRoot: cacheRoot,
      );

      expect(versions, <String>['deadbee']);
    });

    test('两种查询均失败时静默且构建继续', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<String> versions = <String>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        stages.add,
        processRunner: _runner(calls, (call) async {
          if (call.arguments.first == 'describe' ||
              call.arguments.first == 'rev-parse') {
            return ProcessResult(1, 128, '', 'fatal\n');
          }
          return _success();
        }),
        onSourceVersion: versions.add,
        cacheRoot: cacheRoot,
      );

      expect(versions, isEmpty);
      expect(stages, <PackBuildStage>[
        PackBuildStage.downloading,
        PackBuildStage.building,
      ]);
    });

    test('# source: none 不查询版本', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/openvinotoolkit/openvino.git\n'
        '# source: none\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<String> versions = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        onSourceVersion: versions.add,
        cacheRoot: cacheRoot,
      );

      expect(versions, isEmpty);
      expect(
        calls.where((_ProcessCall call) => call.executable == 'git'),
        isEmpty,
      );
      expect(calls, hasLength(1));
      expect(calls.single.executable, 'python');
    });

    test('未提供回调时不产生额外 git 调用', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(calls, hasLength(2));
      expect(calls[0].arguments.first, 'clone');
      expect(calls[1].executable, 'python');
    });
  });
}

PackModel _pack({String? sourcePath, List<FileModel>? files}) {
  return PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      sourcePath: sourcePath,
    )
    ..files =
        files ??
        <FileModel>[FileModel(name: 'build.py', path: 'build.py', size: 10)];
}

Directory _tempDirectory() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'cpp_nuget_pack_build_',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

/// 源目录骨架：`build.py` 写入指定内容，另附白名单图标 / 许可证供清理用例断言。
String _createSource(Directory root, String scriptContent) {
  final String sourcePath = joinPath(root.path, 'src');
  Directory(sourcePath).createSync(recursive: true);
  File(joinPath(sourcePath, 'build.py')).writeAsStringSync(scriptContent);
  File(joinPath(sourcePath, 'icon.png')).writeAsStringSync('png');
  File(joinPath(sourcePath, 'LICENSE')).writeAsStringSync('license');
  return sourcePath;
}

ProcessResult _success() => ProcessResult(1, 0, '', '');

PackStreamingProcessRunner _streamingRunner(_FakeProcessHandler handler) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    final _StreamCall call = (
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    _streamCalls.add(call);
    return handler(call);
  };
}

final List<_StreamCall> _streamCalls = <_StreamCall>[];

_FakeProcess _fakeProcess({
  String stdout = '',
  String stderr = '',
  int exitCode = 0,
}) {
  return _FakeProcess(stdout: stdout, stderr: stderr, exitCode: exitCode);
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

Matcher _buildException(String message, {Matcher? outputTail}) {
  final TypeMatcher<PackBuildException> matcher = isA<PackBuildException>()
      .having((PackBuildException error) => error.message, 'message', message);
  if (outputTail == null) {
    return matcher;
  }
  return matcher.having(
    (PackBuildException error) => error.outputTail,
    'outputTail',
    outputTail,
  );
}
