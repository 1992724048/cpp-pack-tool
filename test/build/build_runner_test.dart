import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
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

  group('单段流水线', () {
    test('构建前清空 .cache/tmp，不复制任何源码到别处', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      File(
          joinPath(
            joinPath(joinPath(sourcePath, '.cache'), 'tmp'),
            'stale.obj',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      File(joinPath(joinPath(joinPath(sourcePath, '.cache'), 'src'), 'keep.a'))
        ..createSync(recursive: true)
        ..writeAsStringSync('keep');
      final Map<String, String> seen = <String, String>{};

      await runPackBuildStreaming(
        _pack(sourcePath: sourcePath),
        streamRunner: _streamingRunner((_StreamCall call) async {
          seen.addAll(call.environment ?? const <String, String>{});
          return _fakeProcess();
        }),
      );

      expect(seen.containsKey('SRC_PATH'), isFalse, reason: '不再下发 SRC_PATH');
      expect(seen.containsKey('BUILD_OUT'), isFalse, reason: '不再下发 BUILD_OUT');
      expect(
        File(
          joinPath(
            joinPath(joinPath(sourcePath, '.cache'), 'tmp'),
            'stale.obj',
          ),
        ).existsSync(),
        isFalse,
        reason: '构建前清空 .cache/tmp',
      );
      expect(
        File(
          joinPath(joinPath(joinPath(sourcePath, '.cache'), 'src'), 'keep.a'),
        ).existsSync(),
        isTrue,
        reason: '只清 tmp，.cache/src 归配方自己管、跨构建保留',
      );
      expect(
        root.listSync().map((FileSystemEntity entity) => baseName(entity.path)),
        <String>['src'],
        reason: '包源目录之外不再落任何备源工作区',
      );
    });

    test('工作目录就是包源目录，配方相对路径无需任何前缀', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      String? workingDirectory;

      await runPackBuildStreaming(
        _pack(sourcePath: sourcePath),
        streamRunner: _streamingRunner((_StreamCall call) async {
          workingDirectory = call.workingDirectory;
          return _fakeProcess();
        }),
      );

      expect(workingDirectory, Directory(sourcePath).absolute.path);
    });

    test('环境里带 CNP_PACKAGE_ROOT / CNP_SRC_DIR / CNP_TMP_DIR / CNP_TOOLS_DIR / CNP_COMPILER', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final Map<String, String> contract = <String, String>{
        'CNP_PACKAGE_ROOT': sourcePath,
        'CNP_SRC_DIR': packSourceDirectory(sourcePath),
        'CNP_TMP_DIR': packTmpDirectory(sourcePath),
        'CNP_TOOLS_DIR': r'D:\tools',
        'CNP_COMPILER': r'C:\tools\icx-cl.exe',
      };
      Map<String, String>? seen;

      await runPackBuildStreaming(
        _pack(sourcePath: sourcePath),
        streamRunner: _streamingRunner((_StreamCall call) async {
          seen = call.environment;
          return _fakeProcess();
        }),
        environment: contract,
      );

      expect(seen, <String, String>{...contract, 'PYTHONIOENCODING': 'utf-8'});
    });
  });

  group('前置校验', () {
    test('缺少源目录信息时抛错且不执行进程', () async {
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(),
          processRunner: _runner(calls, (_) async => _success()),
        ),
        throwsA(_buildException('该包缺少源目录信息')),
      );

      expect(calls, isEmpty);
    });

    test('包内无 build.py 时抛错', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# 配方说明\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath, files: <FileModel>[]),
          processRunner: _runner(calls, (_) async => _success()),
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
          processRunner: _runner(calls, (_) async => _success()),
        ),
        throwsA(_buildException('源目录中找不到 build.py（可能已被移动）')),
      );

      expect(calls, isEmpty);
    });
  });

  group('清理中间产物失败', () {
    test('.cache/tmp 被占用时抛错且不执行构建脚本', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final File locked = File(
        joinPath(joinPath(joinPath(sourcePath, '.cache'), 'tmp'), 'locked.dat'),
      )..createSync(recursive: true);
      locked.writeAsStringSync('busy');
      final RandomAccessFile handle = locked.openSync(mode: FileMode.append);
      addTearDown(handle.closeSync);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          processRunner: _runner(calls, (_) async => _success()),
        ),
        throwsA(
          isA<PackBuildException>().having(
            (PackBuildException error) => error.message,
            'message',
            contains('清空中间产物目录失败'),
          ),
        ),
      );

      expect(
        calls.where((_ProcessCall call) => call.executable == 'python'),
        isEmpty,
        reason: 'tmp 清不掉就不得在脏目录上构建',
      );
    });
  });

  group('执行构建', () {
    test('以 python -u build.py 在包源目录中执行，环境只附加 PYTHONIOENCODING', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(calls, (_) async => _success()),
      );

      expect(calls, hasLength(1));
      final _ProcessCall python = calls.single;
      expect(python.executable, 'python');
      expect(python.arguments, <String>['-u', 'build.py']);
      expect(python.workingDirectory, sourcePath);
      expect(python.environment, <String, String>{'PYTHONIOENCODING': 'utf-8'});
      expect(
        root.listSync().map((FileSystemEntity entity) => baseName(entity.path)),
        <String>['src'],
        reason: '除包源目录外不落任何东西',
      );
    });

    test('python 不可用时回退 py -3', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(calls, (call) async {
          if (call.executable == 'python') {
            throw ProcessException('python', <String>['build.py'], 'not found');
          }
          return _success();
        }),
      );

      expect(calls, hasLength(2));
      expect(calls[0].executable, 'python');
      expect(calls[1].executable, 'py');
      expect(calls[1].arguments, <String>['-3', '-u', 'build.py']);
      expect(calls[1].workingDirectory, sourcePath);
      expect(calls[1].environment, <String, String>{
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('python 与 py 均不可用时抛出未找到 Python', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          processRunner: _runner(calls, (call) async {
            throw ProcessException(
              call.executable,
              call.arguments,
              'not found',
            );
          }),
        ),
        throwsA(_buildException('未找到 Python（python / py），无法执行构建')),
      );

      expect(calls, hasLength(2));
    });

    test('构建非零退出时异常携带合并输出末尾 20 行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# 配方说明\n');
      final String stdout = <String>[
        for (int index = 1; index <= 25; index++)
          'line${index.toString().padLeft(2, '0')}',
      ].join('\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          processRunner: _runner(
            calls,
            (call) async => ProcessResult(1, 3, stdout, 'err-line'),
          ),
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
      final String sourcePath = _createSource(root, _echoBuilder());
      final Map<String, String> injected = <String, String>{
        'CNP_COMPILER': r'C:\tools\icx-cl.exe',
        'CNP_TOOLS_DIR': r'D:\tools',
        'PATH': r'D:\tools\ninja;D:\tools\cmake\bin',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(calls, (_) async => _success()),
        environment: injected,
      );

      expect(calls, hasLength(1));
      expect(calls.single.environment, <String, String>{
        ...injected,
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('未注入环境（null）时沿用既有内建变量', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(calls, (_) async => _success()),
      );

      expect(calls, hasLength(1));
      expect(calls.single.environment, <String, String>{
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('注入的 PYTHONIOENCODING 被覆盖，其余注入变量原样透传', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(calls, (_) async => _success()),
        environment: <String, String>{
          'PYTHONIOENCODING': 'gbk',
          'CNP_TMP_DIR': r'D:\bogus',
        },
      );

      expect(calls, hasLength(1));
      expect(calls.single.environment, <String, String>{
        'PYTHONIOENCODING': 'utf-8',
        'CNP_TMP_DIR': r'D:\bogus',
      });
    });

    test('python 回退 py 时同样携带注入环境', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, _echoBuilder());
      final Map<String, String> injected = <String, String>{
        'CNP_CMAKE': r'D:\tools\cmake\bin\cmake.exe',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(calls, (call) async {
          if (call.executable == 'python') {
            throw ProcessException('python', <String>['build.py'], 'not found');
          }
          return _success();
        }),
        environment: injected,
      );

      expect(calls, hasLength(2));
      expect(calls.last.executable, 'py');
      expect(calls.last.environment, <String, String>{
        ...injected,
        'PYTHONIOENCODING': 'utf-8',
      });
    });
  });

  group('流式输出', () {
    test('流式构建非零退出时异常携带合并输出末尾 20 行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# 配方说明\n');
      final String stdout = <String>[
        for (int index = 1; index <= 25; index++)
          'line${index.toString().padLeft(2, '0')}',
      ].join('\n');
      final List<String> lines = <String>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
          processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
          streamRunner: _streamingRunner((_StreamCall call) async {
            return _fakeProcess(
              stdout: '$stdout\n',
              stderr: 'err-line\n',
              exitCode: 3,
            );
          }),
          onOutput: lines.add,
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
      final String sourcePath = _createSource(root, _echoBuilder());
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final List<String> lines = <String>[];
      final Map<String, String> injected = <String, String>{
        'CNP_TOOLS_DIR': r'D:\tools',
      };

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(calls, (_) async => _success()),
        streamRunner: _streamingRunner(
          (_StreamCall call) async =>
              _fakeProcess(stdout: 'line1\nline2\n', stderr: 'warn1\n'),
        ),
        onOutput: lines.add,
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
        'PYTHONIOENCODING': 'utf-8',
      });
    });

    test('未提供流式执行器时 onOutput 静默降级为一次性捕获', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# 配方说明\n');
      final List<String> lines = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(
          <_ProcessCall>[],
          (_) async => ProcessResult(1, 0, 'done\n', ''),
        ),
        onOutput: lines.add,
      );

      expect(lines, isEmpty);
    });

    test('流式 python 不可用时回退 py -3 并同样转发输出', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# 配方说明\n');
      final List<String> lines = <String>[];

      await runPackBuild(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
        streamRunner: _streamingRunner((_StreamCall call) async {
          if (call.executable == 'python') {
            throw ProcessException('python', <String>['build.py'], 'not found');
          }
          return _fakeProcess(stdout: 'fallback done\n');
        }),
        onOutput: lines.add,
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
      final String sourcePath = _createSource(root, '# 配方说明\n');
      final List<String> lines = <String>[];

      await runPackBuildStreaming(
        _pack(sourcePath: sourcePath),
        processRunner: _runner(
          <_ProcessCall>[],
          (_) async => fail('不应调用收集式执行器'),
        ),
        streamRunner: _streamingRunner(
          (_StreamCall call) async => _fakeProcess(stdout: 'streamed\n'),
        ),
        onOutput: lines.add,
      );

      expect(lines, <String>['streamed']);
      expect(_streamCalls.map((_StreamCall call) => call.executable), <String>[
        'python',
      ]);
      expect(_streamCalls.last.arguments, <String>['-u', 'build.py']);
    });

    test('无效 UTF-8 字节（GBK 中文）经流式收集不抛异常且不丢行', () async {
      final Directory root = _tempDirectory();
      final String sourcePath = _createSource(root, '# 配方说明\n');
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
        processRunner: _runner(<_ProcessCall>[], (_) async => _success()),
        streamRunner: _streamingRunner(
          (_StreamCall call) async => _FakeProcess.raw(
            stdoutBytes: stdoutBytes,
            stderrBytes: stderrBytes,
          ),
        ),
        onOutput: lines.add,
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
      final String sourcePath = _createSource(root, '# 配方说明\n');
      final List<String> lines = <String>[];

      await expectLater(
        runPackBuild(
          _pack(sourcePath: sourcePath),
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
        '# 配方说明\n'
        "import sys\n"
        "print('中文输出：构建开始')\n"
        "print('中文错误：诊断信息', file=sys.stderr)\n",
      );
      final List<String> lines = <String>[];

      await runPackBuildStreaming(
        _pack(sourcePath: sourcePath),
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
        '# 配方说明\n'
        "import sys\n"
        "print('开始构建')\n"
        "print('中文错误：编译失败', file=sys.stderr)\n"
        "sys.exit(3)\n",
      );
      final List<String> lines = <String>[];

      await expectLater(
        runPackBuildStreaming(
          _pack(sourcePath: sourcePath),
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

/// 只回一行输出的配方（构建流水线不关心脚本内容，只关心怎么被调起来）。
String _echoBuilder() => "print('build ok')\n";

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
