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
    int exitCode = 0,
  }) : this.raw(
         stdoutBytes: utf8.encode(stdout),
         stderrBytes: utf8.encode(stderr),
         exitCode: exitCode,
       );

  /// 直接指定原始字节的变体，用于覆盖非 UTF-8 输出（如中文 Windows 的 GBK）。
  _FakeProcess.raw({
    required List<int> stdoutBytes,
    required List<int> stderrBytes,
    this._exitCode = 0,
  }) : stdout = _FakeStream(stdoutBytes),
       stderr = _FakeStream(stderrBytes);

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
  _FakeStream(this.bytes);

  final List<int> bytes;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

void main() {
  setUp(_streamCalls.clear);
  final Object? pythonSkipReason = _pythonSkipReason();

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
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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

    test('build.py 首行缺少源码声明时抛错', () async {
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
        throwsA(_buildExceptionMatcher(contains('build.py 首行缺少源码声明'))),
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
        throwsA(_buildExceptionMatcher(contains('build.py 首行缺少源码声明'))),
      );

      expect(calls, isEmpty);
    });

    test('首行为旧式仓库地址（裸 URL）时按缺少声明抛错', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# https://github.com/foo/bar.git\n# profile: v1\n',
      );
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
          _buildExceptionMatcher(
            allOf(
              contains('build.py 首行缺少源码声明'),
              contains('# source: <包内相对目录>'),
              contains('# source: none'),
            ),
          ),
        ),
      );

      expect(stages, isEmpty);
      expect(calls, isEmpty);
    });

    test('build.py 缺少 Profile 声明时前置失败（无进程/无阶段/不清源目录/不建缓存）', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# source: .cnp-src\n');
      final String stalePath = joinPath(sourcePath, 'stale.txt');
      File(stalePath).writeAsStringSync('stale');
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: cacheRoot,
        ),
        throwsA(
          isA<PackBuildException>().having(
            (PackBuildException error) => error.message,
            'message',
            allOf(contains('缺少 Profile 声明'), contains('# profile: v1')),
          ),
        ),
      );

      expect(stages, isEmpty, reason: 'Profile 校验在下载阶段回调之前');
      expect(calls, isEmpty, reason: 'Profile 校验在 git/python 执行之前');
      expect(
        File(stalePath).existsSync(),
        isTrue,
        reason: 'Profile 校验在源目录清理之前',
      );
      expect(
        Directory(joinPath(cacheRoot, 'build')).existsSync(),
        isFalse,
        reason: 'Profile 校验在缓存目录创建之前',
      );
    });
  });

  group('预置源码（# source: <dir>）', () {
    test('整树拷入 SRC_PATH：内容一致、嵌套目录与空目录均保留', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: .cnp-src\n# profile: v1\nprint(1)\n',
      );
      _createPresetSource(sourcePath, <String, String>{
        'main.cpp': 'int main() {}',
        r'include\zlib.h': '#pragma once',
      });
      Directory(joinPath(sourcePath, '.cnp-src/empty'))
          .createSync(recursive: true);
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
        PackBuildStage.staging,
        PackBuildStage.building,
      ]);
      expect(calls, hasLength(1), reason: '预置源码配方不执行任何 git 命令');
      expect(calls.single.executable, 'python');
      expect(
        File(joinPath(targetPath, 'main.cpp')).readAsStringSync(),
        'int main() {}',
      );
      expect(
        File(joinPath(targetPath, 'include/zlib.h')).readAsStringSync(),
        '#pragma once',
      );
      expect(
        Directory(joinPath(targetPath, 'empty')).existsSync(),
        isTrue,
        reason: '空目录一并复制，保持树形结构',
      );
      expect(
        calls.single.environment!['SRC_PATH'],
        Directory(targetPath).absolute.path,
      );
    });

    test('目录声明为多级子目录时按相对路径解析', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: vendor/zlib\n# profile: v1\n',
      );
      Directory(joinPath(sourcePath, 'vendor/zlib'))
          .createSync(recursive: true);
      File(joinPath(sourcePath, 'vendor/zlib/zlib.h')).writeAsStringSync('z');
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(File(joinPath(targetPath, 'zlib.h')).existsSync(), isTrue);
    });

    test('每次构建重置缓存：上次构建的残留文件消失', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: .cnp-src\n# profile: v1\n',
      );
      _createPresetSource(sourcePath, <String, String>{'main.cpp': 'v1'});
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final File residual = File(joinPath(targetPath, 'residual.txt'))
        ..createSync(recursive: true);
      residual.writeAsStringSync('residual');

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(residual.existsSync(), isFalse, reason: '预置源码配方每次构建重置缓存');
      expect(File(joinPath(targetPath, 'main.cpp')).readAsStringSync(), 'v1');
    });

    test('预置源码目录不存在时抛错且不建缓存、不清源目录', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: .cnp-src\n# profile: v1\n',
      );
      final String stalePath = joinPath(sourcePath, 'stale.txt');
      File(stalePath).writeAsStringSync('stale');
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(calls, (_) async => _success()),
          cacheRoot: cacheRoot,
        ),
        throwsA(
          isA<PackBuildException>().having(
            (PackBuildException error) => error.message,
            'message',
            allOf(
              contains('找不到包内预置源码目录'),
              contains(joinPath(sourcePath, '.cnp-src')),
              contains('# source: .cnp-src'),
            ),
          ),
        ),
      );

      expect(stages, isEmpty);
      expect(calls, isEmpty);
      expect(File(stalePath).existsSync(), isTrue);
      expect(Directory(joinPath(cacheRoot, 'build')).existsSync(), isFalse);
    });

    test('预置源码目录为空（递归后零文件）时单独报错', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: .cnp-src\n# profile: v1\n',
      );
      Directory(joinPath(sourcePath, '.cnp-src/nested'))
          .createSync(recursive: true);
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
          cacheRoot: cacheRoot,
        ),
        throwsA(
          isA<PackBuildException>().having(
            (PackBuildException error) => error.message,
            'message',
            allOf(
              contains('包内预置源码目录为空'),
              contains(joinPath(sourcePath, '.cnp-src')),
              contains('# source: .cnp-src'),
            ),
          ),
        ),
      );

      expect(stages, isEmpty);
      expect(Directory(joinPath(cacheRoot, 'build')).existsSync(), isFalse);
    });

    test('声明值越界时前置失败（无副作用）', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: ../escape\n# profile: v1\n',
      );
      final String cacheRoot = joinPath(root.path, 'cache');
      final List<PackBuildStage> stages = <PackBuildStage>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          stages.add,
          processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
          cacheRoot: cacheRoot,
        ),
        throwsA(
          isA<PackBuildException>().having(
            (PackBuildException error) => error.message,
            'message',
            allOf(
              contains('build.py 源码目录声明非法'),
              contains('# source: ../escape'),
            ),
          ),
        ),
      );

      expect(stages, isEmpty);
      expect(Directory(joinPath(cacheRoot, 'build')).existsSync(), isFalse);
    });
  });

  group('构建前清理', () {
    test('清理先于 build.py 执行：白名单保留、其余文件删除', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
      File(joinPath(sourcePath, 'stale.txt')).writeAsStringSync('stale');
      Directory(joinPath(sourcePath, 'build-release'))
          .createSync(recursive: true);
      File(joinPath(sourcePath, 'build-release/CMakeCache.txt'))
          .writeAsStringSync('x');
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

      expect(calls, hasLength(1));
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
        '# source: none\n# profile: v1\n',
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

      expect(stages, <PackBuildStage>[PackBuildStage.staging]);
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
        '# source: none\n# profile: v1\n',
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

      final String resolved = calls
          .firstWhere((_ProcessCall call) => call.executable == 'python')
          .environment!['SRC_PATH']!;
      expect(
        resolved.replaceAll('/', r'\'),
        joinPath(root.path, 'cache/build/demo').replaceAll('/', r'\'),
        reason: '相对 cacheRoot 以工作目录为基准解析为同一绝对路径',
      );
      expect(calls, hasLength(2), reason: '两次构建各含一次构建脚本执行');
    });
  });

  group('预构建（# source: none）', () {
    test('跳过 git：仅创建缓存目录并注入 SRC_PATH 执行构建', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n'
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
        PackBuildStage.staging,
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
        'PYTHONIOENCODING': 'utf-8',
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
        '# source: none\n# profile: v1\n',
      );
      File(joinPath(sourcePath, 'stale.txt')).writeAsStringSync('stale');
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      // 第一次构建后写入脚本下载/解压产物，作为第二次构建前已存在的缓存。
      File(joinPath(targetPath, 'downloads/openvino.zip'))
          .createSync(recursive: true);
      File(joinPath(targetPath, 'unpacked/.complete'))
          .createSync(recursive: true);
      expect(
        File(joinPath(sourcePath, 'build.py')).readAsStringSync(),
        startsWith('# source: none'),
      );

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(calls, hasLength(2));
      expect(
        calls.every((_ProcessCall call) => call.executable == 'python'),
        isTrue,
      );
      expect(
        File(joinPath(targetPath, 'downloads/openvino.zip')).existsSync(),
        isTrue,
        reason: 'source: none 缓存目录（downloads）跨构建保留',
      );
      expect(
        File(joinPath(targetPath, 'unpacked/.complete')).existsSync(),
        isTrue,
        reason: 'source: none 缓存目录（unpacked）跨构建保留',
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
        '# source: none\n# profile: v1\n',
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
        'PYTHONIOENCODING': 'utf-8',
      });
    });
  });

  group('执行构建', () {
    test('python 不可用时回退 py -3', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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
        PackBuildStage.staging,
        PackBuildStage.building,
      ]);
      expect(calls, hasLength(2));
      expect(calls[0].executable, 'python');
      expect(calls[1].executable, 'py');
      expect(calls[1].arguments, <String>['-3', '-u', 'build.py']);
      expect(calls[1].workingDirectory, sourcePath);
      expect(calls[1].environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('python 与 py 均不可用时抛出未找到 Python', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(calls, (call) async {
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

      expect(calls, hasLength(2));
    });

    test('构建非零退出时异常携带合并输出末尾 20 行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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
            (call) async => ProcessResult(1, 3, stdout, 'err-line'),
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
    test('注入的子进程环境透传到构建脚本调用', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
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

      expect(calls, hasLength(1));
      expect(calls.single.environment, <String, String>{
        ...injected,
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('未注入环境（null）时沿用既有内建变量', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
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

      expect(calls, hasLength(1));
      expect(calls.single.environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('注入的同名变量不覆盖必需变量', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
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
          'SRC_PATH': r'D:\bogus',
          'BUILD_OUT': r'D:\bogus',
          'PYTHONIOENCODING': 'gbk',
        },
      );

      expect(calls, hasLength(1));
      expect(calls.single.environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('python 回退 py 时同样携带注入环境', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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

      expect(calls, hasLength(2));
      expect(calls.last.executable, 'py');
      expect(calls.last.environment, <String, String>{
        ...injected,
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
        'PYTHONIOENCODING': 'utf-8',
      });
    });
  });

  group('流式输出', () {
    test('流式构建非零退出时异常携带合并输出末尾 20 行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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

      expect(lines, hasLength(26), reason: '25 行 stdout + 1 行 stderr 都经回调转发');
    });

    test('注入流式执行器且回调非空时构建脚本逐行转发并转发环境', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: .cnp-src\n# profile: v1\n',
      );
      _createPresetSource(sourcePath, <String, String>{'main.cpp': 'v1'});
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
        streamRunner: _streamingRunner(
          (_StreamCall call) async =>
              _fakeProcess(stdout: 'line1\nline2\n', stderr: 'warn1\n'),
        ),
        onOutput: lines.add,
        cacheRoot: cacheRoot,
        environment: injected,
      );

      expect(lines, <String>['line1', 'line2', 'warn1']);
      expect(calls, isEmpty, reason: '注入流式执行器时构建脚本走流式');

      expect(_streamCalls, hasLength(1));
      final _StreamCall stream = _streamCalls.single;
      expect(stream.executable, 'python');
      expect(stream.arguments, <String>['-u', 'build.py']);
      expect(stream.workingDirectory, sourcePath);
      expect(stream.environment, <String, String>{
        ...injected,
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('未提供流式执行器时 onOutput 静默降级为一次性捕获', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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
          return _fakeProcess(stdout: 'fallback done\n');
        }),
        onOutput: lines.add,
        cacheRoot: cacheRoot,
      );

      expect(lines, <String>['fallback done']);
      expect(_streamCalls.map((_StreamCall call) => call.executable), <String>[
        'python',
        'py',
      ]);
      expect(_streamCalls.last.arguments, <String>['-3', '-u', 'build.py']);
    });

    test('runPackBuildStreaming 默认流式转发构建脚本输出', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
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

      expect(lines, <String>['streamed']);
      expect(_streamCalls.map((_StreamCall call) => call.executable), <String>[
        'python',
      ]);
      expect(_streamCalls.last.arguments, <String>['-u', 'build.py']);
    });

    test('无效 UTF-8 字节（GBK 中文）经流式收集不抛异常且不丢行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
      final List<String> lines = <String>[];
      // GBK 编码的「中文」+ 合法 UTF-8 行：0xD6/0xD0/0xCE/0xC4 不构成合法 UTF-8。
      final List<int> stdoutBytes = <int>[
        0xD6,
        0xD0,
        0xCE,
        0xC4,
        0x0A,
        ...utf8.encode('line-after-invalid\n'),
      ];
      final List<int> stderrBytes = <int>[
        ...utf8.encode('错误: '),
        0xBA,
        0xF3,
        0x0A,
        ...utf8.encode('tail-line\n'),
      ];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
        streamRunner: _streamingRunner(
          (_StreamCall call) async => _FakeProcess.raw(
            stdoutBytes: stdoutBytes,
            stderrBytes: stderrBytes,
          ),
        ),
        onOutput: lines.add,
        cacheRoot: joinPath(root.path, 'cache'),
      );

      expect(lines, hasLength(4), reason: '无效字节行按替换字符保留，行数不丢');
      expect(
        lines[0],
        contains('\uFFFD'),
        reason: '无效字节解码为替换字符而非抛 FormatException',
      );
      expect(lines[1], 'line-after-invalid');
      expect(lines[2], contains('错误: '));
      expect(lines[3], 'tail-line');
    });

    test('失败输出尾部含无效 UTF-8 字节时不抛异常且保留可读行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n',
      );
      final List<String> lines = <String>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          (_) {},
          processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
          streamRunner: _streamingRunner(
            (_StreamCall call) async => _FakeProcess.raw(
              stdoutBytes: <int>[
                ...utf8.encode('readable-line\n'),
                0xD6,
                0xD0,
                0xCE,
                0xC4,
                0x0A,
                ...utf8.encode('中文错误：编译失败\n'),
              ],
              stderrBytes: <int>[],
              exitCode: 3,
            ),
          ),
          onOutput: lines.add,
          cacheRoot: joinPath(root.path, 'cache'),
        ),
        throwsA(
          _buildException(
            '构建失败（退出码 3）',
            outputTail: allOf(
              contains('readable-line'),
              contains('中文错误：编译失败'),
              contains('\uFFFD'),
            ),
          ),
        ),
      );

      expect(lines, hasLength(3), reason: '无效字节行不丢失（替换字符保留行位）');
    });
  });

  group('真实进程流式编码（仅 Windows + Python）', () {
    test('中文 stdout/stderr 经生产流式路径按 UTF-8 解码且无替换字符', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n'
        "import sys\n"
        "print('中文输出：构建开始')\n"
        "print('中文错误：诊断信息', file=sys.stderr)\n",
      );
      final List<String> lines = <String>[];

      await runPackBuildStreaming(
        _pack(sourcePath: sourcePath),
        (_) {},
        cacheRoot: joinPath(root.path, 'cache'),
        onOutput: lines.add,
      );

      // ignore: avoid_print
      print('[evidence] pythonLines=$lines');
      expect(lines, contains('中文输出：构建开始'));
      expect(lines, contains('中文错误：诊断信息'));
      expect(
        lines.where((String line) => line.contains('\uFFFD')),
        isEmpty,
        reason: 'PYTHONIOENCODING=utf-8 + 容错解码后不应出现替换字符',
      );
    }, skip: pythonSkipReason);

    test('中文失败诊断经生产流式路径保留到异常输出尾部', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(
        root,
        '# source: none\n# profile: v1\n'
        "import sys\n"
        "print('开始构建')\n"
        "print('中文错误：编译失败', file=sys.stderr)\n"
        "sys.exit(3)\n",
      );
      final List<String> lines = <String>[];

      await expectLater(
        runPackBuildStreaming(
          _pack(sourcePath: sourcePath),
          (_) {},
          cacheRoot: joinPath(root.path, 'cache'),
          onOutput: lines.add,
        ),
        throwsA(
          _buildException(
            '构建失败（退出码 3）',
            outputTail: allOf(
              contains('开始构建'),
              contains('中文错误：编译失败'),
              isNot(contains('\uFFFD')),
            ),
          ),
        ),
      );

      expect(lines, contains('中文错误：编译失败'));
    }, skip: pythonSkipReason);
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

/// 真实进程测试的跳过原因（与 build_support_module_test 口径一致）：
/// 非 Windows 或无可用 Python（`python` / `py -3`）时返回文案，否则 null。
Object? _pythonSkipReason() {
  if (!Platform.isWindows) {
    return '仅 Windows 平台执行（依赖真实 Python 进程）';
  }
  for (final List<String> candidate in <List<String>>[
    <String>['python'],
    <String>['py', '-3'],
  ]) {
    try {
      final ProcessResult result = Process.runSync(candidate.first, <String>[
        ...candidate.sublist(1),
        '--version',
      ]);
      if (result.exitCode == 0) {
        return null;
      }
    } on ProcessException {
      // 当前候选不可用，继续探测下一个。
    }
  }
  return '未检测到可用的 Python（python / py -3 均不可用）';
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

/// 在包源目录下建 `.cnp-src` 预置源码目录（键为相对路径，分隔符正反皆可）。
void _createPresetSource(String sourcePath, Map<String, String> files) {
  for (final MapEntry<String, String> entry in files.entries) {
    final File file = File(
      joinPath(joinPath(sourcePath, '.cnp-src'), entry.key),
    )..createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
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

/// [message] 允许子串/正则等 Matcher（错误信息含可变路径时使用）。
Matcher _buildExceptionMatcher(Object message, {Matcher? outputTail}) {
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
