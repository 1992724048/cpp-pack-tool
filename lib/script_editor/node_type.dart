enum ScriptPinKind { exec, data }

enum ScriptDataType { string, boolean, listString, number }

enum ScriptNodeCategory {
  flow('流控'),
  file('文件'),
  process('进程'),
  context('上下文'),
  value('常量'),
  string('字符串'),
  log('日志'),
  logic('逻辑'),
  math('数值'),
  crypto('编码与安全'),
  variable('变量');

  const ScriptNodeCategory(this.label);

  final String label;
}

enum ScriptParamType {
  text,
  boolean,
  macroKey,
  logLevel,
  stringOperator,
  packageFilePath,
  number,
  mathOperator,
  bitwiseOperator,
  numberOperator,
  hashAlgorithm,
}

class ScriptPinDescriptor {
  const ScriptPinDescriptor({
    required this.id,
    required this.label,
    required this.isInput,
    this.kind = ScriptPinKind.data,
    this.dataType,
    this.required = false,
  });

  final String id;
  final String label;
  final bool isInput;
  final ScriptPinKind kind;
  final ScriptDataType? dataType;
  final bool required;
}

class ScriptParamDescriptor {
  const ScriptParamDescriptor({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
  });

  final String key;
  final String label;
  final ScriptParamType type;
  final Object? defaultValue;
}

class ScriptNodeTypeDescriptor {
  const ScriptNodeTypeDescriptor({
    required this.typeKey,
    required this.displayName,
    required this.category,
    required this.pins,
    this.params = const <ScriptParamDescriptor>[],
  });

  final String typeKey;
  final String displayName;
  final ScriptNodeCategory category;
  final List<ScriptPinDescriptor> pins;
  final List<ScriptParamDescriptor> params;
}
