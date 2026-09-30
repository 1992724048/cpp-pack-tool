import 'dart:convert';

import 'package:cpp_nuget_pack/pack/model/build_model.dart';
import 'package:cpp_nuget_pack/pack/model/cmd_model.dart';
import 'package:cpp_nuget_pack/pack/model/dependency_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/lib_dir_model.dart';
import 'package:cpp_nuget_pack/pack/model/library_model.dart';
import 'package:cpp_nuget_pack/pack/model/macro_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/nuget/nuget_builder.dart';
import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const NuGetPackageBuilder _builder = NuGetPackageBuilder();

void main() {
  group('文件映射', () {
    test('头文件与模块映射到含源目录命名空间的 include 并剥离 include 前缀', () async {
      final PackModel pack = _pack(sourcePath: r'D:\libs\mylib')
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
          FileModel(name: 'bar.hpp', path: 'Include/detail/bar.hpp', size: 20),
          FileModel(name: 'mod.ixx', path: 'src/mod.ixx', size: 30),
          FileModel(name: 'plain.h', path: 'plain.h', size: 40),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'include/foo.h'),
        'build/native/include/mylib/foo.h',
      );
      expect(
        _packagePathOf(plan, 'Include/detail/bar.hpp'),
        'build/native/include/mylib/detail/bar.hpp',
      );
      expect(
        _packagePathOf(plan, 'src/mod.ixx'),
        'build/native/include/mylib/src/mod.ixx',
      );
      expect(
        _packagePathOf(plan, 'plain.h'),
        'build/native/include/mylib/plain.h',
      );
    });

    test('剥离 include 后首段与命名空间同名时不重复叠加', () async {
      final PackModel pack = _pack(sourcePath: r'D:\libs\gtest')
        ..files = <FileModel>[
          FileModel(name: 'gtest.h', path: 'include/gtest/gtest.h', size: 10),
          FileModel(
            name: 'gtest-port.h',
            path: 'include/gtest/internal/gtest-port.h',
            size: 20,
          ),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'include/gtest/gtest.h'),
        'build/native/include/gtest/gtest.h',
      );
      expect(
        _packagePathOf(plan, 'include/gtest/internal/gtest-port.h'),
        'build/native/include/gtest/internal/gtest-port.h',
      );
    });

    test('首段与命名空间大小写不敏感匹配时不叠加且结果沿文件路径大小写', () async {
      final PackModel pack = _pack(sourcePath: r'D:\libs\OpenVINO')
        ..files = <FileModel>[
          FileModel(
            name: 'openvino.h',
            path: 'include/openvino/openvino.h',
            size: 10,
          ),
          FileModel(
            name: 'extra.h',
            path: 'include/OPENVINO/extra.h',
            size: 20,
          ),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'include/openvino/openvino.h'),
        'build/native/include/openvino/openvino.h',
      );
      expect(
        _packagePathOf(plan, 'include/OPENVINO/extra.h'),
        'build/native/include/OPENVINO/extra.h',
      );
    });

    test('异名首段与平铺文件仍叠加命名空间', () async {
      final PackModel pack = _pack(sourcePath: r'D:\libs\mimalloc')
        ..files = <FileModel>[
          FileModel(name: 'mimalloc.h', path: 'include/mimalloc.h', size: 10),
          FileModel(
            name: 'foo.h',
            path: 'include/mimalloc-internal/foo.h',
            size: 20,
          ),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'include/mimalloc.h'),
        'build/native/include/mimalloc/mimalloc.h',
      );
      expect(
        _packagePathOf(plan, 'include/mimalloc-internal/foo.h'),
        'build/native/include/mimalloc/mimalloc-internal/foo.h',
      );
    });

    test('源目录缺失或 basename 为空时顶层命名空间回退为包名', () async {
      final PackModel noSource = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        ];
      final PackModel trailingSeparator = _pack(sourcePath: r'D:\libs\demo\')
        ..files = <FileModel>[
          FileModel(name: 'bar.h', path: 'include/bar.h', size: 10),
        ];

      expect(
        _packagePathOf(await _builder.buildPlan(noSource), 'include/foo.h'),
        'build/native/include/demo/foo.h',
      );
      expect(
        _packagePathOf(
          await _builder.buildPlan(trailingSeparator),
          'include/bar.h',
        ),
        'build/native/include/demo/bar.h',
      );
    });

    test('库文件映射到 files/library 并剥离 lib/bin 前缀保留子目录', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.lib', path: 'lib/x64/Release/foo.lib', size: 40),
          FileModel(name: 'bar.lib', path: 'Lib/foo/bar.lib', size: 50),
          FileModel(name: 'baz.dll', path: 'bin/x64/Debug/baz.dll', size: 60),
          FileModel(name: 'qux.pdb', path: 'Bin/qux.pdb', size: 70),
          FileModel(name: 'plain.lib', path: 'plain.lib', size: 80),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'lib/x64/Release/foo.lib'),
        'build/native/files/library/x64/Release/foo.lib',
      );
      expect(
        _packagePathOf(plan, 'Lib/foo/bar.lib'),
        'build/native/files/library/foo/bar.lib',
      );
      expect(
        _packagePathOf(plan, 'bin/x64/Debug/baz.dll'),
        'build/native/files/library/x64/Debug/baz.dll',
      );
      expect(_packagePathOf(plan, 'Bin/qux.pdb'), 'build/native/files/library/qux.pdb');
      expect(_packagePathOf(plan, 'plain.lib'), 'build/native/files/library/plain.lib');
    });

    test('NuGet 将 .a 放入 files/library 并保留二进制标记', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'libz.a', path: 'lib/release/libz.a', size: 10),
          FileModel(name: 'libz.dll.a', path: 'lib/debug/libz.dll.a', size: 20),
          FileModel(name: 'plain.a', path: 'plain.a', size: 30),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'lib/release/libz.a'),
        'build/native/files/library/release/libz.a',
      );
      expect(
        _packagePathOf(plan, 'lib/debug/libz.dll.a'),
        'build/native/files/library/debug/libz.dll.a',
      );
      expect(_packagePathOf(plan, 'plain.a'), 'build/native/files/library/plain.a');
      expect(_fileSource(plan, 'lib/release/libz.a').isBinary, isTrue);
      expect(_fileSource(plan, 'lib/debug/libz.dll.a').isBinary, isTrue);
      expect(_fileSource(plan, 'plain.a').isBinary, isTrue);
    });

    test('源码、资源、可执行文件等其他类型映射到 files 且不剥离路径段', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 10),
          FileModel(name: 'README.md', path: 'README.md', size: 20),
          FileModel(name: 'logo.png', path: 'assets/logo.png', size: 30),
          FileModel(name: 'app.exe', path: 'bin/app.exe', size: 40),
          FileModel(name: 'util.cpp', path: 'lib/util.cpp', size: 50),
          FileModel(name: 'build.bat', path: 'scripts/build.bat', size: 60),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'src/main.cpp'),
        'build/native/files/source/src/main.cpp',
      );
      expect(_packagePathOf(plan, 'README.md'), 'build/native/files/other/README.md');
      expect(
        _packagePathOf(plan, 'assets/logo.png'),
        'build/native/files/other/assets/logo.png',
      );
      expect(
        _packagePathOf(plan, 'bin/app.exe'),
        'build/native/files/executable/bin/app.exe',
      );
      expect(
        _packagePathOf(plan, 'lib/util.cpp'),
        'build/native/files/source/lib/util.cpp',
      );
      expect(
        _packagePathOf(plan, 'scripts/build.bat'),
        'build/native/files/script/scripts/build.bat',
      );
    });

    test('根级 build.py 不入包且大小写不敏感，子目录保留', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'build.py', path: 'build.py', size: 10),
          FileModel(name: 'Build.py', path: 'Build.py', size: 20),
          FileModel(name: 'build.py', path: 'scripts/build.py', size: 30),
          FileModel(name: 'main.cpp', path: 'main.cpp', size: 40),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);
      final List<String> filePaths = plan.entries
          .map((PackageEntry entry) => entry.source)
          .whereType<PackageFileSource>()
          .map((PackageFileSource source) => source.path)
          .toList();

      expect(filePaths, isNot(contains('build.py')));
      expect(filePaths, isNot(contains('Build.py')));
      expect(
        _packagePathOf(plan, 'scripts/build.py'),
        'build/native/files/python/scripts/build.py',
      );
    });

    test('空文件列表仅生成 nuspec 与 targets', () async {
      final PackagePlan plan = await _builder.buildPlan(_pack());

      expect(plan.fileCount, 2);
      expect(
        plan.entries.map((PackageEntry entry) => entry.packagePath),
        <String>['build/native/demo.targets', 'demo.nuspec'],
      );
    });

    test('二进制标记覆盖库文件与可执行文件', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
          FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 15),
          FileModel(name: 'foo.lib', path: 'lib/foo.lib', size: 20),
          FileModel(name: 'foo.dll', path: 'bin/foo.dll', size: 30),
          FileModel(name: 'foo.pdb', path: 'lib/foo.pdb', size: 40),
          FileModel(name: 'app.exe', path: 'bin/app.exe', size: 50),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(_fileSource(plan, 'include/foo.h').isBinary, isFalse);
      expect(_fileSource(plan, 'src/main.cpp').isBinary, isFalse);
      expect(_fileSource(plan, 'lib/foo.lib').isBinary, isTrue);
      expect(_fileSource(plan, 'bin/foo.dll').isBinary, isTrue);
      expect(_fileSource(plan, 'lib/foo.pdb').isBinary, isTrue);
      expect(_fileSource(plan, 'bin/app.exe').isBinary, isTrue);
    });

    test('.png 等未映射扩展名被标记为二进制', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'logo.png', path: 'assets/logo.png', size: 4),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(_fileSource(plan, 'assets/logo.png').isBinary, isTrue);
    });

    test('.map 与 .exp 不算二进制', () {
      final FileModel map = FileModel(name: 'foo.map', path: 'x/foo.map', size: 4);

      expect(isBinaryFileType(map.type, map.extension), isFalse);

      final FileModel exp = FileModel(name: 'foo.exp', path: 'x/foo.exp', size: 4);

      expect(isBinaryFileType(exp.type, exp.extension), isFalse);
    });
  });

  group('nuspec', () {
    test('生成完整元数据与 native0.0 依赖组', () async {
      final PackModel pack =
          _pack(version: '1.2.3+7', description: '演示包', license: 'MIT')
            ..dependencies = <DependencyModel>[
              const DependencyModel(name: 'libfoo', version: '[1.0,)'),
            ];

      final String nuspec = _nuspecOf(await _builder.buildPlan(pack));

      expect(nuspec, contains('<?xml version="1.0" encoding="utf-8"?>'));
      expect(
        nuspec,
        contains(
          '<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">',
        ),
      );
      expect(nuspec, contains('<id>demo</id>'));
      expect(nuspec, contains('<version>1.2.3</version>'));
      expect(nuspec, contains('<authors>tester</authors>'));
      expect(nuspec, contains('<description>演示包</description>'));
      expect(nuspec, contains('<license type="expression">MIT</license>'));
      expect(
        nuspec,
        contains('<requireLicenseAcceptance>false</requireLicenseAcceptance>'),
      );
      expect(nuspec, contains('<tags>native C++</tags>'));
      expect(nuspec, contains('<group targetFramework="native0.0">'));
      expect(nuspec, contains('<dependency id="libfoo" version="[1.0,)" />'));
    });

    test('恒定声明包图标且位于许可证声明与许可接受之间', () async {
      final String nuspec = _nuspecOf(
        await _builder.buildPlan(_pack(license: 'MIT')),
      );

      expect(nuspec, contains(r'<icon>images\icon.png</icon>'));
      expect(
        nuspec.indexOf(r'<icon>images\icon.png</icon>'),
        greaterThan(nuspec.indexOf('<license type="expression">MIT</license>')),
      );
      expect(
        nuspec.indexOf(r'<icon>images\icon.png</icon>'),
        lessThan(nuspec.indexOf('<requireLicenseAcceptance>')),
      );
    });

    test('多个依赖全部写入依赖组', () async {
      final PackModel pack = _pack()
        ..dependencies = <DependencyModel>[
          const DependencyModel(name: 'libfoo', version: '[1.0,)'),
          const DependencyModel(name: 'libbar', version: '2.0.0'),
        ];

      final String nuspec = _nuspecOf(await _builder.buildPlan(pack));

      expect(nuspec, contains('<dependency id="libfoo" version="[1.0,)" />'));
      expect(nuspec, contains('<dependency id="libbar" version="2.0.0" />'));
    });

    test('描述为空时回退为包名', () async {
      expect(
        _nuspecOf(await _builder.buildPlan(_pack(description: ''))),
        contains('<description>demo</description>'),
      );
      expect(
        _nuspecOf(await _builder.buildPlan(_pack())),
        contains('<description>demo</description>'),
      );
    });

    test('许可证为空时省略 license 节点与依赖节点', () async {
      final String nuspec = _nuspecOf(await _builder.buildPlan(_pack()));

      expect(nuspec, isNot(contains('<license')));
      expect(nuspec, isNot(contains('<dependencies>')));
    });

    test('XML 特殊字符被转义', () async {
      final PackModel pack =
          _pack(author: 'A & B', description: 'x < y > z "q" \'s\'')
            ..dependencies = <DependencyModel>[
              const DependencyModel(name: 'lib&foo', version: '<1.0>'),
            ];

      final String nuspec = _nuspecOf(await _builder.buildPlan(pack));

      expect(nuspec, contains('<authors>A &amp; B</authors>'));
      expect(
        nuspec,
        contains(
          '<description>x &lt; y &gt; z &quot;q&quot; &apos;s&apos;</description>',
        ),
      );
      expect(
        nuspec,
        contains('<dependency id="lib&amp;foo" version="&lt;1.0&gt;" />'),
      );
    });
  });

  group('targets', () {
    test('始终写入 include 目录行与 files 下 11 个子目录搜索根', () async {
      final String targets = _targetsOf(await _builder.buildPlan(_pack()));

      expect(
        targets,
        contains(
          r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)include;'
          r'$(MSBuildThisFileDirectory)files\source;'
          r'$(MSBuildThisFileDirectory)files\library;'
          r'$(MSBuildThisFileDirectory)files\assembly;'
          r'$(MSBuildThisFileDirectory)files\resource;'
          r'$(MSBuildThisFileDirectory)files\script;'
          r'$(MSBuildThisFileDirectory)files\fortran;'
          r'$(MSBuildThisFileDirectory)files\llvm;'
          r'$(MSBuildThisFileDirectory)files\python;'
          r'$(MSBuildThisFileDirectory)files\data;'
          r'$(MSBuildThisFileDirectory)files\executable;'
          r'$(MSBuildThisFileDirectory)files\other;'
          r'%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
        ),
      );
      expect(
        targets,
        isNot(
          contains(
            r'$(MSBuildThisFileDirectory)files;%(AdditionalIncludeDirectories)',
          ),
        ),
        reason: 'files/ 根只承载许可证，不再作为搜索根',
      );
      expect(
        targets,
        contains(
          '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
        ),
      );
    });

    test(r'手选模型全为所有配置、库文件只有 dll 与 pdb 时 .targets 不含任何 $(Configuration)', () async {
      final PackModel pack = _pack()
        ..macros = <MacroModel>[const MacroModel(value: 'ALL=1')]
        ..libDirectories = <LibDirModel>[
          const LibDirModel(path: r'third_party\lib'),
        ]
        ..libraries = <LibraryModel>[const LibraryModel(name: 'mylib.lib')]
        ..commands = <CmdModel>[
          const CmdModel(command: 'echo one', type: CmdType.preBuild),
        ]
        ..files = <FileModel>[
          FileModel(name: 'foo.dll', path: 'bin/x64/Release/foo.dll', size: 10),
          FileModel(name: 'foo.pdb', path: 'bin/x64/Debug/foo.pdb', size: 10),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        isNot(contains(r'$(Configuration)')),
        reason: '本用例守的是手选全配置模型不切条件组；dll / pdb 走独立的运行时'
            '项组，其不参与配置推断由「dll 与 pdb 不做配置隔离」用例把关',
      );
      expect(targets, contains('<ItemDefinitionGroup>'), reason: '仍有全配置的分组');
    });

    test('手选 Release 的宏落在 Release 条件定义组内', () async {
      final PackModel pack = _pack()
        ..macros = <MacroModel>[
          const MacroModel(value: 'ALL=1'),
          const MacroModel(value: 'REL=1', buildModel: BuildModel.release),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      final int allGroupIndex = targets.indexOf('  <ItemDefinitionGroup>');
      final int releaseGroupIndex = targets.indexOf(
        r'''<ItemDefinitionGroup Condition="'$(Configuration)'=='Release'">''',
      );
      expect(
        releaseGroupIndex,
        greaterThan(allGroupIndex),
        reason: '手选的 Release 宏仍切出条件定义组，且排在无条件组之后',
      );
      expect(
        targets.substring(releaseGroupIndex),
        contains(
          '<PreprocessorDefinitions>REL=1;'
          '%(PreprocessorDefinitions)</PreprocessorDefinitions>',
        ),
      );
      expect(
        targets.substring(allGroupIndex, releaseGroupIndex),
        isNot(contains('REL=1')),
        reason: 'REL=1 不落进无条件定义组',
      );
    });

    test('路径里的 release 段切出条件组而手选命令仍带配置后缀', () async {
      final PackModel pack = _pack()
        ..commands = <CmdModel>[
          const CmdModel(
            command: 'echo pre-rel',
            type: CmdType.preBuild,
            buildModel: BuildModel.release,
          ),
        ]
        ..files = <FileModel>[
          FileModel(name: 'lib.lib', path: 'lib/release/lib.lib', size: 10),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)files\library\release;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
        reason: '路径里的 release 段原样保留为库目录名',
      );
      expect(
        targets,
        contains(
          r'<AdditionalDependencies>lib.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
        reason: '文件本身照旧按扩展名分类',
      );
      final int releaseGroupIndex = targets.indexOf(
        r'''<ItemDefinitionGroup Condition="'$(Configuration)'=='Release'">''',
      );
      expect(releaseGroupIndex, greaterThan(-1), reason: 'release 段切出条件定义组');
      expect(
        targets.substring(releaseGroupIndex),
        contains(r'files\library\release'),
        reason: '派生库目录落在 Release 条件定义组内',
      );
      expect(
        targets.substring(0, releaseGroupIndex),
        isNot(contains('lib.lib')),
        reason: '派生附加库不落进无条件定义组',
      );
      expect(
        targets,
        contains('<Target Name="CnpPreBuild_demo_89e495e7_Release" '),
        reason: '手选 Release 的命令仍生成带配置后缀的条件目标',
      );
    });

    test('release / debug 路径段决定 lib 的配置', () {
      expect(
        NuGetPackageBuilder.libraryBuildModelOf('files/library/x64/Release/foo.lib'),
        BuildModel.release,
      );
      expect(
        NuGetPackageBuilder.libraryBuildModelOf('files/library/x64/Debug/foo.lib'),
        BuildModel.debug,
      );
      expect(
        NuGetPackageBuilder.libraryBuildModelOf('files/library/foo.lib'),
        BuildModel.all,
      );
    });

    test('多段命中取最后一个', () {
      expect(
        NuGetPackageBuilder.libraryBuildModelOf('files/library/release/Debug/foo.lib'),
        BuildModel.debug,
      );
      expect(
        NuGetPackageBuilder.libraryBuildModelOf('files/library/Debug/release/foo.lib'),
        BuildModel.release,
      );
    });

    test('大小写不敏感', () {
      expect(
        NuGetPackageBuilder.libraryBuildModelOf('files/library/x64/RELEASE/foo.lib'),
        BuildModel.release,
      );
    });

    test('宏按构建配置分组并生成条件组', () async {
      final PackModel pack = _pack()
        ..macros = <MacroModel>[
          const MacroModel(value: 'ALL=1'),
          const MacroModel(value: 'REL=1', buildModel: BuildModel.release),
          const MacroModel(value: 'DBG=1', buildModel: BuildModel.debug),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          '<PreprocessorDefinitions>ALL=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>',
        ),
      );
      expect(
        targets,
        contains(
          r'''<ItemDefinitionGroup Condition="'$(Configuration)'=='Release'">''',
        ),
      );
      expect(
        targets,
        contains(
          '<PreprocessorDefinitions>REL=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>',
        ),
      );
      expect(
        targets,
        contains(
          r'''<ItemDefinitionGroup Condition="'$(Configuration)'=='Debug'">''',
        ),
      );
      expect(
        targets,
        contains(
          '<PreprocessorDefinitions>DBG=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>',
        ),
      );

      final int releaseIndex = targets.indexOf(r"=='Release'");
      final int debugIndex = targets.indexOf(r"=='Debug'");
      expect(releaseIndex, greaterThan(-1));
      expect(debugIndex, greaterThan(releaseIndex));
    });

    test('附加库目录合并用户条目与派生目录并去重', () async {
      final PackModel pack = _pack()
        ..libDirectories = <LibDirModel>[
          const LibDirModel(path: r'third_party\lib'),
          const LibDirModel(path: r'third_party\LIB'),
        ]
        ..files = <FileModel>[
          FileModel(name: 'foo.lib', path: 'lib/x64/Release/foo.lib', size: 10),
          FileModel(name: 'bar.lib', path: 'lib/bar.lib', size: 20),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>third_party\lib;'
          r'$(MSBuildThisFileDirectory)files\library;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
        reason: '用户条目在前、无配置段的派生目录并入同一条',
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)files\library\x64\Release;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
        reason: '带 release 段的派生目录随配置单独落桶',
      );
      expect(r'third_party\lib'.allMatches(targets).length, 1);
    });

    test('库文件自动加入库目录与附加库并去重', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.lib', path: 'lib/x64/Release/foo.lib', size: 10),
          FileModel(name: 'FOO.LIB', path: 'lib/x64/Release/FOO.LIB', size: 11),
          FileModel(name: 'bar.lib', path: 'lib/Debug/bar.lib', size: 20),
          FileModel(name: 'baz.lib', path: 'lib/baz.lib', size: 30),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)files\library;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
        reason: r'无配置段的 baz.lib 只贡献 files\library 根',
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)files\library\x64\Release;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
        reason: 'Release 桶内两个同名文件去重后只留一条目录',
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)files\library\Debug;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          '<AdditionalDependencies>baz.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        targets,
        contains(
          '<AdditionalDependencies>foo.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        targets,
        contains(
          '<AdditionalDependencies>bar.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        r'$(MSBuildThisFileDirectory)files\library\x64\Release'
            .allMatches(targets)
            .length,
        1,
      );
      expect(r'FOO.LIB'.allMatches(targets).length, 0);
    });

    test('同名 lib 分处 Release 与 Debug 时两条都发射且各带条件', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.lib', path: 'lib/x64/Release/foo.lib', size: 4),
          FileModel(name: 'foo.lib', path: 'lib/x64/Debug/foo.lib', size: 4),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      final int releaseGroupIndex = targets.indexOf(
        r'''<ItemDefinitionGroup Condition="'$(Configuration)'=='Release'">''',
      );
      final int debugGroupIndex = targets.indexOf(
        r'''<ItemDefinitionGroup Condition="'$(Configuration)'=='Debug'">''',
      );
      expect(releaseGroupIndex, greaterThan(-1), reason: 'release 段切出 Release 条件定义组');
      expect(debugGroupIndex, greaterThan(releaseGroupIndex), reason: 'Debug 条件定义组紧随其后');
      final String releaseGroup = targets.substring(releaseGroupIndex, debugGroupIndex);
      final String debugGroup = targets.substring(debugGroupIndex);
      expect(
        releaseGroup,
        contains(
          '<AdditionalDependencies>foo.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
        reason: 'Release 组发射一条 foo.lib',
      );
      expect(
        debugGroup,
        contains(
          '<AdditionalDependencies>foo.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
        reason: 'Debug 组也发射一条 foo.lib',
      );
      expect(releaseGroup, contains(r'files\library\x64\Release'), reason: 'Release 组取 x64/Release 的派生目录');
      expect(debugGroup, contains(r'files\library\x64\Debug'), reason: 'Debug 组取 x64/Debug 的派生目录');
      expect(
        targets.substring(0, releaseGroupIndex),
        isNot(contains('foo.lib')),
        reason: '同名不同配置各落一桶，无条件组不重复列出',
      );
    });

    test('.a 与 .lib 同规则按路径段隔离且不生成运行时二进制部署', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'rel.a', path: 'lib/release/rel.a', size: 10),
          FileModel(name: 'libz.dll.a', path: 'lib/debug/libz.dll.a', size: 20),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);
      final String targets = _targetsOf(plan);

      expect(
        _packagePathOf(plan, 'lib/release/rel.a'),
        'build/native/files/library/release/rel.a',
      );
      expect(
        _packagePathOf(plan, 'lib/debug/libz.dll.a'),
        'build/native/files/library/debug/libz.dll.a',
      );
      expect(
        targets,
        contains(
          r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)include;'
          r'$(MSBuildThisFileDirectory)files\source;',
        ),
      );
      expect(
        targets,
        contains(
          r'''<ItemDefinitionGroup Condition="'$(Configuration)'=='Release'">''',
        ),
        reason: 'release 段的 .a 与 .lib 同规则切出条件定义组',
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)files\library\release;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)files\library\debug;'
          r'%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          '<AdditionalDependencies>rel.a;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        targets,
        contains(
          '<AdditionalDependencies>libz.dll.a;'
          '%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(targets, isNot(contains('<PkgRuntimeBinary')));
      expect(targets, isNot(contains('DeployPkgRuntimeBinaries')));
    });

    test('附加库按构建配置分组', () async {
      final PackModel pack = _pack()
        ..libraries = <LibraryModel>[
          const LibraryModel(name: 'mylib.lib'),
          const LibraryModel(name: 'other.lib', buildModel: BuildModel.debug),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          '<AdditionalDependencies>mylib.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        targets,
        contains(
          '<AdditionalDependencies>other.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
    });

    test('编译前/后命令生成自定义目标与逐命令 Exec 并转义 XML 特殊字符', () async {
      final PackModel pack = _pack()
        ..commands = <CmdModel>[
          const CmdModel(command: 'echo one', type: CmdType.preBuild),
          const CmdModel(command: 'echo two', type: CmdType.preBuild),
          const CmdModel(
            command: r'echo $(ProjectDir) & <done>',
            type: CmdType.postBuild,
          ),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          '<Target Name="CnpPreBuild_demo_89e495e7" BeforeTargets="ClCompile">',
        ),
      );
      expect(
        targets,
        contains(
          '<Target Name="CnpPostBuild_demo_89e495e7" AfterTargets="Build">',
        ),
      );
      expect(
        targets,
        contains(
          r'<Exec Command="echo one" WorkingDirectory="$(ProjectDir)" IgnoreStandardErrorWarningFormat="true" />',
        ),
      );
      expect(
        targets,
        contains(r'<Exec Command="echo $(ProjectDir) &amp; &lt;done&gt;"'),
      );
      expect(
        targets.indexOf('echo one'),
        lessThan(targets.indexOf('echo two')),
      );
      expect(
        targets.indexOf('echo two'),
        lessThan(targets.indexOf('CnpPostBuild_demo_89e495e7')),
      );
      expect(targets, isNot(contains('<PropertyGroup')));
      expect(targets, isNot(contains('PreBuildEvent')));
      expect(targets, isNot(contains('PostBuildEvent')));
    });

    test('编译前/后命令按构建配置生成条件目标（名称带配置后缀）', () async {
      final PackModel pack = _pack()
        ..commands = <CmdModel>[
          const CmdModel(
            command: 'echo pre-rel',
            type: CmdType.preBuild,
            buildModel: BuildModel.release,
          ),
          const CmdModel(
            command: 'echo post-dbg',
            type: CmdType.postBuild,
            buildModel: BuildModel.debug,
          ),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          '<Target Name="CnpPreBuild_demo_89e495e7_Release" '
          'BeforeTargets="ClCompile" '
          r'''Condition="'$(Configuration)'=='Release'">''',
        ),
      );
      expect(
        targets,
        contains(
          '<Target Name="CnpPostBuild_demo_89e495e7_Debug" '
          'AfterTargets="Build" '
          r'''Condition="'$(Configuration)'=='Debug'">''',
        ),
      );
      expect(
        targets.indexOf('echo pre-rel'),
        greaterThan(targets.indexOf('CnpPreBuild_demo_89e495e7_Release')),
      );
      expect(
        targets.indexOf('echo post-dbg'),
        greaterThan(targets.indexOf('CnpPostBuild_demo_89e495e7_Debug')),
      );
      expect(targets, isNot(contains('CnpPreBuild_demo_89e495e7"')));
      expect(targets, isNot(contains('CnpPostBuild_demo_89e495e7"')));
    });

    test('无编译命令时不生成命令目标与 Exec', () async {
      final String targets = _targetsOf(await _builder.buildPlan(_pack()));

      expect(targets, isNot(contains('CnpPreBuild')));
      expect(targets, isNot(contains('CnpPostBuild')));
      expect(targets, isNot(contains('<Exec')));
      expect(targets, isNot(contains('<PropertyGroup')));
    });

    test('dll/pdb 生成唯一无条件运行时项组与硬链接部署目标', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.dll', path: 'bin/x64/Release/foo.dll', size: 10),
          FileModel(name: 'bar.dll', path: 'bin/bar.dll', size: 20),
          FileModel(name: 'foo.pdb', path: 'bin/x64/Debug/foo.pdb', size: 30),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        isNot(contains(r"'$(Configuration)'")),
        reason: '路径里的 Release/Debug 段不再切出条件组',
      );
      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)files\library\x64\Release\foo.dll" />',
        ),
      );
      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)files\library\bar.dll" />',
        ),
      );
      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)files\library\x64\Debug\foo.pdb" />',
        ),
      );
      expect(
        targets,
        contains(
          r'''<Target Name="DeployPkgRuntimeBinaries_demo_89e495e7" AfterTargets="Build" Condition="'@(PkgRuntimeBinary)' != ''">''',
        ),
      );
      expect(
        targets,
        contains(
          r'<Copy SourceFiles="@(PkgRuntimeBinary)" DestinationFolder="$(OutDir)" SkipUnchangedFiles="true" UseHardlinksIfPossible="true" />',
        ),
      );
      expect(
        targets,
        contains(
          r"""<FileWrites Include="@(PkgRuntimeBinary->'$(OutDir)%(Filename)%(Extension)')" />""",
        ),
      );
      expect(
        targets.indexOf('<Target Name="DeployPkgRuntimeBinaries_demo_'),
        greaterThan(targets.indexOf('<PkgRuntimeBinary')),
      );
    });

    test('dll 与 pdb 不做配置隔离', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'bar.dll', path: 'bin/Debug/bar.dll', size: 4),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        isNot(contains('<AdditionalDependencies>')),
        reason: 'dll 不参与附加库派生：本包既无 .lib / .a 也无手选 libraries',
      );
      expect(
        'bar.dll'.allMatches(targets).length,
        1,
        reason: 'dll 仅经 PkgRuntimeBinary 发射一次：既不派生附加库与库目录，'
            '也不因路径段被切进条件组',
      );
      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)files\library\Debug\bar.dll" />',
        ),
      );
      expect(
        targets,
        isNot(contains('<ItemDefinitionGroup Condition')),
        reason: '运行时二进制不产生按配置切分的定义组',
      );
    });

    test('运行时二进制无构建标签时仅生成无条件项组', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.dll', path: 'bin/foo.dll', size: 10),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)files\library\foo.dll" />',
        ),
      );
      expect(targets, isNot(contains('<ItemGroup Condition')));
    });

    test('根目录许可证生成硬链接部署目标且位于 </Project> 之前', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'LICENSE', path: 'LICENSE', size: 10),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          '<Target Name="DeployPkgLicense_demo_89e495e7" AfterTargets="Build"',
        ),
      );
      expect(
        targets,
        contains(
          r"""Condition="Exists('$(MSBuildThisFileDirectory)files\LICENSE')">""",
        ),
      );
      expect(
        targets,
        contains(
          r'''<Copy SourceFiles="$(MSBuildThisFileDirectory)files\LICENSE"''',
        ),
      );
      expect(
        targets,
        contains(r'DestinationFiles="$(OutDir)licenses\demo_license.txt"'),
      );
      expect(
        targets,
        contains(r'SkipUnchangedFiles="true" UseHardlinksIfPossible="true" />'),
      );
      expect(
        targets,
        contains(
          r'<FileWrites Include="$(OutDir)licenses\demo_license.txt" />',
        ),
      );
      expect(
        targets.indexOf('</Project>'),
        greaterThan(targets.indexOf('DeployPkgLicense_demo_89e495e7')),
      );
    });

    test('无许可证时不生成许可证部署目标', () async {
      final String targets = _targetsOf(await _builder.buildPlan(_pack()));

      expect(targets, isNot(contains('DeployPkgLicense')));
    });

    test('仅子目录中的许可证不生成部署目标', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'LICENSE', path: 'docs/LICENSE', size: 10),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(targets, isNot(contains('DeployPkgLicense')));
    });

    test('资源文件生成 ResourceCompile 项并附加所在目录', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'app.rc', path: 'res/app.rc', size: 10),
          FileModel(name: 'version.rc', path: 'version.rc', size: 20),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          r'<ResourceCompile Include="$(MSBuildThisFileDirectory)files\resource\res\app.rc">',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)files\resource\res;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          r'<ResourceCompile Include="$(MSBuildThisFileDirectory)files\resource\version.rc">',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)files\resource;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
        ),
      );
    });

    test('汇编文件生成 MASM 条件导入与唯一 ObjectFileName', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'x.asm', path: 'src/x.asm', size: 10),
          FileModel(name: 'y.asm', path: 'asm/vendor/y.asm', size: 20),
          FileModel(name: 'z.s', path: 'src/z.s', size: 30),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(targets, contains('<ImportGroup Condition="'));
      expect(targets, contains(r"'$(MASMBeforeTargets)' == ''"));
      expect(targets, contains(r"'$(VCTargetsPath)' != ''"));
      expect(
        targets,
        contains(r"Exists('$(VCTargetsPath)\BuildCustomizations\masm.props')"),
      );
      expect(
        targets,
        contains(
          r"Exists('$(VCTargetsPath)\BuildCustomizations\masm.targets')",
        ),
      );
      expect(
        targets,
        contains(
          r'<Import Project="$(VCTargetsPath)\BuildCustomizations\masm.props" />',
        ),
      );
      expect(
        targets,
        contains(
          r'<Import Project="$(VCTargetsPath)\BuildCustomizations\masm.targets" />',
        ),
      );
      expect(
        targets,
        contains(
          r'<MASM Include="$(MSBuildThisFileDirectory)files\assembly\src\x.asm">',
        ),
      );
      expect(
        targets,
        contains(
          r'<ObjectFileName>$(IntDir)asm_demo_89e495e7_files_assembly_src_x.asm.obj</ObjectFileName>',
        ),
      );
      expect(
        targets,
        contains(
          r'<MASM Include="$(MSBuildThisFileDirectory)files\assembly\asm\vendor\y.asm">',
        ),
      );
      expect(
        targets,
        contains(
          r'<ObjectFileName>$(IntDir)asm_demo_89e495e7_files_assembly_asm_vendor_y.asm.obj</ObjectFileName>',
        ),
      );
      expect(targets, isNot(contains('z.s')));
    });

    test('无 .asm 文件时不生成 MASM 导入与项', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 10),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(targets, isNot(contains('<ImportGroup')));
      expect(targets, isNot(contains('<MASM')));
    });

    test('无宏、库目录、附加库、命令与特殊文件时仅保留 include 行', () async {
      final String targets = _targetsOf(await _builder.buildPlan(_pack()));

      expect(targets, isNot(contains('<PreprocessorDefinitions>')));
      expect(targets, isNot(contains('<AdditionalLibraryDirectories>')));
      expect(targets, isNot(contains('<AdditionalDependencies>')));
      expect(targets, isNot(contains('ItemDefinitionGroup Condition')));
      expect(targets, isNot(contains('<PropertyGroup')));
      expect(targets, isNot(contains('CnpPreBuild')));
      expect(targets, isNot(contains('CnpPostBuild')));
      expect(targets, isNot(contains('<Exec')));
      expect(targets, isNot(contains('<ImportGroup')));
      expect(targets, isNot(contains('<MASM')));
      expect(targets, isNot(contains('<ResourceCompile')));
      expect(targets, isNot(contains('PkgRuntimeBinary')));
      expect(targets, isNot(contains('DeployPkgLicense')));
    });
  });

  group('计划', () {
    test('包内条目按大小写不敏感路径确定性排序', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'B.h', path: 'include/B.h', size: 10),
          FileModel(name: 'a.h', path: 'include/a.h', size: 20),
          FileModel(name: 'zeta.lib', path: 'lib/zeta.lib', size: 30),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);
      final List<String> paths = plan.entries
          .map((PackageEntry entry) => entry.packagePath)
          .toList();

      expect(paths, <String>[
        'build/native/demo.targets',
        'build/native/files/library/zeta.lib',
        'build/native/include/demo/a.h',
        'build/native/include/demo/B.h',
        'demo.nuspec',
      ]);

      final PackagePlan rebuilt = await _builder.buildPlan(pack);

      expect(
        rebuilt.entries.map((PackageEntry entry) => entry.packagePath),
        paths,
      );
    });

    test('文件数量与总大小统计与条目一致', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 100),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(plan.fileCount, 3);
      final int generatedBytes = <String>[
        _nuspecOf(plan),
        _targetsOf(plan),
      ].fold<int>(0, (int sum, String text) => sum + utf8.encode(text).length);
      expect(plan.totalSize, 100 + generatedBytes);
    });
  });
}

PackModel _pack({
  String name = 'demo',
  String version = '1.0.0',
  String author = 'tester',
  String? description,
  String? license,
  String? sourcePath,
}) {
  return PackModel(
    name: name,
    version: version,
    author: author,
    description: description,
    license: license,
    sourcePath: sourcePath,
  );
}

String _packagePathOf(PackagePlan plan, String sourcePath) {
  return plan.entries
      .firstWhere(
        (PackageEntry entry) => switch (entry.source) {
          PackageFileSource(:final String path) => path == sourcePath,
          PackageGeneratedSource() => false,
        },
      )
      .packagePath;
}

PackageFileSource _fileSource(PackagePlan plan, String sourcePath) {
  return plan.entries
          .firstWhere(
            (PackageEntry entry) => switch (entry.source) {
              PackageFileSource(:final String path) => path == sourcePath,
              PackageGeneratedSource() => false,
            },
          )
          .source
      as PackageFileSource;
}

String _nuspecOf(PackagePlan plan) => _generatedContent(plan, 'demo.nuspec');

String _targetsOf(PackagePlan plan) =>
    _generatedContent(plan, 'build/native/demo.targets');

String _generatedContent(PackagePlan plan, String packagePath) {
  return (plan.entries
              .firstWhere(
                (PackageEntry entry) => entry.packagePath == packagePath,
              )
              .source
          as PackageGeneratedSource)
      .content;
}
