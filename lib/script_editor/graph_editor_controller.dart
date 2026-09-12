import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_validation.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:flutter/foundation.dart';

final RegExp _numberedNodeIdPattern = RegExp(r'^n(\d+)$');

/// 节点编辑器状态控制器：节点图、选中、视口与诊断的唯一状态源。
///
/// 图结构或参数变更后即时重算 [diagnostics]；实际变更均通知监听者。
class GraphEditorController extends ChangeNotifier {
  GraphEditorController(ScriptProjectModel project)
    : _project = project,
      _diagnostics = GraphValidator.validate(project);

  ScriptProjectModel _project;
  List<ScriptDiagnostic> _diagnostics;
  String? _selectedNodeId;
  ScriptEdgeModel? _selectedEdge;

  ScriptProjectModel get project => _project;

  List<ScriptDiagnostic> get diagnostics => _diagnostics;

  String? get selectedNodeId => _selectedNodeId;

  ScriptEdgeModel? get selectedEdge => _selectedEdge;

  /// 新增节点并返回其 id；params 取注册表默认值。
  ///
  /// [typeKey] 无对应注册项时抛 [ArgumentError]。
  String addNode(String typeKey, Offset scenePosition) {
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(typeKey);
    if (descriptor == null) {
      throw ArgumentError.value(typeKey, 'typeKey', '未知节点类型');
    }
    final ScriptNodeModel node = ScriptNodeModel(
      id: _nextNodeId(),
      type: typeKey,
      x: scenePosition.dx,
      y: scenePosition.dy,
    );
    for (final ScriptParamDescriptor param in descriptor.params) {
      final Object? defaultValue = param.defaultValue;
      if (defaultValue != null) {
        node.params[param.key] = defaultValue;
      }
    }
    _project.nodes.add(node);
    _refreshDiagnostics();
    notifyListeners();
    return node.id;
  }

  /// 删除节点及其全部相邻边；相关选中一并清除。
  void removeNode(String nodeId) {
    final int index = _project.nodes.indexWhere(
      (ScriptNodeModel node) => node.id == nodeId,
    );
    if (index < 0) {
      return;
    }
    _project.nodes.removeAt(index);
    _project.edges.removeWhere(
      (ScriptEdgeModel edge) =>
          edge.from.node == nodeId || edge.to.node == nodeId,
    );
    _pruneSelection();
    _refreshDiagnostics();
    notifyListeners();
  }

  /// 写入节点场景坐标；负坐标 clamp 到 0（与节点库/菜单落点口径一致）。
  void moveNode(String nodeId, Offset scenePosition) {
    final ScriptNodeModel? node = _findNode(nodeId);
    if (node == null) {
      return;
    }
    final double x = math.max(0, scenePosition.dx);
    final double y = math.max(0, scenePosition.dy);
    if (node.x == x && node.y == y) {
      return;
    }
    node.x = x;
    node.y = y;
    notifyListeners();
  }

  /// 写入参数值；仅接受 String / bool / num / `List<String>`，其他类型忽略。
  void updateNodeParam(String nodeId, String paramKey, Object? value) {
    final ScriptNodeModel? node = _findNode(nodeId);
    if (node == null) {
      return;
    }
    final Object? accepted = _acceptedParamValue(value);
    if (accepted == null ||
        _isSameParamValue(node.params[paramKey], accepted)) {
      return;
    }
    node.params[paramKey] = accepted;
    _refreshDiagnostics();
    notifyListeners();
  }

  /// 建立连接：成功返回 null，占用引脚自动静默替换旧连接。
  ///
  /// 失败返回拒绝原因且不修改图；原因文案与视觉规范 §5.5 一致。
  String? connect({
    required ScriptEdgeEndpoint from,
    required ScriptEdgeEndpoint to,
  }) {
    final ScriptNodeModel? fromNode = _findNode(from.node);
    final ScriptNodeModel? toNode = _findNode(to.node);
    final ScriptPinDescriptor? fromPin = fromNode == null
        ? null
        : _pinOf(fromNode, from.pin);
    final ScriptPinDescriptor? toPin = toNode == null
        ? null
        : _pinOf(toNode, to.pin);
    if (fromPin == null || toPin == null) {
      return '无法连接：引脚不存在';
    }
    if (fromPin.isInput || !toPin.isInput) {
      return '无法连接：请从输出引脚拖向输入引脚';
    }
    if (from.node == to.node) {
      return '无法连接：不能连接到同一节点';
    }
    if (fromPin.kind != toPin.kind) {
      return '无法连接：目标引脚需要 ${_pinRequirementLabel(toPin)}';
    }
    if (fromPin.kind == ScriptPinKind.data &&
        fromPin.dataType != toPin.dataType) {
      return '无法连接：目标引脚需要 ${_pinRequirementLabel(toPin)}';
    }
    if (_hasEdge(from, to)) {
      return null;
    }
    _project.edges = _edgesWithReplacement(from, to, fromPin);
    _pruneSelection();
    _refreshDiagnostics();
    notifyListeners();
    return null;
  }

  void removeEdge(ScriptEdgeModel edge) {
    final int index = _edgeIndexOf(edge);
    if (index < 0) {
      return;
    }
    _project.edges.removeAt(index);
    _pruneSelection();
    _refreshDiagnostics();
    notifyListeners();
  }

  /// 删除当前选中的连线；无选中时无操作。
  void removeSelectedEdge() {
    final ScriptEdgeModel? edge = _selectedEdge;
    if (edge == null) {
      return;
    }
    _selectedEdge = null;
    final int index = _edgeIndexOf(edge);
    if (index >= 0) {
      _project.edges.removeAt(index);
    }
    _refreshDiagnostics();
    notifyListeners();
  }

  /// 选中节点；null 清空选中。与 [selectedEdge] 互斥。
  void selectNode(String? nodeId) {
    if (nodeId == null) {
      clearSelection();
      return;
    }
    if (_findNode(nodeId) == null || _selectedNodeId == nodeId) {
      return;
    }
    _selectedNodeId = nodeId;
    _selectedEdge = null;
    notifyListeners();
  }

  /// 选中连线；null 清空选中。与 [selectedNodeId] 互斥。
  void selectEdge(ScriptEdgeModel? edge) {
    if (edge == null) {
      clearSelection();
      return;
    }
    if (!_containsEdge(edge) || identical(_selectedEdge, edge)) {
      return;
    }
    _selectedEdge = edge;
    _selectedNodeId = null;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedNodeId == null && _selectedEdge == null) {
      return;
    }
    _selectedNodeId = null;
    _selectedEdge = null;
    notifyListeners();
  }

  void setViewport({
    required double x,
    required double y,
    required double scale,
  }) {
    if (_project.viewX == x &&
        _project.viewY == y &&
        _project.viewScale == scale) {
      return;
    }
    _project.viewX = x;
    _project.viewY = y;
    _project.viewScale = scale;
    notifyListeners();
  }

  /// 切换到 [next]：替换项目实例、清空选中并重算诊断。
  void loadProject(ScriptProjectModel next) {
    _project = next;
    _selectedNodeId = null;
    _selectedEdge = null;
    _refreshDiagnostics();
    notifyListeners();
  }

  String _nextNodeId() {
    int maxNumber = 0;
    for (final ScriptNodeModel node in _project.nodes) {
      final RegExpMatch? match = _numberedNodeIdPattern.firstMatch(node.id);
      if (match == null) {
        continue;
      }
      final int number = int.parse(match.group(1)!);
      if (number > maxNumber) {
        maxNumber = number;
      }
    }
    return 'n${maxNumber + 1}';
  }

  List<ScriptEdgeModel> _edgesWithReplacement(
    ScriptEdgeEndpoint from,
    ScriptEdgeEndpoint to,
    ScriptPinDescriptor fromPin,
  ) {
    final List<ScriptEdgeModel> edges = <ScriptEdgeModel>[];
    int insertIndex = -1;
    for (final ScriptEdgeModel edge in _project.edges) {
      final bool occupiesTarget = _sameEndpoint(edge.to, to);
      final bool occupiesSource =
          fromPin.kind == ScriptPinKind.exec && _sameEndpoint(edge.from, from);
      if (occupiesTarget || occupiesSource) {
        if (insertIndex < 0) {
          insertIndex = edges.length;
        }
        continue;
      }
      edges.add(edge);
    }
    edges.insert(
      insertIndex < 0 ? edges.length : insertIndex,
      ScriptEdgeModel(from: from, to: to),
    );
    return edges;
  }

  bool _hasEdge(ScriptEdgeEndpoint from, ScriptEdgeEndpoint to) {
    return _project.edges.any(
      (ScriptEdgeModel edge) =>
          _sameEndpoint(edge.from, from) && _sameEndpoint(edge.to, to),
    );
  }

  int _edgeIndexOf(ScriptEdgeModel edge) {
    for (int index = 0; index < _project.edges.length; index++) {
      if (identical(_project.edges[index], edge)) {
        return index;
      }
    }
    return _project.edges.indexWhere(
      (ScriptEdgeModel existing) =>
          _sameEndpoint(existing.from, edge.from) &&
          _sameEndpoint(existing.to, edge.to),
    );
  }

  ScriptNodeModel? _findNode(String nodeId) {
    for (final ScriptNodeModel node in _project.nodes) {
      if (node.id == nodeId) {
        return node;
      }
    }
    return null;
  }

  ScriptPinDescriptor? _pinOf(ScriptNodeModel node, String pinId) {
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    if (descriptor == null) {
      return null;
    }
    for (final ScriptPinDescriptor pin in descriptor.pins) {
      if (pin.id == pinId) {
        return pin;
      }
    }
    return null;
  }

  bool _containsEdge(ScriptEdgeModel edge) {
    return _project.edges.any(
      (ScriptEdgeModel existing) => identical(existing, edge),
    );
  }

  bool _sameEndpoint(ScriptEdgeEndpoint left, ScriptEdgeEndpoint right) {
    return left.node == right.node && left.pin == right.pin;
  }

  String _pinRequirementLabel(ScriptPinDescriptor pin) {
    if (pin.kind == ScriptPinKind.exec) {
      return '执行';
    }
    return switch (pin.dataType) {
      ScriptDataType.string => 'string',
      ScriptDataType.boolean => 'bool',
      ScriptDataType.listString => 'list<string>',
      null => '数据',
    };
  }

  Object? _acceptedParamValue(Object? value) {
    if (value is String || value is bool || value is num) {
      return value;
    }
    if (value is List && value.every((Object? item) => item is String)) {
      return List<String>.of(value.cast<String>());
    }
    return null;
  }

  bool _isSameParamValue(Object? current, Object? next) {
    if (current is List && next is List) {
      return listEquals(current, next);
    }
    return current == next;
  }

  void _pruneSelection() {
    if (_selectedNodeId != null && _findNode(_selectedNodeId!) == null) {
      _selectedNodeId = null;
    }
    final ScriptEdgeModel? selected = _selectedEdge;
    if (selected != null && !_containsEdge(selected)) {
      _selectedEdge = null;
    }
  }

  void _refreshDiagnostics() {
    _diagnostics = GraphValidator.validate(_project);
  }
}
