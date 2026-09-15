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
        launcherContent.contains(
          'if %ERRORLEVEL% EQU 9009 goto :fallback_python',
        ),
        isTrue,
      );
      expect(
        launcherContent.contains('if errorlevel 9009'),
        isFalse,
        reason: '「errorlevel N」为 ≥ 语义，≥9009 的脚本退出码会被误判并二次运行',
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

    test('跨块切开的 CRLF 不产生多余空行', () {
      final LogTailDecoder decoder = LogTailDecoder();
      expect(decoder.add(utf8.encode('foo\r')), <String>['foo']);
      expect(decoder.add(utf8.encode('\nbar\n')), <String>['bar']);
      expect(decoder.flush(), isNull);
    });

    test('块尾 CR 后随非 LF 不退让（空行语义保留）', () {
      final LogTailDecoder decoder = LogTailDecoder();
      expect(decoder.add(utf8.encode('a\r')), <String>['a']);
      expect(decoder.add(utf8.encode('\rb')), <String>['']);
      expect(decoder.flush(), 'b');
    });

    test('任意块切分结果与 LineSplitter 口径一致', () {
      const String full = 'alpha\r\nbeta\rgamma\ndelta\r\n';
      final List<String> expected = const LineSplitter().convert(full);
      for (int split = 0; split <= full.length; split++) {
        final LogTailDecoder decoder = LogTailDecoder();
        final List<String> actual = <String>[
          ...decoder.add(utf8.encode(full.substring(0, split))),
          ...decoder.add(utf8.encode(full.substring(split))),
        ];
        final String? rest = decoder.flush();
        if (rest != null) {
          actual.add(rest);
        }
        expect(actual, expected, reason: '块切分位置 $split');
      }
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
            '已取消以管理员身份重试（UAC 授权被拒绝）'
                '：The operation was canceled by the user.',
          ),
        ),
      );
    });

    test('1223 且非用户取消：附带启动器诊断信息（不误报为纯 UAC 取消）', () async {
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
                'This command cannot be run due to the error: '
                    '系统找不到指定的文件。',
              ),
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsA(
          isA<PackBuildException>().having(
            (e) => e.message,
            'message',
            '已取消以管理员身份重试（UAC 授权被拒绝）'
                '：This command cannot be run due to the error: '
                '系统找不到指定的文件。',
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
    await File(joinPath(source.path, 'build_ok.py')).writeAsString(
      "print('CNP-SMOKE-OK')\n"
      "open('runs.txt', 'a', encoding='utf-8').write('run\\n')\n",
    );
    await File(joinPath(source.path, 'build_fail.py'))
        .writeAsString("import sys\nprint('CNP-SMOKE-FAIL')\nsys.exit(7)\n");
    await File(joinPath(source.path, 'build_9009.py')).writeAsString(
      "import sys\n"
      "open('runs.txt', 'a', encoding='utf-8').write('run\\n')\n"
      "sys.exit(9009)\n",
    );
    await File(joinPath(source.path, 'build_max.py')).writeAsString(
      "import sys\n"
      "open('runs.txt', 'a', encoding='utf-8').write('run\\n')\n"
      "sys.exit(2147483647)\n",
    );

    final String logPath = joinPath(root.path, 'smoke.log');
    final String exitPath = joinPath(root.path, 'smoke.exit');
    final String runsPath = joinPath(source.path, 'runs.txt');

    Future<int> lineCount(String path) async {
      final File file = File(path);
      if (!await file.exists()) {
        return 0;
      }
      return (await file.readAsString())
          .split('\n')
          .where((String line) => line.trim().isNotEmpty)
          .length;
    }

    Future<int> runLauncher(
      String scriptName, {
      String? executable,
      bool? usesLauncher,
    }) async {
      final String launcherPath = joinPath(
        root.path,
        elevatedBuildLauncherFileName,
      );
      await File(launcherPath).writeAsString(
        buildElevatedLauncher(
          sourcePath: source.path,
          scriptRelativePath: scriptName,
          pythonExecutable: executable ?? python.executable,
          pythonUsesLauncher: usesLauncher ?? python.launcher,
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

    final bool alternateAvailable = python.launcher
        ? _interpreterAvailable('python', const <String>['--version'])
        : _interpreterAvailable('py', const <String>['-3', '--version']);

    // 精确 9009：脚本自身以 >9009 退出不得触发回退（EQU 语义回归锁）。
    await File(runsPath).writeAsString('');
    expect(await runLauncher('build_max.py'), 2147483647, reason: '大退出码应原样透传');
    expect(
      await lineCount(runsPath),
      1,
      reason: '退出码 2147483647 ≥9009 但 ≠9009，不得二次运行构建脚本',
    );

    // 恰好 9009 仍按「命令未找到」惯例回退（备用解释器可用时验证确实重跑）。
    await File(runsPath).writeAsString('');
    expect(await runLauncher('build_9009.py'), 9009);
    if (alternateAvailable) {
      expect(await lineCount(runsPath), 2, reason: '恰好 9009 触发备用解释器重跑构建脚本');
    } else {
      print('[skip] 备用解释器不可用，跳过 9009 回退双跑断言');
    }

    // 真实「命令未找到」（裸命令名不在 PATH，cmd 惯例 9009）：回退到备用命令且脚本只跑一次。
    await File(runsPath).writeAsString('');
    expect(
      await runLauncher(
        'build_ok.py',
        executable: 'cnp-missing-python',
        usesLauncher: !python.launcher,
      ),
      0,
      reason: '主解释器不存在（9009）时应回退到备用命令',
    );
    expect(await lineCount(runsPath), 1, reason: '脚本仅经回退解释器执行一次');

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
  if (_interpreterAvailable('python', const <String>['--version'])) {
    return (executable: 'python', launcher: false);
  }
  if (_interpreterAvailable('py', const <String>['-3', '--version'])) {
    return (executable: 'py', launcher: true);
  }
  return null;
}

/// 单个 Python 启动命令是否可用（版本输出含 `python` 且退出码为 0）。
bool _interpreterAvailable(String executable, List<String> arguments) {
  try {
    final ProcessResult result = Process.runSync(executable, arguments);
    return result.exitCode == 0 &&
        '${result.stdout}\n${result.stderr}'.toLowerCase().contains('python');
  } on ProcessException {
    return false;
  }
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
