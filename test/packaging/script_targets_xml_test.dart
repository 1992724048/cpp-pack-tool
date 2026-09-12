import 'dart:convert';
import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/format.dart';
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
  <Target Name="CnpScripts_demo_deadbeef_Pre">
</Project>
''';

final Object? _nonWindowsSkip = Platform.isWindows
    ? null
    : '仅 Windows 平台执行（依赖 powershell.exe 的 [xml] 解析）';

ScriptProjectModel _script(
  String id,
  String name, {
  required ScriptTrigger trigger,
}) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: id,
    name: name,
    trigger: trigger,
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

PackModel _pack(String name, List<FileModel> files) {
  final PackModel pack = PackModel(
    name: name,
    version: '1.0.0',
    author: 'tester',
  );
  pack.files.addAll(files);
  pack.scripts = <ScriptProjectModel>[
    _script('script_1', 'A---B', trigger: ScriptTrigger.pre),
    _script('script_2', 'R&D 打包', trigger: ScriptTrigger.post),
    _script('script_3', '生成版本头', trigger: ScriptTrigger.pre),
    _script('script_4', "脚本 <一> & \"二\" '三' -- 四", trigger: ScriptTrigger.post),
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

void main() {
  test('三份 .targets 均通过 [xml] 整文档解析（含对抗性脚本名与包名）', () async {
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
        hasLength(4),
        reason: '夹具「${fixture.key}」应编译出 4 个脚本条目',
      );
      expect(content, contains('<!-- 脚本：A- - -B -->'));
      expect(content, contains('<!-- 脚本：R&amp;D 打包 -->'));
      expect(content, contains('<!-- 脚本：生成版本头 -->'));
      expect(
        content,
        contains(
          '<!-- 脚本：脚本 &lt;一&gt; &amp; &quot;二&quot; &apos;三&apos; - - 四 -->',
        ),
      );
      if (fixture.hasRuntimeBinaries) {
        expect(content, contains('<Target Name="DeployPkgRuntimeBinaries"'));
        expect(content, contains('AfterTargets="DeployPkgRuntimeBinaries"'));
      } else {
        expect(content, isNot(contains('DeployPkgRuntimeBinaries')));
        expect(content, contains('AfterTargets="Build"'));
      }
      if (fixture.key == 'with_license') {
        expect(content, contains('<Target Name="DeployPkgLicense__licensed_'));
        expect(
          content,
          contains(
            r"""Condition="Exists('$(MSBuildThisFileDirectory)files\LICENSE')">""",
          ),
        );
        expect(
          content,
          contains(
            r'DestinationFiles="$(OutDir)licenses\&amp;licensed_license.txt"',
          ),
        );
      } else {
        expect(content, isNot(contains('DeployPkgLicense')));
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
}
