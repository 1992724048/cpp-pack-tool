import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _ProcessCall = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
});

void main() {
  group('compilerKindId', () {
    test('返回各编译器的稳定标识', () {
      expect(compilerKindId(CompilerKind.icx), 'icx');
      expect(compilerKindId(CompilerKind.clangCl), 'clang-cl');
      expect(compilerKindId(CompilerKind.msvc), 'msvc');
    });
  });

  group('compilerKindFromId', () {
    test('解析稳定标识（大小写不敏感、容忍空白），未知返回 null', () {
      expect(compilerKindFromId('icx'), CompilerKind.icx);
      expect(compilerKindFromId(' clang-cl '), CompilerKind.clangCl);
      expect(compilerKindFromId('MSVC'), CompilerKind.msvc);
      expect(compilerKindFromId('gcc'), isNull);
      expect(compilerKindFromId(''), isNull);
    });
  });

  group('isCompilerUsable', () {
    test('可执行文件与环境脚本均存在时可用', () {
      final Directory root = _tempDirectory();
      final String executable = joinPath(root.path, 'cl.exe');
      _createFile(executable);
      final String script = joinPath(root.path, 'vcvars64.bat');
      _createFile(script);

      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.msvc,
            version: '14.44.35207',
            executablePath: executable,
            environmentScript: script,
          ),
        ),
        isTrue,
      );
      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.clangCl,
            version: '23.1.1',
            executablePath: executable,
            environmentScript: null,
          ),
        ),
        isTrue,
      );
    });

    test('可执行文件缺失或声明脚本缺失时不可用', () {
      final Directory root = _tempDirectory();
      final String missing = joinPath(root.path, 'missing.exe');
      final String script = joinPath(root.path, 'setvars.bat');
      _createFile(script);

      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.msvc,
            version: '14.44.35207',
            executablePath: missing,
            environmentScript: null,
          ),
        ),
        isFalse,
      );
      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.icx,
            version: '2026.1.0',
            executablePath: missing,
            environmentScript: script,
          ),
        ),
        isFalse,
      );

      final String executable = joinPath(root.path, 'icx-cl.exe');
      _createFile(executable);
      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.icx,
            version: '2026.1.0',
            executablePath: executable,
            environmentScript: joinPath(root.path, 'missing/setvars.bat'),
          ),
        ),
        isFalse,
      );
    });
  });

  group('compilerKindLabel', () {
    test('返回各编译器的显示名', () {
      expect(compilerKindLabel(CompilerKind.icx), 'ICX');
      expect(compilerKindLabel(CompilerKind.clangCl), 'clang-cl');
      expect(compilerKindLabel(CompilerKind.msvc), 'MSVC');
    });
  });

  group('detectIcx', () {
    test('解析版本、可执行文件与环境脚本路径', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(
          calls,
          (_) async => _result(
            'Intel(R) oneAPI DPC++/C++ Compiler 2026.1.1 '
            '(2026.1.1.20260729)\r\n',
          ),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(detected, isNotNull);
      final DetectedCompiler compiler = detected!;
      expect(compiler.kind, CompilerKind.icx);
      expect(compiler.version, '2026.1.1');
      expect(
        compiler.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'),
      );
      expect(compiler.environmentScript, joinPath(oneApiRoot, 'setvars.bat'));
      expect(compiler.extraPathEntries, isEmpty);
      expect(calls, hasLength(1));
      expect(calls.single.executable, compiler.executablePath);
      expect(calls.single.arguments, <String>['--version']);
      expect(calls.single.workingDirectory, isNull);
    });

    test('优先最高版本目录且按数值比较', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2025.3/bin/icx-cl.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.2/bin/icx-cl.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.10/bin/icx-cl.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/latest/bin/icx-cl.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(calls, (_) async => _result('Compiler 2027.0.0\n')),
        oneApiRoot: oneApiRoot,
      );

      expect(
        detected?.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.10/bin/icx-cl.exe'),
      );
      expect(calls, hasLength(1));
    });

    test('仅 latest 目录可用时兜底采用', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      final String latestExecutable = joinPath(
        oneApiRoot,
        'compiler/latest/bin/icx-cl.exe',
      );
      _createFile(latestExecutable);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(calls, (_) async => _result('Compiler 2026.1.1\n')),
        oneApiRoot: oneApiRoot,
      );

      expect(detected?.executablePath, latestExecutable);
      expect(calls.single.executable, latestExecutable);
    });

    test('旧布局 windows/bin/icx-cl.exe 也可检出', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      final String expected = joinPath(
        oneApiRoot,
        'compiler/2025.2/windows/bin/icx-cl.exe',
      );
      _createFile(expected);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(calls, (_) async => _result('Compiler 2025.2.1\n')),
        oneApiRoot: oneApiRoot,
      );

      expect(detected?.executablePath, expected);
      expect(calls.single.executable, expected);
    });

    test('同一版本目录中新布局优先于旧布局', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      _createFile(
        joinPath(oneApiRoot, 'compiler/2026.1/windows/bin/icx-cl.exe'),
      );

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('Compiler 2026.1.1\n'),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(
        detected?.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'),
      );
    });

    test('混合布局下按版本号数值比较选择最高版本', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(
        joinPath(oneApiRoot, 'compiler/2025.3/windows/bin/icx-cl.exe'),
      );
      _createFile(
        joinPath(oneApiRoot, 'compiler/2026.2/windows/bin/icx-cl.exe'),
      );
      _createFile(joinPath(oneApiRoot, 'compiler/2026.10/bin/icx-cl.exe'));

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('Compiler 2027.0.0\n'),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(
        detected?.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.10/bin/icx-cl.exe'),
      );
    });

    test('compiler 目录缺失时返回 null 且不执行进程', () async {
      final Directory root = _tempDirectory();
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(calls, (_) async => throw StateError('不应执行进程')),
        oneApiRoot: joinPath(root.path, 'missing'),
      );

      expect(detected, isNull);
      expect(calls, isEmpty);
    });

    test('目录内无 icx-cl.exe 时返回 null 且不执行进程', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/readme.txt'));
      Directory(joinPath(oneApiRoot, 'compiler/2026.2/bin'))
          .createSync(recursive: true);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(calls, (_) async => throw StateError('不应执行进程')),
        oneApiRoot: oneApiRoot,
      );

      expect(detected, isNull);
      expect(calls, isEmpty);
    });

    test('版本输出不匹配时返回 null', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('unknown output\n'),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(detected, isNull);
    });

    test('进程失败时返回 null（退出码非零或无法启动）', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));

      final DetectedCompiler? nonZeroExit = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('', exitCode: 1),
        ),
        oneApiRoot: oneApiRoot,
      );
      final DetectedCompiler? cannotStart = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => throw ProcessException('icx-cl', <String>[
            '--version',
          ], 'not found'),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(nonZeroExit, isNull);
      expect(cannotStart, isNull);
    });
  });

  group('detectClangCl', () {
    test('解析版本与 LLVM bin 路径', () async {
      final Directory root = _tempDirectory();
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      final String executable = joinPath(llvmBinDir, 'clang-cl.exe');
      _createFile(executable);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectClangCl(
        runner: _runner(
          calls,
          (_) async => _result(
            'clang version 23.1.1\r\n'
            'Target: x86_64-pc-windows-msvc\r\n'
            'Thread model: posix\r\n',
          ),
        ),
        llvmBinDir: llvmBinDir,
      );

      expect(detected, isNotNull);
      final DetectedCompiler compiler = detected!;
      expect(compiler.kind, CompilerKind.clangCl);
      expect(compiler.version, '23.1.1');
      expect(compiler.executablePath, executable);
      expect(compiler.environmentScript, isNull);
      expect(compiler.extraPathEntries, <String>[llvmBinDir]);
      expect(calls, hasLength(1));
      expect(calls.single.executable, executable);
      expect(calls.single.arguments, <String>['--version']);
    });

    test('clang-cl.exe 缺失时返回 null 且不执行进程', () async {
      final Directory root = _tempDirectory();
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      Directory(llvmBinDir).createSync(recursive: true);
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectClangCl(
        runner: _runner(calls, (_) async => throw StateError('不应执行进程')),
        llvmBinDir: llvmBinDir,
      );

      expect(detected, isNull);
      expect(calls, isEmpty);
    });

    test('版本输出不匹配时返回 null', () async {
      final Directory root = _tempDirectory();
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      _createFile(joinPath(llvmBinDir, 'clang-cl.exe'));

      final DetectedCompiler? detected = await detectClangCl(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('clang-cl: error\n'),
        ),
        llvmBinDir: llvmBinDir,
      );

      expect(detected, isNull);
    });
  });

  group('detectMsvc', () {
    test('经 vswhere 解析安装路径、工具集版本与 vcvars64', () async {
      final Directory root = _tempDirectory();
      final String installPath = joinPath(root.path, 'VisualStudio');
      _createFile(
        joinPath(
          installPath,
          'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt',
        ),
        content: '14.44.35207\r\n',
      );
      _createFile(
        joinPath(
          installPath,
          'VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/cl.exe',
        ),
      );
      final String vswherePath = joinPath(root.path, 'vswhere.exe');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectMsvc(
        runner: _runner(calls, (_) async => _result('$installPath\r\n')),
        vswherePath: vswherePath,
      );

      expect(detected, isNotNull);
      final DetectedCompiler compiler = detected!;
      expect(compiler.kind, CompilerKind.msvc);
      expect(compiler.version, '14.44.35207');
      expect(
        compiler.executablePath,
        joinPath(
          installPath,
          'VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/cl.exe',
        ),
      );
      expect(
        compiler.environmentScript,
        joinPath(installPath, 'VC/Auxiliary/Build/vcvars64.bat'),
      );
      expect(calls, hasLength(1));
      expect(calls.single.executable, vswherePath);
      expect(calls.single.arguments, <String>[
        '-latest',
        '-products',
        '*',
        '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property',
        'installationPath',
      ]);
    });

    test('工具集版本文件缺失时返回 null', () async {
      final Directory root = _tempDirectory();
      final String installPath = joinPath(root.path, 'VisualStudio');
      Directory(installPath).createSync(recursive: true);

      final DetectedCompiler? detected = await detectMsvc(
        runner: _runner(<_ProcessCall>[], (_) async => _result(installPath)),
        vswherePath: joinPath(root.path, 'vswhere.exe'),
      );

      expect(detected, isNull);
    });

    test('cl.exe 缺失时返回 null', () async {
      final Directory root = _tempDirectory();
      final String installPath = joinPath(root.path, 'VisualStudio');
      _createFile(
        joinPath(
          installPath,
          'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt',
        ),
        content: '14.44.35207\n',
      );

      final DetectedCompiler? detected = await detectMsvc(
        runner: _runner(<_ProcessCall>[], (_) async => _result(installPath)),
        vswherePath: joinPath(root.path, 'vswhere.exe'),
      );

      expect(detected, isNull);
    });

    test('vswhere 失败或输出为空时返回 null', () async {
      final Directory root = _tempDirectory();
      final String vswherePath = joinPath(root.path, 'vswhere.exe');

      final DetectedCompiler? nonZeroExit = await detectMsvc(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('', exitCode: 1),
        ),
        vswherePath: vswherePath,
      );
      final DetectedCompiler? emptyOutput = await detectMsvc(
        runner: _runner(<_ProcessCall>[], (_) async => _result('\r\n')),
        vswherePath: vswherePath,
      );

      expect(nonZeroExit, isNull);
      expect(emptyOutput, isNull);
    });

    test('vswhere 无法启动时返回 null', () async {
      final Directory root = _tempDirectory();

      final DetectedCompiler? detected = await detectMsvc(
        runner: _runner(
          <_ProcessCall>[],
          (_) async =>
              throw ProcessException('vswhere', <String>[], 'not found'),
        ),
        vswherePath: joinPath(root.path, 'vswhere.exe'),
      );

      expect(detected, isNull);
    });
  });

  group('selectCompiler', () {
    test('按优先级返回首个可用', () {
      final DetectedCompiler icx = _compiler(CompilerKind.icx);
      final DetectedCompiler clang = _compiler(CompilerKind.clangCl);

      expect(
        selectCompiler(
          <DetectedCompiler>[icx, clang],
          <String>['clang-cl', 'icx', 'msvc'],
        ),
        same(clang),
      );
      expect(
        selectCompiler(<DetectedCompiler>[icx, clang], <String>['msvc', 'icx']),
        same(icx),
      );
    });

    test('优先级缺项跳过、未知标识忽略、全不可用返回 null', () {
      final DetectedCompiler msvc = _compiler(CompilerKind.msvc);

      expect(
        selectCompiler(
          <DetectedCompiler>[msvc],
          <String>['icx', 'unknown', 'msvc'],
        ),
        same(msvc),
      );
      expect(
        selectCompiler(<DetectedCompiler>[msvc], <String>['icx', 'clang-cl']),
        isNull,
      );
      expect(
        selectCompiler(<DetectedCompiler>[], <String>[
          'icx',
          'clang-cl',
          'msvc',
        ]),
        isNull,
      );
      expect(selectCompiler(<DetectedCompiler>[msvc], <String>[]), isNull);
    });
  });

  group('detectCompilers', () {
    test('默认 oneAPI 根优先使用 %ONEAPI_ROOT%（含自定义安装根）', () async {
      final Directory root = _tempDirectory();
      final String declaredRoot = joinPath(root.path, 'custom-oneapi');
      final String programFilesRoot = joinPath(root.path, 'pf/Intel/oneAPI');
      _createFile(joinPath(declaredRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      _createFile(joinPath(programFilesRoot, 'compiler/2025.0/bin/icx-cl.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner: _runner(calls, (_) async => _result('Compiler 2026.1.0\n')),
        environment: <String, String>{
          'ONEAPI_ROOT': declaredRoot,
          'ProgramFiles(x86)': joinPath(root.path, 'pf'),
        },
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
      );

      expect(compilers, hasLength(1));
      expect(
        compilers.single.executablePath,
        joinPath(declaredRoot, 'compiler/2026.1/bin/icx-cl.exe'),
      );
      expect(
        calls
            .where(
              (_ProcessCall call) => call.executable.endsWith('icx-cl.exe'),
            )
            .length,
        1,
      );
      expect(calls.first.executable, compilers.single.executablePath);
    });

    test('无 %ONEAPI_ROOT% 时回退 Program Files 安装目录', () async {
      final Directory root = _tempDirectory();
      final String programFilesRoot = joinPath(root.path, 'pf/Intel/oneAPI');
      _createFile(
        joinPath(programFilesRoot, 'compiler/2026.1/windows/bin/icx-cl.exe'),
      );

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('Compiler 2026.1.0\n'),
        ),
        environment: <String, String>{
          'ProgramFiles': joinPath(root.path, 'pf'),
        },
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
      );

      expect(compilers, hasLength(1));
      expect(
        compilers.single.executablePath,
        joinPath(programFilesRoot, 'compiler/2026.1/windows/bin/icx-cl.exe'),
      );
    });

    test('%ONEAPI_ROOT% 与标准根重合时去重，只探测一次', () async {
      final Directory root = _tempDirectory();
      final String programFiles = joinPath(root.path, 'pf');
      final String sharedRoot = joinPath(programFiles, 'Intel/oneAPI');
      _createFile(joinPath(sharedRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner: _runner(calls, (_) async => _result('Compiler 2026.1.0\n')),
        environment: <String, String>{
          'ONEAPI_ROOT': sharedRoot,
          'ProgramFiles(x86)': programFiles,
        },
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
      );

      expect(compilers, hasLength(1));
      expect(
        calls
            .where(
              (_ProcessCall call) => call.executable.endsWith('icx-cl.exe'),
            )
            .length,
        1,
      );
    });

    test('从覆盖路径按 icx → clang-cl → msvc 顺序收集', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      _createFile(joinPath(llvmBinDir, 'clang-cl.exe'));
      final String installPath = joinPath(root.path, 'VisualStudio');
      _createFile(
        joinPath(
          installPath,
          'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt',
        ),
        content: '14.44.35207',
      );
      _createFile(
        joinPath(
          installPath,
          'VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/cl.exe',
        ),
      );

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('icx-cl.exe')) {
                return _result('Compiler 2026.1.1\n');
              }
              if (executable.endsWith('clang-cl.exe')) {
                return _result('clang version 23.1.1\n');
              }
              return _result('$installPath\r\n');
            },
        oneApiRoot: oneApiRoot,
        llvmBinDir: llvmBinDir,
        vswherePath: joinPath(root.path, 'vswhere.exe'),
      );

      expect(
        compilers.map(
          (DetectedCompiler compiler) => compilerKindId(compiler.kind),
        ),
        <String>['icx', 'clang-cl', 'msvc'],
      );
    });

    test('environment 透传给各编译器探测子进程', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      _createFile(joinPath(llvmBinDir, 'clang-cl.exe'));
      final String installPath = joinPath(root.path, 'VisualStudio');
      _createFile(
        joinPath(
          installPath,
          'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt',
        ),
        content: '14.44.35207',
      );
      _createFile(
        joinPath(
          installPath,
          'VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/cl.exe',
        ),
      );
      final List<_ProcessCall> calls = <_ProcessCall>[];
      final Map<String, String> environment = <String, String>{
        'TMP': r'D:\tools\.tmp\build',
        'TEMP': r'D:\tools\.tmp\build',
        'CUSTOM': '1',
      };

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner: _runner(calls, (_ProcessCall call) async {
          if (call.executable.endsWith('icx-cl.exe')) {
            return _result('Compiler 2026.1.1\n');
          }
          if (call.executable.endsWith('clang-cl.exe')) {
            return _result('clang version 23.1.1\n');
          }
          return _result('$installPath\r\n');
        }),
        oneApiRoot: oneApiRoot,
        llvmBinDir: llvmBinDir,
        vswherePath: joinPath(root.path, 'vswhere.exe'),
        environment: environment,
      );

      expect(
        compilers.map(
          (DetectedCompiler compiler) => compilerKindId(compiler.kind),
        ),
        <String>['icx', 'clang-cl', 'msvc'],
      );
      expect(calls, hasLength(3));
      for (final _ProcessCall call in calls) {
        expect(call.environment, environment);
      }
    });

    test('environment 键大小写不敏感（副本全大写键仍能定位默认根）', () async {
      final Directory root = _tempDirectory();
      final String programFiles = joinPath(root.path, 'pf');
      final String oneApiRoot = joinPath(programFiles, 'Intel/oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner: _runner(calls, (_) async => _result('Compiler 2026.1.0\n')),
        environment: <String, String>{
          'PROGRAMFILES(X86)': programFiles,
          'TMP': r'C:\tools\.tmp\build',
        },
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
      );

      expect(compilers, hasLength(1));
      expect(compilers.single.kind, CompilerKind.icx);
      expect(
        compilers.single.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'),
      );
      final _ProcessCall icxProbe = calls.singleWhere(
        (_ProcessCall call) => call.executable.endsWith('icx-cl.exe'),
      );
      expect(icxProbe.environment?['TMP'], r'C:\tools\.tmp\build');
    });

    test('clang-cl 无环境脚本时继承 MSVC 的 vcvars 脚本', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      _createFile(joinPath(llvmBinDir, 'clang-cl.exe'));
      final String installPath = joinPath(root.path, 'VisualStudio');
      _createFile(
        joinPath(
          installPath,
          'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt',
        ),
        content: '14.44.35207',
      );
      _createFile(
        joinPath(
          installPath,
          'VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/cl.exe',
        ),
      );

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('icx-cl.exe')) {
                return _result('Compiler 2026.1.1\n');
              }
              if (executable.endsWith('clang-cl.exe')) {
                return _result('clang version 23.1.1\n');
              }
              return _result('$installPath\r\n');
            },
        oneApiRoot: oneApiRoot,
        llvmBinDir: llvmBinDir,
        vswherePath: joinPath(root.path, 'vswhere.exe'),
      );

      final Map<String, DetectedCompiler> byKind = <String, DetectedCompiler>{
        for (final DetectedCompiler compiler in compilers)
          compilerKindId(compiler.kind): compiler,
      };
      final String vcvars = joinPath(
        installPath,
        'VC/Auxiliary/Build/vcvars64.bat',
      );
      expect(byKind['clang-cl']!.environmentScript, vcvars);
      expect(byKind['msvc']!.environmentScript, vcvars);
      expect(
        byKind['icx']!.environmentScript,
        joinPath(oneApiRoot, 'setvars.bat'),
      );
    });

    test('无 MSVC 时 clang-cl 环境脚本保持 null', () async {
      final Directory root = _tempDirectory();
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      _createFile(joinPath(llvmBinDir, 'clang-cl.exe'));

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('clang-cl.exe')) {
                return _result('clang version 23.1.1\n');
              }
              throw ProcessException(executable, arguments, 'not found');
            },
        oneApiRoot: joinPath(root.path, 'oneAPI'),
        llvmBinDir: llvmBinDir,
        vswherePath: joinPath(root.path, 'vswhere.exe'),
      );

      expect(compilers, hasLength(1));
      expect(compilers.single.kind, CompilerKind.clangCl);
      expect(compilers.single.environmentScript, isNull);
    });

    test('全部不可用时返回空列表', () async {
      final Directory root = _tempDirectory();
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner: _runner(
          calls,
          (_) async => throw ProcessException('probe', <String>[], 'not found'),
        ),
        oneApiRoot: joinPath(root.path, 'oneAPI'),
        llvmBinDir: joinPath(root.path, 'LLVM/bin'),
        vswherePath: joinPath(root.path, 'vswhere.exe'),
      );

      expect(compilers, isEmpty);
    });
  });
}

DetectedCompiler _compiler(CompilerKind kind) {
  return DetectedCompiler(
    kind: kind,
    version: '1.0.0',
    executablePath: 'C:/fake/${compilerKindId(kind)}.exe',
    environmentScript: null,
  );
}

Directory _tempDirectory() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'cpp_nuget_pack_toolchain_',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

void _createFile(String path, {String content = ''}) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

ProcessResult _result(String stdout, {int exitCode = 0}) {
  return ProcessResult(0, exitCode, stdout, '');
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
