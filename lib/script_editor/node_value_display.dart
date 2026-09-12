import 'package:cpp_nuget_pack/script_editor/node_type.dart';

const String _emptySummary = '—';

const Map<String, String> _logLevelLabels = <String, String>{
  'info': '信息',
  'warn': '警告',
  'error': '错误',
};

const Map<String, String> _stringOperatorLabels = <String, String>{
  'eq': '等于',
  'ne': '不等于',
  'contains': '包含',
};

/// 参数值 → 值条显示文本（null → `''`）。
///
/// `logLevel`/`stringOperator` 使用检查器同款中文标签；未识别的值回退原文。
/// 后续阶段新增参数类型时在此扩展。
String paramValueText(ScriptParamDescriptor param, Object? value) {
  if (value == null) {
    return '';
  }
  return switch (param.type) {
    ScriptParamType.boolean => value == true ? '是' : '否',
    ScriptParamType.macroKey => '\$($value)',
    ScriptParamType.logLevel => _logLevelLabels[value] ?? value.toString(),
    ScriptParamType.stringOperator =>
      _stringOperatorLabels[value] ?? value.toString(),
    // number / text / packageFilePath 与未知类型同为原文输出；显式列举后再
    // 保留兜底分支会触发 unreachable_switch_case，与 analyze 零问题门禁冲突。
    _ => value.toString(),
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
