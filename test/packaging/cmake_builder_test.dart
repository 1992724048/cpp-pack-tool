import 'dart:convert';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/packaging/cmake_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const CMakePackageBuilder _builder = CMakePackageBuilder();

void main() {
  group('基本信息', () {
    test('id 与显示名', () {
      expect(_builder.id, 'cmake');
      expect(_builder.displayName, 'CMake');
    });

    test('注册表包含 NuGet 与 CMake 构建器', () {
      expect(
        PackageBuilderRegistry.all
            .map((PackageBuilder builder) => builder.id)
            .toList(),
        <String>['nuget', 'cmake'],
      );
    });
  });

  group('文件映射', () {
    test('头文件与模块映射到 include/源目录名 并剥离 include 前缀', () async {
      final PackModel pack = _pack(sourcePath: r'D:\libs\mylib')
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
          FileModel(name: 'bar.hpp', path: 'Include/detail/bar.hpp', size: 20),
          FileModel(name: 'mod.ixx', path: 'src/mod.ixx', size: 30),
          FileModel(name: 'plain.h', path: 'plain.h', size: 40),
        ];

      final PackagePlan plan = await _builder.buildPlan(pack);

      expect(_packagePathOf(plan, 'include/foo.h'), 'include/mylib/foo.h');
      expect(
        _packagePathOf(plan, 'Include/detail/bar.hpp'),
        'include/mylib/detail/bar.hpp',
      );
      expect(_packagePathOf(plan, 'src/mod.ixx'), 'include/mylib/src/mod.ixx');
      expect(_packagePathOf(plan, 'plain.h'), 'include/mylib/plain.h');
    });

    test('源目录缺失或 basename 为空时命名空间回退为包名', () async {
      final PackModel noSource = _pack(name: 'pkg')
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        ];
      final PackModel trailingSeparator =
          _pack(name: 'pkg', sourcePath: r'D:\libs\demo\')
            ..files = <FileModel>[
              FileModel(name: 'bar.h', path: 'include/bar.h', size: 10),
            ];

      expect(
        _packagePathOf(await _builder.buildPlan(noSource), 'include/foo.h'),
        'include/pkg/foo.h',
      );
      expect(
        _packagePathOf(
          await _builder.buildPlan(trailingSeparator),
          'include/bar.h',
        ),
        'include/pkg/bar.h',
      );
    });

    test('库文件映射到 lib 并剥离 lib/bin 前缀保留子目录', () async {
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
        'lib/x64/Release/foo.lib',
      );
      expect(_packagePathOf(plan, 'Lib/foo/bar.lib'), 'lib/foo/bar.lib');
      expect(
        _packagePathOf(plan, 'bin/x64/Debug/baz.dll'),
        'lib/x64/Debug/baz.dll',
      );
      expect(_packagePathOf(plan, 'Bin/qux.pdb'), 'lib/qux.pdb');
      expect(_packagePathOf(plan, 'plain.lib'), 'lib/plain.lib');
    });

    test('其他文件映射到 files 且保留相对路径', () async {
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

      expect(_packagePathOf(plan, 'src/main.cpp'), 'files/src/main.cpp');
      expect(_packagePathOf(plan, 'README.md'), 'files/README.md');
      expect(_packagePathOf(plan, 'assets/logo.png'), 'files/assets/logo.png');
      expect(_packagePathOf(plan, 'bin/app.exe'), 'files/bin/app.exe');
      expect(_packagePathOf(plan, 'lib/util.cpp'), 'files/lib/util.cpp');
      expect(
        _packagePathOf(plan, 'scripts/build.bat'),
        'files/scripts/build.bat',
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
        'files/scripts/build.py',
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

  group('生成文件', () {
    test('空文件列表生成 Config、ConfigVersion 与 Targets', () async {
      final PackagePlan plan = await _builder.buildPlan(
        _pack(version: '1.2.3+7'),
      );

      expect(plan.fileCount, 3);
      expect(
        plan.entries.map((PackageEntry entry) => entry.packagePath),
        <String>[
          'lib/cmake/demo/demoConfig.cmake',
          'lib/cmake/demo/demoConfigVersion.cmake',
          'lib/cmake/demo/demoTargets.cmake',
        ],
      );
    });

    test('版本非数字或段数超出时省略 ConfigVersion', () async {
      for (final String version in <String>['1', '1.2-beta', '1.2.3.4.5']) {
        final PackagePlan plan = await _builder.buildPlan(
          _pack(version: version),
        );

        expect(plan.fileCount, 2, reason: '版本 $version 不应生成 ConfigVersion');
      }
    });

    test('四位版本号同样生成 ConfigVersion', () async {
      final PackagePlan plan = await _builder.buildPlan(
        _pack(version: '1.2.3.4'),
      );

      expect(plan.fileCount, 3);
      expect(
        _generated(plan, 'lib/cmake/demo/demoConfigVersion.cmake'),
        contains('set(PACKAGE_VERSION "1.2.3.4")'),
      );
    });

    test('主版本号规范化前导零', () async {
      final String version = _generated(
        await _builder.buildPlan(_pack(version: '01.2.3')),
        'lib/cmake/demo/demoConfigVersion.cmake',
      );

      expect(version, contains('set(PACKAGE_VERSION_MAJOR "1")'));
    });

    test('Config 自带 check_required_components 宏并加载 Targets', () async {
      final String config = _generated(
        await _builder.buildPlan(_pack()),
        'lib/cmake/demo/demoConfig.cmake',
      );

      expect(
        config,
        _joinLines(const <String>[
          'macro(check_required_components _NAME)',
          r'  foreach(comp ${${_NAME}_FIND_COMPONENTS})',
          r'    if(NOT ${_NAME}_${comp}_FOUND)',
          r'      if(${_NAME}_FIND_REQUIRED_${comp})',
          r'        set(${_NAME}_FOUND FALSE)',
          '      endif()',
          '    endif()',
          '  endforeach()',
          'endmacro()',
          '',
          'if(NOT TARGET demo::demo)',
          r'  include("${CMAKE_CURRENT_LIST_DIR}/demoTargets.cmake")',
          'endif()',
          '',
          'check_required_components(demo)',
        ]),
      );
    });

    test('ConfigVersion 记录数字版本与 SameMajorVersion 兼容规则', () async {
      final String version = _generated(
        await _builder.buildPlan(_pack(version: '1.2.3+7')),
        'lib/cmake/demo/demoConfigVersion.cmake',
      );

      expect(
        version,
        _joinLines(const <String>[
          'set(PACKAGE_VERSION "1.2.3")',
          'set(PACKAGE_VERSION_MAJOR "1")',
          '',
          'if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)',
          '  set(PACKAGE_VERSION_COMPATIBLE FALSE)',
          'else()',
          '  if(PACKAGE_FIND_VERSION_MAJOR STREQUAL PACKAGE_VERSION_MAJOR)',
          '    set(PACKAGE_VERSION_COMPATIBLE TRUE)',
          '  else()',
          '    set(PACKAGE_VERSION_COMPATIBLE FALSE)',
          '  endif()',
          '  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)',
          '    set(PACKAGE_VERSION_EXACT TRUE)',
          '  endif()',
          'endif()',
        ]),
      );
    });

    test('Targets 上溯四级导入前缀并按 Debug/非 Debug 分组链接库', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.lib', path: 'lib/x64/Release/foo.lib', size: 10),
          FileModel(name: 'bar.lib', path: 'lib/x64/Debug/bar.lib', size: 20),
          FileModel(name: 'baz.lib', path: 'lib/baz.lib', size: 30),
        ];

      final String targets = _generated(
        await _builder.buildPlan(pack),
        'lib/cmake/demo/demoTargets.cmake',
      );

      expect(
        targets,
        _joinLines(const <String>[
          r'get_filename_component(_IMPORT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)',
          r'get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)',
          r'get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)',
          r'get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)',
          r'if(_IMPORT_PREFIX STREQUAL "/")',
          r'  set(_IMPORT_PREFIX "")',
          'endif()',
          '',
          'add_library(demo::demo INTERFACE IMPORTED)',
          '',
          '# DLL 需消费方自行拷贝（INTERFACE 目标不支持自动运行时收集）',
          'set_target_properties(demo::demo PROPERTIES',
          r'  INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"',
          r'  INTERFACE_LINK_LIBRARIES "$<$<CONFIG:Debug>:${_IMPORT_PREFIX}/lib/x64/Debug/bar.lib>$<$<NOT:$<CONFIG:Debug>>:${_IMPORT_PREFIX}/lib/baz.lib;${_IMPORT_PREFIX}/lib/x64/Release/foo.lib>"',
          ')',
          '',
          'set(_IMPORT_PREFIX)',
        ]),
      );
      expect(r'get_filename_component'.allMatches(targets).length, 4);
    });

    test('仅一组库时无条件链接且不生成条件表达式', () async {
      final PackModel releaseOnly = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.lib', path: 'lib/Release/foo.lib', size: 10),
        ];
      final PackModel debugOnly = _pack()
        ..files = <FileModel>[
          FileModel(name: 'bar.lib', path: 'lib/Debug/bar.lib', size: 10),
        ];

      final String releaseTargets = _generated(
        await _builder.buildPlan(releaseOnly),
        'lib/cmake/demo/demoTargets.cmake',
      );
      expect(
        releaseTargets,
        contains(
          r'  INTERFACE_LINK_LIBRARIES "${_IMPORT_PREFIX}/lib/Release/foo.lib"',
        ),
      );
      expect(releaseTargets, isNot(contains(r'$<')));

      final String debugTargets = _generated(
        await _builder.buildPlan(debugOnly),
        'lib/cmake/demo/demoTargets.cmake',
      );
      expect(
        debugTargets,
        contains(
          r'  INTERFACE_LINK_LIBRARIES "${_IMPORT_PREFIX}/lib/Debug/bar.lib"',
        ),
      );
      expect(debugTargets, isNot(contains(r'$<')));
    });

    test('无 .lib 时不设置链接库属性', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
          FileModel(name: 'foo.dll', path: 'bin/foo.dll', size: 20),
          FileModel(name: 'foo.pdb', path: 'lib/foo.pdb', size: 30),
        ];

      final String targets = _generated(
        await _builder.buildPlan(pack),
        'lib/cmake/demo/demoTargets.cmake',
      );

      expect(targets, isNot(contains('INTERFACE_LINK_LIBRARIES')));
      expect(targets, contains('INTERFACE_INCLUDE_DIRECTORIES'));
    });

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
        'include/demo/a.h',
        'include/demo/B.h',
        'lib/cmake/demo/demoConfig.cmake',
        'lib/cmake/demo/demoConfigVersion.cmake',
        'lib/cmake/demo/demoTargets.cmake',
        'lib/zeta.lib',
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

      expect(plan.fileCount, 4);
      final int generatedBytes = <String>[
        _generated(plan, 'lib/cmake/demo/demoConfig.cmake'),
        _generated(plan, 'lib/cmake/demo/demoConfigVersion.cmake'),
        _generated(plan, 'lib/cmake/demo/demoTargets.cmake'),
      ].fold<int>(0, (int sum, String text) => sum + utf8.encode(text).length);
      expect(plan.totalSize, 100 + generatedBytes);
    });

    test('含脚本包不产出脚本条目与脚本 Target 片段', () async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        ]
        ..scripts = <ScriptProjectModel>[_validScript()];

      final PackagePlan plan = await _builder.buildPlan(pack);
      final List<String> paths = plan.entries
          .map((PackageEntry entry) => entry.packagePath)
          .toList();

      expect(
        paths.where((String path) => path.toLowerCase().endsWith('.ps1')),
        isEmpty,
      );
      expect(paths.where((String path) => path.contains('scripts/')), isEmpty);
      final String targets = _generated(
        plan,
        'lib/cmake/demo/demoTargets.cmake',
      );
      expect(targets, isNot(contains('CnpScripts_')));
      expect(targets, isNot(contains('<Exec')));
    });
  });
}

PackModel _pack({
  String name = 'demo',
  String version = '1.0.0',
  String? sourcePath,
}) {
  return PackModel(
    name: name,
    version: version,
    author: 'tester',
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

String _generated(PackagePlan plan, String packagePath) {
  return (plan.entries
              .firstWhere(
                (PackageEntry entry) => entry.packagePath == packagePath,
              )
              .source
          as PackageGeneratedSource)
      .content;
}

String _joinLines(List<String> lines) => '${lines.join('\n')}\n';

ScriptProjectModel _validScript() {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '脚本 1',
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
