import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/packaging/script_packaging.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGenerator implements ScriptCodeGenerator {
  _FakeGenerator({
    this.failures = const <String, ScriptCompileResult>{},
    this.throwingIds = const <String>{},
  });

  final Map<String, ScriptCompileResult> failures;
  final Set<String> throwingIds;
  final List<String> compiledIds = <String>[];

  @override
  String get fileExtension => 'ps1';

  @override
  ScriptCompileResult compile(
    ScriptProjectModel project, {
    required String packName,
  }) {
    compiledIds.add(project.id);
    if (throwingIds.contains(project.id)) {
      throw StateError('生成器异常：${project.id}');
    }
    final ScriptCompileResult? failure = failures[project.id];
    if (failure != null) {
      return failure;
    }
    return ScriptCompileResult(
      code: '\uFEFFWrite-Host \'${project.name}\'\n',
      diagnostics: const <ScriptDiagnostic>[],
    );
  }
}

PackModel _pack({String name = 'demo'}) =>
    PackModel(name: name, version: '1.0.0', author: 'tester');

ScriptProjectModel _script(
  String id,
  String scriptName, {
  ScriptTrigger trigger = ScriptTrigger.pre,
  BuildModel buildModel = BuildModel.all,
}) => ScriptProjectModel(
  id: id,
  name: scriptName,
  trigger: trigger,
  buildModel: buildModel,
);

ScriptNodeModel _macroNode(String id, {String? macro}) {
  final ScriptNodeModel node = ScriptNodeModel(id: id, type: 'context.macro');
  if (macro != null) {
    node.params['macro'] = macro;
  }
  return node;
}

ScriptCompileResult _failure(
  List<ScriptDiagnostic> diagnostics, {
  String? code,
}) => ScriptCompileResult(code: code, diagnostics: diagnostics);

const String _packageRoot = 'CNP_PackageRoot=\$(MSBuildThisFileDirectory)';

String _execLine(
  String scriptId, {
  String? condition,
  required String environmentVariables,
}) {
  final String command =
      'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass '
      '-File &quot;\$(MSBuildThisFileDirectory)files\\scripts\\'
      '$scriptId.ps1&quot;';
  final String conditionAttribute = condition == null
      ? ''
      : ' Condition="$condition"';
  return '    <Exec Command="$command"$conditionAttribute '
      'IgnoreStandardErrorWarningFormat="true" '
      'EnvironmentVariables="$environmentVariables" />';
}

void main() {
  group('无脚本', () {
    test('无脚本时条目与片段为空、无问题', () {
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(_pack(), hasRuntimeBinaries: false);

      expect(result.entries, isEmpty);
      expect(result.targetsFragment, '');
      expect(result.issues, isEmpty);
    });

    test('全部脚本编译失败时条目与片段为空、问题逐脚本记录', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script('script_1', '坏一'),
          _script('script_2', '坏二'),
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(
          failures: <String, ScriptCompileResult>{
            'script_1': _failure(<ScriptDiagnostic>[
              const ScriptDiagnostic(message: '缺少入口节点', isError: true),
            ]),
            'script_2': _failure(<ScriptDiagnostic>[
              const ScriptDiagnostic(message: '引脚未连接', isError: true),
            ]),
          },
        ),
      ).build(pack, hasRuntimeBinaries: true);

      expect(result.entries, isEmpty);
      expect(result.targetsFragment, '');
      expect(result.issues, hasLength(2));
      expect(result.issues[0].label, '坏一');
      expect(result.issues[1].label, '坏二');
    });
  });

  group('条目', () {
    test('有效脚本生成 build/native/files/scripts/script_<id>.ps1 且保持列表序', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script('script_2', '二'),
          _script('script_1', '一'),
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      expect(
        result.entries.map((PackageEntry entry) => entry.packagePath),
        <String>[
          'build/native/files/scripts/script_2.ps1',
          'build/native/files/scripts/script_1.ps1',
        ],
      );
      final String code =
          (result.entries.first.source as PackageGeneratedSource).content;

      expect(code, '\uFEFFWrite-Host \'二\'\n');
    });

    test('编译失败脚本跳过并记录问题（含错误数与首条错误）', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script('script_1', '好脚本'),
          _script('script_2', '坏脚本')
            ..nodes = <ScriptNodeModel>[_macroNode('n1', macro: 'OutDir')],
          _script('script_3', '次好脚本'),
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(
          failures: <String, ScriptCompileResult>{
            'script_2': _failure(<ScriptDiagnostic>[
              const ScriptDiagnostic(message: '脚本必须恰好有一个「开始」节点', isError: true),
              const ScriptDiagnostic(message: '第二个错误', isError: true),
              const ScriptDiagnostic(message: '一个警告', isError: false),
            ]),
          },
        ),
      ).build(pack, hasRuntimeBinaries: true);

      expect(
        result.entries.map((PackageEntry entry) => entry.packagePath),
        <String>[
          'build/native/files/scripts/script_1.ps1',
          'build/native/files/scripts/script_3.ps1',
        ],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.single.label, '坏脚本');
      expect(result.issues.single.message, contains('2'));
      expect(result.issues.single.message, contains('脚本必须恰好有一个「开始」节点'));
      expect(result.targetsFragment, isNot(contains('script_2.ps1')));
      expect(result.targetsFragment, isNot(contains('CNP_OutDir')));
    });

    test('code 非空但含错误诊断同样跳过', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[_script('script_1', '半成品')];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(
          failures: <String, ScriptCompileResult>{
            'script_1': _failure(<ScriptDiagnostic>[
              const ScriptDiagnostic(message: '未知节点类型', isError: true),
            ], code: '\uFEFFbroken'),
          },
        ),
      ).build(pack, hasRuntimeBinaries: false);

      expect(result.entries, isEmpty);
      expect(result.issues.single.label, '半成品');
    });

    test('生成器抛异常时转为问题并继续后续脚本', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script('script_2', '炸'),
          _script('script_1', '正常'),
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(throwingIds: <String>{'script_2'}),
      ).build(pack, hasRuntimeBinaries: false);

      expect(
        result.entries.map((PackageEntry entry) => entry.packagePath),
        <String>['build/native/files/scripts/script_1.ps1'],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.single.label, '炸');
      expect(result.issues.single.message, contains('生成器异常：script_2'));
      expect(result.targetsFragment, isNot(contains('script_2.ps1')));
    });
  });

  group('Target 片段', () {
    test('单 pre 脚本 all 构建 golden（命名/hash/无 Condition）', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[_script('script_1', '脚本 1')];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      expect(
        result.targetsFragment,
        '  <Target Name="CnpScripts_demo_89e495e7_Pre" '
        'BeforeTargets="PreBuildEvent">\n'
        '    <!-- 脚本：脚本 1 -->\n'
        '${_execLine('script_1', environmentVariables: _packageRoot)}\n'
        '  </Target>\n',
      );
    });

    test('post release 无运行时二进制 golden（Build 挂点/Release 条件/宏默认回退与去重）', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script(
              'script_7',
              '释放检查',
              trigger: ScriptTrigger.post,
              buildModel: BuildModel.release,
            )
            ..nodes = <ScriptNodeModel>[
              _macroNode('n1', macro: 'OutDir'),
              _macroNode('n2'),
            ],
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      expect(
        result.targetsFragment,
        '  <Target Name="CnpScripts_demo_89e495e7_Post" AfterTargets="Build">\n'
        '    <!-- 脚本：释放检查 -->\n'
        '${_execLine('script_7', condition: '\'\$(Configuration)\'==\'Release\'', environmentVariables: '$_packageRoot;CNP_OutDir=\$(OutDir)')}\n'
        '  </Target>\n',
      );
    });

    test('hasRuntimeBinaries 为真时 post 挂点切换到部署目标之后', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script(
            'script_1',
            '部署后',
            trigger: ScriptTrigger.post,
            buildModel: BuildModel.debug,
          ),
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: true);

      expect(
        result.targetsFragment,
        contains(
          r'<Target Name="CnpScripts_demo_89e495e7_Post" AfterTargets="DeployPkgRuntimeBinaries">',
        ),
      );
      expect(
        result.targetsFragment,
        contains('\'\$(Configuration)\'==\'Debug\''),
      );
    });

    test('pre 与 post 分离为两个 Target 且同组保持列表序', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script('script_2', '后一', trigger: ScriptTrigger.post),
          _script('script_1', '前一', trigger: ScriptTrigger.pre),
          _script('script_3', '后二', trigger: ScriptTrigger.post),
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      final int preTarget = result.targetsFragment.indexOf(
        'CnpScripts_demo_89e495e7_Pre',
      );
      final int postTarget = result.targetsFragment.indexOf(
        'CnpScripts_demo_89e495e7_Post',
      );

      expect(preTarget, greaterThanOrEqualTo(0));
      expect(postTarget, greaterThan(preTarget));
      expect(
        result.targetsFragment,
        contains(
          r'<Target Name="CnpScripts_demo_89e495e7_Post" AfterTargets="Build">',
        ),
      );
      final int firstScript = result.targetsFragment.indexOf('前一');
      expect(firstScript, greaterThan(preTarget));
      expect(
        firstScript,
        lessThan(result.targetsFragment.indexOf('</Target>')),
      );
      final int laterOne = result.targetsFragment.indexOf('后一');
      final int laterTwo = result.targetsFragment.indexOf('后二');
      expect(laterOne, greaterThan(postTarget));
      expect(laterTwo, greaterThan(laterOne));
    });

    test('Target 名清洗非法字符（非 [A-Za-z0-9_] → _）', () {
      final PackModel pack = _pack(name: 'my.lib')
        ..scripts = <ScriptProjectModel>[_script('script_1', '清洗')];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      expect(
        result.targetsFragment,
        contains('<Target Name="CnpScripts_my_lib_5b7003fb_Pre"'),
      );
    });

    test('各脚本的宏集合互相独立、非白名单宏被过滤', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script('script_1', '宏配置')
            ..nodes = <ScriptNodeModel>[
              _macroNode('n1', macro: 'Configuration'),
              _macroNode('n2', macro: 'Bogus'),
            ],
          _script('script_2', '宏目录')
            ..nodes = <ScriptNodeModel>[_macroNode('n1', macro: 'OutDir')],
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      expect(
        result.targetsFragment,
        contains(
          'EnvironmentVariables="$_packageRoot;CNP_Configuration=\$(Configuration)"',
        ),
      );
      expect(
        result.targetsFragment,
        contains('EnvironmentVariables="$_packageRoot;CNP_OutDir=\$(OutDir)"'),
      );
      expect(result.targetsFragment, isNot(contains('Bogus')));
      expect(result.targetsFragment, isNot(contains('CNP_Bogus')));
      expect(
        result.targetsFragment,
        isNot(contains('CNP_Configuration=\$(Configuration);CNP_OutDir')),
      );
      expect(
        'CNP_OutDir=\$(OutDir)'.allMatches(result.targetsFragment).length,
        1,
      );
    });

    test('脚本名注释 XML 转义且 -- 替换为 - -', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[
          _script('script_1', 'A & B -- <C> "D"'),
        ];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      expect(
        result.targetsFragment,
        contains('<!-- 脚本：A &amp; B - - &lt;C&gt; &quot;D&quot; -->'),
      );
      expect(result.targetsFragment, isNot(contains('-- <C>')));
    });

    test('脚本名含 3 个连续 "-" 时注释不残留 --', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[_script('script_1', 'A---B')];
      final ScriptPackagingResult result = ScriptPackaging(
        generator: _FakeGenerator(),
      ).build(pack, hasRuntimeBinaries: false);

      expect(result.targetsFragment, contains('<!-- 脚本：A- - -B -->'));
      expect(result.targetsFragment, isNot(contains('A- --B')));
      expect(result.targetsFragment, isNot(contains('A---B')));
    });

    test('默认生成器（PowerShell5Generator）编译有效图并生成 BOM 代码条目', () {
      final PackModel pack = _pack()
        ..scripts = <ScriptProjectModel>[_validGraph()];
      final ScriptPackagingResult result = const ScriptPackaging().build(
        pack,
        hasRuntimeBinaries: false,
      );

      expect(result.issues, isEmpty);
      expect(result.entries, hasLength(1));
      final String code =
          (result.entries.single.source as PackageGeneratedSource).content;

      expect(code.startsWith('\uFEFF'), isTrue);
      expect(code, contains('Write-Host'));
      expect(
        result.targetsFragment,
        contains('<Target Name="CnpScripts_demo_89e495e7_Pre"'),
      );
    });
  });
}

ScriptProjectModel _validGraph() {
  final ScriptProjectModel project = _script('script_1', '生成版本头');
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
