import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/nuget/nuget_builder.dart';
import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('duplicatePackagePaths', () {
    test('无重复路径时返回空列表', () {
      final PackagePlan plan = PackagePlan(
        entries: <PackageEntry>[
          _entry('build/native/include/demo/foo.h'),
          _entry('build/native/files/readme.md'),
          _entry('demo.nuspec'),
        ],
      );

      expect(duplicatePackagePaths(plan), isEmpty);
    });

    test('大小写不敏感命中，返回首次出现的原样路径且不重复报告', () {
      final PackagePlan plan = PackagePlan(
        entries: <PackageEntry>[
          _entry('build/native/files/foo.h'),
          _entry('Build/Native/Files/FOO.h'),
          _entry('build/native/files/readme.md'),
          _entry('build/native/files/readme.md'),
        ],
      );

      expect(duplicatePackagePaths(plan), <String>[
        'Build/Native/Files/FOO.h',
        'build/native/files/readme.md',
      ]);
    });
  });

  test('NuGet 计划包内路径无重复', () async {
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      sourcePath: r'C:\libs\demo',
    )..files.add(FileModel(name: 'foo.h', path: 'include/foo.h', size: 12));

    final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(pack);

    expect(
      plan.entries
          .map((PackageEntry entry) => entry.packagePath.toLowerCase())
          .toSet()
          .length,
      plan.entries.length,
    );
    expect(duplicatePackagePaths(plan), isEmpty);
  });

  test('两个源文件映射到同一包内路径时命中重复', () async {
    // 命名空间为源目录名 demo：include/demo/foo.h 命中前缀被保留，
    // include/foo.h 则被补上命名空间，两者落到同一路径。
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      sourcePath: r'C:\libs\demo',
    )
      ..files.addAll(<FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 5),
        FileModel(name: 'foo.h', path: 'include/demo/foo.h', size: 5),
      ]);

    final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(pack);

    expect(
      duplicatePackagePaths(plan),
      <String>['build/native/include/demo/foo.h'],
    );
  });

  group('buildNativePayloadPath', () {
    test('各 FileType 的包内落点', () {
      const String ns = 'demo';

      expect(
        buildNativePayloadPath('include/demo/foo.h', FileType.header, ns),
        'build/native/include/$ns/foo.h',
      );
      expect(
        buildNativePayloadPath('src/foo.c', FileType.source, ns),
        'build/native/files/source/src/foo.c',
      );
      expect(
        buildNativePayloadPath('lib/x64/foo.lib', FileType.lib, ns),
        'build/native/files/library/x64/foo.lib',
      );
      expect(
        buildNativePayloadPath('bin/foo.dll', FileType.dll, ns),
        'build/native/files/library/foo.dll',
      );
      expect(
        buildNativePayloadPath('bin/foo.pdb', FileType.pdb, ns),
        'build/native/files/library/foo.pdb',
      );
      expect(
        buildNativePayloadPath('src/a.asm', FileType.asm, ns),
        'build/native/files/assembly/src/a.asm',
      );
      expect(
        buildNativePayloadPath('res/app.rc', FileType.resource, ns),
        'build/native/files/resource/res/app.rc',
      );
      expect(
        buildNativePayloadPath('res/app.ico', FileType.resource, ns),
        'build/native/files/resource/res/app.ico',
      );
      expect(
        buildNativePayloadPath('tools/x.bat', FileType.script, ns),
        'build/native/files/script/tools/x.bat',
      );
      expect(
        buildNativePayloadPath('f/x.f90', FileType.fortran, ns),
        'build/native/files/fortran/f/x.f90',
      );
      expect(
        buildNativePayloadPath('l/x.bc', FileType.llvm, ns),
        'build/native/files/llvm/l/x.bc',
      );
      expect(
        buildNativePayloadPath('p/x.py', FileType.python, ns),
        'build/native/files/python/p/x.py',
      );
      expect(
        buildNativePayloadPath('d/x.db', FileType.database, ns),
        'build/native/files/data/d/x.db',
      );
      expect(
        buildNativePayloadPath('b/x.exe', FileType.executable, ns),
        'build/native/files/executable/b/x.exe',
      );
      expect(
        buildNativePayloadPath('r/x.txt', FileType.other, ns),
        'build/native/files/other/r/x.txt',
      );
      expect(
        buildNativePayloadPath('Makefile', FileType.other, ns),
        'build/native/files/other/Makefile',
      );
    });

    test('模块与头文件同落 include，库仅剥 lib/bin 首段', () {
      const String ns = 'demo';

      expect(
        buildNativePayloadPath('src/mod.cppm', FileType.module, ns),
        'build/native/include/$ns/src/mod.cppm',
      );
      expect(
        buildNativePayloadPath('release/z.lib', FileType.lib, ns),
        'build/native/files/library/release/z.lib',
      );
      expect(
        buildNativePayloadPath('libs/z.lib', FileType.lib, ns),
        'build/native/files/library/libs/z.lib',
      );
    });

    test('根级许可证不进子目录，带路径分隔符的按 other 走', () {
      expect(
        buildNativePayloadPath('LICENSE', FileType.other, 'demo'),
        'build/native/files/LICENSE',
      );
      expect(
        buildNativePayloadPath('NOTICE', FileType.other, 'demo'),
        'build/native/files/NOTICE',
      );
      expect(
        buildNativePayloadPath('sub/LICENSE', FileType.other, 'demo'),
        'build/native/files/other/sub/LICENSE',
      );
    });

    // 上面的落点断言都显式传入 FileType，故对「扩展名映射到哪种 FileType」完全盲：
    // 把 .ico 改判为 other 后本组仍全绿。打包路径上的 FileType 来自 FileModel，
    // 这里把那条映射钉住，.ico 落 resource 子目录才有单测层的依据。
    test('资源类扩展名 .rc / .ico 映射为 resource', () {
      expect(FileModel(name: 'app.rc', path: 'res/app.rc').type, FileType.resource);
      expect(FileModel(name: 'app.ico', path: 'res/app.ico').type, FileType.resource);
    });
  });

  group('stripBuildNative', () {
    test('剥掉 build/native/ 前缀，不匹配返回 null', () {
      expect(stripBuildNative('build/native/files/source/src/a.c'), 'files/source/src/a.c');
      expect(stripBuildNative('build/native/other.targets'), 'other.targets');
      expect(stripBuildNative('demo.nuspec'), isNull);
      expect(stripBuildNative('build/native'), isNull);
    });
  });

  group('payloadSearchRoots', () {
    test('include + files 下 11 个子目录；源文件直接在 files/source 下时不多发动态根', () {
      expect(payloadSearchRoots(<String>['files/source/a.c']), <String>[
        'include',
        for (final String subdirectory in filesSubdirectories) 'files/$subdirectory',
      ]);
    });

    test('files/source 之下每个含源文件的更深目录各一条，确定性排序且去重', () {
      final List<String> roots = payloadSearchRoots(<String>[
        'files/source/third_party/foo/b.c',
        'files/source/src/b.cpp',
        'files/source/src/a.c',
        'files/source/src/a.c',
        'files/other/x.txt',
        'include/demo/foo.h',
      ]);
      // 固定部分：include + files 下 11 个子目录。
      final int fixedRootCount = filesSubdirectories.length + 1;

      expect(roots, hasLength(fixedRootCount + 2));
      expect(roots.take(fixedRootCount), <String>[
        'include',
        for (final String subdirectory in filesSubdirectories) 'files/$subdirectory',
      ]);
      expect(roots.sublist(fixedRootCount), <String>[
        'files/source/src',
        'files/source/third_party/foo',
      ]);
    });

    test('files/ 根目录不作为搜索根下发', () {
      expect(
        payloadSearchRoots(<String>['files/LICENSE']).where((String root) => root == 'files'),
        isEmpty,
        reason: 'files/ 根只承载许可证',
      );
    });
  });

  test('filesSubdirectories 覆盖 filesSubdirectoryOf 的全部取值', () {
    for (final FileType type in FileType.values) {
      final String? subdirectory = filesSubdirectoryOf(type);
      if (subdirectory == null) {
        expect(type, anyOf(FileType.header, FileType.module));
        continue;
      }
      expect(
        filesSubdirectories,
        contains(subdirectory),
        reason: '${type.name} 的子目录须在 filesSubdirectories 中',
      );
    }
    expect(filesSubdirectories, hasLength(11));
  });
}

PackageEntry _entry(String packagePath) => PackageEntry(
  packagePath: packagePath,
  source: PackageGeneratedSource(content: packagePath),
);
