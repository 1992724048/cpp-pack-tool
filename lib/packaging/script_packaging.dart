import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/msbuild_macros.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/sha1.dart';

class PackagingIssue {
  const PackagingIssue({required this.label, required this.message});

  /// 脚本名或「包内路径」。
  final String label;
  final String message;
}

class ScriptPackagingResult {
  const ScriptPackagingResult({
    required this.entries,
    required this.targetsFragment,
    required this.issues,
  });

  /// `.ps1` 生成条目：`build/native/files/scripts/<id>.ps1`（`id` 即 `script_N`）。
  final List<PackageEntry> entries;

  /// 追加进 `.targets` 的文本；无有效脚本时为空串。
  final String targetsFragment;

  /// 编译失败脚本（已跳过生成）。
  final List<PackagingIssue> issues;
}

class ScriptPackaging {
  const ScriptPackaging({this.generator});

  /// 为 null 时使用默认 `PowerShell5Generator`（测试可注入假生成器）。
  final ScriptCodeGenerator? generator;

  static final ScriptCodeGenerator _defaultGenerator = PowerShell5Generator();

  static const String _macroNodeType = 'context.macro';
  static const String _scriptsDirectory = 'build/native/files/scripts';
  static const String _executorPrefix =
      r'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass '
      r'-File ';
  static final RegExp _invalidTargetNameChar = RegExp(r'[^A-Za-z0-9_]');

  ScriptPackagingResult build(
    PackModel pack, {
    required bool hasRuntimeBinaries,
  }) {
    final ScriptCodeGenerator codeGenerator = generator ?? _defaultGenerator;
    final List<PackageEntry> entries = <PackageEntry>[];
    final List<PackagingIssue> issues = <PackagingIssue>[];
    final List<ScriptProjectModel> preScripts = <ScriptProjectModel>[];
    final List<ScriptProjectModel> postScripts = <ScriptProjectModel>[];

    for (final ScriptProjectModel script in pack.scripts) {
      final ScriptCompileResult result;
      try {
        result = codeGenerator.compile(script, packName: pack.name);
      } catch (error) {
        // 生成器实现异常不得中断构建计划（buildPlan 调用方不捕获异常）
        issues.add(
          PackagingIssue(
            label: script.name,
            message: '脚本编译失败：${formatError(error)}',
          ),
        );
        continue;
      }
      final String? code = result.code;
      if (code == null || result.hasErrors) {
        issues.add(
          PackagingIssue(label: script.name, message: _failureMessage(result)),
        );
        continue;
      }
      entries.add(
        PackageEntry(
          packagePath: '$_scriptsDirectory/${_scriptFileName(script)}',
          source: PackageGeneratedSource(content: code),
        ),
      );
      switch (script.trigger) {
        case ScriptTrigger.pre:
          preScripts.add(script);
        case ScriptTrigger.post:
          postScripts.add(script);
      }
    }

    return ScriptPackagingResult(
      entries: List<PackageEntry>.unmodifiable(entries),
      targetsFragment: _targetsFragment(
        pack,
        preScripts: preScripts,
        postScripts: postScripts,
        hasRuntimeBinaries: hasRuntimeBinaries,
      ),
      issues: List<PackagingIssue>.unmodifiable(issues),
    );
  }

  static String _failureMessage(ScriptCompileResult result) {
    final List<ScriptDiagnostic> errors = result.diagnostics
        .where((ScriptDiagnostic diagnostic) => diagnostic.isError)
        .toList();
    if (errors.isEmpty) {
      return '脚本编译失败';
    }
    return '脚本编译失败（共 ${errors.length} 个错误）：${errors.first.message}';
  }

  static String _targetsFragment(
    PackModel pack, {
    required List<ScriptProjectModel> preScripts,
    required List<ScriptProjectModel> postScripts,
    required bool hasRuntimeBinaries,
  }) {
    if (preScripts.isEmpty && postScripts.isEmpty) {
      return '';
    }
    final String cleanId = pack.name.replaceAll(_invalidTargetNameChar, '_');
    final String hash = hash8(pack.name);
    final StringBuffer buffer = StringBuffer();
    _writeScriptTarget(
      buffer,
      name: 'CnpScripts_${cleanId}_${hash}_Pre',
      anchor: 'BeforeTargets="PreBuildEvent"',
      scripts: preScripts,
    );
    _writeScriptTarget(
      buffer,
      name: 'CnpScripts_${cleanId}_${hash}_Post',
      anchor: hasRuntimeBinaries
          ? 'AfterTargets="DeployPkgRuntimeBinaries"'
          : 'AfterTargets="Build"',
      scripts: postScripts,
    );
    return buffer.toString();
  }

  static void _writeScriptTarget(
    StringBuffer buffer, {
    required String name,
    required String anchor,
    required List<ScriptProjectModel> scripts,
  }) {
    if (scripts.isEmpty) {
      return;
    }
    buffer.writeln('  <Target Name="$name" $anchor>');
    for (final ScriptProjectModel script in scripts) {
      buffer
        ..writeln('    <!-- 脚本：${_commentText(script.name)} -->')
        ..writeln('    <Exec ${_execAttributes(script)} />');
    }
    buffer.writeln('  </Target>');
  }

  static String _execAttributes(ScriptProjectModel script) {
    final StringBuffer buffer = StringBuffer(
      'Command="${_escapeXml(_scriptCommand(script))}"',
    );
    final String? condition = _configurationCondition(script.buildModel);
    if (condition != null) {
      buffer.write(' Condition="$condition"');
    }
    buffer
      ..write(' IgnoreStandardErrorWarningFormat="true"')
      ..write(' EnvironmentVariables="${_environmentVariables(script)}"');
    return buffer.toString();
  }

  static String _scriptCommand(ScriptProjectModel script) =>
      '$_executorPrefix"'
      r'$(MSBuildThisFileDirectory)files\scripts\'
      '${_scriptFileName(script)}"';

  /// 包内脚本文件名：`id` 本身为 ASCII 安全格式（spec §2.1 `script_N`），
  /// 直接取 `<id>.ps1`，避免再套前缀得到 `script_script_1.ps1`
  /// （spec §5.2 示例与 M3 计划 Task 4 断言均为 `script_1.ps1`）。
  static String _scriptFileName(ScriptProjectModel script) =>
      '${script.id}.ps1';

  static String? _configurationCondition(BuildModel buildModel) {
    return switch (buildModel) {
      BuildModel.all => null,
      BuildModel.release => "'\$(Configuration)'=='$releaseBuildLabel'",
      BuildModel.debug => "'\$(Configuration)'=='$debugBuildLabel'",
    };
  }

  static String _environmentVariables(ScriptProjectModel script) {
    final List<String> entries = <String>[
      _environmentEntry('CNP_PackageRoot', r'$(MSBuildThisFileDirectory)'),
      for (final String key in _macroKeysOf(script))
        _environmentEntry(macroEnvName(key), '\$($key)'),
    ];
    return _escapeXml(entries.join(';'));
  }

  static String _environmentEntry(String name, String value) =>
      '$name=${_escapeEnvironmentValue(value)}';

  static String _escapeEnvironmentValue(String value) =>
      value.replaceAll('%', '%25').replaceAll(';', '%3B');

  /// 有效脚本图中实际用到的宏键，按白名单顺序去重。
  static List<String> _macroKeysOf(ScriptProjectModel script) {
    final Set<String> usedKeys = <String>{};
    for (final ScriptNodeModel node in script.nodes) {
      if (node.type == _macroNodeType) {
        usedKeys.add('${_macroParamValue(node)}');
      }
    }
    return <String>[
      for (final String key in msbuildMacroKeys)
        if (usedKeys.contains(key)) key,
    ];
  }

  /// 镜像生成器 `_param` 的回退：参数未存储时取注册表默认值（`OutDir`）。
  static Object? _macroParamValue(ScriptNodeModel node) {
    final Object? value = node.params['macro'];
    if (value != null) {
      return value;
    }
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    for (final ScriptParamDescriptor param
        in descriptor?.params ?? const <ScriptParamDescriptor>[]) {
      if (param.key == 'macro') {
        return param.defaultValue;
      }
    }
    return null;
  }

  static String _commentText(String name) =>
      _escapeXml(name).replaceAll('--', '- -');

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
