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

void main() {
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
        'https://github.com/foo/bar.git',
        targetPath,
      ]);
      expect(clone.workingDirectory, isNull);
      expect(clone.environment, <String, String>{'GIT_TERMINAL_PROMPT': '0'});

      final _ProcessCall python = calls[1];
      expect(python.executable, 'python');
      expect(python.arguments, <String>['build.py']);
      expect(python.workingDirectory, sourcePath);
      expect(python.environment, <String, String>{
        'SRC_PATH': Directory(targetPath).absolute.path,
        'BUILD_OUT': Directory(sourcePath).absolute.path,
      });
    });

    test('.git 存在时执行 git pull --ff-only 且保留目录内容', () async {
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

      expect(calls, hasLength(2));
      expect(calls[0].executable, 'git');
      expect(calls[0].arguments, <String>['pull', '--ff-only']);
      expect(calls[0].workingDirectory, targetPath);
      expect(calls[0].environment, <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
      });
      expect(File(joinPath(targetPath, 'keep.txt')).existsSync(), isTrue);
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

    test('拉取失败时抛出异常且不执行构建', () async {
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
      expect(python.arguments, <String>['build.py']);
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
      final String cacheRoot = joinPath(root.path, 'cache');
      final String targetPath = joinPath(cacheRoot, 'build/demo');
      Directory(targetPath).createSync(recursive: true);
      File(joinPath(targetPath, 'downloads.zip')).writeAsStringSync('cached');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        (_) {},
        processRunner: _runner(calls, (_) async => _success()),
        cacheRoot: cacheRoot,
      );

      expect(calls, hasLength(1));
      expect(calls.single.executable, 'python');
      expect(File(joinPath(targetPath, 'downloads.zip')).existsSync(), isTrue);
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
      expect(calls[2].arguments, <String>['-3', 'build.py']);
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

String _createSource(Directory root, String scriptContent) {
  final String sourcePath = joinPath(root.path, 'src');
  Directory(sourcePath).createSync(recursive: true);
  File(joinPath(sourcePath, 'build.py')).writeAsStringSync(scriptContent);
  return sourcePath;
}

ProcessResult _success() => ProcessResult(1, 0, '', '');

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
