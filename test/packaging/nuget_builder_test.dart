import 'dart:convert';

import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
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

    test('库文件映射到 build/native/lib 并剥离 lib/bin 前缀保留子目录', () async {
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
        'build/native/lib/x64/Release/foo.lib',
      );
      expect(
        _packagePathOf(plan, 'Lib/foo/bar.lib'),
        'build/native/lib/foo/bar.lib',
      );
      expect(
        _packagePathOf(plan, 'bin/x64/Debug/baz.dll'),
        'build/native/lib/x64/Debug/baz.dll',
      );
      expect(_packagePathOf(plan, 'Bin/qux.pdb'), 'build/native/lib/qux.pdb');
      expect(_packagePathOf(plan, 'plain.lib'), 'build/native/lib/plain.lib');
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
        'build/native/files/src/main.cpp',
      );
      expect(_packagePathOf(plan, 'README.md'), 'build/native/files/README.md');
      expect(
        _packagePathOf(plan, 'assets/logo.png'),
        'build/native/files/assets/logo.png',
      );
      expect(
        _packagePathOf(plan, 'bin/app.exe'),
        'build/native/files/bin/app.exe',
      );
      expect(
        _packagePathOf(plan, 'lib/util.cpp'),
        'build/native/files/lib/util.cpp',
      );
      expect(
        _packagePathOf(plan, 'scripts/build.bat'),
        'build/native/files/scripts/build.bat',
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
        'build/native/files/scripts/build.py',
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
    test('始终写入 include 目录行', () async {
      final String targets = _targetsOf(await _builder.buildPlan(_pack()));

      expect(
        targets,
        contains(
          r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
        ),
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
          r'<AdditionalLibraryDirectories>third_party\lib;$(MSBuildThisFileDirectory)lib;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)lib\x64\Release;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(r'third_party\lib'.allMatches(targets).length, 1);
      expect(r"=='Release'".allMatches(targets).length, 1);
    });

    test('库文件自动按构建配置加入库目录与附加库并去重', () async {
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
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)lib\x64\Release;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalDependencies>foo.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)lib\Debug;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalDependencies>bar.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalLibraryDirectories>$(MSBuildThisFileDirectory)lib;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalDependencies>baz.lib;%(AdditionalDependencies)</AdditionalDependencies>',
        ),
      );
      expect(
        r'$(MSBuildThisFileDirectory)lib\x64\Release'
            .allMatches(targets)
            .length,
        1,
      );
      expect(r'FOO.LIB'.allMatches(targets).length, 0);
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

    test('编译命令按类型追加消费者值并转义 XML 特殊字符', () async {
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
          r'<PreBuildEvent>$(PreBuildEvent)&#x0D;&#x0A;echo one&#x0D;&#x0A;echo two</PreBuildEvent>',
        ),
      );
      expect(
        targets,
        contains(
          r'<PostBuildEvent>$(PostBuildEvent)&#x0D;&#x0A;echo $(ProjectDir) &amp; &lt;done&gt;</PostBuildEvent>',
        ),
      );
      expect(targets, contains('<PropertyGroup>'));
      expect(targets, isNot(contains('PropertyGroup Condition')));
    });

    test('编译命令按构建配置写入条件 PropertyGroup', () async {
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

      const String releaseGroup =
          r'''<PropertyGroup Condition="'$(Configuration)'=='Release'">''';
      const String debugGroup =
          r'''<PropertyGroup Condition="'$(Configuration)'=='Debug'">''';
      expect(targets, contains(releaseGroup));
      expect(targets, contains(debugGroup));
      expect(
        targets.indexOf('echo pre-rel'),
        greaterThan(targets.indexOf(releaseGroup)),
      );
      expect(
        targets.indexOf('echo post-dbg'),
        greaterThan(targets.indexOf(debugGroup)),
      );
      expect(targets, isNot(contains('<PropertyGroup>')));
    });

    test('无编译命令时不生成命令 PropertyGroup', () async {
      final String targets = _targetsOf(await _builder.buildPlan(_pack()));

      expect(targets, isNot(contains('PreBuildEvent')));
      expect(targets, isNot(contains('PostBuildEvent')));
      expect(targets, isNot(contains('<PropertyGroup')));
    });

    test('dll/pdb 生成条件运行时项与硬链接部署目标', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.dll', path: 'bin/x64/Release/foo.dll', size: 10),
          FileModel(name: 'bar.dll', path: 'bin/bar.dll', size: 20),
          FileModel(name: 'foo.pdb', path: 'bin/x64/Debug/foo.pdb', size: 30),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(r'''<ItemGroup Condition="'$(Configuration)'=='Release'">'''),
      );
      expect(
        targets,
        contains(r'''<ItemGroup Condition="'$(Configuration)'=='Debug'">'''),
      );
      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)lib\x64\Release\foo.dll" />',
        ),
      );
      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)lib\bar.dll" />',
        ),
      );
      expect(
        targets,
        contains(
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)lib\x64\Debug\foo.pdb" />',
        ),
      );
      expect(
        targets,
        contains(
          r'''<Target Name="DeployPkgRuntimeBinaries" AfterTargets="Build" Condition="'@(PkgRuntimeBinary)' != ''">''',
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
        targets.indexOf('<Target Name="DeployPkgRuntimeBinaries"'),
        greaterThan(targets.indexOf('<PkgRuntimeBinary')),
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
          r'<PkgRuntimeBinary Include="$(MSBuildThisFileDirectory)lib\foo.dll" />',
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
          r'<ResourceCompile Include="$(MSBuildThisFileDirectory)files\res\app.rc">',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)files\res;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
        ),
      );
      expect(
        targets,
        contains(
          r'<ResourceCompile Include="$(MSBuildThisFileDirectory)files\version.rc">',
        ),
      );
      expect(
        targets,
        contains(
          r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)files;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
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
          r'<MASM Include="$(MSBuildThisFileDirectory)files\src\x.asm">',
        ),
      );
      expect(
        targets,
        contains(
          r'<ObjectFileName>$(IntDir)asm_files_src_x.asm.obj</ObjectFileName>',
        ),
      );
      expect(
        targets,
        contains(
          r'<MASM Include="$(MSBuildThisFileDirectory)files\asm\vendor\y.asm">',
        ),
      );
      expect(
        targets,
        contains(
          r'<ObjectFileName>$(IntDir)asm_files_asm_vendor_y.asm.obj</ObjectFileName>',
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
      expect(targets, isNot(contains('<ImportGroup')));
      expect(targets, isNot(contains('<MASM')));
      expect(targets, isNot(contains('<ResourceCompile')));
      expect(targets, isNot(contains('PkgRuntimeBinary')));
      expect(targets, isNot(contains('DeployPkgLicense')));
    });
  });

  group('节点脚本', () {
    test('有效脚本生成 .ps1 条目且包内路径无重复', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        ]
        ..scripts = <ScriptProjectModel>[
          _validScript('script_1'),
          _validScript('script_2', trigger: ScriptTrigger.post),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);
      final List<String> paths = plan.entries
          .map((PackageEntry entry) => entry.packagePath)
          .toList();

      expect(
        paths.where((String path) => path.endsWith('.ps1')).toList(),
        <String>[
          'build/native/files/scripts/script_1.ps1',
          'build/native/files/scripts/script_2.ps1',
        ],
      );
      expect(paths.toSet().length, paths.length);
    });

    test('targets 末尾追加 pre/post Target、Exec 与环境变量', () async {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _validScript('script_1'),
          _validScript('script_2', trigger: ScriptTrigger.post),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          '<Target Name="CnpScripts_demo_89e495e7_Pre" BeforeTargets="PreBuildEvent">',
        ),
      );
      expect(
        targets,
        contains(
          '<Target Name="CnpScripts_demo_89e495e7_Post" AfterTargets="Build">',
        ),
      );
      expect(
        targets,
        contains(
          'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass '
          '-File &quot;\$(MSBuildThisFileDirectory)files\\scripts\\'
          'script_1.ps1&quot;',
        ),
      );
      expect(
        targets,
        contains(
          'EnvironmentVariables="CNP_PackageRoot=\$(MSBuildThisFileDirectory)"',
        ),
      );
      expect(targets, contains('IgnoreStandardErrorWarningFormat="true"'));
      expect(
        targets.indexOf('</Project>'),
        greaterThan(targets.indexOf('CnpScripts_demo_89e495e7_Post')),
      );
    });

    test('含运行库时 post Target 挂载到运行时部署目标之后', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.dll', path: 'bin/foo.dll', size: 10),
        ]
        ..scripts = <ScriptProjectModel>[
          _validScript('script_1', trigger: ScriptTrigger.post),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(
        targets,
        contains(
          '<Target Name="CnpScripts_demo_89e495e7_Post" '
          'AfterTargets="DeployPkgRuntimeBinaries">',
        ),
      );
    });

    test('无脚本时不生成脚本条目与 Target 片段', () async {
      final PackagePlan plan = await _builder.buildPlan(_pack());
      final String targets = _targetsOf(plan);

      expect(
        plan.entries.where(
          (PackageEntry entry) => entry.packagePath.endsWith('.ps1'),
        ),
        isEmpty,
      );
      expect(targets, isNot(contains('CnpScripts_')));
      expect(targets, isNot(contains('<Exec')));
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
        'build/native/include/demo/a.h',
        'build/native/include/demo/B.h',
        'build/native/lib/zeta.lib',
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

ScriptProjectModel _validScript(
  String id, {
  ScriptTrigger trigger = ScriptTrigger.pre,
  BuildModel buildModel = BuildModel.all,
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: id,
    name: '脚本 $id',
    trigger: trigger,
    buildModel: buildModel,
  );
  project.nodes = <ScriptNodeModel>[
    ScriptNodeModel(id: 'n1', type: 'flow.entry'),
    ScriptNodeModel(id: 'n2', type: 'value.text')..params['value'] = '你好',
    ScriptNodeModel(id: 'n3', type: 'log.message'),
  ];
  project.edges = <ScriptEdgeModel>[
    ScriptEdgeModel(
      from: ScriptEdgeEndpoint(node: 'n1', pin: 'out'),
      to: ScriptEdgeEndpoint(node: 'n3', pin: 'exec'),
    ),
    ScriptEdgeModel(
      from: ScriptEdgeEndpoint(node: 'n2', pin: 'result'),
      to: ScriptEdgeEndpoint(node: 'n3', pin: 'message'),
    ),
  ];
  return project;
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
