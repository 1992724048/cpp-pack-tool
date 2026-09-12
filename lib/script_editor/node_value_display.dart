import 'package:cpp_nuget_pack/script_editor/node_type.dart';

const String _emptySummary = '—';

/// 日志级别 → 中文标签（检查器 ComboBox 与值条共用）。
const Map<String, String> logLevelLabels = <String, String>{
  'info': '信息',
  'warn': '警告',
  'error': '错误',
};

/// 字符串运算符 → 中文标签（检查器 ComboBox 与值条共用）。
const Map<String, String> stringOperatorLabels = <String, String>{
  'eq': '等于',
  'ne': '不等于',
  'contains': '包含',
};

/// 算术运算符 → 中文标签（检查器 ComboBox 与值条共用）。
const Map<String, String> mathOperatorLabels = <String, String>{
  'add': '加',
  'subtract': '减',
  'multiply': '乘',
  'divide': '除',
  'modulo': '取模',
};

/// 位运算符 → 中文标签（检查器 ComboBox 与值条共用）。
const Map<String, String> bitwiseOperatorLabels = <String, String>{
  'and': '与',
  'or': '或',
  'xor': '异或',
  'shiftLeft': '左移',
  'shiftRight': '右移',
};

/// 数值比较运算符 → 符号标签（检查器 ComboBox 与值条共用）。
const Map<String, String> numberOperatorLabels = <String, String>{
  'lt': '<',
  'le': '≤',
  'gt': '>',
  'ge': '≥',
  'eq': '=',
  'ne': '≠',
};

/// 哈希算法 → 显示名（检查器 ComboBox 与值条共用）。
const Map<String, String> hashAlgorithmLabels = <String, String>{
  'sha256': 'SHA256',
  'sha1': 'SHA1',
  'sha512': 'SHA512',
  'md5': 'MD5',
  'crc32': 'CRC32',
};

/// 参数值 → 值条显示文本（null → `''`）。
///
/// 按 [ScriptParamType] 穷尽分派（新增类型由编译期强制补齐）：标签类取对应
/// 公共标签 map 并在值不在已知集合时回退原文；其余类型输出原文。
String paramValueText(ScriptParamDescriptor param, Object? value) {
  if (value == null) {
    return '';
  }
  return switch (param.type) {
    ScriptParamType.text => value.toString(),
    ScriptParamType.boolean => value == true ? '是' : '否',
    ScriptParamType.macroKey => '\$($value)',
    ScriptParamType.logLevel => logLevelLabels[value] ?? value.toString(),
    ScriptParamType.stringOperator =>
      stringOperatorLabels[value] ?? value.toString(),
    ScriptParamType.packageFilePath => value.toString(),
    ScriptParamType.number => value.toString(),
    ScriptParamType.mathOperator =>
      mathOperatorLabels[value] ?? value.toString(),
    ScriptParamType.bitwiseOperator =>
      bitwiseOperatorLabels[value] ?? value.toString(),
    ScriptParamType.numberOperator =>
      numberOperatorLabels[value] ?? value.toString(),
    ScriptParamType.hashAlgorithm =>
      hashAlgorithmLabels[value] ?? value.toString(),
  };
}

/// 值条单点口径：按注册表序拼接各参数显示文本（` · ` 分隔，跳过空文本）；
/// 汇总为空时返回 `—`。
String nodeValueSummary(
  List<ScriptParamDescriptor> params,
  Map<String, Object?> values,
) {
  final List<String> parts = <String>[];
  for (final ScriptParamDescriptor param in params) {
    final String text = paramValueText(
      param,
      values[param.key] ?? param.defaultValue,
    );
    if (text.isEmpty) {
      continue;
    }
    parts.add(text);
  }
  return parts.isEmpty ? _emptySummary : parts.join(' · ');
}
