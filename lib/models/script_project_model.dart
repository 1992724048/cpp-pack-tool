import 'package:cpp_nuget_pack/models/build_model.dart';

enum ScriptTrigger { pre, post }

class ScriptEdgeEndpoint {
  const ScriptEdgeEndpoint({required this.node, required this.pin});

  final String node;
  final String pin;
}

class ScriptNodeModel {
  ScriptNodeModel({
    required this.id,
    required this.type,
    this.x = 0,
    this.y = 0,
  });

  String id;
  String type;
  double x;
  double y;
  Map<String, Object?> params = <String, Object?>{};
}

class ScriptEdgeModel {
  ScriptEdgeModel({required this.from, required this.to});

  final ScriptEdgeEndpoint from;
  final ScriptEdgeEndpoint to;
}

class ScriptProjectModel {
  ScriptProjectModel({
    required this.id,
    required this.name,
    required this.trigger,
    this.buildModel = BuildModel.all,
  });

  final String id;
  final String name;
  final ScriptTrigger trigger;
  final BuildModel buildModel;

  List<ScriptNodeModel> nodes = <ScriptNodeModel>[];
  List<ScriptEdgeModel> edges = <ScriptEdgeModel>[];
  double viewX = 0;
  double viewY = 0;
  double viewScale = 1.0;

  Map<String, Object?> toMap() => <String, Object?>{
    'version': 1,
    'id': id,
    'name': name,
    'trigger': trigger.name,
    'buildModel': buildModel.name,
    'nodes': <Map<String, Object?>>[
      for (final ScriptNodeModel node in nodes) _nodeToMap(node),
    ],
    'edges': <Map<String, Object?>>[
      for (final ScriptEdgeModel edge in edges) _edgeToMap(edge),
    ],
    'viewport': <String, Object?>{'x': viewX, 'y': viewY, 'scale': viewScale},
  };

  factory ScriptProjectModel.fromMap(
    Map<String, Object?> map, {
    List<String>? warnings,
  }) {
    final ScriptProjectModel project = ScriptProjectModel(
      id: _requiredString(map, 'id'),
      name: _requiredString(map, 'name'),
      trigger: _triggerFromName(map['trigger']),
      buildModel: BuildModel.fromName(map['buildModel']),
    );

    final Set<String> nodeIds = <String>{};
    for (final Object? item in _listOrEmpty(map, 'nodes')) {
      final ScriptNodeModel? node = _nodeFromItem(item);
      if (node == null) {
        continue;
      }
      if (!nodeIds.add(node.id)) {
        warnings?.add('脚本「${project.id}」节点 id 重复，已丢弃：${node.id}');
        continue;
      }
      project.nodes.add(node);
    }

    for (final Object? item in _listOrEmpty(map, 'edges')) {
      final ScriptEdgeModel? edge = _edgeFromItem(item);
      if (edge == null) {
        continue;
      }
      if (!nodeIds.contains(edge.from.node) ||
          !nodeIds.contains(edge.to.node)) {
        continue;
      }
      project.edges.add(edge);
    }

    final Object? viewport = map['viewport'];
    if (viewport is Map) {
      final Map<String, Object?> values = _stringKeyMap(viewport);
      project.viewX = _doubleOr(values['x'], 0);
      project.viewY = _doubleOr(values['y'], 0);
      project.viewScale = _doubleOr(values['scale'], 1.0);
    }
    return project;
  }
}

ScriptTrigger _triggerFromName(Object? value) {
  if (value is! String) {
    throw const FormatException('脚本缺少 trigger 字段');
  }
  for (final ScriptTrigger trigger in ScriptTrigger.values) {
    if (trigger.name == value) {
      return trigger;
    }
  }
  throw FormatException('脚本 trigger 字段值非法：$value');
}

String _requiredString(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value == null || (value is String && value.isEmpty)) {
    throw FormatException('脚本缺少 $key 字段');
  }
  if (value is! String) {
    throw FormatException('脚本 $key 字段类型错误，应为字符串');
  }
  return value;
}

List<Object?> _listOrEmpty(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value == null) {
    return const <Object?>[];
  }
  if (value is! List) {
    throw FormatException('脚本 $key 字段类型错误，应为列表');
  }
  return value;
}

ScriptNodeModel? _nodeFromItem(Object? item) {
  if (item is! Map) {
    return null;
  }
  final Map<String, Object?> nodeMap = _stringKeyMap(item);
  final Object? id = nodeMap['id'];
  final Object? type = nodeMap['type'];
  if (id is! String || id.isEmpty || type is! String || type.isEmpty) {
    return null;
  }
  final ScriptNodeModel node = ScriptNodeModel(id: id, type: type);
  node.x = _doubleOr(nodeMap['x'], 0);
  node.y = _doubleOr(nodeMap['y'], 0);
  node.params = _filteredParams(nodeMap['params']);
  return node;
}

ScriptEdgeModel? _edgeFromItem(Object? item) {
  if (item is! Map) {
    return null;
  }
  final Map<String, Object?> edgeMap = _stringKeyMap(item);
  final ScriptEdgeEndpoint? from = _endpointFromItem(edgeMap['from']);
  final ScriptEdgeEndpoint? to = _endpointFromItem(edgeMap['to']);
  if (from == null || to == null) {
    return null;
  }
  return ScriptEdgeModel(from: from, to: to);
}

ScriptEdgeEndpoint? _endpointFromItem(Object? item) {
  if (item is! Map) {
    return null;
  }
  final Map<String, Object?> endpointMap = _stringKeyMap(item);
  final Object? node = endpointMap['node'];
  final Object? pin = endpointMap['pin'];
  if (node is! String || node.isEmpty || pin is! String || pin.isEmpty) {
    return null;
  }
  return ScriptEdgeEndpoint(node: node, pin: pin);
}

Map<String, Object?> _nodeToMap(ScriptNodeModel node) => <String, Object?>{
  'id': node.id,
  'type': node.type,
  'x': node.x,
  'y': node.y,
  'params': _filteredParams(node.params),
};

Map<String, Object?> _edgeToMap(ScriptEdgeModel edge) => <String, Object?>{
  'from': <String, Object?>{'node': edge.from.node, 'pin': edge.from.pin},
  'to': <String, Object?>{'node': edge.to.node, 'pin': edge.to.pin},
};

Map<String, Object?> _filteredParams(Object? value) {
  if (value is! Map) {
    return <String, Object?>{};
  }
  final Map<String, Object?> params = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final Object? key = entry.key;
    final Object? filtered = _filteredParamValue(entry.value);
    if (key is String && filtered != null) {
      params[key] = filtered;
    }
  }
  return params;
}

Object? _filteredParamValue(Object? value) {
  if (value is String || value is bool || value is num) {
    return value;
  }
  if (value is List && value.every((Object? element) => element is String)) {
    return List<String>.of(value.cast<String>());
  }
  return null;
}

double _doubleOr(Object? value, double fallback) {
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

Map<String, Object?> _stringKeyMap(Map<Object?, Object?> map) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in map.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
