import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
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
      final Directory root = _tempDirectory();
      final Map<String, String> base = <String, String>{'FOO': 'bar'};
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final Map<String, String> environment = await captureToolchainEnvironment(
        _compiler(environmentScript: null),
        runner: _runner(calls, (_) async => throw StateError('不应执行进程')),
        baseEnvironment: base,
        scratchDirectory: root.path,
      );

      expect(environment, <String, String>{'FOO': 'bar'});
      environment['FOO'] = 'changed';
      expect(base['FOO'], 'bar');
      expect(calls, isEmpty);
      expect(
        Directory(root.path).listSync(),
        isEmpty,
        reason: '无环境脚本时连包装目录都不该建',
      );
    });

    test('经临时批处理包装捕获 set 输出：忽略杂项行、大小写不敏感覆盖 base', () async {
      final Directory root = _tempDirectory();
      final String script = joinPath(root.path, 'Build/vcvars64.bat');
      _createFile(script);
      final Directory scratch = _tempDirectory();
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
        scratchDirectory: scratch.path,
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

    test('包装脚本建在指定 scratchDirectory 下的 cnp-env-* 子目录，用完连子目录一并删除', () async {
      final Directory root = _tempDirectory();
      final String script = joinPath(root.path, 'Build/vcvars64.bat');
      _createFile(script);
      final Directory scratch = _tempDirectory();
      String? wrapperPath;

      final Map<String, String> environment = await captureToolchainEnvironment(
        _compiler(environmentScript: script),
        runner: _runner(<_ProcessCall>[], (_ProcessCall call) async {
          wrapperPath = call.arguments[1];
          expect(File(wrapperPath!).existsSync(), isTrue);
          return ProcessResult(0, 0, '', '');
        }),
        baseEnvironment: <String, String>{},
        scratchDirectory: scratch.path,
      );

      expect(environment, isEmpty);
      expect(wrapperPath, isNotNull);
      final Directory wrapperDir = Directory(wrapperPath!).parent;
      expect(
        wrapperDir.parent.path.toLowerCase(),
        scratch.absolute.path.toLowerCase(),
        reason: '包装目录必须落在调用方指定的 scratchDirectory 下，不借道宿主临时目录',
      );
      expect(baseName(wrapperDir.path), startsWith('cnp-env-'));
      expect(File(wrapperPath!).existsSync(), isFalse);
      expect(wrapperDir.existsSync(), isFalse, reason: '捕获用的子目录用完即删');
      expect(scratch.existsSync(), isTrue, reason: 'scratchDirectory 本身不得删除');
    });

    test('scratchDirectory 不可用时抛 BuildPreparationException 且不起进程', () async {
      final Directory root = _tempDirectory();
      final String script = joinPath(root.path, 'Build/setvars.bat');
      final String blocked = joinPath(root.path, 'blocked');
      _createFile(blocked, content: 'not a directory');
      final List<_ProcessCall> calls = <_ProcessCall>[];

      await expectLater(
        captureToolchainEnvironment(
          _compiler(environmentScript: script),
          runner: _runner(calls, (_) async => throw StateError('不应执行进程')),
          baseEnvironment: <String, String>{},
          scratchDirectory: blocked,
        ),
        throwsA(
          isA<BuildPreparationException>().having(
            (BuildPreparationException error) => error.message,
            'message',
            allOf(contains('无法在'), contains(blocked)),
          ),
        ),
      );

      expect(
        calls,
        isEmpty,
        reason: '包装目录建不出来就不该起 cmd，更不该把原始文件系统异常漏给用户',
      );
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
          scratchDirectory: root.path,
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

    test('cmd 无法启动时抛 BuildPreparationException 且清理包装目录', () async {
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
          scratchDirectory: root.path,
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
    test('只读检测不改写环境也不建目录：子进程环境即传入的 baseEnvironment', () async {
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
        reason: '只读检测不得创建任何目录',
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

    test('只注入五个 CNP_* 变量（TMP/TEMP 的无条件改写由另两条用例守住）', () {
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

    test('TMP/TEMP 无条件改写为 <包源>/.cache/tmp，与 CNP_TMP_DIR 同值且不改写入参', () {
      final Map<String, String> base = <String, String>{
        'tmp': r'C:\Windows\Temp',
        'temp': r'C:\Windows\Temp',
      };

      final BuildEnvironment env = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: base,
        toolsRoot: r'C:\tools',
        packageRoot: r'C:\libs\demo',
      );

      expect(env.environment['TMP'], r'C:\libs\demo\.cache\tmp');
      expect(env.environment['TEMP'], r'C:\libs\demo\.cache\tmp');
      expect(env.environment['CNP_TMP_DIR'], env.environment['TMP']);
      expect(
        env.environment.keys.where(
          (String key) => <String>{'tmp', 'temp'}.contains(key.toLowerCase()),
        ),
        <String>{'TMP', 'TEMP'},
        reason: '键大小写不敏感：小写 tmp 不得与 TMP 并存',
      );
      expect(
        base,
        <String, String>{'tmp': r'C:\Windows\Temp', 'temp': r'C:\Windows\Temp'},
        reason: '入参不得被改写',
      );
    });

    test('宿主 TMP 存在且可写时仍无条件改写：可用不等于放行', () {
      final Directory hostTmp = _tempDirectory();
      final File probe = File(joinPath(hostTmp.path, 'probe.tmp'));
      probe.writeAsStringSync('x');
      expect(
        probe.existsSync(),
        isTrue,
        reason: '前置条件：这个宿主 TMP 确实存在且可写',
      );
      final String packageRoot = joinPath(_tempDirectory().path, 'demo');

      final BuildEnvironment env = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{'TMP': hostTmp.path, 'TEMP': hostTmp.path},
        toolsRoot: r'C:\tools',
        packageRoot: packageRoot,
      );

      expect(
        env.environment['TMP'],
        packTmpDirectory(packageRoot),
        reason: '改写按产品裁决无条件执行，不看宿主 TMP 是否可用',
      );
      expect(env.environment['TEMP'], packTmpDirectory(packageRoot));
      expect(
        env.environment.values.any(
          (String value) => value == hostTmp.path,
        ),
        isFalse,
        reason: '宿主 TMP 不得残留到子进程环境',
      );
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
        packageRoot: _packageRoot(root),
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
        packageRoot: _packageRoot(root),
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
        packageRoot: _packageRoot(root),
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
        packageRoot: _packageRoot(root),
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
        packageRoot: _packageRoot(root),
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
        packageRoot: _packageRoot(root),
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
      expect(result.environment['CNP_PACKAGE_ROOT'], _packageRoot(root));
      expect(base, <String, String>{'FOO': '1'});
    });

    test('探测与捕获子进程的 TMP/TEMP 都无条件改写为 <包源>/.cache/tmp', () async {
      final Directory root = _tempDirectory();
      final String packageRoot = joinPath(root.path, 'demo');
      final String buildTmp = packTmpDirectory(packageRoot);
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
        packageRoot: packageRoot,
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
        icxProbes.single.environment?['TMP'],
        buildTmp,
        reason: '宿主临时位置与当前工作目录都不可用时 ICX 在检测阶段就失败，探测子进程必须已拿到改写后的 TMP',
      );
      expect(icxProbes.single.environment?['TEMP'], buildTmp);
      expect(
        captureBase,
        isNot(same(base)),
        reason: '捕获入参是改写后的副本，不是调用方的原始 base',
      );
      expect(captureBase?['TMP'], buildTmp);
      expect(captureBase?['TEMP'], buildTmp);
      expect(result.environment['TMP'], buildTmp);
      expect(result.environment['TEMP'], buildTmp);
      expect(result.environment['CNP_TMP_DIR'], buildTmp);
      expect(result.environment['KEEP'], '1');
      expect(result.environment['CAPTURED'], 'yes');
      expect(
        result.environment.values.any(
          (String value) => value.contains(r'C:\hostile'),
        ),
        isFalse,
        reason: '宿主 TMP/TEMP 不得残留到子进程环境',
      );
      expect(
        Directory(buildTmp).existsSync(),
        isTrue,
        reason: '检测早于构建前的清空重建，改写目标必须先存在',
      );
      expect(Directory(toolsRoot).existsSync(), isFalse, reason: '不创建工具目录');
      expect(
        base,
        <String, String>{
          'ONEAPI_ROOT': oneApiRoot,
          'TMP': r'C:\hostile-tmp',
          'TEMP': r'C:\hostile-temp',
          'KEEP': '1',
        },
        reason: '调用方传入的 base 不得被改写',
      );
    });

    test('改写不按编译器种类分支：ICX 探测失败后接手的是 clang-cl，探测子进程 TMP 同样是包内路径', () async {
      final Directory root = _tempDirectory();
      final String packageRoot = joinPath(root.path, 'demo');
      final String buildTmp = packTmpDirectory(packageRoot);
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
      final String programFiles = joinPath(root.path, 'pf');
      _createFile(joinPath(programFiles, 'LLVM/bin/clang-cl.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: packageRoot,
        toolsRoot: '${root.path}\\tools',
        baseEnvironment: <String, String>{
          'ONEAPI_ROOT': oneApiRoot,
          'ProgramFiles': programFiles,
          'TMP': r'C:\hostile-tmp',
          'TEMP': r'C:\hostile-temp',
        },
        runner: _runner(calls, (_ProcessCall call) async {
          if (call.executable.endsWith('icx.exe')) {
            return ProcessResult(0, 1, '', 'icx: error: unable to make temporary file');
          }
          return ProcessResult(0, 0, 'clang version 23.1.1\n', '');
        }),
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) => baseEnvironment),
      );

      expect(result.compiler.kind, CompilerKind.clangCl);
      final _ProcessCall clangProbe = calls.singleWhere(
        (_ProcessCall call) => call.executable.endsWith('clang-cl.exe'),
      );
      expect(clangProbe.environment?['TMP'], buildTmp, reason: '改写与编译器种类无关');
      expect(clangProbe.environment?['TEMP'], buildTmp);
      expect(result.environment['TMP'], buildTmp);
      expect(result.environment['TEMP'], buildTmp);
    });

    test('中间产物目录不可创建时抛 BuildPreparationException 且不检测编译器', () async {
      final Directory root = _tempDirectory();
      final String packageRoot = joinPath(root.path, 'blocked');
      _createFile(packageRoot, content: 'not a directory');
      final String buildTmp = packTmpDirectory(packageRoot);

      await expectLater(
        prepareBuildEnvironment(
          packageRoot: packageRoot,
          toolsRoot: '${root.path}\\tools',
          baseEnvironment: <String, String>{},
          detect: () async => throw StateError('不应检测编译器'),
          capture: _captureStub(<CompilerKind>[], (
            DetectedCompiler compiler,
            Map<String, String> baseEnvironment,
          ) => baseEnvironment),
        ),
        throwsA(
          isA<BuildPreparationException>().having(
            (BuildPreparationException error) => error.message,
            'message',
            allOf(contains('无法创建中间产物目录'), contains(buildTmp)),
          ),
        ),
      );
    });

    test('baseEnvironment 为 null 时以宿主环境为底，TMP/TEMP 仍改写为 <包源>/.cache/tmp', () async {
      final Directory root = _tempDirectory();
      final String packageRoot = joinPath(root.path, 'demo');
      final String buildTmp = packTmpDirectory(packageRoot);
      Map<String, String>? captureBase;

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: packageRoot,
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

      final Set<String> hostKeys = Platform.environment.keys
          .toSet()
          .difference(<String>{'TMP', 'TEMP'});
      expect(captureBase, isNotNull);
      expect(
        captureBase!.keys.toSet().difference(<String>{'TMP', 'TEMP'}),
        hostKeys,
        reason: '底表仍是宿主环境，只多出被改写的 TMP/TEMP',
      );
      expect(captureBase?['TMP'], buildTmp);
      expect(captureBase?['TEMP'], buildTmp);
      expect(
        result.environment.keys.toSet().difference(<String>{
          'TMP',
          'TEMP',
          'CNP_PACKAGE_ROOT',
          'CNP_SRC_DIR',
          'CNP_TMP_DIR',
          'CNP_TOOLS_DIR',
          'CNP_COMPILER',
        }),
        hostKeys,
        reason: '装配阶段只多出 TMP/TEMP 与五个 CNP_，宿主环境其余部分原样继承',
      );
      expect(result.environment['TMP'], buildTmp);
      expect(result.environment['TEMP'], buildTmp);
    });

    test('宿主 TMP 存在且可写时探测与捕获子进程仍改写：改写无条件，不看可用性', () async {
      final Directory root = _tempDirectory();
      final String packageRoot = _packageRoot(root);
      final String buildTmp = packTmpDirectory(packageRoot);
      final String hostTmp = _tempDirectory().path;
      _createFile(joinPath(hostTmp, 'probe.tmp'));
      final String oneApiRoot = joinPath(root.path, 'oneAPI');
      _createFile(joinPath(oneApiRoot, 'compiler/2026.1/bin/icx.exe'));
      final List<_ProcessCall> calls = <_ProcessCall>[];
      Map<String, String>? captureBase;

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: packageRoot,
        toolsRoot: '${root.path}\\tools',
        baseEnvironment: <String, String>{
          'ONEAPI_ROOT': oneApiRoot,
          'TMP': hostTmp,
          'TEMP': hostTmp,
        },
        runner: _runner(calls, (_) async => ProcessResult(0, 0, 'Compiler 2026.1.0\n', '')),
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          captureBase = baseEnvironment;
          return Map<String, String>.of(baseEnvironment);
        }),
      );

      expect(
        File(joinPath(hostTmp, 'probe.tmp')).existsSync(),
        isTrue,
        reason: '前置条件：这个宿主 TMP 确实存在且可写，条件式实现不会改写它',
      );
      final _ProcessCall probe = calls.singleWhere(
        (_ProcessCall call) => call.executable.endsWith('icx.exe'),
      );
      expect(
        probe.environment?['TMP'],
        buildTmp,
        reason: '宿主 TMP 可用也照样改写，否则「无条件」这条裁决会退化成「能用就不改」',
      );
      expect(probe.environment?['TEMP'], buildTmp);
      expect(captureBase?['TMP'], buildTmp);
      expect(captureBase?['TEMP'], buildTmp);
      expect(result.environment['TMP'], buildTmp);
      expect(result.environment['TEMP'], buildTmp);
    });

    test('环境捕获包装目录建在包内 .cache/tmp，不借道宿主临时目录', () async {
      final Directory root = _tempDirectory();
      final String packageRoot = _packageRoot(root);
      final String buildTmp = packTmpDirectory(packageRoot);
      final List<_ProcessCall> calls = <_ProcessCall>[];
      String? wrapperPath;

      final BuildEnvironment result = await prepareBuildEnvironment(
        packageRoot: packageRoot,
        toolsRoot: '${root.path}\\tools',
        cachedCompilers: <DetectedCompiler>[
          _cachedCompiler(root, environmentScript: 'setvars.bat'),
        ],
        baseEnvironment: <String, String>{
          'TMP': r'C:\hostile-tmp',
          'TEMP': r'C:\hostile-temp',
        },
        runner: _runner(calls, (_ProcessCall call) async {
          wrapperPath = call.arguments[1];
          return ProcessResult(0, 0, 'Path=C:\\VC\\bin\r\n', '');
        }),
      );

      expect(result.compiler.kind, CompilerKind.msvc);
      expect(wrapperPath, isNotNull, reason: '带环境脚本的编译器必过包装文件这一步');
      final Directory wrapperDir = Directory(wrapperPath!).parent;
      expect(
        wrapperDir.parent.absolute.path.toLowerCase(),
        Directory(buildTmp).absolute.path.toLowerCase(),
        reason: '包装目录必须落在已建好的 <包源>/.cache/tmp 下：宿主临时目录不可用'
            '且当前工作目录同样不可写时，借道 Directory.systemTemp 会在起 cmd '
            '之前就抛未包装的异常',
      );
      expect(baseName(wrapperDir.path), startsWith('cnp-env-'));
      expect(wrapperDir.existsSync(), isFalse, reason: '捕获用的子目录用完即删');
      expect(Directory(buildTmp).existsSync(), isTrue, reason: '父目录留给配方的中间产物');
    });

    test('无可用编译器时抛 BuildPreparationException 且不捕获', () async {
      final Directory root = _tempDirectory();
      final List<CompilerKind> captured = <CompilerKind>[];

      await expectLater(
        prepareBuildEnvironment(
          packageRoot: _packageRoot(root),
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
      final Directory root = _tempDirectory();

      await expectLater(
        prepareBuildEnvironment(
          packageRoot: _packageRoot(root),
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
        packageRoot: _packageRoot(root),
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
      expect(result.environment['CNP_PACKAGE_ROOT'], _packageRoot(root));
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
        packageRoot: _packageRoot(root),
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

    test('包级入口不下发编译参数与选项变量', () async {
      final Directory root = _tempDirectory();
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

      final Map<String, String> environment = await prepare(_pack(sourcePath: _packageRoot(root)));

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

/// 捕获函数替身：记录选中编译器，环境内容由 [build] 决定；[scratchDirectories]
/// 非 null 时逐次记录收到的包装目录父目录。
ToolchainEnvironmentCapture _captureStub(
  List<CompilerKind> selected,
  Map<String, String> Function(
    DetectedCompiler compiler,
    Map<String, String> baseEnvironment,
  )
  build, {
  List<String>? scratchDirectories,
}) {
  return (
    DetectedCompiler compiler, {
    PackProcessRunner runner = Process.run,
    Map<String, String>? baseEnvironment,
    required String scratchDirectory,
  }) async {
    selected.add(compiler.kind);
    scratchDirectories?.add(scratchDirectory);
    return build(compiler, baseEnvironment ?? const <String, String>{});
  };
}

PackModel _pack({
  String? sourcePath,
}) {
  return PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
    sourcePath: sourcePath,
  );
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

/// 包源目录夹具：准备流程会在其下建 `.cache/tmp`，故必须落在 [_tempDirectory]
/// 之下，不得用固定盘符路径——那会往测试机上写真实目录。
String _packageRoot(Directory root) => joinPath(root.path, 'demo');

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
