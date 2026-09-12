import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/msbuild_macros.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/script_editor/variable_rules.dart';

const String _branchTypeKey = 'flow.branch';
const Set<String> _logLevels = <String>{'info', 'warn', 'error'};
const Set<String> _stringOperators = <String>{'eq', 'ne', 'contains'};
const Set<String> _mathOperators = <String>{
  'add',
  'subtract',
  'multiply',
  'divide',
  'modulo',
};
const Set<String> _bitwiseOperators = <String>{
  'and',
  'or',
  'xor',
  'shiftLeft',
  'shiftRight',
};
const Set<String> _numberOperators = <String>{
  'lt',
  'le',
  'gt',
  'ge',
  'eq',
  'ne',
};
const Set<String> _hashAlgorithms = <String>{
  'sha256',
  'sha1',
  'sha512',
  'md5',
  'crc32',
};

const String _variableNameFormatError = '变量名须以字母或下划线开头，且仅含字母、数字、下划线';
final RegExp _namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

class GraphValidator {
  static List<ScriptDiagnostic> validate(ScriptProjectModel project) {
    final List<ScriptDiagnostic> diagnostics = <ScriptDiagnostic>[];
    final Set<String> nodeIds = <String>{
      for (final ScriptNodeModel node in project.nodes) node.id,
    };
    final Map<String, ScriptNodeTypeDescriptor> descriptorById =
        <String, ScriptNodeTypeDescriptor>{};
    for (final ScriptNodeModel node in project.nodes) {
      final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(
        node.type,
      );
      if (descriptor == null) {
        diagnostics.add(
          ScriptDiagnostic(
            message: '未知节点类型「${node.type}」',
            nodeId: node.id,
            isError: true,
          ),
        );
        continue;
      }
      descriptorById[node.id] = descriptor;
    }

    _validateEntryCount(project.nodes, diagnostics);
    for (final ScriptNodeModel node in project.nodes) {
      final ScriptNodeTypeDescriptor? descriptor = descriptorById[node.id];
      if (descriptor != null) {
        _validateParams(node, descriptor, diagnostics);
      }
    }
    _validateNodeLevelParams(project.nodes, descriptorById, diagnostics);

    final _GraphFacts facts = _collectFacts(
      project.edges,
      nodeIds,
      descriptorById,
      diagnostics,
    );
    _validateRequiredInputs(project.nodes, descriptorById, facts, diagnostics);
    _validateCycles(project.nodes, facts, diagnostics);
    _validateWarnings(project.nodes, descriptorById, facts, diagnostics);
    return diagnostics;
  }

  static void _validateEntryCount(
    List<ScriptNodeModel> nodes,
    List<ScriptDiagnostic> diagnostics,
  ) {
    final int count = nodes
        .where((ScriptNodeModel node) => node.type == entryTypeKey)
        .length;
    if (count == 1) {
      return;
    }
    final String detail = count == 0 ? '当前没有入口节点' : '当前有 $count 个';
    diagnostics.add(
      ScriptDiagnostic(message: '脚本必须恰好有一个「开始」节点，$detail', isError: true),
    );
  }

  static void _validateParams(
    ScriptNodeModel node,
    ScriptNodeTypeDescriptor descriptor,
    List<ScriptDiagnostic> diagnostics,
  ) {
    for (final ScriptParamDescriptor param in descriptor.params) {
      final Object? value = node.params[param.key] ?? param.defaultValue;
      final String? message = _paramErrorMessage(descriptor, param, value);
      if (message != null) {
        diagnostics.add(
          ScriptDiagnostic(message: message, nodeId: node.id, isError: true),
        );
      }
    }
  }

  static String? _paramErrorMessage(
    ScriptNodeTypeDescriptor descriptor,
    ScriptParamDescriptor param,
    Object? value,
  ) {
    switch (param.type) {
      case ScriptParamType.macroKey:
        if (value is String && msbuildMacroKeys.contains(value)) {
          return null;
        }
        return '参数「${param.label}」的值「$value」不在 MSBuild 宏白名单内';
      case ScriptParamType.logLevel:
        if (value is String && _logLevels.contains(value)) {
          return null;
        }
        return '参数「${param.label}」的值「$value」非法，应为 info / warn / error';
      case ScriptParamType.stringOperator:
        if (value is String && _stringOperators.contains(value)) {
          return null;
        }
        return '参数「${param.label}」的值「$value」非法，应为 eq / ne / contains';
      case ScriptParamType.mathOperator:
        if (value is String && _mathOperators.contains(value)) {
          return null;
        }
        return '参数「${param.label}」的值「$value」非法，应为 add / subtract / multiply / divide / modulo';
      case ScriptParamType.bitwiseOperator:
        if (value is String && _bitwiseOperators.contains(value)) {
          return null;
        }
        return '参数「${param.label}」的值「$value」非法，应为 and / or / xor / shiftLeft / shiftRight';
      case ScriptParamType.numberOperator:
        if (value is String && _numberOperators.contains(value)) {
          return null;
        }
        return '参数「${param.label}」的值「$value」非法，应为 lt / le / gt / ge / eq / ne';
      case ScriptParamType.hashAlgorithm:
        if (value is String && _hashAlgorithms.contains(value)) {
          return null;
        }
        return '参数「${param.label}」的值「$value」非法，应为 sha256 / sha1 / sha512 / md5 / crc32';
      case ScriptParamType.packageFilePath:
        if (value is String && value.trim().isNotEmpty) {
          return null;
        }
        return '参数「${param.label}」的值「$value」非法，应为非空路径';
      case ScriptParamType.scriptFilePath:
        if (value is String && value.trim().isNotEmpty) {
          return null;
        }
        return '参数「${param.label}」不能为空';
      case ScriptParamType.textLines:
        // 多行列表清洗在写入侧（检查器控件）完成，无参数级错误规则。
        return null;
      case ScriptParamType.text:
        if (param.key != 'name') {
          return null;
        }
        final bool isEnvironment = descriptor.typeKey == 'context.environment';
        final bool isVariable = variableTypeVariants.containsKey(
          descriptor.typeKey,
        );
        if (!isEnvironment && !isVariable) {
          return null;
        }
        if (value is String && _namePattern.hasMatch(value)) {
          return null;
        }
        if (isEnvironment) {
          return '参数「${param.label}」的值「$value」不是合法环境变量名';
        }
        return _variableNameFormatError;
      case ScriptParamType.boolean:
        return null;
      case ScriptParamType.number:
        if (value is num && value.isFinite) {
          return null;
        }
        return '参数「${param.label}」的值「$value」必须为数字';
    }
  }

  /// 节点级参数规则：注册表参数声明无法表达的规则（AES 口令二选一、
  /// 签名证书来源二选一、口令环境变量名格式、变量同名同类型、findTool 工具名必填）。
  /// 在参数校验循环之后按节点声明序追加，不改变既有诊断顺序。
  static void _validateNodeLevelParams(
    List<ScriptNodeModel> nodes,
    Map<String, ScriptNodeTypeDescriptor> descriptorById,
    List<ScriptDiagnostic> diagnostics,
  ) {
    for (final ScriptNodeModel node in nodes) {
      final ScriptNodeTypeDescriptor? descriptor = descriptorById[node.id];
      if (descriptor == null) {
        continue;
      }
      switch (descriptor.typeKey) {
        case 'crypto.aesEncrypt':
        case 'crypto.aesDecrypt':
          _validateAesParams(node, descriptor, diagnostics);
        case 'crypto.signFile':
          _validateSignFileParams(node, descriptor, diagnostics);
        case 'system.findTool':
          _validateFindToolParams(node, descriptor, diagnostics);
      }
    }
    _validateVariableNameTypes(nodes, descriptorById, diagnostics);
  }

  /// 同一变量名只允许一种类型变体：按节点声明序收集 `小写名 → {变体, 书写名}`，
  /// 首个出现节点的变体与书写形式为准（与生成器首见一致）；名称按 PowerShell
  /// 语义大小写不敏感（lower-key 归并），后续同名不同变体节点报错（消息用该
  /// 节点自身的书写名）；同名同类型（含大小写变体）重复出现合法。名称本身
  /// 非法的节点已由参数级报错，不再参与收集以免级联噪声。
  static void _validateVariableNameTypes(
    List<ScriptNodeModel> nodes,
    Map<String, ScriptNodeTypeDescriptor> descriptorById,
    List<ScriptDiagnostic> diagnostics,
  ) {
    final Map<String, ({String type, String displayName})> variantByName =
        <String, ({String type, String displayName})>{};
    for (final ScriptNodeModel node in nodes) {
      final ScriptNodeTypeDescriptor? descriptor = descriptorById[node.id];
      if (descriptor == null) {
        continue;
      }
      final String? variant = variableTypeVariants[descriptor.typeKey];
      if (variant == null) {
        continue;
      }
      final String name = _paramText(node, descriptor, 'name');
      if (name.isEmpty || !_namePattern.hasMatch(name)) {
        continue;
      }
      final ({String type, String displayName})? known =
          variantByName[name.toLowerCase()];
      if (known == null) {
        variantByName[name.toLowerCase()] = (type: variant, displayName: name);
        continue;
      }
      if (known.type != variant) {
        diagnostics.add(
          ScriptDiagnostic(
            message: '变量 $name 类型不一致',
            nodeId: node.id,
            isError: true,
          ),
        );
      }
    }
  }

  static void _validateAesParams(
    ScriptNodeModel node,
    ScriptNodeTypeDescriptor descriptor,
    List<ScriptDiagnostic> diagnostics,
  ) {
    final String password = _paramText(node, descriptor, 'password');
    final String passwordEnv = _paramText(node, descriptor, 'passwordEnv');
    if (password.isEmpty && passwordEnv.isEmpty) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '口令或口令环境变量名需二选一',
          nodeId: node.id,
          isError: true,
        ),
      );
      return;
    }
    _validatePasswordEnvName(node, descriptor, passwordEnv, diagnostics);
  }

  static void _validateSignFileParams(
    ScriptNodeModel node,
    ScriptNodeTypeDescriptor descriptor,
    List<ScriptDiagnostic> diagnostics,
  ) {
    final String pfxPath = _paramText(node, descriptor, 'pfxPath');
    final String thumbprint = _paramText(node, descriptor, 'thumbprint');
    if (pfxPath.isEmpty && thumbprint.isEmpty) {
      diagnostics.add(
        ScriptDiagnostic(
          message: 'PFX 路径或证书指纹需二选一',
          nodeId: node.id,
          isError: true,
        ),
      );
    }
    _validatePasswordEnvName(
      node,
      descriptor,
      _paramText(node, descriptor, 'passwordEnv'),
      diagnostics,
    );
  }

  static void _validatePasswordEnvName(
    ScriptNodeModel node,
    ScriptNodeTypeDescriptor descriptor,
    String passwordEnv,
    List<ScriptDiagnostic> diagnostics,
  ) {
    if (passwordEnv.isEmpty || _namePattern.hasMatch(passwordEnv)) {
      return;
    }
    diagnostics.add(
      ScriptDiagnostic(
        message:
            '参数「${_paramLabel(descriptor, 'passwordEnv')}」的值「$passwordEnv」不是合法环境变量名',
        nodeId: node.id,
        isError: true,
      ),
    );
  }

  /// findTool 工具名必填：空名会令 `Find-CnpTool` 内的 `Get-Command -Name ''`
  /// 抛参数绑定异常（`-ErrorAction SilentlyContinue` 无法抑制），故默认态即拦截。
  static void _validateFindToolParams(
    ScriptNodeModel node,
    ScriptNodeTypeDescriptor descriptor,
    List<ScriptDiagnostic> diagnostics,
  ) {
    if (_paramText(node, descriptor, 'name').trim().isEmpty) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '参数「${_paramLabel(descriptor, 'name')}」不能为空',
          nodeId: node.id,
          isError: true,
        ),
      );
    }
  }

  /// 取字符串参数有效值：节点未写时回退注册表默认值，非字符串按空串处理。
  static String _paramText(
    ScriptNodeModel node,
    ScriptNodeTypeDescriptor descriptor,
    String key,
  ) {
    for (final ScriptParamDescriptor param in descriptor.params) {
      if (param.key != key) {
        continue;
      }
      final Object? value = node.params[key] ?? param.defaultValue;
      return value is String ? value : '';
    }
    return '';
  }

  static String _paramLabel(ScriptNodeTypeDescriptor descriptor, String key) {
    for (final ScriptParamDescriptor param in descriptor.params) {
      if (param.key == key) {
        return param.label;
      }
    }
    return key;
  }

  static _GraphFacts _collectFacts(
    List<ScriptEdgeModel> edges,
    Set<String> nodeIds,
    Map<String, ScriptNodeTypeDescriptor> descriptorById,
    List<ScriptDiagnostic> diagnostics,
  ) {
    final _GraphFacts facts = _GraphFacts();
    for (final ScriptEdgeModel edge in edges) {
      _collectEdge(edge, nodeIds, descriptorById, facts, diagnostics);
    }
    _validateMultipleConnections(facts, diagnostics);
    return facts;
  }

  static void _collectEdge(
    ScriptEdgeModel edge,
    Set<String> nodeIds,
    Map<String, ScriptNodeTypeDescriptor> descriptorById,
    _GraphFacts facts,
    List<ScriptDiagnostic> diagnostics,
  ) {
    bool endpointMissing = false;
    if (!nodeIds.contains(edge.from.node)) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '边引用了不存在的节点「${edge.from.node}」',
          nodeId: edge.from.node,
          isError: true,
        ),
      );
      endpointMissing = true;
    }
    if (!nodeIds.contains(edge.to.node)) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '边引用了不存在的节点「${edge.to.node}」',
          nodeId: edge.to.node,
          isError: true,
        ),
      );
      endpointMissing = true;
    }
    if (endpointMissing) {
      return;
    }

    final ScriptNodeTypeDescriptor? fromDescriptor =
        descriptorById[edge.from.node];
    final ScriptNodeTypeDescriptor? toDescriptor = descriptorById[edge.to.node];
    if (fromDescriptor == null || toDescriptor == null) {
      return; // 未知类型节点无法解析引脚，已有独立错误
    }

    final ScriptPinDescriptor? fromPin = _pinOf(fromDescriptor, edge.from.pin);
    final ScriptPinDescriptor? toPin = _pinOf(toDescriptor, edge.to.pin);
    if (fromPin == null) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '节点「${edge.from.node}」不存在引脚「${edge.from.pin}」',
          nodeId: edge.from.node,
          isError: true,
        ),
      );
    }
    if (toPin == null) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '节点「${edge.to.node}」不存在引脚「${edge.to.pin}」',
          nodeId: edge.to.node,
          isError: true,
        ),
      );
    }
    if (fromPin == null || toPin == null) {
      return;
    }
    if (fromPin.isInput) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '边端点「${edge.from.node}.${edge.from.pin}」不是输出引脚',
          nodeId: edge.from.node,
          isError: true,
        ),
      );
      return;
    }
    if (!toPin.isInput) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '边端点「${edge.to.node}.${edge.to.pin}」不是输入引脚',
          nodeId: edge.to.node,
          isError: true,
        ),
      );
      return;
    }

    final PinKey fromKey = (nodeId: edge.from.node, pinId: edge.from.pin);
    final PinKey toKey = (nodeId: edge.to.node, pinId: edge.to.pin);
    facts.connectedOutputs.add(fromKey);
    facts.connectedInputs.add(toKey);
    facts.connectionCounts.update(
      fromKey,
      (int count) => count + 1,
      ifAbsent: () => 1,
    );
    facts.connectionCounts.update(
      toKey,
      (int count) => count + 1,
      ifAbsent: () => 1,
    );
    facts.pinByKey[fromKey] = fromPin;
    facts.pinByKey[toKey] = toPin;

    if (fromPin.kind != toPin.kind) {
      diagnostics.add(
        ScriptDiagnostic(
          message:
              '引脚种类不匹配：「${edge.from.node}.${edge.from.pin}」为${_kindLabel(fromPin.kind)}引脚，'
              '「${edge.to.node}.${edge.to.pin}」为${_kindLabel(toPin.kind)}引脚',
          nodeId: edge.to.node,
          isError: true,
        ),
      );
      return;
    }
    if (fromPin.kind == ScriptPinKind.exec) {
      facts.execEdges
          .putIfAbsent(edge.from.node, () => <String>[])
          .add(edge.to.node);
      return;
    }
    if (fromPin.dataType != toPin.dataType) {
      diagnostics.add(
        ScriptDiagnostic(
          message:
              '数据类型不匹配：「${edge.from.node}.${edge.from.pin}」输出 ${_dataTypeLabel(fromPin.dataType)}，'
              '「${edge.to.node}.${edge.to.pin}」需要 ${_dataTypeLabel(toPin.dataType)}',
          nodeId: edge.to.node,
          isError: true,
        ),
      );
    }
    facts.dataEdges
        .putIfAbsent(edge.from.node, () => <String>[])
        .add(edge.to.node);
    facts.reverseDataEdges
        .putIfAbsent(edge.to.node, () => <String>[])
        .add(edge.from.node);
  }

  static void _validateMultipleConnections(
    _GraphFacts facts,
    List<ScriptDiagnostic> diagnostics,
  ) {
    for (final MapEntry<PinKey, int> entry in facts.connectionCounts.entries) {
      if (entry.value < 2) {
        continue;
      }
      final ScriptPinDescriptor pin = facts.pinByKey[entry.key]!;
      if (pin.kind == ScriptPinKind.data && !pin.isInput) {
        continue; // 数据输出允许扇出
      }
      final String role;
      if (pin.kind == ScriptPinKind.exec) {
        role = pin.isInput ? '执行输入' : '执行输出';
      } else {
        role = pin.isInput ? '数据输入' : '数据输出';
      }
      diagnostics.add(
        ScriptDiagnostic(
          message:
              '$role「${entry.key.nodeId}.${entry.key.pinId}」被 ${entry.value} 条边连接',
          nodeId: entry.key.nodeId,
          isError: true,
        ),
      );
    }
  }

  static void _validateRequiredInputs(
    List<ScriptNodeModel> nodes,
    Map<String, ScriptNodeTypeDescriptor> descriptorById,
    _GraphFacts facts,
    List<ScriptDiagnostic> diagnostics,
  ) {
    for (final ScriptNodeModel node in nodes) {
      final ScriptNodeTypeDescriptor? descriptor = descriptorById[node.id];
      if (descriptor == null) {
        continue;
      }
      for (final ScriptPinDescriptor pin in descriptor.pins) {
        if (!pin.isInput || !pin.required) {
          continue;
        }
        if (facts.connectedInputs.contains((nodeId: node.id, pinId: pin.id))) {
          continue;
        }
        diagnostics.add(
          ScriptDiagnostic(
            message: '节点「${node.id}」的必填输入「${pin.label}」未连接',
            nodeId: node.id,
            isError: true,
          ),
        );
      }
    }
  }

  static void _validateCycles(
    List<ScriptNodeModel> nodes,
    _GraphFacts facts,
    List<ScriptDiagnostic> diagnostics,
  ) {
    final List<String> nodeIds = <String>[
      for (final ScriptNodeModel node in nodes) node.id,
    ];
    final String? execCycle = _findCycle(facts.execEdges, nodeIds);
    if (execCycle != null) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '执行连接存在环（节点「$execCycle」）',
          nodeId: execCycle,
          isError: true,
        ),
      );
    }
    final String? dataCycle = _findCycle(facts.dataEdges, nodeIds);
    if (dataCycle != null) {
      diagnostics.add(
        ScriptDiagnostic(
          message: '数据连接存在环（节点「$dataCycle」）',
          nodeId: dataCycle,
          isError: true,
        ),
      );
    }
  }

  static void _validateWarnings(
    List<ScriptNodeModel> nodes,
    Map<String, ScriptNodeTypeDescriptor> descriptorById,
    _GraphFacts facts,
    List<ScriptDiagnostic> diagnostics,
  ) {
    for (final ScriptNodeModel node in nodes) {
      final ScriptNodeTypeDescriptor? descriptor = descriptorById[node.id];
      if (descriptor == null ||
          _hasConnectedOutput(descriptor, node.id, facts)) {
        continue;
      }
      if (descriptor.typeKey == entryTypeKey) {
        diagnostics.add(
          ScriptDiagnostic(
            message: '入口节点「${node.id}」的输出未连接',
            nodeId: node.id,
            isError: false,
          ),
        );
      } else if (descriptor.typeKey == _branchTypeKey) {
        diagnostics.add(
          ScriptDiagnostic(
            message: '分支节点「${node.id}」的两个出口均未连接',
            nodeId: node.id,
            isError: false,
          ),
        );
      }
    }

    final Set<String> activeNodes = _collectActiveNodes(nodes, facts);
    for (final ScriptNodeModel node in nodes) {
      final ScriptNodeTypeDescriptor? descriptor = descriptorById[node.id];
      if (descriptor == null || !_isPureDataNode(descriptor)) {
        continue;
      }
      if (activeNodes.contains(node.id)) {
        continue;
      }
      diagnostics.add(
        ScriptDiagnostic(
          message: '数据节点「${node.id}」（${descriptor.displayName}）未被使用，不参与脚本生成',
          nodeId: node.id,
          isError: false,
        ),
      );
    }
  }

  static ScriptPinDescriptor? _pinOf(
    ScriptNodeTypeDescriptor descriptor,
    String pinId,
  ) {
    for (final ScriptPinDescriptor pin in descriptor.pins) {
      if (pin.id == pinId) {
        return pin;
      }
    }
    return null;
  }

  static bool _hasConnectedOutput(
    ScriptNodeTypeDescriptor descriptor,
    String nodeId,
    _GraphFacts facts,
  ) {
    for (final ScriptPinDescriptor pin in descriptor.pins) {
      if (!pin.isInput &&
          facts.connectedOutputs.contains((nodeId: nodeId, pinId: pin.id))) {
        return true;
      }
    }
    return false;
  }

  static bool _isPureDataNode(ScriptNodeTypeDescriptor descriptor) {
    return descriptor.pins.isNotEmpty &&
        descriptor.pins.every(
          (ScriptPinDescriptor pin) => pin.kind == ScriptPinKind.data,
        );
  }

  static Set<String> _collectActiveNodes(
    List<ScriptNodeModel> nodes,
    _GraphFacts facts,
  ) {
    final Set<String> active = <String>{};
    final List<String> queue = <String>[];
    for (final ScriptNodeModel node in nodes) {
      if (node.type == entryTypeKey) {
        active.add(node.id);
        queue.add(node.id);
      }
    }
    int queueIndex = 0;
    while (queueIndex < queue.length) {
      final String current = queue[queueIndex];
      queueIndex++;
      final List<String> execNext =
          facts.execEdges[current] ?? const <String>[];
      final List<String> dataPrevious =
          facts.reverseDataEdges[current] ?? const <String>[];
      for (final String next in <String>[...execNext, ...dataPrevious]) {
        if (active.add(next)) {
          queue.add(next);
        }
      }
    }
    return active;
  }

  static String? _findCycle(
    Map<String, List<String>> adjacency,
    List<String> nodeIds,
  ) {
    final Set<String> visited = <String>{};
    for (final String root in nodeIds) {
      if (visited.contains(root)) {
        continue;
      }
      visited.add(root);
      final Set<String> inStack = <String>{root};
      final List<(String, int)> stack = <(String, int)>[(root, 0)];
      while (stack.isNotEmpty) {
        final (String node, int index) = stack.last;
        final List<String> neighbors = adjacency[node] ?? const <String>[];
        if (index >= neighbors.length) {
          stack.removeLast();
          inStack.remove(node);
          continue;
        }
        stack[stack.length - 1] = (node, index + 1);
        final String next = neighbors[index];
        if (inStack.contains(next)) {
          return next;
        }
        if (visited.contains(next)) {
          continue;
        }
        visited.add(next);
        inStack.add(next);
        stack.add((next, 0));
      }
    }
    return null;
  }

  static String _kindLabel(ScriptPinKind kind) {
    return kind == ScriptPinKind.exec ? '执行' : '数据';
  }

  static String _dataTypeLabel(ScriptDataType? dataType) {
    return switch (dataType) {
      ScriptDataType.string => 'string',
      ScriptDataType.boolean => 'bool',
      ScriptDataType.listString => 'list<string>',
      ScriptDataType.number => '数值',
      null => '未知类型',
    };
  }
}

class _GraphFacts {
  final Set<PinKey> connectedInputs = <PinKey>{};
  final Set<PinKey> connectedOutputs = <PinKey>{};
  final Map<PinKey, int> connectionCounts = <PinKey, int>{};
  final Map<PinKey, ScriptPinDescriptor> pinByKey =
      <PinKey, ScriptPinDescriptor>{};
  final Map<String, List<String>> execEdges = <String, List<String>>{};
  final Map<String, List<String>> dataEdges = <String, List<String>>{};
  final Map<String, List<String>> reverseDataEdges = <String, List<String>>{};
}
