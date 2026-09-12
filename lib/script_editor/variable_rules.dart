import 'dart:collection';

/// 脚本变量节点 typeKey → 类型变体（number|string）：校验器「同名同类型」
/// 规则与生成器首见归一口径一致（首个出现节点的变体为准，后续异变体报错）。
const Map<String, String> variableTypeVariants = <String, String>{
  'variable.setNumber': 'number',
  'variable.getNumber': 'number',
  'variable.setString': 'string',
  'variable.getString': 'string',
};

/// 变量名（`name` 参数）适用名称校验的节点类型：环境变量 + 全部脚本变量
/// 节点；自 [variableTypeVariants] 派生，避免与校验器集合漂移。
final Set<String> variableNameNodeTypes = UnmodifiableSetView<String>(<String>{
  'context.environment',
  ...variableTypeVariants.keys,
});
