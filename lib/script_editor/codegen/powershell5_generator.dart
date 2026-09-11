import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/code_writer.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/graph_validation.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';

const String _entryTypeKey = 'flow.entry';
const String _defaultExecPinId = 'out';

class PowerShell5Generator implements ScriptCodeGenerator {
  @override
  String get fileExtension => 'ps1';

  @override
  ScriptCompileResult compile(
    ScriptProjectModel project, {
    required String packName,
  }) {
    final List<ScriptDiagnostic> diagnostics = GraphValidator.validate(project);
    if (diagnostics.any((ScriptDiagnostic diagnostic) => diagnostic.isError)) {
      return ScriptCompileResult(code: null, diagnostics: diagnostics);
    }

    final CodeWriter writer = CodeWriter();
    final _PowerShellEmitter emitter = _PowerShellEmitter(
      project: project,
      writer: writer,
    );
    writer.writeln(
      '# 由 cpp_nuget_pack 生成 — $packName / ${project.name}。请使用节点编辑器修改，勿手工编辑本文件。',
    );
    writer.writeln(r"$ErrorActionPreference = 'Stop'");
    writer.writeln('try {');
    writer.indent(emitter.emitEntryChain);
    writer.writeln('} catch {');
    writer.indent(() {
      writer.writeln(
        r'Write-Host "脚本执行失败: $($_.Exception.Message)" -ForegroundColor Red',
      );
      writer.writeln('exit 1');
    });
    writer.writeln('}');
    return ScriptCompileResult(code: '\uFEFF$writer', diagnostics: diagnostics);
  }
}

class _PowerShellEmitter {
  _PowerShellEmitter({
    required ScriptProjectModel project,
    required this.writer,
  }) : _index = _GraphIndex(project);

  final CodeWriter writer;
  final _GraphIndex _index;

  void emitEntryChain() {
    final ScriptNodeModel? entry = _index.firstNodeOfType(_entryTypeKey);
    if (entry == null) {
      return; // 校验保证恰好一个入口；此处仅防御
    }
    _emitChain(_index.execTarget(entry.id, _defaultExecPinId));
  }

  void _emitChain(String? startNodeId) {
    String? nodeId = startNodeId;
    while (nodeId != null) {
      final ScriptNodeModel? node = _index.nodeById[nodeId];
      if (node == null) {
        return; // 校验保证边指向存在的节点；此处仅防御
      }
      _emitNode(node);
      nodeId = _continuationNodeId(node);
    }
  }

  /// 线性链默认沿普通 exec 输出 `out` 继续；T6 的循环节点将改由 `completed` 续接。
  String? _continuationNodeId(ScriptNodeModel node) {
    return _index.execTarget(node.id, _defaultExecPinId);
  }

  void _emitNode(ScriptNodeModel node) {
    switch (node.type) {
      case 'log.message':
        _emitLogMessage(node);
      default:
        // T6/T7/T8 扩展点：分支/循环、文件/进程、上下文/字符串/逻辑节点在此登记发射
        throw UnsupportedError('节点类型「${node.type}」的代码生成尚未实现');
    }
  }

  void _emitLogMessage(ScriptNodeModel node) {
    final String message = _expression(node, 'message');
    switch (_param(node, 'level')) {
      case 'warn':
        writer.writeln(
          "Write-Host ('[警告] ' + $message) -ForegroundColor Yellow",
        );
      case 'error':
        writer.writeln("Write-Host ('[错误] ' + $message) -ForegroundColor Red");
      default:
        writer.writeln('Write-Host $message');
    }
  }

  /// 内联 `node` 输入引脚处的数据表达式（递归展开上游数据节点）。
  String _expression(ScriptNodeModel node, String pinId) {
    final ScriptEdgeModel? edge = _index.incomingEdge(node.id, pinId);
    if (edge == null) {
      throw StateError('输入引脚「${node.id}.$pinId」未连接，无法生成表达式');
    }
    return _outputExpression(_index.nodeById[edge.from.node]!, edge.from.pin);
  }

  /// 数据节点输出引脚的表达式；T6 补充循环项、T8 补充上下文/字符串/逻辑节点。
  String _outputExpression(ScriptNodeModel node, String pinId) {
    switch (node.type) {
      case 'value.text':
        return _textLiteral(_param(node, 'value'));
      case 'value.boolean':
        return _param(node, 'value') == true ? r'$true' : r'$false';
      default:
        throw UnsupportedError('节点类型「${node.type}」的表达式生成尚未实现');
    }
  }

  Object? _param(ScriptNodeModel node, String key) {
    final Object? value = node.params[key];
    if (value != null) {
      return value;
    }
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    for (final ScriptParamDescriptor param
        in descriptor?.params ?? const <ScriptParamDescriptor>[]) {
      if (param.key == key) {
        return param.defaultValue;
      }
    }
    return null;
  }

  String _textLiteral(Object? value) {
    final String text = value == null ? '' : '$value';
    return "'${text.replaceAll("'", "''")}'";
  }
}

typedef _PinKey = ({String nodeId, String pinId});

class _GraphIndex {
  _GraphIndex(ScriptProjectModel project) {
    for (final ScriptNodeModel node in project.nodes) {
      nodeById[node.id] = node;
    }
    for (final ScriptEdgeModel edge in project.edges) {
      incomingEdges[(nodeId: edge.to.node, pinId: edge.to.pin)] = edge;
      outgoingEdges
          .putIfAbsent((
            nodeId: edge.from.node,
            pinId: edge.from.pin,
          ), () => <ScriptEdgeModel>[])
          .add(edge);
    }
  }

  final Map<String, ScriptNodeModel> nodeById = <String, ScriptNodeModel>{};
  final Map<_PinKey, ScriptEdgeModel> incomingEdges =
      <_PinKey, ScriptEdgeModel>{};
  final Map<_PinKey, List<ScriptEdgeModel>> outgoingEdges =
      <_PinKey, List<ScriptEdgeModel>>{};

  ScriptNodeModel? firstNodeOfType(String typeKey) {
    for (final ScriptNodeModel node in nodeById.values) {
      if (node.type == typeKey) {
        return node;
      }
    }
    return null;
  }

  ScriptEdgeModel? incomingEdge(String nodeId, String pinId) {
    return incomingEdges[(nodeId: nodeId, pinId: pinId)];
  }

  String? execTarget(String nodeId, String pinId) {
    final List<ScriptEdgeModel> edges =
        outgoingEdges[(nodeId: nodeId, pinId: pinId)] ??
        const <ScriptEdgeModel>[];
    return edges.isEmpty ? null : edges.first.to.node;
  }
}
