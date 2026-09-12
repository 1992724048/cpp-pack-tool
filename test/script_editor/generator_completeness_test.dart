import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 各数据类型的「最小提供者」类型：输出满足被测节点的必填输入；
/// 提供者自身的必填输入（如 file.list 的目录）由 string 提供者递归补足。
const Map<ScriptDataType, String> _providerTypeKeys = <ScriptDataType, String>{
  ScriptDataType.string: 'value.text',
  ScriptDataType.boolean: 'value.boolean',
  ScriptDataType.number: 'value.number',
  ScriptDataType.listString: 'file.list',
};

/// 各数据类型输出的「消费节点」类型：把被测类型的输出真正接入表达式发射
/// 路径（未消费的纯数据节点不会触发输出发射，护栏会漏掉其缺失 case）。
/// 消费节点为纯数据节点时（number → math.numberToString）继续向下桥接，
/// 直到接入含 exec 的消费节点，保证发射路径真正执行。
const Map<ScriptDataType, String> _consumerTypeKeys = <ScriptDataType, String>{
  ScriptDataType.string: 'log.message',
  ScriptDataType.boolean: 'flow.branch',
  ScriptDataType.listString: 'flow.foreach',
  ScriptDataType.number: 'math.numberToString',
};

/// 注册表默认参数不满足校验的类型需给出最小合法夹具值
/// （context.environment 与 variable 四类的名称须匹配正则、context.packageFile
/// 路径须非空、crypto 加密/签名节点的口令与证书来源二选一）。
const Map<String, Map<String, Object?>> _fixtureParams =
    <String, Map<String, Object?>>{
      'context.environment': <String, Object?>{'name': 'CNP_COMPLETENESS'},
      'context.packageFile': <String, Object?>{'path': 'lib/sample.lib'},
      'variable.setNumber': <String, Object?>{'name': 'CNP_COMPLETENESS'},
      'variable.getNumber': <String, Object?>{'name': 'CNP_COMPLETENESS'},
      'variable.setString': <String, Object?>{'name': 'CNP_COMPLETENESS'},
      'variable.getString': <String, Object?>{'name': 'CNP_COMPLETENESS'},
      'crypto.aesEncrypt': <String, Object?>{'password': 'secret'},
      'crypto.aesDecrypt': <String, Object?>{'password': 'secret'},
      'crypto.signFile': <String, Object?>{'pfxPath': 'cert.pfx'},
    };

ScriptEdgeModel _edge(
  String fromNode,
  String fromPin,
  String toNode,
  String toPin,
) {
  return ScriptEdgeModel(
    from: ScriptEdgeEndpoint(node: fromNode, pin: fromPin),
    to: ScriptEdgeEndpoint(node: toNode, pin: toPin),
  );
}

ScriptPinDescriptor? _execInputPin(String typeKey) {
  for (final ScriptPinDescriptor pin in NodeRegistry.byType(typeKey)!.pins) {
    if (pin.isInput && pin.kind == ScriptPinKind.exec) {
      return pin;
    }
  }
  return null;
}

String _execOutputPinId(String typeKey) {
  String? fallback;
  for (final ScriptPinDescriptor pin in NodeRegistry.byType(typeKey)!.pins) {
    if (!pin.isInput && pin.kind == ScriptPinKind.exec) {
      if (pin.id == defaultExecPinId) {
        return pin.id;
      }
      fallback ??= pin.id;
    }
  }
  if (fallback == null) {
    throw StateError('节点「$typeKey」缺少执行输出引脚');
  }
  return fallback;
}

String _dataOutputPinId(String typeKey, ScriptDataType dataType) {
  return NodeRegistry.byType(typeKey)!.pins
      .singleWhere(
        (ScriptPinDescriptor pin) =>
            !pin.isInput &&
            pin.kind == ScriptPinKind.data &&
            pin.dataType == dataType,
        orElse: () => throw StateError('节点「$typeKey」缺少 $dataType 输出引脚'),
      )
      .id;
}

String _dataInputPinId(String typeKey, ScriptDataType dataType) {
  return NodeRegistry.byType(typeKey)!.pins
      .firstWhere(
        (ScriptPinDescriptor pin) =>
            pin.isInput &&
            pin.kind == ScriptPinKind.data &&
            pin.dataType == dataType,
        orElse: () => throw StateError('节点「$typeKey」缺少 $dataType 输入引脚'),
      )
      .id;
}

/// 被测类型的最小合法图：一个入口 + 该类型节点 + 必填输入的提供者，
/// 并把该类型的数据输出接给消费节点（保证发射路径真正执行）。
ScriptProjectModel _minimalGraphFor(ScriptNodeTypeDescriptor type) {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_completeness',
    name: '完整性 ${type.typeKey}',
    trigger: ScriptTrigger.pre,
  );
  int nodeCounter = 0;

  ScriptNodeModel addNode(String typeKey) {
    final ScriptNodeModel node = ScriptNodeModel(
      id: 'n${++nodeCounter}',
      type: typeKey,
    );
    final Map<String, Object?>? fixture = _fixtureParams[typeKey];
    if (fixture != null) {
      node.params = Map<String, Object?>.of(fixture);
    }
    project.nodes.add(node);
    return node;
  }

  final ScriptNodeModel entry = addNode(entryTypeKey);
  if (type.typeKey == entryTypeKey) {
    return project;
  }
  final ScriptNodeModel node = addNode(type.typeKey);

  final Map<ScriptDataType, ScriptNodeModel> providers =
      <ScriptDataType, ScriptNodeModel>{};

  ScriptNodeModel ensureProvider(ScriptDataType dataType) {
    final ScriptNodeModel? existing = providers[dataType];
    if (existing != null) {
      return existing;
    }
    final ScriptNodeModel provider = addNode(_providerTypeKeys[dataType]!);
    providers[dataType] = provider;
    for (final ScriptPinDescriptor pin in NodeRegistry.byType(
      provider.type,
    )!.pins) {
      if (!pin.isInput || !pin.required) {
        continue;
      }
      final ScriptDataType needed = pin.dataType!;
      if (needed == dataType) {
        throw StateError('提供者「${provider.type}」的输入「${pin.id}」需要自身类型');
      }
      final ScriptNodeModel nested = ensureProvider(needed);
      project.edges.add(
        _edge(
          nested.id,
          _dataOutputPinId(nested.type, needed),
          provider.id,
          pin.id,
        ),
      );
    }
    return provider;
  }

  final ScriptPinDescriptor? execInput = _execInputPin(type.typeKey);
  if (execInput != null) {
    project.edges.add(_edge(entry.id, defaultExecPinId, node.id, execInput.id));
  }

  for (final ScriptPinDescriptor pin in type.pins) {
    if (!pin.isInput || !pin.required || pin.kind != ScriptPinKind.data) {
      continue;
    }
    final ScriptDataType dataType = pin.dataType!;
    final ScriptNodeModel provider = ensureProvider(dataType);
    project.edges.add(
      _edge(
        provider.id,
        _dataOutputPinId(provider.type, dataType),
        node.id,
        pin.id,
      ),
    );
  }

  /// 把 [source] 的 [dataType] 输出接给该类型的消费节点；消费节点为纯数据
  /// 节点时继续为其数据输出桥接下游（visited 防环），直到接入 exec 消费节点。
  void connectConsumer(
    ScriptNodeModel source,
    String outputPinId,
    ScriptDataType dataType,
    Set<ScriptDataType> visited,
  ) {
    final String? consumerTypeKey = _consumerTypeKeys[dataType];
    if (consumerTypeKey == null) {
      return;
    }
    final ScriptNodeTypeDescriptor? consumerDescriptor = NodeRegistry.byType(
      consumerTypeKey,
    );
    if (consumerDescriptor == null) {
      throw StateError('消费节点类型「$consumerTypeKey」未注册');
    }
    final ScriptNodeModel consumer = addNode(consumerTypeKey);
    project.edges.add(
      _edge(
        source.id,
        outputPinId,
        consumer.id,
        _dataInputPinId(consumerTypeKey, dataType),
      ),
    );
    final ScriptPinDescriptor? consumerExecInput = _execInputPin(
      consumerTypeKey,
    );
    if (consumerExecInput != null) {
      final String execSourceNodeId = execInput == null ? entry.id : node.id;
      final String execSourcePinId = execInput == null
          ? defaultExecPinId
          : _execOutputPinId(type.typeKey);
      project.edges.add(
        _edge(
          execSourceNodeId,
          execSourcePinId,
          consumer.id,
          consumerExecInput.id,
        ),
      );
      return;
    }
    for (final ScriptPinDescriptor consumerPin in consumerDescriptor.pins) {
      if (consumerPin.isInput || consumerPin.kind != ScriptPinKind.data) {
        continue;
      }
      final ScriptDataType nextType = consumerPin.dataType!;
      if (!visited.add(nextType)) {
        continue;
      }
      connectConsumer(consumer, consumerPin.id, nextType, visited);
    }
  }

  for (final ScriptPinDescriptor pin in type.pins) {
    if (pin.isInput || pin.kind != ScriptPinKind.data) {
      continue;
    }
    final ScriptDataType dataType = pin.dataType!;
    connectConsumer(node, pin.id, dataType, <ScriptDataType>{dataType});
  }

  return project;
}

void main() {
  group('引擎全类型发射完整性', () {
    test('NodeRegistry 每个类型的最小合法图都能编译出脚本', () {
      final PowerShell5Generator generator = PowerShell5Generator();
      final Set<String> compiledTypeKeys = <String>{};

      for (final ScriptNodeTypeDescriptor type in NodeRegistry.all) {
        final ScriptProjectModel project = _minimalGraphFor(type);
        // 生成器缺发射 case 时在此抛 UnsupportedError，测试即失败（护栏核心）。
        final ScriptCompileResult result = generator.compile(
          project,
          packName: 'demo',
        );
        final List<ScriptDiagnostic> errors = result.diagnostics
            .where((ScriptDiagnostic diagnostic) => diagnostic.isError)
            .toList();
        expect(
          errors,
          isEmpty,
          reason:
              '「${type.typeKey}」编译产生错误诊断：'
              '${errors.map((ScriptDiagnostic diagnostic) => diagnostic.message).join('；')}',
        );
        expect(result.code, isNotNull, reason: '「${type.typeKey}」未生成脚本');
        compiledTypeKeys.add(type.typeKey);
      }

      expect(
        compiledTypeKeys,
        hasLength(NodeRegistry.all.length),
        reason: '编译覆盖的类型数应等于注册表类型数',
      );
      expect(
        NodeRegistry.all.length,
        greaterThanOrEqualTo(46),
        reason: '注册表类型数量异常缩减（当前 46 类），护栏失效',
      );
    });
  });
}
