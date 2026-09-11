import 'dart:convert';

import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const NuGetPackageBuilder _builder = NuGetPackageBuilder();

void main() {
  group('文件映射', () {
    test('头文件与模块映射到 build/native/include 并剥离 include 前缀', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
          FileModel(name: 'bar.hpp', path: 'Include/detail/bar.hpp', size: 20),
          FileModel(name: 'mod.ixx', path: 'src/mod.ixx', size: 30),
          FileModel(name: 'plain.h', path: 'plain.h', size: 40),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        _packagePathOf(plan, 'include/foo.h'),
        'build/native/include/foo.h',
      );
      expect(
        _packagePathOf(plan, 'Include/detail/bar.hpp'),
        'build/native/include/detail/bar.hpp',
      );
      expect(
        _packagePathOf(plan, 'src/mod.ixx'),
        'build/native/include/src/mod.ixx',
      );
      expect(_packagePathOf(plan, 'plain.h'), 'build/native/include/plain.h');
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

    test('源码、资源、可执行文件等其他类型不打包', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 10),
          FileModel(name: 'README.md', path: 'README.md', size: 20),
          FileModel(name: 'logo.png', path: 'assets/logo.png', size: 30),
          FileModel(name: 'app.exe', path: 'bin/app.exe', size: 40),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(
        plan.entries.map((PackageEntry entry) => entry.packagePath),
        <String>['build/native/demo.targets', 'demo.nuspec'],
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

    test('二进制标记仅用于库文件', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
          FileModel(name: 'foo.lib', path: 'lib/foo.lib', size: 20),
          FileModel(name: 'foo.dll', path: 'bin/foo.dll', size: 30),
          FileModel(name: 'foo.pdb', path: 'lib/foo.pdb', size: 40),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(_fileSource(plan, 'include/foo.h').isBinary, isFalse);
      expect(_fileSource(plan, 'lib/foo.lib').isBinary, isTrue);
      expect(_fileSource(plan, 'bin/foo.dll').isBinary, isTrue);
      expect(_fileSource(plan, 'lib/foo.pdb').isBinary, isTrue);
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

    test('编译命令不写入 targets', () async {
      final PackModel pack = _pack()
        ..commands = <CmdModel>[
          const CmdModel(command: 'echo pre', type: CmdType.preBuild),
          const CmdModel(command: 'echo post', type: CmdType.postBuild),
        ];

      final String targets = _targetsOf(await _builder.buildPlan(pack));

      expect(targets, isNot(contains('echo pre')));
      expect(targets, isNot(contains('echo post')));
    });

    test('无宏、库目录、附加库时仅保留 include 行', () async {
      final String targets = _targetsOf(await _builder.buildPlan(_pack()));

      expect(targets, isNot(contains('<PreprocessorDefinitions>')));
      expect(targets, isNot(contains('<AdditionalLibraryDirectories>')));
      expect(targets, isNot(contains('<AdditionalDependencies>')));
      expect(targets, isNot(contains('ItemDefinitionGroup Condition')));
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
        'build/native/include/a.h',
        'build/native/include/B.h',
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
}) {
  return PackModel(
    name: name,
    version: version,
    author: author,
    description: description,
    license: license,
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
