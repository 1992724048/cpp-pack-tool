import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/build/provisioning.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _ProcessCall = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
});

void main() {
  group('ensureTool 下载与解压', () {
    test('首次下载：剥离单层根目录、写入来源标记并收集 PATH 目录', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String url = 'https://example.com/nasm-3.02-win.zip';
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          return _zip(<ArchiveFile>[
            ArchiveFile.directory('nasm-3.02/'),
            ArchiveFile.bytes('nasm-3.02/nasm.exe', <int>[0x4d, 0x5a]),
            ArchiveFile.string('nasm-3.02/docs/readme.txt', 'hello'),
            ArchiveFile.string('nasm-3.02/bin/tool.dll', 'dll'),
          ]);
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureTool(
        name: 'nasm',
        url: url,
      );

      expect(fetchCalls, <Uri>[Uri.parse(url)]);
      expect(tool.name, 'nasm');
      expect(tool.directory, joinPath(toolsRoot, 'nasm'));
      expect(
        File(joinPath(tool.directory, 'nasm.exe')).readAsBytesSync(),
        <int>[0x4d, 0x5a],
      );
      expect(
        File(joinPath(tool.directory, 'docs/readme.txt')).readAsStringSync(),
        'hello',
      );
      expect(File(joinPath(tool.directory, '.source')).readAsStringSync(), url);
      expect(tool.pathEntries, <String>[
        tool.directory,
        joinPath(tool.directory, 'bin'),
      ]);
    });

    test('单层根剥离时跳过根外的目录条目', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (_) async {
          return _zip(<ArchiveFile>[
            ArchiveFile.string('tool/nasm.exe', 'MZ'),
            ArchiveFile.directory('other/'),
          ]);
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureTool(
        name: 'nasm',
        url: 'https://example.com/tool.zip',
      );

      expect(File(joinPath(tool.directory, 'nasm.exe')).existsSync(), isTrue);
      expect(
        Directory(joinPath(tool.directory, 'other')).existsSync(),
        isFalse,
      );
    });

    test('无单层根目录的压缩包原样解压', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (_) async {
          return _zip(<ArchiveFile>[
            ArchiveFile.string('ninja.exe', 'MZ'),
            ArchiveFile.string('README.txt', 'doc'),
          ]);
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureTool(
        name: 'ninja',
        url: 'https://example.com/ninja-win.zip',
      );

      expect(
        File(joinPath(tool.directory, 'ninja.exe')).readAsStringSync(),
        'MZ',
      );
      expect(
        File(joinPath(tool.directory, 'README.txt')).readAsStringSync(),
        'doc',
      );
      expect(tool.pathEntries, <String>[tool.directory]);
    });

    test('binSubdir 目录存在时加入 PATH 目录', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (_) async {
          return _zip(<ArchiveFile>[
            ArchiveFile.string('strawberry/perl/bin/perl.exe', 'perl'),
          ]);
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureTool(
        name: 'strawberry',
        url: 'https://example.com/strawberry.zip',
        binSubdir: 'perl/bin',
      );

      expect(tool.pathEntries, <String>[
        tool.directory,
        joinPath(tool.directory, 'perl/bin'),
      ]);
    });

    test('来源标记命中时不重复下载', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String url = 'https://example.com/nasm-win.zip';
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (_) async {
          return _zip(<ArchiveFile>[ArchiveFile.string('root/nasm.exe', 'MZ')]);
        }),
      );

      await provisioner.ensureTool(name: 'nasm', url: url);
      final ProvisionedTool second = await provisioner.ensureTool(
        name: 'nasm',
        url: url,
      );

      expect(fetchCalls, hasLength(1));
      expect(File(joinPath(second.directory, 'nasm.exe')).existsSync(), isTrue);
      expect(
        File(joinPath(second.directory, '.source')).readAsStringSync(),
        url,
      );
    });

    test('URL 变化时重新下载并替换目录', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          return uri.path.contains('a.zip')
              ? _zip(<ArchiveFile>[ArchiveFile.string('tool/old.txt', 'old')])
              : _zip(<ArchiveFile>[ArchiveFile.string('tool/new.txt', 'new')]);
        }),
      );

      await provisioner.ensureTool(
        name: 'nasm',
        url: 'https://example.com/a.zip',
      );
      final ProvisionedTool tool = await provisioner.ensureTool(
        name: 'nasm',
        url: 'https://example.com/b.zip',
      );

      expect(fetchCalls, hasLength(2));
      expect(File(joinPath(tool.directory, 'old.txt')).existsSync(), isFalse);
      expect(
        File(joinPath(tool.directory, 'new.txt')).readAsStringSync(),
        'new',
      );
      expect(
        File(joinPath(tool.directory, '.source')).readAsStringSync(),
        'https://example.com/b.zip',
      );
    });

    test('下载失败：抛 BuildPreparationException 且不留残留', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String url = 'https://example.com/nasm-win.zip';
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (_) async {
          throw Exception('network down');
        }),
      );

      await expectLater(
        provisioner.ensureTool(name: 'nasm', url: url),
        throwsA(
          _preparationException(
            message: allOf(contains(url), contains('下载失败')),
          ),
        ),
      );

      _expectNoResidue(toolsRoot, 'nasm');
    });

    test('压缩包无效：抛 BuildPreparationException 且不留残留', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String url = 'https://example.com/nasm-win.zip';
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (_) async {
          return Uint8List.fromList(<int>[1, 2, 3, 4]);
        }),
      );

      await expectLater(
        provisioner.ensureTool(name: 'nasm', url: url),
        throwsA(_preparationException(message: contains(url))),
      );

      _expectNoResidue(toolsRoot, 'nasm');
    });

    test('解压失败不破坏已安装的旧版本且清理临时目录', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final String toolPath = joinPath(toolsRoot, 'nasm');
      Directory(toolPath).createSync(recursive: true);
      File(joinPath(toolPath, 'keep.txt')).writeAsStringSync('keep');
      File(joinPath(toolPath, '.source'))
          .writeAsStringSync('https://example.com/old.zip');
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (_) async {
          return _zip(<ArchiveFile>[ArchiveFile.string('../evil.txt', 'evil')]);
        }),
      );

      await expectLater(
        provisioner.ensureTool(
          name: 'nasm',
          url: 'https://example.com/new.zip',
        ),
        throwsA(_preparationException(message: contains('不安全'))),
      );

      expect(File(joinPath(toolPath, 'keep.txt')).readAsStringSync(), 'keep');
      expect(
        File(joinPath(toolPath, '.source')).readAsStringSync(),
        'https://example.com/old.zip',
      );
      _expectTempClean(toolsRoot);
    });

    test('工具名清洗：非法字符替换且拒绝目录逃逸', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String url = 'https://example.com/tool.zip';
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (_) async {
          return _zip(<ArchiveFile>[ArchiveFile.string('tool/nasm.exe', 'MZ')]);
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureTool(
        name: 'nasm/x64',
        url: url,
      );

      expect(tool.name, 'nasm_x64');
      expect(tool.directory, joinPath(toolsRoot, 'nasm_x64'));
      expect(File(joinPath(tool.directory, 'nasm.exe')).existsSync(), isTrue);

      await expectLater(
        provisioner.ensureTool(name: '..', url: url),
        throwsA(_preparationException(message: contains('非法'))),
      );
    });
  });

  group('目录替换重试', () {
    test('目标被文件句柄占用时短延迟重试后成功', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final Directory target = Directory(joinPath(toolsRoot, 'nasm'))
        ..createSync(recursive: true);
      final RandomAccessFile handle = File(joinPath(target.path, 'locked.txt'))
          .openSync(mode: FileMode.write);
      Timer(const Duration(milliseconds: 50), handle.closeSync);

      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        replaceRetryDelay: const Duration(milliseconds: 300),
        fetch: _fetchStub(<Uri>[], (_) async {
          return _zip(<ArchiveFile>[ArchiveFile.string('nasm.exe', 'MZ')]);
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureTool(
        name: 'nasm',
        url: 'https://example.com/nasm.zip',
      );

      expect(
        File(joinPath(tool.directory, 'nasm.exe')).readAsStringSync(),
        'MZ',
      );
      expect(
        File(joinPath(tool.directory, 'locked.txt')).existsSync(),
        isFalse,
      );
      _expectTempClean(toolsRoot);
    });

    test('重试耗尽后抛 BuildPreparationException 并保留原目录', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final Directory target = Directory(joinPath(toolsRoot, 'nasm'))
        ..createSync(recursive: true);
      final RandomAccessFile handle = File(joinPath(target.path, 'locked.txt'))
          .openSync(mode: FileMode.write);
      addTearDown(handle.closeSync);

      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        replaceAttempts: 3,
        replaceRetryDelay: const Duration(milliseconds: 50),
        fetch: _fetchStub(<Uri>[], (_) async {
          return _zip(<ArchiveFile>[ArchiveFile.string('nasm.exe', 'MZ')]);
        }),
      );

      final Stopwatch stopwatch = Stopwatch()..start();
      await expectLater(
        provisioner.ensureTool(
          name: 'nasm',
          url: 'https://example.com/nasm.zip',
        ),
        throwsA(_preparationException(message: contains('安装失败'))),
      );
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        greaterThanOrEqualTo(80),
        reason: '两次重试延迟（50ms × 2）',
      );
      expect(File(joinPath(target.path, 'locked.txt')).existsSync(), isTrue);
      _expectTempClean(toolsRoot);
    });
  });

  group('ensureCmakeNinja', () {
    test('本地 cmake ≥ 3.25 与 ninja 可用时不下载', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final List<Uri> fetchCalls = <Uri>[];
      final List<_ProcessCall> processCalls = <_ProcessCall>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          fail('不应下载：$uri');
        }),
        runner: _runnerStub(
          processCalls,
          (_) async => ProcessResult(0, 0, 'cmake version 3.25.0\n', ''),
        ),
        environment: const <String, String>{},
      );

      final CmakeNinja result = await provisioner.ensureCmakeNinja();

      expect(result.cmakeExecutable, 'cmake');
      expect(result.ninjaExecutable, 'ninja');
      expect(result.pathEntries, isEmpty);
      expect(fetchCalls, isEmpty);
      expect(processCalls.map((_ProcessCall call) => call.executable), <String>[
        'cmake',
        'ninja',
      ]);
      expect(processCalls.first.arguments, <String>['--version']);
    });

    test('本地 cmake 过旧时回退 %ProgramFiles%\\CMake\\bin', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String programFiles = r'X:\FakeProgramFiles';
      final String fallback = joinPath(
        joinPath(programFiles, 'CMake'),
        'bin/cmake.exe',
      );
      final List<Uri> fetchCalls = <Uri>[];
      final List<_ProcessCall> processCalls = <_ProcessCall>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          fail('不应下载：$uri');
        }),
        runner: _runnerStub(processCalls, (_ProcessCall call) async {
          if (call.executable == 'cmake') {
            return ProcessResult(0, 1, '', 'unknown command');
          }
          if (call.executable == fallback) {
            return ProcessResult(0, 0, 'cmake version 4.4.3\n', '');
          }
          return ProcessResult(0, 0, '1.13.1\n', '');
        }),
        environment: const <String, String>{'ProgramFiles': programFiles},
      );

      final CmakeNinja result = await provisioner.ensureCmakeNinja();

      expect(result.cmakeExecutable, fallback);
      expect(result.ninjaExecutable, 'ninja');
      expect(result.pathEntries, isEmpty);
      expect(fetchCalls, isEmpty);
      expect(processCalls.map((_ProcessCall call) => call.executable), <String>[
        'cmake',
        fallback,
        'ninja',
      ]);
    });

    test('本地缺失且解析失败时回退内置版本下载 cmake 与 ninja', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final List<Uri> fetchCalls = <Uri>[];
      final List<_ProcessCall> processCalls = <_ProcessCall>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          final String url = uri.toString();
          if (url == cmakeReleasesApiUrl || url == ninjaReleasesApiUrl) {
            throw StateError('解析不可用（测试回退路径）');
          }
          if (url == cmakeDownloadUrl) {
            return _zip(<ArchiveFile>[
              ArchiveFile.directory('cmake-4.4.3-windows-x86_64/'),
              ArchiveFile.string(
                'cmake-4.4.3-windows-x86_64/bin/cmake.exe',
                'MZ',
              ),
              ArchiveFile.string(
                'cmake-4.4.3-windows-x86_64/share/cmake/help.txt',
                'help',
              ),
            ]);
          }
          if (url == ninjaDownloadUrl) {
            return _zip(<ArchiveFile>[ArchiveFile.string('ninja.exe', 'MZ')]);
          }
          throw StateError('未知下载地址：$url');
        }),
        runner: _runnerStub(
          processCalls,
          (_) async => throw ProcessException('missing', const <String>[]),
        ),
        environment: const <String, String>{},
      );

      final CmakeNinja result = await provisioner.ensureCmakeNinja();

      expect(fetchCalls, <Uri>[
        Uri.parse(cmakeReleasesApiUrl),
        Uri.parse(cmakeDownloadUrl),
        Uri.parse(ninjaReleasesApiUrl),
        Uri.parse(ninjaDownloadUrl),
      ]);
      expect(
        result.cmakeExecutable,
        joinPath(toolsRoot, 'cmake/bin/cmake.exe'),
      );
      expect(result.ninjaExecutable, joinPath(toolsRoot, 'ninja/ninja.exe'));
      expect(result.pathEntries, <String>[
        joinPath(toolsRoot, 'cmake'),
        joinPath(toolsRoot, 'cmake/bin'),
        joinPath(toolsRoot, 'ninja'),
      ]);
      expect(
        File(joinPath(toolsRoot, 'cmake/.source')).readAsStringSync(),
        cmakeDownloadUrl,
      );
      expect(
        File(joinPath(toolsRoot, 'ninja/.source')).readAsStringSync(),
        ninjaDownloadUrl,
      );
    });

    test('解析成功时使用最新正式版资产地址下载', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String newCmakeUrl =
          'https://github.com/Kitware/CMake/releases/download/'
          'v9.9.9/cmake-9.9.9-windows-x86_64.zip';
      const String newNinjaUrl =
          'https://github.com/ninja-build/ninja/releases/download/'
          'v1.99.0/ninja-win.zip';
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          switch (uri.toString()) {
            case cmakeReleasesApiUrl:
              return _releaseAssetJson(
                assetName: 'cmake-9.9.9-windows-x86_64.zip',
                assetUrl: newCmakeUrl,
              );
            case newCmakeUrl:
              return _zip(<ArchiveFile>[
                ArchiveFile.string(
                  'cmake-9.9.9-windows-x86_64/bin/cmake.exe',
                  'MZ',
                ),
              ]);
            case ninjaReleasesApiUrl:
              return _releaseAssetJson(
                assetName: 'ninja-win.zip',
                assetUrl: newNinjaUrl,
              );
            case newNinjaUrl:
              return _zip(<ArchiveFile>[
                ArchiveFile.string('ninja.exe', 'MZ'),
              ]);
          }
          throw StateError('未知下载地址：$uri');
        }),
        runner: _runnerStub(
          <_ProcessCall>[],
          (_) async => throw ProcessException('missing', const <String>[]),
        ),
        environment: const <String, String>{},
      );

      final CmakeNinja result = await provisioner.ensureCmakeNinja();

      expect(fetchCalls, <Uri>[
        Uri.parse(cmakeReleasesApiUrl),
        Uri.parse(newCmakeUrl),
        Uri.parse(ninjaReleasesApiUrl),
        Uri.parse(newNinjaUrl),
      ]);
      expect(
        result.cmakeExecutable,
        joinPath(toolsRoot, 'cmake/bin/cmake.exe'),
      );
      expect(result.ninjaExecutable, joinPath(toolsRoot, 'ninja/ninja.exe'));
      expect(
        File(joinPath(toolsRoot, 'cmake/.source')).readAsStringSync(),
        newCmakeUrl,
      );
      expect(
        File(joinPath(toolsRoot, 'ninja/.source')).readAsStringSync(),
        newNinjaUrl,
      );
    });

    test('已安装标记命中时复用，不重复解析/下载', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      File(joinPath(toolsRoot, 'cmake/bin/cmake.exe'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('MZ');
      File(
        joinPath(toolsRoot, 'cmake/.source'),
      ).writeAsStringSync(cmakeDownloadUrl);
      File(joinPath(toolsRoot, 'ninja/ninja.exe'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('MZ');
      File(
        joinPath(toolsRoot, 'ninja/.source'),
      ).writeAsStringSync(ninjaDownloadUrl);
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          fail('不应下载：$uri');
        }),
        runner: _runnerStub(
          <_ProcessCall>[],
          (_) async => throw ProcessException('missing', const <String>[]),
        ),
        environment: const <String, String>{},
      );

      final CmakeNinja result = await provisioner.ensureCmakeNinja();

      expect(fetchCalls, isEmpty);
      expect(
        result.cmakeExecutable,
        joinPath(toolsRoot, 'cmake/bin/cmake.exe'),
      );
      expect(result.ninjaExecutable, joinPath(toolsRoot, 'ninja/ninja.exe'));
      expect(result.pathEntries, <String>[
        joinPath(toolsRoot, 'cmake'),
        joinPath(toolsRoot, 'cmake/bin'),
        joinPath(toolsRoot, 'ninja'),
      ]);
    });

    test('仅缺 ninja 时只下载 ninja（解析失败回退内置版本）', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final List<Uri> fetchCalls = <Uri>[];
      final List<_ProcessCall> processCalls = <_ProcessCall>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          if (uri.toString() == ninjaReleasesApiUrl) {
            throw StateError('解析不可用（测试回退路径）');
          }
          return _zip(<ArchiveFile>[ArchiveFile.string('ninja.exe', 'MZ')]);
        }),
        runner: _runnerStub(processCalls, (_ProcessCall call) async {
          if (call.executable == 'cmake') {
            return ProcessResult(0, 0, 'cmake version 4.0.0\n', '');
          }
          throw ProcessException('ninja', const <String>['--version']);
        }),
        environment: const <String, String>{},
      );

      final CmakeNinja result = await provisioner.ensureCmakeNinja();

      expect(fetchCalls, <Uri>[
        Uri.parse(ninjaReleasesApiUrl),
        Uri.parse(ninjaDownloadUrl),
      ]);
      expect(result.cmakeExecutable, 'cmake');
      expect(result.ninjaExecutable, joinPath(toolsRoot, 'ninja/ninja.exe'));
      expect(result.pathEntries, <String>[joinPath(toolsRoot, 'ninja')]);
    });
  });

  group('ensureClangLlvm', () {
    test('解析成功：下载 tar.xz、剥离单层根并解压到 tools/clang', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String version = '23.1.1';
      final String assetUrl = clangLlvmUrlForVersion(version);
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          final String url = uri.toString();
          if (url == clangReleasesApiUrl) {
            return _releaseAssetJson(
              assetName: 'clang+llvm-23.1.1-x86_64-pc-windows-msvc.tar.xz',
              assetUrl: assetUrl,
            );
          }
          if (url == assetUrl) {
            return _tarXz(<ArchiveFile>[
              ArchiveFile.directory(
                'clang+llvm-23.1.1-x86_64-pc-windows-msvc/',
              ),
              ArchiveFile.string(
                'clang+llvm-23.1.1-x86_64-pc-windows-msvc/bin/clang-cl.exe',
                'MZ',
              ),
              ArchiveFile.string(
                'clang+llvm-23.1.1-x86_64-pc-windows-msvc/bin/clang.exe',
                'MZ',
              ),
              ArchiveFile.string(
                'clang+llvm-23.1.1-x86_64-pc-windows-msvc/README.txt',
                'doc',
              ),
            ]);
          }
          throw StateError('未知下载地址：$url');
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureClangLlvm();

      expect(fetchCalls, <Uri>[
        Uri.parse(clangReleasesApiUrl),
        Uri.parse(assetUrl),
      ]);
      expect(tool.name, 'clang');
      expect(tool.directory, joinPath(toolsRoot, 'clang'));
      expect(
        File(joinPath(tool.directory, 'bin/clang-cl.exe')).readAsStringSync(),
        'MZ',
      );
      expect(tool.pathEntries, <String>[
        joinPath(toolsRoot, 'clang'),
        joinPath(toolsRoot, 'clang/bin'),
      ]);
      expect(
        File(joinPath(tool.directory, '.source')).readAsStringSync(),
        assetUrl,
      );
    });

    test('解析失败回退内置版本地址', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final String fallbackUrl = clangLlvmUrlForVersion(clangLlvmFallbackVersion);
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          final String url = uri.toString();
          if (url == clangReleasesApiUrl) {
            throw Exception('network down');
          }
          if (url == fallbackUrl) {
            return _tarXz(<ArchiveFile>[
              ArchiveFile.string(
                'clang+llvm-$clangLlvmFallbackVersion-x86_64-pc-windows-msvc/'
                'bin/clang-cl.exe',
                'MZ',
              ),
            ]);
          }
          throw StateError('未知下载地址：$url');
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureClangLlvm();

      expect(fetchCalls, <Uri>[
        Uri.parse(clangReleasesApiUrl),
        Uri.parse(fallbackUrl),
      ]);
      expect(
        File(joinPath(tool.directory, '.source')).readAsStringSync(),
        fallbackUrl,
      );
    });

    test('预发布版本不采用，回退内置版本地址', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final String fallbackUrl = clangLlvmUrlForVersion(clangLlvmFallbackVersion);
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          final String url = uri.toString();
          if (url == clangReleasesApiUrl) {
            return _releaseAssetJson(
              assetName: 'clang+llvm-24.0.0-x86_64-pc-windows-msvc.tar.xz',
              assetUrl: clangLlvmUrlForVersion('24.0.0'),
              prerelease: true,
            );
          }
          if (url == fallbackUrl) {
            return _tarXz(<ArchiveFile>[
              ArchiveFile.string(
                'clang+llvm-$clangLlvmFallbackVersion-x86_64-pc-windows-msvc/'
                'bin/clang-cl.exe',
                'MZ',
              ),
            ]);
          }
          throw StateError('未知下载地址：$url');
        }),
      );

      await provisioner.ensureClangLlvm();

      expect(fetchCalls, <Uri>[
        Uri.parse(clangReleasesApiUrl),
        Uri.parse(fallbackUrl),
      ]);
      expect(
        File(joinPath(toolsRoot, 'clang/.source')).readAsStringSync(),
        fallbackUrl,
      );
    });

    test('tar.xz 路径不安全：抛 BuildPreparationException 且不留残留', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final String assetUrl = clangLlvmUrlForVersion('23.1.1');
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (Uri uri) async {
          final String url = uri.toString();
          if (url == clangReleasesApiUrl) {
            return _releaseAssetJson(
              assetName: 'clang+llvm-23.1.1-x86_64-pc-windows-msvc.tar.xz',
              assetUrl: assetUrl,
            );
          }
          return _tarXz(<ArchiveFile>[
            ArchiveFile.string('../evil.txt', 'evil'),
          ]);
        }),
      );

      await expectLater(
        provisioner.ensureClangLlvm(),
        throwsA(_preparationException(message: contains('不安全'))),
      );

      _expectNoResidue(toolsRoot, 'clang');
    });

    test('来源标记命中时复用，不重复解析/下载', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final String sourceUrl = clangLlvmUrlForVersion('23.1.1');
      File(joinPath(toolsRoot, 'clang/bin/clang-cl.exe'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('MZ');
      File(
        joinPath(toolsRoot, 'clang/.source'),
      ).writeAsStringSync(sourceUrl);
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          fail('不应下载：$uri');
        }),
      );

      final ProvisionedTool tool = await provisioner.ensureClangLlvm();

      expect(fetchCalls, isEmpty);
      expect(tool.directory, joinPath(toolsRoot, 'clang'));
      expect(tool.pathEntries, <String>[
        joinPath(toolsRoot, 'clang'),
        joinPath(toolsRoot, 'clang/bin'),
      ]);
      expect(
        File(joinPath(tool.directory, 'bin/clang-cl.exe')).readAsStringSync(),
        'MZ',
      );
    });
  });

  group('ensurePython', () {
    test('本机 python 可用时直接返回且不下载', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final List<Uri> fetchCalls = <Uri>[];
      final List<_ProcessCall> processCalls = <_ProcessCall>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          fail('不应下载：$uri');
        }),
        runner: _runnerStub(
          processCalls,
          (_) async => ProcessResult(0, 0, 'Python 3.14.7\r\n', ''),
        ),
        environment: const <String, String>{},
      );

      final ProvisionedPython python = await provisioner.ensurePython();

      expect(python.executable, 'python');
      expect(python.source, PythonSource.local);
      expect(python.pathEntries, isEmpty);
      expect(fetchCalls, isEmpty);
      expect(processCalls, hasLength(1));
      expect(processCalls.single.executable, 'python');
      expect(processCalls.single.arguments, <String>['--version']);
    });

    test('python 为 Store 别名假体时回退 py -3 并前置真实解释器目录', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final Directory interpreterDir = Directory(
        joinPath(root.path, 'Python312'),
      )..createSync(recursive: true);
      final List<Uri> fetchCalls = <Uri>[];
      final List<_ProcessCall> processCalls = <_ProcessCall>[];
      const String stubOutput =
          'Python was not found; run without arguments to install from the '
          'Microsoft Store, or disable this shortcut from Settings > Manage '
          'App Execution Aliases.\r\n';
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          fail('不应下载：$uri');
        }),
        runner: _runnerStub(processCalls, (_ProcessCall call) async {
          if (call.executable == 'python') {
            return ProcessResult(0, 0, stubOutput, '');
          }
          if (call.arguments.length == 2) {
            return ProcessResult(0, 0, 'Python 3.12.4\r\n', '');
          }
          return ProcessResult(
            0,
            0,
            '${joinPath(interpreterDir.path, 'python.exe')}\r\n',
            '',
          );
        }),
        environment: const <String, String>{},
      );

      final ProvisionedPython python = await provisioner.ensurePython();

      final String expectedDirectory = File(
        joinPath(interpreterDir.path, 'python.exe'),
      ).parent.path;
      expect(python.executable, 'py');
      expect(python.source, PythonSource.launcher);
      expect(python.pathEntries, <String>[expectedDirectory]);
      expect(fetchCalls, isEmpty);
      expect(
        processCalls.map((_ProcessCall call) => call.executable),
        <String>['python', 'py', 'py'],
      );
      expect(processCalls[1].arguments, <String>['-3', '--version']);
      expect(processCalls[2].arguments, <String>[
        '-3',
        '-c',
        'import sys; print(sys.executable)',
      ]);
    });

    test('无本机 Python 时下载 embeddable 包并解压到 tools/python', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      const String indexHtml =
          '<html><body>'
          '<a href="2.7.18/">2.7.18/</a>'
          '<a href="3.5.10/">3.5.10/</a>'
          '<a href="3.14.7/">3.14.7/</a>'
          '<a href="3.15.0/">3.15.0/</a>'
          '<a href="3.15.0a1/">3.15.0a1/</a>'
          '</body></html>';
      final String embedUrl = pythonEmbedUrlForVersion('3.14.7');
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          final String url = uri.toString();
          if (url == pythonFtpIndexUrl) {
            return Uint8List.fromList(utf8.encode(indexHtml));
          }
          if (url == '${pythonFtpIndexUrl}3.15.0/') {
            return Uint8List.fromList(utf8.encode('<html></html>'));
          }
          if (url == '${pythonFtpIndexUrl}3.14.7/') {
            return Uint8List.fromList(
              utf8.encode('<a href="python-3.14.7-embed-amd64.zip">x</a>'),
            );
          }
          if (url == embedUrl) {
            return _zip(<ArchiveFile>[
              ArchiveFile.string('python.exe', 'MZ'),
              ArchiveFile.string('python314.dll', 'DLL'),
              ArchiveFile.string('python314.zip', 'STDLIB'),
            ]);
          }
          throw StateError('未知下载地址：$url');
        }),
        runner: _missingProcessRunner(),
        environment: const <String, String>{},
      );

      final ProvisionedPython python = await provisioner.ensurePython();

      expect(python.executable, joinPath(toolsRoot, 'python/python.exe'));
      expect(python.source, PythonSource.provisioned);
      expect(python.pathEntries, <String>[joinPath(toolsRoot, 'python')]);
      expect(fetchCalls, <Uri>[
        Uri.parse(pythonFtpIndexUrl),
        Uri.parse('${pythonFtpIndexUrl}3.15.0/'),
        Uri.parse('${pythonFtpIndexUrl}3.14.7/'),
        Uri.parse(embedUrl),
      ]);
      expect(
        File(joinPath(toolsRoot, 'python/python.exe')).readAsStringSync(),
        'MZ',
      );
      expect(
        File(joinPath(toolsRoot, 'python/python314.zip')).readAsStringSync(),
        'STDLIB',
      );
      expect(
        File(joinPath(toolsRoot, 'python/.source')).readAsStringSync(),
        embedUrl,
      );
    });

    test('目录列表不可用时回退内置版本', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final String fallbackUrl = pythonEmbedUrlForVersion(
        pythonFallbackVersion,
      );
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          if (uri.toString() == pythonFtpIndexUrl) {
            throw Exception('index down');
          }
          if (uri.toString() == fallbackUrl) {
            return _zip(<ArchiveFile>[ArchiveFile.string('python.exe', 'MZ')]);
          }
          throw StateError('未知下载地址：$uri');
        }),
        runner: _missingProcessRunner(),
        environment: const <String, String>{},
      );

      final ProvisionedPython python = await provisioner.ensurePython();

      expect(python.source, PythonSource.provisioned);
      expect(fetchCalls, <Uri>[
        Uri.parse(pythonFtpIndexUrl),
        Uri.parse(fallbackUrl),
      ]);
      expect(
        File(joinPath(toolsRoot, 'python/.source')).readAsStringSync(),
        fallbackUrl,
      );
    });

    test('来源标记命中时复用已供给解释器，不重复下载压缩包', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final Directory toolDir = Directory(joinPath(toolsRoot, 'python'))
        ..createSync(recursive: true);
      File(joinPath(toolDir.path, 'python.exe')).writeAsStringSync('MZ');
      File(
        joinPath(toolDir.path, '.source'),
      ).writeAsStringSync(pythonEmbedUrlForVersion('3.14.7'));
      final List<Uri> fetchCalls = <Uri>[];
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(fetchCalls, (Uri uri) async {
          final String url = uri.toString();
          if (url == pythonFtpIndexUrl) {
            return _pythonIndexBytes();
          }
          if (url == '${pythonFtpIndexUrl}3.14.7/') {
            return _pythonVersionListingBytes();
          }
          fail('不应下载压缩包：$url');
        }),
        runner: _missingProcessRunner(),
        environment: const <String, String>{},
      );

      final ProvisionedPython python = await provisioner.ensurePython();

      expect(python.source, PythonSource.provisioned);
      expect(python.pathEntries, <String>[joinPath(toolsRoot, 'python')]);
      expect(fetchCalls, <Uri>[
        Uri.parse(pythonFtpIndexUrl),
        Uri.parse('${pythonFtpIndexUrl}3.14.7/'),
      ]);
      expect(
        File(joinPath(toolsRoot, 'python/python.exe')).readAsStringSync(),
        'MZ',
      );
    });

    test('压缩包下载失败：抛 BuildPreparationException 且不留残留', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final String embedUrl = pythonEmbedUrlForVersion('3.14.7');
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (Uri uri) async {
          final String url = uri.toString();
          if (url == pythonFtpIndexUrl) {
            return _pythonIndexBytes();
          }
          if (url == '${pythonFtpIndexUrl}3.14.7/') {
            return _pythonVersionListingBytes();
          }
          throw Exception('network down');
        }),
        runner: _missingProcessRunner(),
        environment: const <String, String>{},
      );

      await expectLater(
        provisioner.ensurePython(),
        throwsA(
          _preparationException(
            message: allOf(contains(embedUrl), contains('下载失败')),
          ),
        ),
      );

      _expectNoResidue(toolsRoot, 'python');
    });

    test('压缩包路径不安全：抛 BuildPreparationException 且不留残留', () async {
      final Directory root = _tempDirectory();
      final String toolsRoot = joinPath(root.path, 'tools');
      final ToolProvisioner provisioner = ToolProvisioner(
        toolsRoot: toolsRoot,
        fetch: _fetchStub(<Uri>[], (Uri uri) async {
          final String url = uri.toString();
          if (url == pythonFtpIndexUrl) {
            return _pythonIndexBytes();
          }
          if (url == '${pythonFtpIndexUrl}3.14.7/') {
            return _pythonVersionListingBytes();
          }
          return _zip(<ArchiveFile>[ArchiveFile.string('../evil.txt', 'evil')]);
        }),
        runner: _missingProcessRunner(),
        environment: const <String, String>{},
      );

      await expectLater(
        provisioner.ensurePython(),
        throwsA(_preparationException(message: contains('不安全'))),
      );

      _expectNoResidue(toolsRoot, 'python');
    });
  });
}

Uint8List _zip(List<ArchiveFile> files) {
  final Archive archive = Archive();
  for (final ArchiveFile file in files) {
    archive.addFile(file);
  }
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _tarXz(List<ArchiveFile> files) {
  final Archive archive = Archive();
  for (final ArchiveFile file in files) {
    archive.addFile(file);
  }
  return Uint8List.fromList(XZEncoder().encode(TarEncoder().encode(archive)));
}

/// GitHub `releases/latest` 形状的响应（仅含解析所需字段）。
Uint8List _releaseAssetJson({
  required String assetName,
  required String assetUrl,
  bool prerelease = false,
}) {
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'prerelease': prerelease,
        'assets': <Object?>[
          <String, Object?>{
            'name': assetName,
            'browser_download_url': assetUrl,
          },
        ],
      }),
    ),
  );
}

ToolFetcher _fetchStub(
  List<Uri> calls,
  Future<Uint8List> Function(Uri uri) responder,
) {
  return (Uri uri) async {
    calls.add(uri);
    return responder(uri);
  };
}

Directory _tempDirectory() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'cpp_nuget_pack_provisioning_',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

void _expectNoResidue(String toolsRoot, String name) {
  expect(Directory(joinPath(toolsRoot, name)).existsSync(), isFalse);
  _expectTempClean(toolsRoot);
}

void _expectTempClean(String toolsRoot) {
  final Directory temp = Directory(joinPath(toolsRoot, '.tmp'));
  if (temp.existsSync()) {
    expect(temp.listSync(), isEmpty);
  }
}

PackProcessRunner _runnerStub(
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

PackProcessRunner _missingProcessRunner() {
  return _runnerStub(
    <_ProcessCall>[],
    (_) async => throw ProcessException('missing', const <String>[]),
  );
}

Uint8List _pythonIndexBytes() =>
    Uint8List.fromList(utf8.encode('<a href="3.14.7/">3.14.7/</a>'));

Uint8List _pythonVersionListingBytes() =>
    Uint8List.fromList(utf8.encode('python-3.14.7-embed-amd64.zip'));

Matcher _preparationException({Matcher? message}) {
  final TypeMatcher<BuildPreparationException> matcher =
      isA<BuildPreparationException>();
  if (message == null) {
    return matcher;
  }
  return matcher.having(
    (BuildPreparationException error) => error.message,
    'message',
    message,
  );
}
