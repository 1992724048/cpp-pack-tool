// ignore_for_file: avoid_print

// 提权重试模块测试：UAC 启动器全部为测试替身，绝不触发真实 UAC 弹窗；
// 真实 cmd/Python 冒烟由 CNP_ELEVATED_LAUNCHER_SMOKE=1 门控（直接运行 launcher，
// 不经 Start-Process，不触发提权）。

import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/elevated_build.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

const String _launcherSmokeSkipReason =
    '设置 CNP_ELEVATED_LAUNCHER_SMOKE=1 运行（真实 cmd.exe + Python 执行 launcher；不触发 UAC）';

void main() {
  group('detectTempPermissionFailure', () {
    test('命中 ICX 临时目录权限失败特征', () {
      expect(
        detectTempPermissionFailure(
          'icx: error #10026: error generating temporary file',
        ),
        isTrue,
      );
      expect(
        detectTempPermissionFailure(
          'icx: error #10030: cannot open internal argument file',
        ),
        isTrue,
      );
      expect(
        detectTempPermissionFailure(
          'ERROR # 10030: cannot open internal '
          'argument file',
        ),
        isTrue,
      );
      expect(detectTempPermissionFailure('Error #10026'), isTrue);
      expect(
        detectTempPermissionFailure(
          'fatal: cannot open internal argument file',
        ),
        isTrue,
      );
      expect(
        detectTempPermissionFailure('icx: error generating temporary file'),
        isTrue,
      );
    });

    test('未命中时不误报（仅命中特征才提供重试入口）', () {
      expect(detectTempPermissionFailure('构建失败（退出码 1）'), isFalse);
      expect(
        detectTempPermissionFailure('error: cannot find file foo.h'),
        isFalse,
      );
      expect(
        detectTempPermissionFailure('error #10025: unknown error'),
        isFalse,
      );
      expect(
        detectTempPermissionFailure('Access is denied.'),
        isFalse,
        reason: '泛化的访问拒绝不构成临时目录权限失败特征',
      );
      expect(detectTempPermissionFailure(''), isFalse);
    });
  });

  group('buildElevatedLauncher', () {
    test('包含代码页切换、CRLF 行尾、环境设置与退出码标记', () {
      final String content = buildElevatedLauncher(
        sourcePath: r'C:\libs\中文 目录',
        scriptRelativePath: 'sub/build.py',
        pythonExecutable: r'C:\tools\python\python.exe',
        environment: <String, String>{
          'TMP': r'C:\100%temp',
          'SRC_PATH': r'C:\cache\build\demo',
          'QUOTED': 'a"b',
        },
        logPath: r'C:\run\elevated_build.log',
        exitCodePath: r'C:\run\elevated_build.exit',
      );

      expect(content, startsWith('@echo off\r\nchcp 65001 >nul 2>&1\r\n'));
      expect(content.contains('中文 目录'), isTrue);
      expect(content.contains('"sub\\build.py"'), isTrue);
      expect(content.contains(r'C:\tools\python\python.exe'), isTrue);
      expect(content.contains(r'set "TMP=C:\100%%temp"'), isTrue);
      expect(content.contains(r'set "QUOTED=ab"'), isTrue);
      expect(
        content.contains(r'echo %ERRORLEVEL% > "C:\run\elevated_build.exit"'),
        isTrue,
      );
      expect(
        content.contains(r'call :main > "C:\run\elevated_build.log" 2>&1'),
        isTrue,
      );
      expect(
        RegExp(r'(?<!\r)\n').hasMatch(content),
        isFalse,
        reason: '批处理文件必须全部使用 CRLF 行尾（cmd 对 LF 行尾会吞字符）',
      );
      expect(RegExp(r'\r(?!\n)').hasMatch(content), isFalse);
    });

    test('py 启动器补 -3 且回退 python；失败回退写在 9009 分支', () {
      final String launcherContent = buildElevatedLauncher(
        sourcePath: r'C:\libs\demo',
        scriptRelativePath: 'build.py',
        pythonExecutable: 'py',
        pythonUsesLauncher: true,
        logPath: r'C:\run\log.txt',
        exitCodePath: r'C:\run\exit.txt',
      );
      expect(launcherContent.contains('"py" -3 -u "build.py"'), isTrue);
      expect(
        launcherContent.contains('if errorlevel 9009 goto :fallback_python'),
        isTrue,
      );
      expect(launcherContent.contains('python -u "build.py"'), isTrue);

      final String pythonFallback = buildElevatedLauncher(
        sourcePath: r'C:\libs\demo',
        scriptRelativePath: 'build.py',
        pythonExecutable: 'python',
        logPath: r'C:\run\log.txt',
        exitCodePath: r'C:\run\exit.txt',
      );
      expect(pythonFallback.contains('"python" -u "build.py"'), isTrue);
      expect(pythonFallback.contains('py -3 -u "build.py"'), isTrue);
    });

    test('cd 失败经 errorlevel 提前退出（不执行构建脚本）', () {
      final String content = buildElevatedLauncher(
        sourcePath: r'C:\missing',
        scriptRelativePath: 'build.py',
        pythonExecutable: 'python',
        logPath: r'C:\run\log.txt',
        exitCodePath: r'C:\run\exit.txt',
      );
      final int cdIndex = content.indexOf('cd /d "C:\\missing"');
      final int guardIndex = content.indexOf(
        'if errorlevel 1 exit /b %ERRORLEVEL%',
        cdIndex,
      );
      final int scriptIndex = content.indexOf('"python" -u "build.py"');
      expect(cdIndex, greaterThan(0));
      expect(guardIndex, greaterThan(cdIndex));
      expect(scriptIndex, greaterThan(guardIndex));
    });
  });

  group('buildElevatedStarterScript', () {
    test('请求 RunAs、以 PID 轮询等待并区分取消退出码', () {
      final String script = buildElevatedStarterScript(r"C:\a'b\launcher.cmd");
      expect(script.contains(r"-Verb RunAs"), isTrue);
      expect(script.contains(r"-PassThru"), isTrue);
      expect(script.contains(r"C:\a''b\launcher.cmd"), isTrue);
      expect(script.contains('GetProcessById'), isTrue);
      expect(script.contains('exit 1223'), isTrue);
      expect(
        script.contains(r'$process.WaitForExit()'),
        isFalse,
        reason: '经 ShellExecute 启动的进程对象退出码不可靠，改用 PID 轮询',
      );
    });
  });

  group('LogTailDecoder', () {
    test('按 \\r\\n / \\r / \\n 切分并保留未终结片段', () {
      final LogTailDecoder decoder = LogTailDecoder();
      expect(decoder.add(utf8.encode('a\r\nb\rc\nd')), <String>['a', 'b', 'c']);
      expect(decoder.flush(), 'd');
      expect(decoder.flush(), isNull);
    });

    test('跨块的不完整 UTF-8 序列不乱码', () {
      final LogTailDecoder decoder = LogTailDecoder();
      final List<int> bytes = utf8.encode('中文行\n');
      expect(decoder.add(bytes.sublist(0, 3)), isEmpty);
      expect(decoder.add(bytes.sublist(3)), <String>['中文行']);
    });

    test('空行与连续分隔符保留为空行', () {
      final LogTailDecoder decoder = LogTailDecoder();
      expect(decoder.add(utf8.encode('a\n\nb')), <String>['a', '']);
      expect(decoder.flush(), 'b');
    });
  });

  group('runElevatedPackBuild', () {
    test('成功：源码准备 → 提权构建 → 日志逐行回调且不抛错', () async {
      final Directory root = await _tempDirectory();
      final List<String> output = <String>[];
      final List<PackBuildStage> stages = <PackBuildStage>[];
      String? receivedVersion;
      Map<String, String>? prepareEnvironment;

      await runElevatedPackBuild(
        _pack(),
        stages.add,
        buildEnvironment: _buildEnvironment(root.path),
        prepareSource:
            (
              PackModel pack,
              void Function(PackBuildStage) onStage, {
              PackProcessRunner processRunner = Process.run,
              PackStreamingProcessRunner? streamRunner,
              void Function(String line)? onOutput,
              void Function(String version)? onSourceVersion,
              String cacheRoot = 'cache',
              Map<String, String>? environment,
            }) async {
              prepareEnvironment = environment;
              onStage(PackBuildStage.downloading);
              onSourceVersion?.call('v3.1.4');
              return PackSourcePreparation(
                sourcePath: r'C:\libs\demo',
                scriptPath: 'build.py',
                target: Directory(r'C:\cache\build\demo'),
              );
            },
        launcherStarter: _starterWriting(
          root,
          logText: 'line-1\r\n中文行\rmore',
          exitCode: '0',
        ),
        pollInterval: const Duration(milliseconds: 1),
        onOutput: output.add,
        onSourceVersion: (String version) => receivedVersion = version,
      );

      expect(stages, <PackBuildStage>[
        PackBuildStage.downloading,
        PackBuildStage.building,
      ]);
      expect(output, <String>['line-1', '中文行', 'more']);
      expect(receivedVersion, 'v3.1.4');
      expect(prepareEnvironment?['TMP'], root.path);

      final File launcher = File(
        joinPath(
          joinPath(root.path, elevatedBuildDirectoryName),
          elevatedBuildLauncherFileName,
        ),
      );
      final String content = await launcher.readAsString();
      expect(content.contains('cd /d "C:\\libs\\demo"'), isTrue);
      expect(content.contains('"python" -u "build.py"'), isTrue);
      expect(content.contains(r'BUILD_OUT=C:\libs\demo'), isTrue);
      expect(content.contains('SRC_PATH='), isTrue);
      expect(content.contains('PYTHONIOENCODING=utf-8'), isTrue);
    });

    test('提权构建非零退出：抛带输出尾部的 PackBuildException', () async {
      final Directory root = await _tempDirectory();
      final List<String> output = <String>[];

      await expectLater(
        runElevatedPackBuild(
          _pack(),
          (_) {},
          buildEnvironment: _buildEnvironment(root.path),
          prepareSource: _fakePrepareSource(),
          launcherStarter: _starterWriting(
            root,
            logText: 'first line\nlast line\n',
            exitCode: '3',
          ),
          pollInterval: const Duration(milliseconds: 1),
          onOutput: output.add,
        ),
        throwsA(
          isA<PackBuildException>()
              .having((e) => e.message, 'message', '以管理员身份构建失败（退出码 3）')
              .having(
                (e) => e.outputTail,
                'outputTail',
                'first line\nlast line',
              ),
        ),
      );
      expect(output, <String>['first line', 'last line']);
    });

    test('UAC 取消：给出明确中文提示且不抛底层异常', () async {
      final Directory root = await _tempDirectory();

      await expectLater(
        runElevatedPackBuild(
          _pack(),
          (_) {},
          buildEnvironment: _buildEnvironment(root.path),
          prepareSource: _fakePrepareSource(),
          launcherStarter:
              (
                String executable,
                List<String> arguments, {
                String? workingDirectory,
                Map<String, String>? environment,
              }) async => ProcessResult(
                1,
                elevationCancelledExitCode,
                '',
                'The operation was canceled by the user.',
              ),
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsA(
          isA<PackBuildException>().having(
            (e) => e.message,
            'message',
            '已取消以管理员身份重试（UAC 授权被拒绝）',
          ),
        ),
      );
    });

    test('启动器无法运行（ProcessException）时报明确错误', () async {
      final Directory root = await _tempDirectory();

      await expectLater(
        runElevatedPackBuild(
          _pack(),
          (_) {},
          buildEnvironment: _buildEnvironment(root.path),
          prepareSource: _fakePrepareSource(),
          launcherStarter:
              (
                String executable,
                List<String> arguments, {
                String? workingDirectory,
                Map<String, String>? environment,
              }) async => throw ProcessException(
                'powershell.exe',
                const <String>[],
                '系统找不到指定的文件',
              ),
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsA(
          isA<PackBuildException>().having(
            (e) => e.message,
            'message',
            contains('无法启动提权构建'),
          ),
        ),
      );
    });

    test('启动器正常退出但未写退出码标记：提示进程可能被强制结束', () async {
      final Directory root = await _tempDirectory();

      await expectLater(
        runElevatedPackBuild(
          _pack(),
          (_) {},
          buildEnvironment: _buildEnvironment(root.path),
          prepareSource: _fakePrepareSource(),
          launcherStarter: (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
            Map<String, String>? environment,
          }) async => ProcessResult(1, 0, '', ''),
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsA(
          isA<PackBuildException>().having(
            (e) => e.message,
            'message',
            contains('未写入退出码标记'),
          ),
        ),
      );
    });

    test('供给版 Python 以绝对路径嵌入 launcher（py 启动器带 -3）', () async {
      final Directory root = await _tempDirectory();
      final BuildEnvironment provisioned = _buildEnvironment(
        root.path,
        python: ProvisionedPython(
          executable: joinPath(
            joinPath(root.path, 'tools'),
            'python/python.exe',
          ),
          source: PythonSource.provisioned,
          pathEntries: const <String>[],
        ),
      );

      await runElevatedPackBuild(
        _pack(),
        (_) {},
        buildEnvironment: provisioned,
        prepareSource: _fakePrepareSource(),
        launcherStarter: _starterWriting(root, logText: '', exitCode: '0'),
        pollInterval: const Duration(milliseconds: 1),
      );

      final String content = await File(
        joinPath(
          joinPath(root.path, elevatedBuildDirectoryName),
          elevatedBuildLauncherFileName,
        ),
      ).readAsString();
      expect(
        content.contains(
          '"${joinPath(joinPath(root.path, 'tools'), 'python/python.exe')}" '
          '-u "build.py"',
        ),
        isTrue,
      );

      final BuildEnvironment launcherPython = _buildEnvironment(
        root.path,
        python: const ProvisionedPython(
          executable: 'py',
          source: PythonSource.launcher,
          pathEntries: <String>[],
        ),
      );
      await runElevatedPackBuild(
        _pack(),
        (_) {},
        buildEnvironment: launcherPython,
        prepareSource: _fakePrepareSource(),
        launcherStarter: _starterWriting(root, logText: '', exitCode: '0'),
        pollInterval: const Duration(milliseconds: 1),
      );
      final String pyContent = await File(
        joinPath(
          joinPath(root.path, elevatedBuildDirectoryName),
          elevatedBuildLauncherFileName,
        ),
      ).readAsString();
      expect(pyContent.contains('"py" -3 -u "build.py"'), isTrue);
    });
  });

  test('真实冒烟：launcher 经 cmd + Python 执行构建脚本并写退出码标记', () async {
    if (_launcherSmokeSkip()) {
      print('[skip] $_launcherSmokeSkipReason');
      return;
    }
    final ({String executable, bool launcher})? python = _probePython();
    if (python == null) {
      print('[skip] 未检测到可用 Python（python / py -3）');
      return;
    }

    final Directory root = await _tempDirectory();
    final Directory source = Directory(joinPath(root.path, '中文 目录'));
    await source.create(recursive: true);
    await File(joinPath(source.path, 'build_ok.py'))
        .writeAsString("print('CNP-SMOKE-OK')\n");
    await File(joinPath(source.path, 'build_fail.py'))
        .writeAsString("import sys\nprint('CNP-SMOKE-FAIL')\nsys.exit(7)\n");

    final String logPath = joinPath(root.path, 'smoke.log');
    final String exitPath = joinPath(root.path, 'smoke.exit');

    Future<int> runLauncher(String scriptName) async {
      final String launcherPath = joinPath(
        root.path,
        elevatedBuildLauncherFileName,
      );
      await File(launcherPath).writeAsString(
        buildElevatedLauncher(
          sourcePath: source.path,
          scriptRelativePath: scriptName,
          pythonExecutable: python.executable,
          pythonUsesLauncher: python.launcher,
          environment: <String, String>{'TMP': root.path, 'TEMP': root.path},
          logPath: logPath,
          exitCodePath: exitPath,
        ),
      );
      await File(exitPath).writeAsString('');
      final ProcessResult result = await Process.run('cmd.exe', <String>[
        '/d',
        '/c',
        launcherPath,
      ]);
      print(
        '[evidence] cmd exit=${result.exitCode} marker=${await _readMarker(exitPath)}',
      );
      return int.parse((await _readMarker(exitPath)).trim());
    }

    expect(await runLauncher('build_ok.py'), 0);
    final String successLog = await File(logPath).readAsString();
    print('[evidence] success log=${successLog.trim()}');
    expect(successLog, contains('CNP-SMOKE-OK'));

    expect(await runLauncher('build_fail.py'), 7);
    final String failureLog = await File(logPath).readAsString();
    print('[evidence] failure log=${failureLog.trim()}');
    expect(failureLog, contains('CNP-SMOKE-FAIL'));

    // 提权启动脚本语法校验：Windows PowerShell 5.1 仅解析（不执行、不触发 UAC）。
    final String starterPath = joinPath(root.path, 'elevated_starter.ps1');
    await File(starterPath).writeAsString(
      buildElevatedStarterScript(joinPath(root.path, 'launcher.cmd')),
    );
    final String parseScriptPath = joinPath(root.path, 'parse_check.ps1');
    await File(parseScriptPath).writeAsString(
      "try { [void][ScriptBlock]::Create([IO.File]::ReadAllText('"
      "${starterPath.replaceAll("'", "''")}', [Text.Encoding]::UTF8)); exit 0 } "
      "catch { [Console]::Error.WriteLine(\$_.Exception.Message); exit 1 }",
    );
    final ProcessResult parse = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      parseScriptPath,
    ]);
    print('[evidence] starter parse exit=${parse.exitCode} ${parse.stderr}');
    expect(parse.exitCode, 0, reason: '提权启动脚本应可被 PowerShell 5.1 解析');
  }, skip: _launcherSmokeSkip() ? _launcherSmokeSkipReason : false);
}

/// 真实冒烟门控（环境变量启用；CI 默认跳过）。
bool _launcherSmokeSkip() =>
    Platform.environment['CNP_ELEVATED_LAUNCHER_SMOKE'] != '1';

Future<String> _readMarker(String path) async {
  final File file = File(path);
  if (!await file.exists()) {
    return '<missing>';
  }
  return await file.readAsString();
}

({String executable, bool launcher})? _probePython() {
  final List<({String executable, List<String> arguments, bool launcher})>
  candidates = <({String executable, List<String> arguments, bool launcher})>[
    (executable: 'python', arguments: <String>['--version'], launcher: false),
    (executable: 'py', arguments: <String>['-3', '--version'], launcher: true),
  ];
  for (final ({String executable, List<String> arguments, bool launcher})
      candidate
      in candidates) {
    try {
      final ProcessResult result = Process.runSync(
        candidate.executable,
        candidate.arguments,
      );
      final String versionText = '${result.stdout}\n${result.stderr}'
          .toLowerCase();
      if (result.exitCode == 0 && versionText.contains('python')) {
        return (executable: candidate.executable, launcher: candidate.launcher);
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}

/// 提权启动器替身：直接写入日志与退出码标记（不启动任何提权进程）。
Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
})
_starterWriting(
  Directory root, {
  required String logText,
  required String exitCode,
}) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final Directory elevated = Directory(
      joinPath(root.path, elevatedBuildDirectoryName),
    );
    if (logText.isNotEmpty) {
      await File(joinPath(elevated.path, elevatedBuildLogFileName))
          .writeAsString(logText);
    }
    await File(joinPath(elevated.path, elevatedBuildExitFileName))
        .writeAsString('$exitCode\r\n');
    return ProcessResult(1, 0, '', '');
  };
}

PackSourcePreparer _fakePrepareSource({
  String sourcePath = r'C:\libs\demo',
  String scriptPath = 'build.py',
  String targetPath = r'C:\cache\build\demo',
}) {
  return (
    PackModel pack,
    void Function(PackBuildStage) onStage, {
    PackProcessRunner processRunner = Process.run,
    PackStreamingProcessRunner? streamRunner,
    void Function(String line)? onOutput,
    void Function(String version)? onSourceVersion,
    String cacheRoot = 'cache',
    Map<String, String>? environment,
  }) async {
    onStage(PackBuildStage.downloading);
    return PackSourcePreparation(
      sourcePath: sourcePath,
      scriptPath: scriptPath,
      target: Directory(targetPath),
    );
  };
}

BuildEnvironment _buildEnvironment(
  String tempRoot, {
  ProvisionedPython? python,
}) {
  return BuildEnvironment(
    compiler: DetectedCompiler(
      kind: CompilerKind.icx,
      version: '2026.1.1',
      executablePath: r'C:\tools\icx-cl.exe',
      environmentScript: null,
    ),
    environment: <String, String>{
      'TMP': tempRoot,
      'TEMP': tempRoot,
      'Path': r'C:\tools\bin',
    },
    cmakePath: r'C:\tools\cmake\bin\cmake.exe',
    ninjaPath: r'C:\tools\ninja\ninja.exe',
    toolsDir: r'C:\tools',
    python: python,
  );
}

PackModel _pack() {
  return PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      description: '描述',
      sourcePath: r'C:\libs\demo',
    )
    ..files = <FileModel>[
      FileModel(name: 'build.py', path: 'build.py', size: 100),
    ];
}

Future<Directory> _tempDirectory() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'cnp-elevated-test-',
  );
  addTearDown(() async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // 测试清理失败不影响断言。
    }
  });
  return directory;
}
