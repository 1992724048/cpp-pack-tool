import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
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
  group('captureToolchainEnvironment', () {
    test('无环境脚本时返回 base 拷贝且不执行进程', () async {
      final Map<String, String> base = <String, String>{'FOO': 'bar'};
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final Map<String, String> environment = await captureToolchainEnvironment(
        _compiler(environmentScript: null),
        runner: _runner(calls, (_) async => throw StateError('不应执行进程')),
        baseEnvironment: base,
      );

      expect(environment, <String, String>{'FOO': 'bar'});
      environment['FOO'] = 'changed';
      expect(base['FOO'], 'bar');
      expect(calls, isEmpty);
    });

    test('经临时批处理包装捕获 set 输出：忽略杂项行、大小写不敏感覆盖 base', () async {
      final Directory root = _tempDirectory();
      final String script = joinPath(root.path, 'Build/vcvars64.bat');
      final Map<String, String> base = <String, String>{
        'KEEP': '1',
        'vctoolsinstalldir': 'old',
      };
      final String setOutput = <String>[
        r'VCToolsInstallDir=C:\VC',
        r'=C:=C:\',
        '',
        r'Path=C:\VC\bin;C:\Windows',
        r'ProgramFiles=C:\Program Files',
        'NO_SEPARATOR_LINE',
      ].join('\r\n');
      final List<_ProcessCall> calls = <_ProcessCall>[];
      String? wrapperContent;

      final Map<String, String> environment = await captureToolchainEnvironment(
        _compiler(environmentScript: script),
        runner: _runner(calls, (_ProcessCall call) async {
          wrapperContent = File(call.arguments[1]).readAsStringSync();
          return ProcessResult(0, 0, setOutput, '');
        }),
        baseEnvironment: base,
      );

      expect(calls, hasLength(1));
      expect(calls.single.executable, 'cmd');
      expect(calls.single.arguments, hasLength(2));
      expect(calls.single.arguments.first, '/c');
      expect(calls.single.arguments[1], endsWith('capture.cmd'));
      expect(
        wrapperContent,
        '@echo off\r\ncall "$script" >nul 2>&1 && set\r\n',
      );
      expect(calls.single.environment, base);

      expect(environment[r'VCToolsInstallDir'], r'C:\VC');
      expect(environment[r'Path'], r'C:\VC\bin;C:\Windows');
      expect(environment['ProgramFiles'], r'C:\Program Files');
      expect(environment['KEEP'], '1');
      expect(
        environment.keys.where(
          (String key) => key.toLowerCase() == 'vctoolsinstalldir',
        ),
        hasLength(1),
      );
      expect(environment.containsKey(r'=C:'), isFalse);
      expect(environment.containsKey(''), isFalse);
      expect(environment.containsKey('NO_SEPARATOR_LINE'), isFalse);
      expect(base[r'vctoolsinstalldir'], 'old');
      expect(base.containsKey(r'VCToolsInstallDir'), isFalse);
    });

    test('捕获完成后删除包装脚本与临时目录', () async {
      final Directory root = _tempDirectory();
      final String script = joinPath(root.path, 'Build/vcvars64.bat');
      String? wrapperPath;

      final Map<String, String> environment = await captureToolchainEnvironment(
        _compiler(environmentScript: script),
        runner: _runner(<_ProcessCall>[], (_ProcessCall call) async {
          wrapperPath = call.arguments[1];
          expect(File(wrapperPath!).existsSync(), isTrue);
          return ProcessResult(0, 0, '', '');
        }),
        baseEnvironment: <String, String>{},
      );

      expect(environment, isEmpty);
      expect(wrapperPath, isNotNull);
      expect(File(wrapperPath!).existsSync(), isFalse);
      expect(Directory(wrapperPath!).parent.existsSync(), isFalse);
    });

    test('进程非零退出时抛 BuildPreparationException', () async {
      final Directory root = _tempDirectory();
      final String script = joinPath(root.path, 'Build/vcvars64.bat');

      await expectLater(
        captureToolchainEnvironment(
          _compiler(environmentScript: script),
          runner: _runner(
            <_ProcessCall>[],
            (_) async => ProcessResult(0, 1, '', 'error'),
          ),
          baseEnvironment: <String, String>{},
        ),
        throwsA(
          isA<BuildPreparationException>().having(
            (BuildPreparationException error) => error.message,
            'message',
            allOf(contains('退出码 1'), contains(script)),
          ),
        ),
      );
    });

    test('cmd 无法启动时抛 BuildPreparationException 且清理临时目录', () async {
      final Directory root = _tempDirectory();
      final String script = joinPath(root.path, 'Build/setvars.bat');
      String? wrapperPath;

      await expectLater(
        captureToolchainEnvironment(
          _compiler(environmentScript: script),
          runner: _runner(<_ProcessCall>[], (_ProcessCall call) async {
            wrapperPath = call.arguments[1];
            throw ProcessException('cmd', <String>['/c'], 'not found');
          }),
          baseEnvironment: <String, String>{},
        ),
        throwsA(
          isA<BuildPreparationException>().having(
            (BuildPreparationException error) => error.message,
            'message',
            allOf(contains('cmd'), contains(script)),
          ),
        ),
      );

      expect(wrapperPath, isNotNull);
      expect(Directory(wrapperPath!).parent.existsSync(), isFalse);
    });
  });

  group('detectCompilersReadOnly', () {
    test('只读检测不在受控临时目录下进行：子进程环境即传入的 baseEnvironment', () async {
      final Directory root = _tempDirectory();
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx-cl.exe'));
      final Map<String, String> base = <String, String>{
        'ONEAPI_ROOT': oneApiRoot,
        'PATH': r'C:\tools\bin',
        'TMP': r'C:\hostile-tmp',
        'TEMP': r'C:\hostile-temp',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final List<DetectedCompiler> compilers = await detectCompilersReadOnly(
        baseEnvironment: base,
        runner: _runner(
          calls,
          (_) async => ProcessResult(0, 0, 'Compiler 2026.1.0\n', ''),
        ),
      );

      expect(compilers.single.kind, CompilerKind.icx);
      expect(compilers.single.version, '2026.1.0');
      expect(calls.single.environment, base, reason: '只读检测不得改写 TMP/TEMP 或注入任何变量');
      expect(base['TMP'], r'C:\hostile-tmp');
      expect(base['TEMP'], r'C:\hostile-temp');
      expect(
        Directory(root.path)
            .listSync()
            .map((FileSystemEntity entity) => baseName(entity.path))
            .toList(),
        <String>['oneAPI'],
        reason: '只读检测不得创建任何临时目录',
      );
    });

    test('注入检测函数时直接采用其结果', () async {
      final List<DetectedCompiler> injected = <DetectedCompiler>[_compiler()];

      final List<DetectedCompiler> compilers = await detectCompilersReadOnly(
        baseEnvironment: <String, String>{},
        detect: () async => injected,
        runner: _runner(
          <_ProcessCall>[],
          (_) async => throw StateError('不应执行进程'),
        ),
      );

      expect(compilers, same(injected));
    });
  });

  group('assembleBuildEnvironment', () {
    test('前置工具目录与编译器目录、附加目录并保留 PATH 原值与键名', () {
      final DetectedCompiler compiler = _compiler(
        kind: CompilerKind.clangCl,
        version: '23.1.1',
        executablePath: r'C:\LLVM\bin\clang-cl.exe',
        extraPathEntries: <String>[r'C:\LLVM\bin'],
      );
      final Directory tools = _tempDirectory();
      final Map<String, String> base = <String, String>{
        'Path': r'C:\Windows;C:\Windows\System32',
        'KEEP': '1',
      };

      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: compiler,
        environment: base,
        toolsRoot: tools.path,
        packageRoot: r'C:\libs\demo',
      );

      expect(
        result.environment['Path'],
        '${tools.path};${r'C:\LLVM\bin'};'
        r'C:\Windows;C:\Windows\System32',
      );
      expect(result.environment['KEEP'], '1');
      expect(result.compiler, same(compiler));
      expect(result.toolsDir, tools.path);
      expect(result.environment['CNP_TOOLS_DIR'], tools.path);
      expect(result.environment['CNP_COMPILER'], r'C:\LLVM\bin\clang-cl.exe');
      expect(base['Path'], r'C:\Windows;C:\Windows\System32');
      expect(base.containsKey('CNP_TOOLS_DIR'), isFalse);
    });

    test('共享工具目录自身与其下所有递归子目录都前置到 PATH', () {
      final Directory tools = _tempDirectory();
      Directory('${tools.path}/cmake/bin').createSync(recursive: true);
      Directory('${tools.path}/nasm').createSync(recursive: true);
      Directory('${tools.path}/deep/nested/dir').createSync(recursive: true);

      final BuildEnvironment env = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{'Path': r'C:\Windows\system32'},
        toolsRoot: tools.path,
        packageRoot: r'C:\libs\demo',
      );

      final String path = env.environment['Path']!;
      expect(
        path,
        '${tools.path};${tools.path}\\cmake;${tools.path}\\cmake\\bin;'
        '${tools.path}\\deep;${tools.path}\\deep\\nested;'
        '${tools.path}\\deep\\nested\\dir;${tools.path}\\nasm;'
        r'C:\VC;C:\Windows\system32',
      );
      expect(path, contains(tools.path), reason: '工具根目录自身也要在 PATH 上');
      expect(
        path,
        contains(r'C:\Windows\system32'),
        reason: '原有 PATH 必须保留',
      );
    });

    test('只注入 CNP_PACKAGE_ROOT/CNP_SRC_DIR/CNP_TMP_DIR/CNP_TOOLS_DIR/CNP_COMPILER 五个变量', () {
      final BuildEnvironment env = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{},
        toolsRoot: r'C:\tools',
        packageRoot: r'C:\libs\demo',
      );

      final Map<String, String> e = env.environment;
      expect(e['CNP_PACKAGE_ROOT'], r'C:\libs\demo');
      expect(e['CNP_SRC_DIR'], r'C:\libs\demo\.cache\src');
      expect(e['CNP_TMP_DIR'], r'C:\libs\demo\.cache\tmp');
      expect(e['CNP_TOOLS_DIR'], r'C:\tools');
      expect(e['CNP_COMPILER'], isNotNull);

      final Iterable<String> injected = e.keys.where((String k) => k.startsWith('CNP_'));
      expect(injected.toSet(), <String>{
        'CNP_PACKAGE_ROOT', 'CNP_SRC_DIR', 'CNP_TMP_DIR', 'CNP_TOOLS_DIR', 'CNP_COMPILER',
      }, reason: '不得有多余的 CNP_ 变量');
      expect(e.containsKey('PYTHONPATH'), isFalse, reason: '不再注入 PYTHONPATH');
    });

    test('调用方声明的 TMP/TEMP 原样透传，不被改写成受控临时目录', () {
      final BuildEnvironment env = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{
          'TMP': r'C:\Windows\Temp',
          'TEMP': r'C:\Windows\Temp',
        },
        toolsRoot: r'C:\tools',
        packageRoot: r'C:\libs\demo',
      );

      expect(env.environment['TMP'], r'C:\Windows\Temp');
      expect(env.environment['TEMP'], r'C:\Windows\Temp');
    });

    test('不推导 windres：调用方显式声明的 CNP_RC_COMPILER 原样透传，本层不推导也不覆盖', () {
      final Directory root = _tempDirectory();
      final String llvmBinDir = joinPath(root.path, 'LLVM/bin');
      final String clangCl = joinPath(llvmBinDir, 'clang-cl.exe');
      _createFile(clangCl);
      _createFile(joinPath(llvmBinDir, 'windres.exe'));
      final DetectedCompiler compiler = DetectedCompiler(
        kind: CompilerKind.clangCl,
        version: '23.1.1',
        executablePath: clangCl,
        environmentScript: null,
        extraPathEntries: <String>[llvmBinDir],
      );

      final BuildEnvironment derived = assembleBuildEnvironment(
        compiler: compiler,
        environment: <String, String>{'FOO': '1'},
        toolsRoot: r'C:\tools',
        packageRoot: r'C:\libs\demo',
      );

      expect(
        derived.environment.containsKey('CNP_RC_COMPILER'),
        isFalse,
        reason: 'RC 编译器不由编译器可执行文件目录推导',
      );

      final BuildEnvironment declared = assembleBuildEnvironment(
        compiler: compiler,
        environment: <String, String>{
          'FOO': '1',
          'CNP_RC_COMPILER': r'D:\tools\windres.exe',
        },
        toolsRoot: r'C:\tools',
        packageRoot: r'C:\libs\demo',
      );

      expect(declared.environment['CNP_RC_COMPILER'], r'D:\tools\windres.exe');
      expect(
        declared.environment['CNP_COMPILER'],
        isNot(equals(r'D:\tools\windres.exe')),
        reason: 'CNP_COMPILER 恒为首选编译器路径，不受调用方声明影响',
      );
    });

    test('PATH 前置条目大小写不敏感去重、跳过空条目并保留首个写法', () {
      final DetectedCompiler compiler = _compiler(
        executablePath: r'C:\LLVM\bin\clang-cl.exe',
        extraPathEntries: <String>[r'C:\LLVM\BIN', '  ', r'C:\LLVM\bin'],
      );
      final Directory tools = _tempDirectory();

      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: compiler,
        environment: <String, String>{'Path': r'C:\Windows'},
        toolsRoot: tools.path,
        packageRoot: r'C:\libs\demo',
      );

      expect(
        result.environment['Path'],
        '${tools.path};${r'C:\LLVM\bin'};${r'C:\Windows'}',
      );
    });

    test('无 PATH 键时以 Path 键写入前置目录', () {
      final Directory tools = _tempDirectory();
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(extraPathEntries: <String>[r'C:\LLVM\bin']),
        environment: <String, String>{'FOO': '1'},
        toolsRoot: tools.path,
        packageRoot: r'C:\libs\demo',
      );

      expect(
        result.environment['Path'],
        '${tools.path};${r'C:\VC'};${r'C:\LLVM\bin'}',
      );
      expect(result.environment['FOO'], '1');
    });

    test('工具目录不可枚举时只前置其自身且不抛错', () {
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{'FOO': '1'},
        toolsRoot: r'C:\not-exist-tools',
        packageRoot: r'C:\libs\demo',
      );

      expect(
        result.environment['Path'],
        r'C:\not-exist-tools;C:\VC',
        reason: '工具目录读不动不应阻断构建，其自身仍应前置',
      );
      expect(result.environment['CNP_TOOLS_DIR'], r'C:\not-exist-tools');
    });

    test('不下发任何编译参数 Profile 变量', () {
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{'FOO': '1'},
        toolsRoot: r'C:\tools',
        packageRoot: r'C:\libs\demo',
      );

      expect(
        result.environment.keys
            .where((String key) => key.startsWith('CNP_BUILD_PROFILE_')),
        isEmpty,
      );
      expect(
        result.environment.keys
            .any((String key) => key.endsWith('_RUNTIME')),
        isFalse,
      );
      expect(result.environment['FOO'], '1');
    });

    test('父环境残留的旧运行库与旧 IPO 键按普通变量原样透传', () {
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(kind: CompilerKind.msvc),
        environment: <String, String>{
          'cnp_runtime_library': 'mt',
          'Cnp_No_Ipo': '1',
        },
        toolsRoot: r'C:\tools',
        packageRoot: r'C:\libs\demo',
      );

      expect(
        result.environment['cnp_runtime_library'],
        'mt',
        reason: '无对应清理契约，按父环境原样透传',
      );
      expect(
        result.environment['Cnp_No_Ipo'],
        '1',
        reason: '旧 IPO 键已无消费方，同样按父环境原样透传',
      );
    });
  });

  group('prepareBuildEnvironment', () {
    test('缓存有效时直接选择缓存编译器且不触发检测', () async {
      final Directory root = _tempDirectory();
      final DetectedCompiler cached = _cachedCompiler(root);
      int detectCalls = 0;
      final List<List<DetectedCompiler>> reported = <List<DetectedCompiler>>[];

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        priority: <String>['msvc'],
        toolsRoot: joinPath(root.path, 'tools'),
        baseEnvironment: <String, String>{},
        cachedCompilers: <DetectedCompiler>[cached],
        onCompilersDetected: reported.add,
        detect: () async {
          detectCalls++;
          return const <DetectedCompiler>[];
        },
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(detectCalls, 0);
      expect(reported, isEmpty);
      expect(result.compiler, same(cached));
      expect(result.environment['CNP_COMPILER'], cached.executablePath);
    });

    test('缓存可执行文件缺失时重检并回调新结果', () async {
      final Directory root = _tempDirectory();
      final DetectedCompiler stale = _compiler(
        executablePath: joinPath(root.path, 'missing/cl.exe'),
      );
      final DetectedCompiler fresh = _cachedCompiler(root);
      int detectCalls = 0;
      final List<List<DetectedCompiler>> reported = <List<DetectedCompiler>>[];

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        priority: <String>['msvc'],
        toolsRoot: joinPath(root.path, 'tools'),
        baseEnvironment: <String, String>{},
        cachedCompilers: <DetectedCompiler>[stale],
        onCompilersDetected: reported.add,
        detect: () async {
          detectCalls++;
          return <DetectedCompiler>[fresh];
        },
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(detectCalls, 1);
      expect(reported, hasLength(1));
      expect(reported.single.single, same(fresh));
      expect(result.compiler, same(fresh));
    });

    test('缓存环境脚本缺失时视为失效并重检', () async {
      final Directory root = _tempDirectory();
      final DetectedCompiler cached = _cachedCompiler(root);
      final DetectedCompiler stale = DetectedCompiler(
        kind: cached.kind,
        version: cached.version,
        executablePath: cached.executablePath,
        environmentScript: joinPath(root.path, 'missing/vcvars64.bat'),
      );

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        priority: <String>['msvc'],
        toolsRoot: joinPath(root.path, 'tools'),
        baseEnvironment: <String, String>{},
        cachedCompilers: <DetectedCompiler>[stale],
        detect: () async => <DetectedCompiler>[cached],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(result.compiler, same(cached));
    });

    test('缓存有效但均不匹配优先级时重检', () async {
      final Directory root = _tempDirectory();
      final DetectedCompiler cached = _cachedCompiler(root);
      final DetectedCompiler icx = _compiler(
        kind: CompilerKind.icx,
        version: '2026.1.0',
        executablePath: joinPath(root.path, 'icx-cl.exe'),
      );
      int detectCalls = 0;

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        priority: <String>['icx'],
        toolsRoot: joinPath(root.path, 'tools'),
        baseEnvironment: <String, String>{},
        cachedCompilers: <DetectedCompiler>[cached],
        detect: () async {
          detectCalls++;
          return <DetectedCompiler>[icx];
        },
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(detectCalls, 1);
      expect(result.compiler, same(icx));
    });

    test('无缓存时保持原行为：检测并经回调上报新结果', () async {
      final Directory root = _tempDirectory();
      final DetectedCompiler detectedCompiler = _compiler();
      final List<List<DetectedCompiler>> reported = <List<DetectedCompiler>>[];

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        priority: <String>['msvc'],
        toolsRoot: joinPath(root.path, 'tools'),
        baseEnvironment: <String, String>{},
        onCompilersDetected: reported.add,
        detect: () async => <DetectedCompiler>[detectedCompiler],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(reported, hasLength(1));
      expect(reported.single.single, same(detectedCompiler));
      expect(result.compiler, same(detectedCompiler));
    });

    test('按优先级选择编译器并透传捕获环境', () async {
      final Directory root = _tempDirectory();
      final DetectedCompiler msvc = _compiler();
      final DetectedCompiler clangCl = _compiler(
        kind: CompilerKind.clangCl,
        version: '23.1.1',
        executablePath: r'C:\LLVM\bin\clang-cl.exe',
        extraPathEntries: <String>[r'C:\LLVM\bin'],
      );
      final Map<String, String> base = <String, String>{'FOO': '1'};
      final List<CompilerKind> captured = <CompilerKind>[];

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        priority: <String>['clang-cl', 'msvc'],
        runner: _runner(
          <_ProcessCall>[],
          (_) async => throw StateError('不应执行进程'),
        ),
        toolsRoot: joinPath(root.path, 'tools'),
        baseEnvironment: base,
        detect: () async => <DetectedCompiler>[msvc, clangCl],
        capture: _captureStub(captured, (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return <String, String>{...baseEnvironment, 'CAPTURED': 'yes'};
        }),
      );

      expect(result.compiler, same(clangCl));
      expect(captured, <CompilerKind>[CompilerKind.clangCl]);
      expect(result.environment['FOO'], '1');
      expect(result.environment['CAPTURED'], 'yes');
      expect(result.environment['CNP_COMPILER'], r'C:\LLVM\bin\clang-cl.exe');
      expect(result.environment['CNP_PACKAGE_ROOT'], r'C:\libs\demo');
      expect(base, <String, String>{'FOO': '1'});
    });

    test('调用方声明的 TMP/TEMP 与父环境原样透传，不注入受控临时目录', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = '${root.path}\\tools';
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
      final Map<String, String> base = <String, String>{
        'ONEAPI_ROOT': oneApiRoot,
        'TMP': r'C:\hostile-tmp',
        'TEMP': r'C:\hostile-temp',
        'KEEP': '1',
      };
      final List<_ProcessCall> calls = <_ProcessCall>[];
      Map<String, String>? captureBase;

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        toolsRoot: toolsRoot,
        baseEnvironment: base,
        runner: _runner(calls, (_ProcessCall call) async {
          return ProcessResult(0, 0, 'Compiler 2026.1.0\n', '');
        }),
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          captureBase = baseEnvironment;
          return <String, String>{...baseEnvironment, 'CAPTURED': 'yes'};
        }),
      );

      expect(result.compiler.kind, CompilerKind.icx);
      expect(result.compiler.version, '2026.1.0');
      final Iterable<_ProcessCall> icxProbes = calls.where(
        (_ProcessCall call) => call.executable.endsWith('icx.exe'),
      );
      expect(icxProbes, hasLength(1));
      expect(
        icxProbes.single.environment,
        base,
        reason: '检测子进程直接使用原始环境，不改写 TMP/TEMP',
      );
      expect(captureBase, same(base), reason: '捕获入参即原始 base 环境');
      expect(result.environment['TMP'], r'C:\hostile-tmp');
      expect(result.environment['TEMP'], r'C:\hostile-temp');
      expect(result.environment['KEEP'], '1');
      expect(result.environment['CAPTURED'], 'yes');
      expect(
        result.environment.values.any((String value) => value.contains(r'\.tmp')),
        isFalse,
        reason: '不得注入受控临时目录',
      );
      expect(Directory(toolsRoot).existsSync(), isFalse, reason: '不创建工具目录');
    });

    test('baseEnvironment 为 null 时以宿主环境为底且不改写宿主 TMP/TEMP', () async {
      final Directory root = _tempDirectory();
      Map<String, String>? captureBase;

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        toolsRoot: '${root.path}\\tools',
        detect: () async => <DetectedCompiler>[_compiler()],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          captureBase = baseEnvironment;
          return Map<String, String>.of(baseEnvironment);
        }),
      );

      expect(captureBase, isNotNull);
      expect(captureBase?['TMP'], Platform.environment['TMP']);
      expect(captureBase?['TEMP'], Platform.environment['TEMP']);
      expect(result.environment['TMP'], Platform.environment['TMP']);
      expect(result.environment['TEMP'], Platform.environment['TEMP']);
    });

    test('无可用编译器时抛 BuildPreparationException 且不捕获', () async {
      final List<CompilerKind> captured = <CompilerKind>[];

      await expectLater(
        prepareBuildEnvironment(
          packageRoot: r'C:\libs\demo',
          baseEnvironment: <String, String>{},
          detect: () async => <DetectedCompiler>[],
          capture: _captureStub(captured, (
            DetectedCompiler compiler,
            Map<String, String> baseEnvironment,
          ) {
            return baseEnvironment;
          }),
        ),
        throwsA(
          isA<BuildPreparationException>().having(
            (BuildPreparationException error) => error.message,
            'message',
            allOf(
              contains('未检测到可用编译器'),
              isNot(contains('clang/LLVM')),
            ),
          ),
        ),
      );

      expect(captured, isEmpty);
    });

    test('检测结果不在优先级列表内时视为无可用编译器', () async {
      await expectLater(
        prepareBuildEnvironment(
          packageRoot: r'C:\libs\demo',
          priority: <String>['icx'],
          baseEnvironment: <String, String>{},
          detect: () async => <DetectedCompiler>[_compiler()],
          capture: _captureStub(<CompilerKind>[], (
            DetectedCompiler compiler,
            Map<String, String> baseEnvironment,
          ) {
            return baseEnvironment;
          }),
        ),
        throwsA(isA<BuildPreparationException>()),
      );
    });

    test('返回新环境且不修改传入 base（捕获直接返回 base 时同样安全）', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = '${root.path}\\tools';
      final Map<String, String> base = <String, String>{
        'FOO': '1',
        'Path': r'C:\Windows',
      };

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        toolsRoot: toolsRoot,
        baseEnvironment: base,
        detect: () async => <DetectedCompiler>[
          _compiler(extraPathEntries: <String>[r'C:\LLVM\bin']),
        ],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(
        result.environment['Path'],
        '${Directory(toolsRoot).absolute.path};${r'C:\VC'};'
        r'C:\LLVM\bin;C:\Windows',
      );
      expect(result.environment['CNP_PACKAGE_ROOT'], r'C:\libs\demo');
      expect(base['Path'], r'C:\Windows');
      expect(base.containsKey('CNP_PACKAGE_ROOT'), isFalse);
    });

    test('工具根目录与其下所有递归子目录整体前置到 PATH', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = '${root.path}\\tools';
      Directory('$toolsRoot/cmake/bin').createSync(recursive: true);
      Directory('$toolsRoot/nasm').createSync(recursive: true);
      final Map<String, String> base = <String, String>{'Path': r'C:\Windows'};

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: r'C:\libs\demo',
        priority: <String>['msvc'],
        toolsRoot: toolsRoot,
        baseEnvironment: base,
        detect: () async => <DetectedCompiler>[
          _compiler(extraPathEntries: <String>[r'C:\LLVM\bin']),
        ],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      final String toolsDir = Directory(toolsRoot).absolute.path;
      expect(
        result.environment['Path'],
        '$toolsDir;$toolsDir\\cmake;$toolsDir\\cmake\\bin;$toolsDir\\nasm;'
        r'C:\VC;C:\LLVM\bin;C:\Windows',
      );
      expect(result.environment['CNP_TOOLS_DIR'], toolsDir);
      expect(base['Path'], r'C:\Windows');
    });
  });

  group('preparePackBuildEnvironment', () {
    test('以包源目录为 packageRoot 下发 CNP_PACKAGE_ROOT 与其下的源码/中间产物区', () async {
      final Directory root = _tempDirectory();
      final PackModel pack = _pack(sourcePath: root.path);

      final BuildEnvironment result = await preparePackBuildEnvironment(
        pack,
        priority: <String>['msvc'],
        toolsRoot: '${root.path}\\tools',
        baseEnvironment: <String, String>{'FOO': '1'},
        detect: () async => <DetectedCompiler>[_compiler()],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(result.environment['CNP_PACKAGE_ROOT'], root.path);
      expect(result.environment['CNP_SRC_DIR'], '${root.path}\\.cache\\src');
      expect(result.environment['CNP_TMP_DIR'], '${root.path}\\.cache\\tmp');
      expect(result.environment['FOO'], '1');
    });

    test('包级入口不下发编译参数与选项变量且不改写老包 buildOptions', () async {
      Future<Map<String, String>> prepare(PackModel pack) async {
        final BuildEnvironment result = await preparePackBuildEnvironment(
          pack,
          priority: <String>['msvc'],
          toolsRoot: r'C:\tools',
          baseEnvironment: <String, String>{},
          detect: () async => <DetectedCompiler>[_compiler()],
          capture: _captureStub(<CompilerKind>[], (
            DetectedCompiler compiler,
            Map<String, String> baseEnvironment,
          ) {
            return baseEnvironment;
          }),
        );
        return result.environment;
      }

      final PackModel legacy = _pack(
        sourcePath: r'C:\libs\demo',
        buildOptions: <String, String>{'runtime': 'MT'},
      );
      final Map<String, String> environment = await prepare(legacy);

      expect(
        environment.keys
            .where((String key) => key.startsWith('CNP_BUILD_PROFILE_')),
        isEmpty,
        reason: '编译参数由配方自定，包级入口不投影任何 Profile 变量',
      );
      expect(
        environment.keys.any((String key) => key.startsWith('CNP_OPTION_')),
        isFalse,
        reason: '不再注入构建选项变量',
      );
      expect(environment['CNP_COMPILER'], r'C:\VC\cl.exe');
      expect(legacy.buildOptions['runtime'], 'MT', reason: '旧 YAML 键不再被改写');
    });

    test('包缺少源目录信息时抛 BuildPreparationException 且不检测编译器', () async {
      await expectLater(
        preparePackBuildEnvironment(
          _pack(),
          priority: <String>['msvc'],
          baseEnvironment: <String, String>{},
          detect: () async => throw StateError('不应检测编译器'),
          capture: _captureStub(<CompilerKind>[], (
            DetectedCompiler compiler,
            Map<String, String> baseEnvironment,
          ) {
            return baseEnvironment;
          }),
        ),
        throwsA(
          isA<BuildPreparationException>().having(
            (BuildPreparationException error) => error.message,
            'message',
            contains('该包缺少源目录信息'),
          ),
        ),
      );
    });
  });
}

DetectedCompiler _compiler({
  CompilerKind kind = CompilerKind.msvc,
  String version = '14.44.35207',
  String executablePath = r'C:\VC\cl.exe',
  String? environmentScript,
  List<String> extraPathEntries = const <String>[],
}) {
  return DetectedCompiler(
    kind: kind,
    version: version,
    executablePath: executablePath,
    environmentScript: environmentScript,
    extraPathEntries: extraPathEntries,
  );
}

/// 在 [root] 下落盘可执行文件的可用缓存条目（跨会话复用的有效性判据）。
DetectedCompiler _cachedCompiler(
  Directory root, {
  CompilerKind kind = CompilerKind.msvc,
  String? environmentScript,
}) {
  final String executable = joinPath(root.path, '${compilerKindId(kind)}.exe');
  _createFile(executable);
  final String? script = environmentScript == null
      ? null
      : joinPath(root.path, 'Build/$environmentScript');
  if (script != null) {
    _createFile(script);
  }
  return DetectedCompiler(
    kind: kind,
    version: '14.44.35207',
    executablePath: executable,
    environmentScript: script,
  );
}

/// 捕获函数替身：记录选中编译器，环境内容由 [build] 决定。
ToolchainEnvironmentCapture _captureStub(
  List<CompilerKind> selected,
  Map<String, String> Function(
    DetectedCompiler compiler,
    Map<String, String> baseEnvironment,
  )
  build,
) {
  return (
    DetectedCompiler compiler, {
    PackProcessRunner runner = Process.run,
    Map<String, String>? baseEnvironment,
  }) async {
    selected.add(compiler.kind);
    return build(compiler, baseEnvironment ?? const <String, String>{});
  };
}

PackModel _pack({
  String? sourcePath,
  Map<String, String> buildOptions = const <String, String>{},
}) {
  final PackModel pack = PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
    sourcePath: sourcePath,
  );
  pack.buildOptions = <String, String>{...buildOptions};
  return pack;
}

void _createFile(String path, {String content = 'MZ'}) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Directory _tempDirectory() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'cpp_nuget_pack_build_env_',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
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
