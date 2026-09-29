import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
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
}

PackageEntry _entry(String packagePath) => PackageEntry(
  packagePath: packagePath,
  source: PackageGeneratedSource(content: packagePath),
);
