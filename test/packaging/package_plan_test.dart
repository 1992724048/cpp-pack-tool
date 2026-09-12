import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
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

  test('含脚本的 NuGet 计划无重复包内路径', () async {
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      sourcePath: r'C:\libs\demo',
    )
      ..files.add(FileModel(name: 'foo.h', path: 'include/foo.h', size: 12))
      ..scripts.add(_validScript());

    final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(pack);

    expect(
      plan.entries.map((PackageEntry entry) => entry.packagePath),
      contains('build/native/files/scripts/script_1.ps1'),
    );
    expect(
      plan.entries
          .map((PackageEntry entry) => entry.packagePath.toLowerCase())
          .toSet()
          .length,
      plan.entries.length,
    );
    expect(duplicatePackagePaths(plan), isEmpty);
  });

  test('脚本生成路径与源目录文件重名时命中重复', () async {
    final PackModel pack = PackModel(
      name: 'demo',
      version: '1.0.0',
      author: 'tester',
      sourcePath: r'C:\libs\demo',
    )
      ..files.add(
        FileModel(name: 'script_1.ps1', path: 'scripts/script_1.ps1', size: 5),
      )
      ..scripts.add(_validScript());

    final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(pack);

    expect(
      duplicatePackagePaths(plan),
      <String>['build/native/files/scripts/script_1.ps1'],
    );
  });
}

PackageEntry _entry(String packagePath) => PackageEntry(
  packagePath: packagePath,
  source: PackageGeneratedSource(content: packagePath),
);

ScriptProjectModel _validScript() {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '生成版本头',
    trigger: ScriptTrigger.pre,
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
