import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/node_value_display.dart';
import 'package:flutter_test/flutter_test.dart';

ScriptParamDescriptor _param(
  ScriptParamType type, {
  String key = 'value',
  Object? defaultValue,
}) {
  return ScriptParamDescriptor(
    key: key,
    label: '参数',
    type: type,
    defaultValue: defaultValue,
  );
}

void main() {
  group('paramValueText', () {
    test('null 对任意类型均返回空文本', () {
      for (final ScriptParamType type in ScriptParamType.values) {
        expect(paramValueText(_param(type), null), '', reason: '$type');
      }
    });

    test('number 输出数字文本（int 不带小数、double 保留小数）', () {
      expect(paramValueText(_param(ScriptParamType.number), 5), '5');
      expect(paramValueText(_param(ScriptParamType.number), 5.5), '5.5');
      expect(paramValueText(_param(ScriptParamType.number), -3), '-3');
    });

    test('boolean 输出 是/否', () {
      expect(paramValueText(_param(ScriptParamType.boolean), true), '是');
      expect(paramValueText(_param(ScriptParamType.boolean), false), '否');
    });

    test('macroKey 输出 \$(Name)', () {
      expect(
        paramValueText(_param(ScriptParamType.macroKey), 'OutDir'),
        r'$(OutDir)',
      );
      expect(
        paramValueText(
          _param(ScriptParamType.macroKey),
          'MSBuildThisFileDirectory',
        ),
        r'$(MSBuildThisFileDirectory)',
      );
    });

    test('text 输出原值（不做 trim）', () {
      expect(
        paramValueText(_param(ScriptParamType.text), ' hello world '),
        ' hello world ',
      );
    });

    test('logLevel 输出检查器同款中文标签', () {
      expect(paramValueText(_param(ScriptParamType.logLevel), 'info'), '信息');
      expect(paramValueText(_param(ScriptParamType.logLevel), 'warn'), '警告');
      expect(paramValueText(_param(ScriptParamType.logLevel), 'error'), '错误');
    });

    test('stringOperator 输出检查器同款中文标签', () {
      expect(
        paramValueText(_param(ScriptParamType.stringOperator), 'eq'),
        '等于',
      );
      expect(
        paramValueText(_param(ScriptParamType.stringOperator), 'ne'),
        '不等于',
      );
      expect(
        paramValueText(_param(ScriptParamType.stringOperator), 'contains'),
        '包含',
      );
    });

    test('packageFilePath 输出原样', () {
      expect(
        paramValueText(
          _param(ScriptParamType.packageFilePath),
          r'files\build\x64\Release\app.exe',
        ),
        r'files\build\x64\Release\app.exe',
      );
    });

    test('未识别值回退原文（logLevel / stringOperator）', () {
      expect(paramValueText(_param(ScriptParamType.logLevel), 'debug'), 'debug');
      expect(
        paramValueText(_param(ScriptParamType.stringOperator), 'startsWith'),
        'startsWith',
      );
    });

    test('非字符串值以 toString 输出（兜底路径）', () {
      expect(paramValueText(_param(ScriptParamType.text), 42), '42');
      expect(paramValueText(_param(ScriptParamType.number), '5'), '5');
      expect(paramValueText(_param(ScriptParamType.boolean), 'true'), '否');
    });

    // 未知类型的兜底（原文输出）随后续阶段扩展枚举时生效：ScriptParamType 为
    // 封闭枚举，测试期无法构造未知类型值，故以未识别值/混合值的回退覆盖同一
    // 兜底语义（见 node_value_display.dart 的 wildcard 分支）。
  });

  group('nodeValueSummary', () {
    test('按参数声明序拼接并以「 · 」分隔，值优先于默认值', () {
      final List<ScriptParamDescriptor> params = <ScriptParamDescriptor>[
        _param(ScriptParamType.text, key: 'message', defaultValue: ''),
        _param(ScriptParamType.boolean, key: 'enabled', defaultValue: true),
        _param(ScriptParamType.macroKey, key: 'macro', defaultValue: 'OutDir'),
      ];
      expect(
        nodeValueSummary(params, <String, Object?>{'message': '开始构建'}),
        r'开始构建 · 是 · $(OutDir)',
      );
    });

    test('缺失键回退 defaultValue', () {
      final List<ScriptParamDescriptor> params = <ScriptParamDescriptor>[
        _param(ScriptParamType.text, key: 'first', defaultValue: '默认一'),
        _param(ScriptParamType.text, key: 'second', defaultValue: '默认二'),
      ];
      expect(nodeValueSummary(params, <String, Object?>{'first': '实际一'}), '实际一 · 默认二');
    });

    test('空文本跳过（含显式空串覆盖非空默认值）', () {
      final List<ScriptParamDescriptor> params = <ScriptParamDescriptor>[
        _param(ScriptParamType.text, key: 'empty', defaultValue: '默认'),
        _param(ScriptParamType.boolean, key: 'flag', defaultValue: false),
      ];
      expect(nodeValueSummary(params, <String, Object?>{'empty': ''}), '否');
    });

    test('缺值且默认值为 null 时不参与拼接', () {
      final List<ScriptParamDescriptor> params = <ScriptParamDescriptor>[
        _param(ScriptParamType.text, key: 'missing'),
        _param(ScriptParamType.boolean, key: 'flag', defaultValue: true),
      ];
      expect(nodeValueSummary(params, const <String, Object?>{}), '是');
    });

    test('汇总为空返回「—」（无参数 / 全空）', () {
      expect(
        nodeValueSummary(const <ScriptParamDescriptor>[], const <String, Object?>{}),
        '—',
      );
      expect(
        nodeValueSummary(
          <ScriptParamDescriptor>[
            _param(ScriptParamType.text, key: 'a', defaultValue: ''),
          ],
          const <String, Object?>{'a': ''},
        ),
        '—',
      );
    });

    test('values 中不属于参数的键被忽略', () {
      final List<ScriptParamDescriptor> params = <ScriptParamDescriptor>[
        _param(ScriptParamType.text, key: 'a', defaultValue: '甲'),
      ];
      expect(nodeValueSummary(params, <String, Object?>{'b': '乙'}), '甲');
    });
  });
}
