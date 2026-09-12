import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
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

typedef _ToolCall = ({String name, String url, String? binSubdir});

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

    test('PYTHONPATH 前置工具目录并按分号连接原值', () {
      final Map<String, String> base = <String, String>{
        'PYTHONPATH': r'C:\existing\modules',
      };

      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: base,
        cmakeNinja: _cmakeNinja(),
        toolsRoot: 'tools',
      );

      expect(
        result.environment['PYTHONPATH'],
        '${Directory('tools').absolute.path};${r'C:\existing\modules'}',
      );
      expect(base['PYTHONPATH'], r'C:\existing\modules');
    });

    test('无 PYTHONPATH 原值时仅写入工具目录绝对路径', () {
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{'FOO': '1'},
        cmakeNinja: _cmakeNinja(),
        toolsRoot: 'tools',
      );

      expect(
        result.environment['PYTHONPATH'],
        Directory('tools').absolute.path,
      );
    });

    test('按选项名注入 CNP_OPTION_ 环境变量且仅限传入选项', () {
      final BuildEnvironment result = assembleBuildEnvironment(
        compiler: _compiler(),
        environment: <String, String>{'FOO': '1'},
        cmakeNinja: _cmakeNinja(),
        toolsRoot: 'tools',
        options: const <String, String>{'tbb': 'on', 'open_mp': 'off'},
      );

      expect(result.environment['CNP_OPTION_TBB'], 'on');
      expect(result.environment['CNP_OPTION_OPEN_MP'], 'off');
      expect(result.environment.containsKey('CNP_OPTION_OTHER'), isFalse);
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

    test('声明工具按序供给并将工具目录汇入 PATH 的 cmake 之后', () async {
      final Map<String, String> base = <String, String>{
        'Path': r'C:\Windows',
      };
      final _FakeProvisioner provisioner = _FakeProvisioner(
        _cmakeNinja(
          cmakeExecutable: r'C:\tools\cmake\bin\cmake.exe',
          ninjaExecutable: r'C:\tools\ninja\ninja.exe',
          pathEntries: <String>[r'C:\tools\ninja', r'C:\tools\cmake\bin'],
        ),
        toolResults: <String, ProvisionedTool>{
          'perl': ProvisionedTool(
            name: 'perl',
            directory: r'C:\tools\perl',
            pathEntries: <String>[
              r'C:\tools\perl',
              r'C:\tools\perl\bin',
              r'C:\tools\perl\perl\bin',
            ],
          ),
          'nasm': ProvisionedTool(
            name: 'nasm',
            directory: r'C:\tools\nasm',
            pathEntries: <String>[r'C:\tools\nasm'],
          ),
        },
      );

      final BuildEnvironment result = await prepareBuildEnvironment(
        priority: <String>['msvc'],
        provisioner: provisioner,
        toolsRoot: 'tools',
        baseEnvironment: base,
        tools: const <BuildScriptTool>[
          BuildScriptTool(
            name: 'perl',
            url: 'https://example.com/perl.zip',
            binSubdir: 'perl/bin',
          ),
          BuildScriptTool(name: 'nasm', url: 'https://example.com/nasm.zip'),
        ],
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

      expect(provisioner.ensureCmakeNinjaCalls, 1);
      expect(provisioner.ensureToolCalls, hasLength(2));
      expect(provisioner.ensureToolCalls[0].name, 'perl');
      expect(provisioner.ensureToolCalls[0].url, 'https://example.com/perl.zip');
      expect(provisioner.ensureToolCalls[0].binSubdir, 'perl/bin');
      expect(provisioner.ensureToolCalls[1].name, 'nasm');
      expect(provisioner.ensureToolCalls[1].url, 'https://example.com/nasm.zip');
      expect(provisioner.ensureToolCalls[1].binSubdir, isNull);
      expect(
        result.environment['Path'],
        r'C:\tools\ninja;C:\tools\cmake\bin;C:\tools\perl;C:\tools\perl\bin;'
        r'C:\tools\perl\perl\bin;C:\tools\nasm;C:\LLVM\bin;C:\Windows',
      );
      expect(
        result.environment['CNP_TOOLS_DIR'],
        Directory('tools').absolute.path,
      );
      expect(base['Path'], r'C:\Windows');
    });

    test('Python 解释器目录前置到声明工具与编译器附加目录之前', () async {
      final _FakeProvisioner provisioner = _FakeProvisioner(
        _cmakeNinja(
          cmakeExecutable: r'C:\tools\cmake\bin\cmake.exe',
          ninjaExecutable: r'C:\tools\ninja\ninja.exe',
          pathEntries: <String>[r'C:\tools\ninja', r'C:\tools\cmake\bin'],
        ),
        pythonResult: const ProvisionedPython(
          executable: r'C:\tools\python\python.exe',
          source: PythonSource.provisioned,
          pathEntries: <String>[r'C:\tools\python'],
        ),
        toolResults: <String, ProvisionedTool>{
          'perl': ProvisionedTool(
            name: 'perl',
            directory: r'C:\tools\perl',
            pathEntries: <String>[r'C:\tools\perl\bin'],
          ),
        },
      );

      final BuildEnvironment result = await prepareBuildEnvironment(
        priority: <String>['msvc'],
        provisioner: provisioner,
        toolsRoot: 'tools',
        baseEnvironment: <String, String>{'Path': r'C:\Windows'},
        tools: const <BuildScriptTool>[
          BuildScriptTool(name: 'perl', url: 'https://example.com/perl.zip'),
        ],
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

      expect(provisioner.ensurePythonCalls, 1);
      expect(
        result.environment['Path'],
        r'C:\tools\ninja;C:\tools\cmake\bin;C:\tools\python;'
        r'C:\tools\perl\bin;C:\LLVM\bin;C:\Windows',
      );
    });

    test('释放辅助模块到 toolsRoot（目录不存在则创建并覆盖写）', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'nested/tools');
      const String moduleContent = 'def summary(out):\n    pass\n';

      Future<BuildEnvironment> prepare() {
        return prepareBuildEnvironment(
          priority: <String>['msvc'],
          provisioner: _FakeProvisioner(_cmakeNinja()),
          toolsRoot: toolsRoot,
          baseEnvironment: <String, String>{},
          supportModule: moduleContent,
          detect: () async => <DetectedCompiler>[_compiler()],
          capture: _captureStub(<CompilerKind>[], (
            DetectedCompiler compiler,
            Map<String, String> baseEnvironment,
          ) {
            return baseEnvironment;
          }),
        );
      }

      await prepare();
      final File module = File(joinPath(toolsRoot, 'cnp_build_support.py'));
      expect(module.existsSync(), isTrue);
      expect(module.readAsStringSync(), moduleContent);

      await prepare();
      expect(module.readAsStringSync(), moduleContent);
    });

    test('supportModule 为 null 时不写辅助模块', () async {
      final Directory root = _tempDirectory();

      await prepareBuildEnvironment(
        priority: <String>['msvc'],
        provisioner: _FakeProvisioner(_cmakeNinja()),
        toolsRoot: root.path,
        baseEnvironment: <String, String>{},
        detect: () async => <DetectedCompiler>[_compiler()],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(Directory(root.path).listSync(), isEmpty);
    });

    test('工具供给失败时传播 BuildPreparationException', () async {
      final _FakeProvisioner provisioner = _FakeProvisioner(
        _cmakeNinja(),
        toolError: const BuildPreparationException(
          '工具 perl 下载失败：https://example.com/perl.zip',
        ),
      );

      await expectLater(
        prepareBuildEnvironment(
          priority: <String>['msvc'],
          provisioner: provisioner,
          baseEnvironment: <String, String>{},
          tools: const <BuildScriptTool>[
            BuildScriptTool(
              name: 'perl',
              url: 'https://example.com/perl.zip',
              binSubdir: 'perl/bin',
            ),
          ],
          detect: () async => <DetectedCompiler>[_compiler()],
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
            contains('perl'),
          ),
        ),
      );

      expect(provisioner.ensureToolCalls, hasLength(1));
    });
  });

  group('preparePackBuildEnvironment', () {
    test('读取头部并透传工具、选项与辅助模块', () async {
      final Directory root = _tempDirectory();
      final PackModel pack = _pack(
        buildOptions: <String, String>{
          'tbb': 'on',
          'mpi': 'invalid',
          'unknown': 'x',
        },
      );
      final _FakeProvisioner provisioner = _FakeProvisioner(
        _cmakeNinja(),
        toolResults: <String, ProvisionedTool>{
          'perl': ProvisionedTool(
            name: 'perl',
            directory: r'C:\tools\perl',
            pathEntries: <String>[r'C:\tools\perl\bin'],
          ),
        },
        pythonResult: const ProvisionedPython(
          executable: r'C:\tools\python\python.exe',
          source: PythonSource.provisioned,
          pathEntries: <String>[r'C:\tools\python'],
        ),
      );
      PackModel? loadedPack;

      final BuildEnvironment result = await preparePackBuildEnvironment(
        pack,
        priority: <String>['msvc'],
        provisioner: provisioner,
        toolsRoot: root.path,
        baseEnvironment: <String, String>{'FOO': '1'},
        loadHeader: (PackModel value) async {
          loadedPack = value;
          return const BuildScriptHeader(
            repo: 'https://github.com/example/lib.git',
            tools: <BuildScriptTool>[
              BuildScriptTool(
                name: 'perl',
                url: 'https://example.com/perl.zip',
                binSubdir: 'perl/bin',
              ),
            ],
            options: <BuildScriptOption>[
              BuildScriptOption(name: 'tbb', values: <String>['off', 'on']),
              BuildScriptOption(name: 'mpi', values: <String>['off', 'on']),
            ],
          );
        },
        loadSupportModule: () async => 'SUPPORT',
        detect: () async => <DetectedCompiler>[_compiler()],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(loadedPack, same(pack));
      expect(provisioner.ensurePythonCalls, 1);
      expect(provisioner.ensureToolCalls.single.name, 'perl');
      expect(provisioner.ensureToolCalls.single.binSubdir, 'perl/bin');
      expect(
        result.environment['Path'],
        r'C:\tools\python;C:\tools\perl\bin',
      );
      expect(result.environment['CNP_OPTION_TBB'], 'on');
      expect(result.environment['CNP_OPTION_MPI'], 'off');
      expect(result.environment.containsKey('CNP_OPTION_UNKNOWN'), isFalse);
      expect(
        result.environment['PYTHONPATH'],
        Directory(root.path).absolute.path,
      );
      expect(
        File(joinPath(root.path, 'cnp_build_support.py')).readAsStringSync(),
        'SUPPORT',
      );
    });

    test('无头部时不下发已保存选项且不写辅助模块', () async {
      final Directory root = _tempDirectory();

      final BuildEnvironment result = await preparePackBuildEnvironment(
        _pack(buildOptions: <String, String>{'tbb': 'on'}),
        priority: <String>['msvc'],
        provisioner: _FakeProvisioner(_cmakeNinja()),
        toolsRoot: root.path,
        baseEnvironment: <String, String>{},
        loadHeader: (PackModel pack) async => null,
        detect: () async => <DetectedCompiler>[_compiler()],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(result.environment.containsKey('CNP_OPTION_TBB'), isFalse);
      expect(
        File(joinPath(root.path, 'cnp_build_support.py')).existsSync(),
        isFalse,
      );
    });

    test('头部读取失败包装为 BuildPreparationException 且不检测/供给', () async {
      final _FakeProvisioner provisioner = _FakeProvisioner(_cmakeNinja());

      await expectLater(
        preparePackBuildEnvironment(
          _pack(),
          priority: <String>['msvc'],
          provisioner: provisioner,
          baseEnvironment: <String, String>{},
          loadHeader: (PackModel pack) async =>
              throw const FileSystemException('拒绝访问'),
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
            allOf(contains('读取 build.py 失败'), contains('拒绝访问')),
          ),
        ),
      );

      expect(provisioner.ensureCmakeNinjaCalls, 0);
    });

    test('辅助模块加载失败按 null 容错并继续装配', () async {
      final Directory root = _tempDirectory();

      final BuildEnvironment result = await preparePackBuildEnvironment(
        _pack(),
        priority: <String>['msvc'],
        provisioner: _FakeProvisioner(_cmakeNinja()),
        toolsRoot: root.path,
        baseEnvironment: <String, String>{},
        loadHeader: (PackModel pack) async => null,
        loadSupportModule: () async => throw StateError('asset 缺失'),
        detect: () async => <DetectedCompiler>[_compiler()],
        capture: _captureStub(<CompilerKind>[], (
          DetectedCompiler compiler,
          Map<String, String> baseEnvironment,
        ) {
          return baseEnvironment;
        }),
      );

      expect(result.environment['CNP_CMAKE'], 'cmake');
      expect(
        File(joinPath(root.path, 'cnp_build_support.py')).existsSync(),
        isFalse,
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
  _FakeProvisioner(
    this.result, {
    this.toolResults = const <String, ProvisionedTool>{},
    this.toolError,
    this.pythonResult = const ProvisionedPython(
      executable: 'python',
      source: PythonSource.local,
      pathEntries: <String>[],
    ),
  });

  final CmakeNinja result;
  final Map<String, ProvisionedTool> toolResults;
  final Object? toolError;
  final ProvisionedPython pythonResult;
  int ensureCmakeNinjaCalls = 0;
  int ensurePythonCalls = 0;
  final List<_ToolCall> ensureToolCalls = <_ToolCall>[];

  @override
  Future<ProvisionedTool> ensureTool({
    required String name,
    required String url,
    String? binSubdir,
  }) async {
    ensureToolCalls.add((name: name, url: url, binSubdir: binSubdir));
    final Object? error = toolError;
    if (error != null) {
      throw error;
    }
    final ProvisionedTool? tool = toolResults[name];
    if (tool == null) {
      throw StateError('不应调用 ensureTool');
    }
    return tool;
  }

  @override
  Future<CmakeNinja> ensureCmakeNinja() async {
    ensureCmakeNinjaCalls++;
    return result;
  }

  @override
  Future<ProvisionedPython> ensurePython() async {
    ensurePythonCalls++;
    return pythonResult;
  }
}

PackModel _pack({Map<String, String> buildOptions = const <String, String>{}}) {
  final PackModel pack = PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
  );
  pack.buildOptions = <String, String>{...buildOptions};
  return pack;
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
