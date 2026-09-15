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
      expect(compilerKindId(CompilerKind.mingw), 'mingw');
    });
  });

  group('compilerKindFromId', () {
    test('解析稳定标识（大小写不敏感、容忍空白），未知返回 null', () {
      expect(compilerKindFromId('icx'), CompilerKind.icx);
      expect(compilerKindFromId(' clang-cl '), CompilerKind.clangCl);
      expect(compilerKindFromId('MSVC'), CompilerKind.msvc);
      expect(compilerKindFromId('MinGW'), CompilerKind.mingw);
      expect(compilerKindFromId('gcc'), isNull);
      expect(compilerKindFromId(''), isNull);
    });

    test('R23 的 GNU clang 标识不再解析为有效种类，由迁移逻辑识别', () {
      expect(compilerKindFromId('clang'), isNull);
      expect(isLegacyCompilerKindId(' clang '), isTrue);
      expect(isLegacyCompilerKindId('clang-cl'), isFalse);
      expect(isLegacyCompilerKindId('CLANG'), isTrue);
      expect(isLegacyCompilerKindId(''), isFalse);
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
    test('声明的 C++ 驱动缺失时不可用（MinGW 的 gcc/g++ 分设）', () {
      final Directory root = _tempDirectory();
      final String executable = joinPath(root.path, 'gcc.exe');
      _createFile(executable);

      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.mingw,
            version: '14.2.0（UCRT64）',
            executablePath: executable,
            cxxExecutablePath: joinPath(root.path, 'g++.exe'),
            environmentScript: null,
          ),
        ),
        isFalse,
      );

      final String cxxExecutable = joinPath(root.path, 'g++.exe');
      _createFile(cxxExecutable);
      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.mingw,
            version: '14.2.0（UCRT64）',
            executablePath: executable,
            cxxExecutablePath: cxxExecutable,
            environmentScript: null,
          ),
        ),
        isTrue,
      );
      expect(
        isCompilerUsable(
          DetectedCompiler(
            kind: CompilerKind.mingw,
            version: '14.2.0（UCRT64）',
            executablePath: executable,
            environmentScript: null,
          ),
        ),
        isTrue,
        reason: '未声明 C++ 驱动时按 C 驱动回退，不额外校验',
      );
    });
  });

  group('compilerKindLabel', () {
    test('返回各编译器的显示名', () {
      expect(compilerKindLabel(CompilerKind.icx), 'ICX');
      expect(compilerKindLabel(CompilerKind.clangCl), 'clang-cl');
      expect(compilerKindLabel(CompilerKind.msvc), 'MSVC');
      expect(compilerKindLabel(CompilerKind.mingw), 'MinGW');
    });
  });

  group('detectIcx', () {
    test('解析版本、可执行文件与环境脚本路径（优先 icx.exe）', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
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
        joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'),
      );
      expect(compiler.environmentScript, joinPath(oneApiRoot, 'setvars.bat'));
      expect(compiler.extraPathEntries, isEmpty);
      expect(calls, hasLength(1));
      expect(calls.single.executable, compiler.executablePath);
      expect(calls.single.arguments, <String>['--version']);
      expect(calls.single.workingDirectory, isNull);
    });

    test('同一目录 icx.exe 与 icx-cl.exe 并存时优先 icx.exe', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(calls, (_) async => _result('Compiler 2026.1.1\n')),
        oneApiRoot: oneApiRoot,
      );

      expect(
        detected?.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'),
      );
      expect(calls.single.executable, detected!.executablePath);
    });

    test('安装缺失 icx.exe 时回退旧名 icx-cl.exe', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      final String legacy = joinPath(
        oneApiRoot,
        'compiler/2026.2/bin/icx-cl.exe',
      );
      _createFile(legacy);

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('Compiler 2026.1.1\n'),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(detected?.executablePath, legacy);
    });

    test('优先最高版本目录且按数值比较', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2025.3/bin/icx.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.2/bin/icx.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.10/bin/icx.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/latest/bin/icx.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(calls, (_) async => _result('Compiler 2027.0.0\n')),
        oneApiRoot: oneApiRoot,
      );

      expect(
        detected?.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.10/bin/icx.exe'),
      );
      expect(calls, hasLength(1));
    });

    test('仅 latest 目录可用时兜底采用', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      final String latestExecutable = joinPath(
        oneApiRoot,
        'compiler/latest/bin/icx.exe',
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

    test('旧布局 windows/bin/icx.exe 也可检出', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      final String expected = joinPath(
        oneApiRoot,
        'compiler/2025.2/windows/bin/icx.exe',
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
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/windows/bin/icx.exe'));

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('Compiler 2026.1.1\n'),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(
        detected?.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'),
      );
    });

    test('混合布局下按版本号数值比较选择最高版本', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2025.3/windows/bin/icx.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.2/windows/bin/icx.exe'));
      _createFile(joinPath(oneApiRoot, 'compiler/2026.10/bin/icx.exe'));

      final DetectedCompiler? detected = await detectIcx(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('Compiler 2027.0.0\n'),
        ),
        oneApiRoot: oneApiRoot,
      );

      expect(
        detected?.executablePath,
        joinPath(oneApiRoot, 'compiler/2026.10/bin/icx.exe'),
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

    test('目录内无 icx 可执行文件时返回 null 且不执行进程', () async {
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
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));

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
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));

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

  group('detectMingw', () {
    test('经 -dumpmachine 判定并解析版本、C++ 驱动与附加 PATH', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/ucrt64/bin');
      _createFile(joinPath(binDir, 'gcc.exe'));
      _createFile(joinPath(binDir, 'g++.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(calls, (_ProcessCall call) async {
          if (call.arguments.single == '-dumpmachine') {
            return _result('x86_64-w64-mingw32\r\n');
          }
          return _result('14.2.0\r\n');
        }),
        binDir: binDir,
        environmentTag: 'UCRT64',
      );

      expect(detected, isNotNull);
      final DetectedCompiler compiler = detected!;
      expect(compiler.kind, CompilerKind.mingw);
      expect(compiler.version, '14.2.0（UCRT64）');
      expect(compiler.executablePath, joinPath(binDir, 'gcc.exe'));
      expect(compiler.cxxExecutablePath, joinPath(binDir, 'g++.exe'));
      expect(compiler.cxxCompilerPath, joinPath(binDir, 'g++.exe'));
      expect(compiler.environmentScript, isNull);
      expect(compiler.extraPathEntries, <String>[binDir]);
      expect(
        calls.map((_ProcessCall call) => call.arguments.single).toList(),
        <String>['-dumpmachine', '-dumpfullversion'],
      );
    });

    test('版本回退链：-dumpfullversion 失败 → -dumpversion（单段）', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/ucrt64/bin');
      _createFile(joinPath(binDir, 'gcc.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(calls, (_ProcessCall call) async {
          switch (call.arguments.single) {
            case '-dumpmachine':
              return _result('x86_64-w64-mingw32\n');
            case '-dumpfullversion':
              return _result('', exitCode: 1);
            default:
              return _result('14\n');
          }
        }),
        binDir: binDir,
        environmentTag: 'UCRT64',
      );

      expect(detected?.version, '14（UCRT64）');
      expect(
        calls.map((_ProcessCall call) => call.arguments.single).toList(),
        <String>['-dumpmachine', '-dumpfullversion', '-dumpversion'],
      );
    });

    test('版本回退链：dump 输出不可用时取 --version 首行最后一个版本 token', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/ucrt64/bin');
      _createFile(joinPath(binDir, 'gcc.exe'));

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(<_ProcessCall>[], (_ProcessCall call) async {
          switch (call.arguments.single) {
            case '-dumpmachine':
              return _result('x86_64-w64-mingw32\n');
            case '-dumpfullversion':
              return _result('  \r\n');
            case '-dumpversion':
              return _result('', exitCode: 1);
            default:
              return _result(
                'gcc (Rev2, Built by MSYS2 project) 14.2.0\r\n'
                'Copyright (C) 2024 Free Software Foundation, Inc. 13.9.9\r\n',
              );
          }
        }),
        binDir: binDir,
      );

      expect(
        detected?.version,
        '14.2.0',
        reason: '仅取首行；第二行的版本号不参与解析，未传标注时版本为纯版本号',
      );
    });

    test('CLANG64 的 GNU ABI clang：windows-gnu 三元组与 clang++ 映射', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/clang64/bin');
      _createFile(joinPath(binDir, 'clang.exe'));
      _createFile(joinPath(binDir, 'clang++.exe'));

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(<_ProcessCall>[], (_ProcessCall call) async {
          switch (call.arguments.single) {
            case '-dumpmachine':
              return _result('x86_64-w64-windows-gnu\n');
            case '-dumpfullversion':
              return _result('', exitCode: 1);
            default:
              return _result('20.1.8\n');
          }
        }),
        binDir: binDir,
        cExecutableName: 'clang.exe',
        environmentTag: 'CLANG64',
      );

      expect(detected, isNotNull);
      expect(detected!.version, '20.1.8（CLANG64）');
      expect(detected.cxxExecutablePath, joinPath(binDir, 'clang++.exe'));
      expect(detected.executablePath, joinPath(binDir, 'clang.exe'));
    });

    test('MSVC 目标的 clang 被 -dumpmachine 拒绝且不再探测版本', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'LLVM/bin');
      _createFile(joinPath(binDir, 'clang.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(calls, (_ProcessCall call) async {
          return _result('x86_64-pc-windows-msvc\n');
        }),
        binDir: binDir,
        cExecutableName: 'clang.exe',
      );

      expect(detected, isNull);
      expect(calls, hasLength(1));
    });

    test('i686 等非 x64 三元组被拒绝', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/mingw32/bin');
      _createFile(joinPath(binDir, 'gcc.exe'));

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => _result('i686-w64-mingw32\n'),
        ),
        binDir: binDir,
      );

      expect(detected, isNull);
    });

    test('可执行文件缺失时返回 null 且不执行进程', () async {
      final Directory root = _tempDirectory();
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(calls, (_) async => throw StateError('不应执行进程')),
        binDir: joinPath(root.path, 'msys64/ucrt64/bin'),
      );

      expect(detected, isNull);
      expect(calls, isEmpty);
    });

    test('-dumpmachine 无法启动时返回 null', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/ucrt64/bin');
      _createFile(joinPath(binDir, 'gcc.exe'));

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(
          <_ProcessCall>[],
          (_) async => throw ProcessException('gcc', <String>[], 'not found'),
        ),
        binDir: binDir,
      );

      expect(detected, isNull);
    });

    test('C++ 驱动缺失时 cxxExecutablePath 留空并回退 C 驱动', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/ucrt64/bin');
      final String executable = joinPath(binDir, 'gcc.exe');
      _createFile(executable);

      final DetectedCompiler? detected = await detectMingw(
        runner: _runner(<_ProcessCall>[], (_ProcessCall call) async {
          if (call.arguments.single == '-dumpmachine') {
            return _result('x86_64-w64-mingw32\n');
          }
          return _result('14.2.0\n');
        }),
        binDir: binDir,
      );

      expect(detected, isNotNull);
      expect(detected!.cxxExecutablePath, isNull);
      expect(detected.cxxCompilerPath, executable);
    });

    test('environment 透传给探测子进程', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'msys64/ucrt64/bin');
      _createFile(joinPath(binDir, 'gcc.exe'));
      final Map<String, String> environment = <String, String>{
        'TMP': r'D:\tools\.tmp\build',
        'CUSTOM': '1',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await detectMingw(
        runner: _runner(calls, (_ProcessCall call) async {
          if (call.arguments.single == '-dumpmachine') {
            return _result('x86_64-w64-mingw32\n');
          }
          return _result('14.2.0\n');
        }),
        binDir: binDir,
        environment: environment,
      );

      expect(calls, isNotEmpty);
      for (final _ProcessCall call in calls) {
        expect(call.environment, same(environment));
      }
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

    test('R23 的 clang 优先级不再匹配 clang-cl（迁移由 SettingsModel 负责）', () {
      final DetectedCompiler clangCl = _compiler(CompilerKind.clangCl);

      expect(
        selectCompiler(<DetectedCompiler>[clangCl], <String>['clang', 'msvc']),
        isNull,
      );
    });
  });

  group('detectCompilers', () {
    test('默认 oneAPI 根优先使用 %ONEAPI_ROOT%（含自定义安装根）', () async {
      final Directory root = _tempDirectory();
      final String declaredRoot = joinPath(root.path, 'custom-oneapi');
      final String programFilesRoot = joinPath(root.path, 'pf/Intel/oneAPI');
      _createFile(joinPath(declaredRoot, 'compiler/2026.1/bin/icx.exe'));
      _createFile(joinPath(programFilesRoot, 'compiler/2025.0/bin/icx.exe'));
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
        joinPath(declaredRoot, 'compiler/2026.1/bin/icx.exe'),
      );
      expect(
        calls
            .where((_ProcessCall call) => call.executable.endsWith('icx.exe'))
            .length,
        1,
      );
      expect(calls.first.executable, compilers.single.executablePath);
    });

    test('无 %ONEAPI_ROOT% 时回退 Program Files 安装目录', () async {
      final Directory root = _tempDirectory();
      final String programFilesRoot = joinPath(root.path, 'pf/Intel/oneAPI');
      _createFile(
        joinPath(programFilesRoot, 'compiler/2026.1/windows/bin/icx.exe'),
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
        joinPath(programFilesRoot, 'compiler/2026.1/windows/bin/icx.exe'),
      );
    });

    test('%ONEAPI_ROOT% 与标准根重合时去重，只探测一次', () async {
      final Directory root = _tempDirectory();
      final String programFiles = joinPath(root.path, 'pf');
      final String sharedRoot = joinPath(programFiles, 'Intel/oneAPI');
      _createFile(joinPath(sharedRoot, 'compiler/2026.1/bin/icx.exe'));
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
            .where((_ProcessCall call) => call.executable.endsWith('icx.exe'))
            .length,
        1,
      );
    });

    test('从覆盖路径按 icx → clang-cl → msvc → mingw 顺序收集', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
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
      final String msys2Root = joinPath(root.path, 'msys64');
      final String mingwBin = joinPath(msys2Root, 'ucrt64/bin');
      _createFile(joinPath(mingwBin, 'gcc.exe'));
      _createFile(joinPath(mingwBin, 'g++.exe'));

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('icx.exe')) {
                return _result('Compiler 2026.1.1\n');
              }
              if (executable.endsWith('clang-cl.exe')) {
                return _result('clang version 23.1.1\n');
              }
              if (executable.endsWith('gcc.exe')) {
                return arguments.single == '-dumpmachine'
                    ? _result('x86_64-w64-mingw32\n')
                    : _result('14.2.0\n');
              }
              return _result('$installPath\r\n');
            },
        oneApiRoot: oneApiRoot,
        llvmBinDir: llvmBinDir,
        vswherePath: joinPath(root.path, 'vswhere.exe'),
        msys2Root: msys2Root,
        environment: const <String, String>{},
      );

      expect(
        compilers.map(
          (DetectedCompiler compiler) => compilerKindId(compiler.kind),
        ),
        <String>['icx', 'clang-cl', 'msvc', 'mingw'],
      );
      expect(compilers.last.version, '14.2.0（UCRT64）');
      expect(
        compilers.last.environmentScript,
        isNull,
        reason: 'MinGW 无环境脚本，绝不继承 MSVC 的 vcvars',
      );
    });

    test('MinGW 固定子环境顺序：UCRT64 优先于 CLANG64 与 MINGW64', () async {
      final Directory root = _tempDirectory();
      final String msys2Root = joinPath(root.path, 'msys64');
      _createFile(joinPath(msys2Root, 'ucrt64/bin/gcc.exe'));
      _createFile(joinPath(msys2Root, 'ucrt64/bin/g++.exe'));
      _createFile(joinPath(msys2Root, 'clang64/bin/clang.exe'));
      _createFile(joinPath(msys2Root, 'clang64/bin/clang++.exe'));
      _createFile(joinPath(msys2Root, 'mingw64/bin/gcc.exe'));
      _createFile(joinPath(msys2Root, 'mingw64/bin/g++.exe'));

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('vswhere.exe')) {
                throw ProcessException(executable, arguments, 'not found');
              }
              if (executable.endsWith('clang.exe')) {
                return arguments.single == '-dumpmachine'
                    ? _result('x86_64-w64-windows-gnu\n')
                    : _result('20.1.8\n');
              }
              return arguments.single == '-dumpmachine'
                  ? _result('x86_64-w64-mingw32\n')
                  : _result('14.2.0\n');
            },
        oneApiRoot: joinPath(root.path, 'missing-oneapi'),
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
        msys2Root: msys2Root,
        environment: const <String, String>{},
      );

      expect(compilers, hasLength(1));
      expect(compilers.single.kind, CompilerKind.mingw);
      expect(compilers.single.version, '14.2.0（UCRT64）');
      expect(
        compilers.single.executablePath,
        joinPath(msys2Root, 'ucrt64/bin/gcc.exe'),
      );
    });

    test('仅 MINGW64 可用时采用并在版本串标注已弃用', () async {
      final Directory root = _tempDirectory();
      final String msys2Root = joinPath(root.path, 'msys64');
      _createFile(joinPath(msys2Root, 'mingw64/bin/gcc.exe'));
      _createFile(joinPath(msys2Root, 'mingw64/bin/g++.exe'));

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('vswhere.exe')) {
                throw ProcessException(executable, arguments, 'not found');
              }
              return arguments.single == '-dumpmachine'
                  ? _result('x86_64-w64-mingw32\n')
                  : _result('14.2.0\n');
            },
        oneApiRoot: joinPath(root.path, 'missing-oneapi'),
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
        msys2Root: msys2Root,
        environment: const <String, String>{},
      );

      expect(compilers, hasLength(1));
      expect(compilers.single.version, '14.2.0（MINGW64，已弃用）');
      expect(
        compilers.single.executablePath,
        joinPath(msys2Root, 'mingw64/bin/gcc.exe'),
      );
    });

    test('固定候选缺失时 PATH 兜底并从路径识别子环境', () async {
      final Directory root = _tempDirectory();
      final String binDir = joinPath(root.path, 'custom/ucrt64/bin');
      _createFile(joinPath(binDir, 'gcc.exe'));
      _createFile(joinPath(binDir, 'g++.exe'));

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('gcc.exe')) {
                return arguments.single == '-dumpmachine'
                    ? _result('x86_64-w64-mingw32\n')
                    : _result('14.2.0\n');
              }
              throw ProcessException(executable, arguments, 'not found');
            },
        oneApiRoot: joinPath(root.path, 'missing-oneapi'),
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
        msys2Root: joinPath(root.path, 'missing-msys2'),
        environment: <String, String>{'Path': binDir},
      );

      expect(compilers, hasLength(1));
      expect(compilers.single.version, '14.2.0（UCRT64）');
      expect(compilers.single.executablePath, joinPath(binDir, 'gcc.exe'));
      expect(compilers.single.cxxExecutablePath, joinPath(binDir, 'g++.exe'));
    });

    test('PATH 兜底拒绝 MSVC 目标的 clang', () async {
      final Directory root = _tempDirectory();
      final String llvmBin = joinPath(root.path, 'LLVM/bin');
      _createFile(joinPath(llvmBin, 'clang.exe'));

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('clang.exe')) {
                return _result('x86_64-pc-windows-msvc\n');
              }
              throw ProcessException(executable, arguments, 'not found');
            },
        oneApiRoot: joinPath(root.path, 'missing-oneapi'),
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
        msys2Root: joinPath(root.path, 'missing-msys2'),
        environment: <String, String>{'PATH': llvmBin},
      );

      expect(compilers, isEmpty);
    });

    test('MSYS2_ROOT 覆盖默认安装根', () async {
      final Directory root = _tempDirectory();
      final String msys2Root = joinPath(root.path, 'custom-msys2');
      _createFile(joinPath(msys2Root, 'ucrt64/bin/gcc.exe'));
      _createFile(joinPath(msys2Root, 'ucrt64/bin/g++.exe'));

      final List<DetectedCompiler> compilers = await detectCompilers(
        runner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              if (executable.endsWith('vswhere.exe')) {
                throw ProcessException(executable, arguments, 'not found');
              }
              return arguments.single == '-dumpmachine'
                  ? _result('x86_64-w64-mingw32\n')
                  : _result('14.2.0\n');
            },
        oneApiRoot: joinPath(root.path, 'missing-oneapi'),
        llvmBinDir: joinPath(root.path, 'missing-llvm/bin'),
        vswherePath: joinPath(root.path, 'missing-vswhere.exe'),
        environment: <String, String>{'MSYS2_ROOT': msys2Root},
      );

      expect(compilers, hasLength(1));
      expect(compilers.single.version, '14.2.0（UCRT64）');
      expect(
        compilers.single.executablePath,
        joinPath(msys2Root, 'ucrt64/bin/gcc.exe'),
      );
    });

    test('environment 透传给各编译器探测子进程', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
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
          if (call.executable.endsWith('icx.exe')) {
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
        msys2Root: joinPath(root.path, 'missing-msys2'),
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
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
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
        joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'),
      );
      final _ProcessCall icxProbe = calls.singleWhere(
        (_ProcessCall call) => call.executable.endsWith('icx.exe'),
      );
      expect(icxProbe.environment?['TMP'], r'C:\tools\.tmp\build');
    });

    test('clang-cl 无环境脚本时继承 MSVC 的 vcvars 脚本', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
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
              if (executable.endsWith('icx.exe')) {
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
