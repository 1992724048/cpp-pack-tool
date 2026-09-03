import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/models/pack_project.dart';
import 'package:cpp_nuget_pack/services/msbuild_generator.dart';

void main() {
  group('PackProject', () {
    test('JSON round-trip preserves all fields', () {
      final project = PackProject(
        packageId: 'V8.Native',
        version: '15.2.124.1',
        description: '预编译静态库',
        authors: 'ACME',
        owners: 'ACME',
        tags: 'v8, native',
        license: 'MIT',
        repository: 'https://example.com/repo',
        preBuildCommand: 'clean.bat',
        postBuildCommand: 'sign.ps1',
        sourceDirs: [
          SourceDir(
            path: r'C:\src\v8',
            mappings: [
              FileMapping(srcGlob: r'*.h', target: r'build\native\include\v8'),
            ],
          ),
        ],
        platforms: ['x64', 'arm64'],
        configurations: ['Debug', 'Release'],
        compileConfig: CompileConfig(
          languageStandard: 'stdcpplatest',
          clanguageStandard: 'c17',
          configDefines: {'Debug': 'V8_ENABLE_CHECKS'},
        ),
      );

      final restored = PackProject.fromJson(project.toJson());

      expect(restored.packageId, 'V8.Native');
      expect(restored.version, '15.2.124.1');
      expect(restored.description, '预编译静态库');
      expect(restored.authors, 'ACME');
      expect(restored.owners, 'ACME');
      expect(restored.tags, 'v8, native');
      expect(restored.license, 'MIT');
      expect(restored.repository, 'https://example.com/repo');
      expect(restored.preBuildCommand, 'clean.bat');
      expect(restored.postBuildCommand, 'sign.ps1');
      expect(restored.platforms, ['x64', 'arm64']);
      expect(restored.configurations, ['Debug', 'Release']);
      expect(restored.sourceDirs, hasLength(1));
      expect(restored.sourceDirs.first.path, r'C:\src\v8');
      expect(restored.sourceDirs.first.name, 'v8');
      expect(restored.sourceDirs.first.mappings.single.srcGlob, r'*.h');
      expect(
        restored.sourceDirs.first.mappings.single.target,
        r'build\native\include\v8',
      );
      expect(restored.compileConfig.configDefines['Debug'], 'V8_ENABLE_CHECKS');
      expect(restored.compileConfig.languageStandard, 'stdcpplatest');
      expect(restored.compileConfig.clanguageStandard, 'c17');
    });

    test('copy() produces an independent deep copy', () {
      final project = PackProject(
        packageId: 'Pkg.A',
        sourceDirs: [
          SourceDir(
            path: r'C:\src',
            mappings: [FileMapping(srcGlob: r'*.h', target: 'inc')],
          ),
        ],
      );

      final copy = project.copy();
      expect(copy.toJson(), project.toJson());
      expect(identical(copy.sourceDirs, project.sourceDirs), isFalse);
      expect(
        identical(copy.sourceDirs.first, project.sourceDirs.first),
        isFalse,
      );
      expect(identical(copy.compileConfig, project.compileConfig), isFalse);
    });

    test('copyWith updates only given fields', () {
      final project = PackProject(packageId: 'A.B', version: '1.0.0');
      final updated = project.copyWith(version: '2.0.0');

      expect(updated.packageId, 'A.B');
      expect(updated.version, '2.0.0');
      expect(updated.preBuildCommand, '');
      expect(updated.postBuildCommand, '');
    });

    test('copyWith syncs pre/post build commands', () {
      final project = PackProject(packageId: 'A.B', version: '1.0.0');
      final updated = project.copyWith(
        preBuildCommand: 'clean.bat',
        postBuildCommand: 'sign.ps1',
      );

      expect(updated.preBuildCommand, 'clean.bat');
      expect(updated.postBuildCommand, 'sign.ps1');
      expect(updated.packageId, 'A.B');
    });

    test('validate throws for empty or illegal package id', () {
      expect(
        () => PackProject(packageId: '').validate(),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PackProject(packageId: 'a b').validate(),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PackProject(packageId: '.start').validate(),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PackProject(packageId: 'end.').validate(),
        throwsA(isA<FormatException>()),
      );
    });

    test('isValidPackageId applies NuGet rules', () {
      expect(PackProject.isValidPackageId('V8.Native'), isTrue);
      expect(PackProject.isValidPackageId('Newtonsoft.Json'), isTrue);
      expect(PackProject.isValidPackageId('A_B-C'), isTrue);
      expect(PackProject.isValidPackageId(''), isFalse);
      expect(PackProject.isValidPackageId('a b'), isFalse);
      expect(PackProject.isValidPackageId('.lead'), isFalse);
      expect(PackProject.isValidPackageId('trail.'), isFalse);
      expect(PackProject.isValidPackageId('a..b'), isFalse);
    });

    test('dependencies JSON round-trip', () {
      final project = PackProject(
        packageId: 'A.B',
        dependencies: [
          PackDependency(id: 'V8.Native', version: '15.2.124.1'),
          PackDependency(id: 'Zlib', version: '[1.0,2.0)'),
        ],
      );
      final restored = PackProject.fromJson(project.toJson());
      expect(restored.dependencies, hasLength(2));
      expect(restored.dependencies[0].id, 'V8.Native');
      expect(restored.dependencies[0].version, '15.2.124.1');
      expect(restored.dependencies[1].id, 'Zlib');
      expect(restored.dependencies[1].version, '[1.0,2.0)');
    });

    test('fromJson 旧配置无 dependencies 键 → 空列表', () {
      final restored = PackProject.fromJson(<String, dynamic>{
        'packageId': 'X.Y',
      });
      expect(restored.dependencies, isEmpty);
    });
  });

  group('SourceDir', () {
    test('name is derived from path when not given', () {
      expect(SourceDir(path: r'C:\x\v8').name, 'v8');
      expect(SourceDir(path: r'C:\x\v8', name: 'custom').name, 'custom');
    });

    test('copyWith re-derives name when path changes', () {
      final dir = SourceDir(path: r'C:\a\old', name: 'old');
      final renamed = dir.copyWith(path: r'C:\a\new');
      expect(renamed.path, r'C:\a\new');
      expect(renamed.name, 'new');
    });
  });

  group('FileMapping', () {
    test('defaults platforms/configurations to empty (all)', () {
      final mapping = FileMapping(srcGlob: '*.h', target: 'inc');
      expect(mapping.platforms, isEmpty);
      expect(mapping.configurations, isEmpty);
    });

    test('fileKind 按扩展名分类（header/source/staticLibrary/dynamicLibrary/data/executable/other）', () {
      expect(FileMapping(srcGlob: 'a.h').fileKind, 'header');
      expect(FileMapping(srcGlob: 'a.hpp').fileKind, 'header');
      expect(FileMapping(srcGlob: 'a.hxx').fileKind, 'header');
      expect(FileMapping(srcGlob: 'a.inl').fileKind, 'header');
      expect(FileMapping(srcGlob: 'a.cpp').fileKind, 'source');
      expect(FileMapping(srcGlob: 'a.cc').fileKind, 'source');
      expect(FileMapping(srcGlob: 'a.c').fileKind, 'source');
      expect(FileMapping(srcGlob: 'a.lib').fileKind, 'staticLibrary');
      expect(FileMapping(srcGlob: 'a.a').fileKind, 'staticLibrary');
      expect(FileMapping(srcGlob: 'a.so').fileKind, 'dynamicLibrary');
      expect(FileMapping(srcGlob: 'a.dll').fileKind, 'dynamicLibrary');
      expect(FileMapping(srcGlob: 'a.exe').fileKind, 'executable');
      expect(FileMapping(srcGlob: 'a.dat').fileKind, 'data');
      expect(FileMapping(srcGlob: 'a.json').fileKind, 'data');
      expect(FileMapping(srcGlob: 'a.xml').fileKind, 'data');
      expect(FileMapping(srcGlob: 'a.cppm').fileKind, 'module');
      expect(FileMapping(srcGlob: 'a.ixx').fileKind, 'module');
      expect(FileMapping(srcGlob: 'a.mpp').fileKind, 'module');
      expect(FileMapping(srcGlob: 'a.unknown').fileKind, 'other');
      expect(FileMapping(srcGlob: '').fileKind, 'other');
    });

    test('isHeaderMapping 与 fileKind==header 等价', () {
      expect(FileMapping(srcGlob: 'a.h').isHeaderMapping, isTrue);
      expect(FileMapping(srcGlob: 'a.cpp').isHeaderMapping, isFalse);
      expect(FileMapping(srcGlob: 'a.dat').isHeaderMapping, isFalse);
    });

    test('isSourceMapping 覆盖 source 与 module', () {
      expect(FileMapping(srcGlob: 'a.cpp').isSourceMapping, isTrue);
      expect(FileMapping(srcGlob: 'a.cppm').isSourceMapping, isTrue);
      expect(FileMapping(srcGlob: 'a.ixx').isSourceMapping, isTrue);
      expect(FileMapping(srcGlob: 'a.mpp').isSourceMapping, isTrue);
      expect(FileMapping(srcGlob: 'a.h').isSourceMapping, isFalse);
      expect(FileMapping(srcGlob: 'a.lib').isSourceMapping, isFalse);
      expect(FileMapping(srcGlob: 'a.dat').isSourceMapping, isFalse);
    });

    test('pre/post build command JSON round-trip', () {
      final mapping = FileMapping(
        srcGlob: r'bin\x64\Debug\inject.exe',
        target: r'build\native\tools\Debug',
        preBuildCommand: r'$(OutDir)\inject.exe --setup',
        postBuildCommand: 'copy /y x y',
      );
      final restored = FileMapping.fromJson(mapping.toJson());
      expect(restored.preBuildCommand, r'$(OutDir)\inject.exe --setup');
      expect(restored.postBuildCommand, 'copy /y x y');
      // copyWith 未提供命令字段时保持不变。
      expect(
        restored.copyWith(target: 't').preBuildCommand,
        r'$(OutDir)\inject.exe --setup',
      );
    });
  });

  group('CompileConfig', () {
    test('fromJson 容忍旧 JSON 中的 dataFilesToCopy/injectedSources 键', () {
      final json = <String, dynamic>{
        'languageStandard': 'stdcpp17',
        'dataFilesToCopy': ['icudtl.dat'],
        'injectedSources': [r'src\v8wrap\win32.cpp'],
      };
      final config = CompileConfig.fromJson(json);
      expect(config.languageStandard, 'stdcpp17');
      // 旧字段已迁移至文件映射，加载时直接忽略，不报错。
    });

    test('preBuildCommands/postBuildCommands 默认空，JSON 往返一致', () {
      final config = CompileConfig(
        preBuildCommands: ['echo pre'],
        postBuildCommands: ['copy /y a b'],
      );
      expect(config.preBuildCommands, ['echo pre']);
      expect(config.postBuildCommands, ['copy /y a b']);

      final restored = CompileConfig.fromJson(config.toJson());
      expect(restored.preBuildCommands, ['echo pre']);
      expect(restored.postBuildCommands, ['copy /y a b']);

      // copyWith 未提供时保持不变。
      expect(restored.copyWith(languageStandard: 'stdcpp20').preBuildCommands, [
        'echo pre',
      ]);
    });

    test('fromJson 旧 JSON 无命令键 → 空列表', () {
      final config = CompileConfig.fromJson(<String, dynamic>{
        'languageStandard': 'stdcpp20',
      });
      expect(config.preBuildCommands, isEmpty);
      expect(config.postBuildCommands, isEmpty);
    });
  });

  group('MSBuild identifier sanitizer', () {
    test('replaces non-word characters and normalizes', () {
      expect(sanitizeMsBuildIdentifier('V8.Native'), 'V8_Native');
      expect(sanitizeMsBuildIdentifier('foo-bar.baz'), 'foo_bar_baz');
      expect(sanitizeMsBuildIdentifier('icudtl.dat'), 'icudtl_dat');
      expect(sanitizeMsBuildIdentifier('A/B'), 'A_B');
    });

    test('handles empty input and leading digit', () {
      expect(sanitizeMsBuildIdentifier(''), 'Pkg');
      expect(sanitizeMsBuildIdentifier('123abc'), '_123abc');
    });
  });
}
