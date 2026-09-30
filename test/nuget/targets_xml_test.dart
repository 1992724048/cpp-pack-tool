import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/pack/model/cmd_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/nuget/nuget_builder.dart';
import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// ASCII 检查脚本：把文件文本交给 PowerShell 的 `[xml]` 解析器做整文档良构性
/// 解析，失败时打印异常消息并以非零退出码结束。
const String _xmlParseCheckScript = r'''param([string]$Path)
$text = [System.IO.File]::ReadAllText($Path)
try {
    [void][xml]$text
    exit 0
} catch {
    Write-Output $_.Exception.Message
    exit 1
}
''';

/// 故意不闭合 `Project` 标签的畸形 XML，供检查器自检。
const String _brokenTargets = '''<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Target Name="DeployPkgRuntimeBinaries">
</Project>
''';

final Object? _nonWindowsSkip = Platform.isWindows
    ? null
    : '仅 Windows 平台执行（依赖 powershell.exe 的 [xml] 解析）';

PackModel _pack(String name, List<FileModel> files) {
  final PackModel pack = PackModel(
    name: name,
    version: '1.0.0',
    author: 'tester',
  );
  pack.files.addAll(files);
  pack.commands = <CmdModel>[
    const CmdModel(
      command: r'''echo 'a & b' <c> > "d"''',
      type: CmdType.preBuild,
    ),
  ];
  return pack;
}

String _targetsContent(PackagePlan plan, String packName) {
  return (plan.entries
              .firstWhere(
                (PackageEntry entry) =>
                    entry.packagePath == 'build/native/$packName.targets',
              )
              .source
          as PackageGeneratedSource)
      .content;
}

Future<String> _targetsOf(PackModel pack) async {
  return _targetsContent(await const NuGetPackageBuilder().buildPlan(pack), pack.name);
}

PackModel _packNamed(String name) => _pack(name, <FileModel>[
  FileModel(name: '$name.dll', path: 'lib/$name.dll', size: 64),
]);

PackModel _packWithFiles(List<FileModel> files, {required String name}) => _pack(name, files);

String _deployTargetName(String targets) =>
    RegExp(r'<Target Name="(DeployPkgRuntimeBinaries[^"]*)"').firstMatch(targets)!.group(1)!;

/// 切出许可证部署目标块（不含其闭合标签）。让 `<Copy>` 计数只覆盖该目标内的副本，
/// 不被夹具里的 .dll/.pdb 触发的运行库部署项（同样发 `<Copy>`）干扰。
String _licenseTargetBlock(String targets) {
  final int start = targets.indexOf(r'<Target Name="DeployPkgLicenses_');
  expect(start, greaterThanOrEqualTo(0), reason: '未发射许可证部署目标');
  final int end = targets.indexOf('  </Target>', start);
  expect(end, greaterThan(start), reason: '许可证部署目标块未正常闭合');
  return targets.substring(start, end);
}

void main() {
  test('三份 .targets 均通过 [xml] 整文档解析（含对抗性包名）', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'cnp_targets_xml_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final String checkPath = joinPath(tempDir.path, 'check.ps1');
    File(checkPath).writeAsStringSync(_xmlParseCheckScript, encoding: ascii);

    final List<({String key, PackModel pack, bool hasRuntimeBinaries})>
    fixtures = <({String key, PackModel pack, bool hasRuntimeBinaries})>[
      (
        key: 'runtime_binaries',
        pack: _pack('demo', <FileModel>[
          FileModel(name: 'demo.dll', path: 'lib/demo.dll', size: 64),
        ]),
        hasRuntimeBinaries: true,
      ),
      (
        key: 'no_runtime_binaries',
        pack: _pack('plain', <FileModel>[
          FileModel(name: 'plain.h', path: 'include/plain.h', size: 32),
        ]),
        hasRuntimeBinaries: false,
      ),
      (
        key: 'with_license',
        pack: _pack('&licensed', <FileModel>[
          FileModel(name: 'LICENSE', path: 'LICENSE', size: 48),
        ]),
        hasRuntimeBinaries: false,
      ),
    ];

    for (final fixture in fixtures) {
      final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(
        fixture.pack,
      );
      final String content = _targetsContent(plan, fixture.pack.name);

      expect(
        plan.entries.where(
          (PackageEntry entry) => entry.packagePath.endsWith('.ps1'),
        ),
        isEmpty,
        reason: '夹具「${fixture.key}」不应产出任何脚本条目',
      );
      expect(
        content,
        contains(
          r'<Exec Command="echo &apos;a &amp; b&apos; &lt;c&gt; &gt; &quot;d&quot;"',
        ),
        reason: '夹具「${fixture.key}」的命令 Exec 应转义 XML 特殊字符',
      );
      if (fixture.hasRuntimeBinaries) {
        expect(content, contains('<Target Name="DeployPkgRuntimeBinaries_demo_'));
      } else {
        expect(content, isNot(contains('DeployPkgRuntimeBinaries')));
      }
      if (fixture.key == 'with_license') {
        expect(content, contains('<Target Name="DeployPkgLicenses__licensed_'));
        expect(content, contains(r'<Copy '));
        expect(
          content,
          contains(r'''Condition="Exists('$(MSBuildThisFileDirectory)files\LICENSE')"'''),
        );
        expect(
          content,
          contains(
            r'DestinationFiles="$(OutDir)LICENSES\&amp;licensed_LICENSE"',
          ),
        );
      } else {
        expect(content, isNot(contains('DeployPkgLicenses')));
      }

      final String targetsPath = joinPath(tempDir.path, '${fixture.key}.targets');
      File(targetsPath).writeAsStringSync(content, encoding: utf8);

      final ProcessResult check = Process.runSync('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        checkPath,
        '-Path',
        targetsPath,
      ]);
      expect(
        check.exitCode,
        0,
        reason:
            '夹具「${fixture.key}」.targets 整文档 XML 解析失败：'
            'stdout=${check.stdout}\nstderr=${check.stderr}',
      );
    }
  }, skip: _nonWindowsSkip);

  test('检查器能检出故意畸形的 .targets（自检）', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'cnp_targets_xml_broken_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final String checkPath = joinPath(tempDir.path, 'check.ps1');
    File(checkPath).writeAsStringSync(_xmlParseCheckScript, encoding: ascii);
    final String brokenPath = joinPath(tempDir.path, 'broken.targets');
    File(brokenPath).writeAsStringSync(_brokenTargets, encoding: ascii);

    final ProcessResult check = Process.runSync('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      checkPath,
      '-Path',
      brokenPath,
    ]);
    expect(check.exitCode, isNot(0), reason: '检查脚本应报告故意畸形 XML，实际退出码为 0');
    expect(
      check.stdout.toString().trim(),
      isNotEmpty,
      reason: '检查脚本应打印解析错误消息',
    );
  }, skip: _nonWindowsSkip);

  test('两个包的部署目标名不相等', () async {
    final String first = await _targetsOf(_packNamed('Alpha'));
    final String second = await _targetsOf(_packNamed('Beta'));
    final RegExp pattern = RegExp(r'<Target Name="(DeployPkgRuntimeBinaries_[A-Za-z0-9_]+)"');
    expect(pattern.firstMatch(first)!.group(1), isNot(pattern.firstMatch(second)!.group(1)));
  });

  test('同 cleanId 不同原始名因 hash 不同仍不相等', () async {
    // 用同一 cleanId、不同原始名构造：'A.B' 与 'A-B' → cleanId 同为 A_B
    final String first = await _targetsOf(_packNamed('A.B'));
    final String second = await _targetsOf(_packNamed('A-B'));
    expect(_deployTargetName(first), isNot(_deployTargetName(second)));
  });

  test('asm 的 ObjectFileName 含包标识', () async {
    final String targets = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'boot.asm', path: 'src/boot.asm', size: 1),
    ], name: 'A.B'));
    expect(targets, contains(r'asm_A_B_'));
    expect(targets, isNot(contains(r'$(IntDir)asm_files_src_boot.asm.obj')));
  });

  test('发射 13 条固定搜索根（include 1 条 + files 12 个子目录）', () async {
    final String targets = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'a.c', path: 'src/a.c', size: 1),
    ], name: 'demo'));

    expect(
      targets,
      contains(r'<AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)include;'),
    );
    for (final String subdirectory in filesSubdirectories) {
      expect(
        targets,
        contains('\$(MSBuildThisFileDirectory)files\\$subdirectory;'),
        reason: '缺少 files\\$subdirectory 搜索根',
      );
    }
    expect(
      targets,
      isNot(
        contains(r'$(MSBuildThisFileDirectory)files;%(AdditionalIncludeDirectories)'),
      ),
      reason: 'files/ 根只承载许可证，不再作为搜索根',
    );
  });

  test('files/source 下每个含源文件的更深目录各发一条动态搜索根', () async {
    final String targets = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'a.c', path: 'src/a.c', size: 1),
      FileModel(name: 'b.c', path: 'third_party/foo/b.c', size: 1),
      FileModel(name: 'c.h', path: 'include/demo/c.h', size: 1),
    ], name: 'demo'));

    expect(
      targets,
      contains(r'$(MSBuildThisFileDirectory)files\source\src;'),
    );
    expect(
      targets,
      contains(r'$(MSBuildThisFileDirectory)files\source\third_party\foo;'),
    );
    expect(
      targets,
      isNot(contains(r'$(MSBuildThisFileDirectory)files\source\include')),
      reason: r'头文件落 include/，不该在 files\source 下多发一条',
    );
    expect(
      r'$(MSBuildThisFileDirectory)files\source;'.allMatches(targets).length,
      1,
      reason: r'files\source 固定根只发一次，src/a.c 不应让它重复出现',
    );
  });

  test('LICENSE 与 NOTICE 同时存在时两个都部署', () async {
    final String targets = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'LICENSE', path: 'LICENSE', size: 8),
      FileModel(name: 'NOTICE', path: 'NOTICE', size: 8),
    ], name: 'demo'));

    expect(targets, contains(r'$(OutDir)LICENSES\demo_LICENSE'));
    expect(targets, contains(r'$(OutDir)LICENSES\demo_NOTICE'));
    expect(RegExp(r'<Target Name="DeployPkgLicenses_').allMatches(targets), hasLength(1));
    expect(RegExp(r'<Copy ').allMatches(_licenseTargetBlock(targets)), hasLength(2));
  });

  test('部署目录是大写 LICENSES', () async {
    final String targets = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'LICENSE', path: 'LICENSE', size: 8),
    ], name: 'demo'));

    expect(targets, contains(r'$(OutDir)LICENSES'));
    expect(targets, isNot(contains(r'$(OutDir)licenses')));
  });

  test('两个包的许可证目标文件名互不覆盖', () async {
    final String first = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'NOTICE', path: 'NOTICE', size: 8),
    ], name: 'Alpha'));
    final String second = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'NOTICE', path: 'NOTICE', size: 8),
    ], name: 'Beta'));

    expect(first, contains(r'$(OutDir)LICENSES\Alpha_NOTICE'));
    expect(second, contains(r'$(OutDir)LICENSES\Beta_NOTICE'));
  });

  test('无许可文件时不发射部署目标', () async {
    final String targets = await _targetsOf(_packWithFiles(<FileModel>[
      FileModel(name: 'a.c', path: 'src/a.c', size: 1),
    ], name: 'demo'));

    expect(targets, isNot(contains('DeployPkgLicenses_')));
  });
}
