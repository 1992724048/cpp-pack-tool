import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
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

  group('assembleBuildEnvironment', () {
    test('前置工具目录与编译器附加目录并保留 PATH 原值与键名', () {
      final DetectedCompiler compiler = _compiler(
        kind: CompilerKind.clangCl,
        version: '23.1.1',
        executablePath: r'C:\LLVM\bin\clang-cl.exe',
        extraPathEntries: <String>[r'C:\LLVM\bin'],
      );
      final CmakeNinja cmakeNinja = _cmakeNinja(
        pathEntries: <String>[r'C:\tools\ninja', r'C:\tools\cmake\bin'],
      );
      final Map<String, String> base = <String, String>{
        'Path': r'C:\Windows;C:\Windows\System32',
        'KEEP': '1',
      };

      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: compiler,
        environment: base,
        cmakeNinja: cmakeNinja,
        toolsRoot: 'tools',
      );

      expect(
        result.environment['Path'],
        r'C:\tools\ninja;C:\tools\cmake\bin;C:\LLVM\bin;'
        r'C:\Windows;C:\Windows\System32',
      );
      expect(result.environment['KEEP'], '1');
      expect(result.compiler, same(compiler));
      expect(result.cmakePath, cmakeNinja.cmakeExecutable);
      expect(result.ninjaPath, cmakeNinja.ninjaExecutable);
      expect(result.toolsDir, Directory('tools').absolute.path);
      expect(result.environment['CNP_CMAKE'], cmakeNinja.cmakeExecutable);
      expect(result.environment['CNP_NINJA'], cmakeNinja.ninjaExecutable);
      expect(
        result.environment['CNP_TOOLS_DIR'],
        Directory('tools').absolute.path,
      );
      expect(result.environment['CNP_C_COMPILER'], compiler.executablePath);
      expect(result.environment['CNP_CXX_COMPILER'], compiler.executablePath);
      expect(result.environment['CNP_COMPILER_KIND'], 'clang-cl');
      expect(base['Path'], r'C:\Windows;C:\Windows\System32');
      expect(base.containsKey('CNP_CMAKE'), isFalse);
    });

    test('ninja 目录前置到 cmake 目录之前', () {
      final CmakeNinja cmakeNinja = CmakeNinja(
        cmakeExecutable: r'C:\tools\cmake\bin\cmake.exe',
        ninjaExecutable: r'C:\tools\ninja\ninja.exe',
        pathEntries: <String>[
          r'C:\tools\cmake',
          r'C:\tools\cmake\bin',
          r'C:\tools\ninja',
        ],
      );

      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(extraPathEntries: <String>[r'C:\LLVM\bin']),
        environment: <String, String>{'Path': r'C:\Windows'},
        cmakeNinja: cmakeNinja,
        toolsRoot: 'tools',
      );

      expect(
        result.environment['Path'],
        r'C:\tools\ninja;C:\tools\cmake;C:\tools\cmake\bin;'
        r'C:\LLVM\bin;C:\Windows',
      );
    });

    test('PATH 前置条目大小写不敏感去重并保留首个写法', () {
      final DetectedCompiler compiler = _compiler(
        extraPathEntries: <String>[r'C:\LLVM\bin', r'C:\llvm\BIN', '  '],
      );
      final CmakeNinja cmakeNinja = _cmakeNinja(
        pathEntries: <String>[r'C:\tools\ninja', r'C:\TOOLS\NINJA'],
      );

      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: compiler,
        environment: <String, String>{'Path': r'C:\Windows'},
        cmakeNinja: cmakeNinja,
        toolsRoot: 'tools',
      );

      expect(
        result.environment['Path'],
        r'C:\tools\ninja;C:\LLVM\bin;C:\Windows',
      );
    });

    test('无 PATH 键时以 Path 键写入前置目录', () {
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(extraPathEntries: <String>[r'C:\LLVM\bin']),
        environment: <String, String>{'FOO': '1'},
        cmakeNinja: _cmakeNinja(pathEntries: <String>[r'C:\tools\ninja']),
        toolsRoot: 'tools',
      );

      expect(result.environment['Path'], r'C:\tools\ninja;C:\LLVM\bin');
      expect(result.environment['FOO'], '1');
    });

    test('无前置目录且无 PATH 键时不创建 Path', () {
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{'FOO': '1'},
        cmakeNinja: _cmakeNinja(),
        toolsRoot: 'tools',
      );

      expect(result.environment.containsKey('Path'), isFalse);
      expect(result.environment.containsKey('PATH'), isFalse);
    });
  });

  group('prepareBuildEnvironment', () {
    test('按优先级选择编译器并透传捕获环境与供给工具', () async {
      final DetectedCompiler msvc = _compiler();
      final DetectedCompiler clangCl = _compiler(
        kind: CompilerKind.clangCl,
        version: '23.1.1',
        executablePath: r'C:\LLVM\bin\clang-cl.exe',
        extraPathEntries: <String>[r'C:\LLVM\bin'],
      );
      final CmakeNinja cmakeNinja = _cmakeNinja(
        pathEntries: <String>[r'C:\tools\ninja', r'C:\tools\cmake\bin'],
      );
      final _FakeProvisioner provisioner = _FakeProvisioner(cmakeNinja);
      final Map<String, String> base = <String, String>{'FOO': '1'};
      final List<CompilerKind> captured = <CompilerKind>[];

      final BuildEnvironment result = await prepareBuildEnvironment(
        priority: <String>['clang-cl', 'msvc'],
        runner: _runner(
          <_ProcessCall>[],
          (_) async => throw StateError('不应执行进程'),
        ),
        provisioner: provisioner,
        toolsRoot: 'tools',
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
      expect(provisioner.ensureCmakeNinjaCalls, 1);
      expect(result.environment['FOO'], '1');
      expect(result.environment['CAPTURED'], 'yes');
      expect(result.environment['CNP_COMPILER_KIND'], 'clang-cl');
      expect(result.environment['CNP_CMAKE'], cmakeNinja.cmakeExecutable);
      expect(base, <String, String>{'FOO': '1'});
    });

    test('无可用编译器时抛 BuildPreparationException 且不捕获/供给', () async {
      final _FakeProvisioner provisioner = _FakeProvisioner(_cmakeNinja());
      final List<CompilerKind> captured = <CompilerKind>[];

      await expectLater(
        prepareBuildEnvironment(
          provisioner: provisioner,
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
            contains('未检测到可用编译器'),
          ),
        ),
      );

      expect(captured, isEmpty);
      expect(provisioner.ensureCmakeNinjaCalls, 0);
    });

    test('检测结果不在优先级列表内时视为无可用编译器', () async {
      await expectLater(
        prepareBuildEnvironment(
          priority: <String>['icx'],
          provisioner: _FakeProvisioner(_cmakeNinja()),
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
      final Map<String, String> base = <String, String>{
        'FOO': '1',
        'Path': r'C:\Windows',
      };

      final BuildEnvironment result = await prepareBuildEnvironment(
        provisioner: _FakeProvisioner(
          _cmakeNinja(pathEntries: <String>[r'C:\tools\ninja']),
        ),
        toolsRoot: 'tools',
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
        r'C:\tools\ninja;C:\LLVM\bin;C:\Windows',
      );
      expect(result.environment['CNP_CMAKE'], 'cmake');
      expect(base['Path'], r'C:\Windows');
      expect(base.containsKey('CNP_CMAKE'), isFalse);
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

CmakeNinja _cmakeNinja({
  String cmakeExecutable = 'cmake',
  String ninjaExecutable = 'ninja',
  List<String> pathEntries = const <String>[],
}) {
  return CmakeNinja(
    cmakeExecutable: cmakeExecutable,
    ninjaExecutable: ninjaExecutable,
    pathEntries: pathEntries,
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

class _FakeProvisioner implements ToolProvisioner {
  _FakeProvisioner(this.result);

  final CmakeNinja result;
  int ensureCmakeNinjaCalls = 0;

  @override
  Future<ProvisionedTool> ensureTool({
    required String name,
    required String url,
    String? binSubdir,
  }) {
    throw StateError('不应调用 ensureTool');
  }

  @override
  Future<CmakeNinja> ensureCmakeNinja() async {
    ensureCmakeNinjaCalls++;
    return result;
  }
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
