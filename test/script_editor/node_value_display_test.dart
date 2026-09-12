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

    test('mathOperator 输出中文运算符（加/减/乘/除/取模）', () {
      expect(paramValueText(_param(ScriptParamType.mathOperator), 'add'), '加');
      expect(
        paramValueText(_param(ScriptParamType.mathOperator), 'subtract'),
        '减',
      );
      expect(
        paramValueText(_param(ScriptParamType.mathOperator), 'multiply'),
        '乘',
      );
      expect(
        paramValueText(_param(ScriptParamType.mathOperator), 'divide'),
        '除',
      );
      expect(
        paramValueText(_param(ScriptParamType.mathOperator), 'modulo'),
        '取模',
      );
    });

    test('bitwiseOperator 输出中文运算符（与/或/异或/左移/右移）', () {
      expect(
        paramValueText(_param(ScriptParamType.bitwiseOperator), 'and'),
        '与',
      );
      expect(
        paramValueText(_param(ScriptParamType.bitwiseOperator), 'or'),
        '或',
      );
      expect(
        paramValueText(_param(ScriptParamType.bitwiseOperator), 'xor'),
        '异或',
      );
      expect(
        paramValueText(_param(ScriptParamType.bitwiseOperator), 'shiftLeft'),
        '左移',
      );
      expect(
        paramValueText(_param(ScriptParamType.bitwiseOperator), 'shiftRight'),
        '右移',
      );
    });

    test('numberOperator 输出比较符号（< ≤ > ≥ = ≠）', () {
      expect(paramValueText(_param(ScriptParamType.numberOperator), 'lt'), '<');
      expect(paramValueText(_param(ScriptParamType.numberOperator), 'le'), '≤');
      expect(paramValueText(_param(ScriptParamType.numberOperator), 'gt'), '>');
      expect(paramValueText(_param(ScriptParamType.numberOperator), 'ge'), '≥');
      expect(paramValueText(_param(ScriptParamType.numberOperator), 'eq'), '=');
      expect(paramValueText(_param(ScriptParamType.numberOperator), 'ne'), '≠');
    });

    test('hashAlgorithm 输出算法显示名（SHA256/SHA1/SHA512/MD5/CRC32）', () {
      expect(
        paramValueText(_param(ScriptParamType.hashAlgorithm), 'sha256'),
        'SHA256',
      );
      expect(
        paramValueText(_param(ScriptParamType.hashAlgorithm), 'sha1'),
        'SHA1',
      );
      expect(
        paramValueText(_param(ScriptParamType.hashAlgorithm), 'sha512'),
        'SHA512',
      );
      expect(
        paramValueText(_param(ScriptParamType.hashAlgorithm), 'md5'),
        'MD5',
      );
      expect(
        paramValueText(_param(ScriptParamType.hashAlgorithm), 'crc32'),
        'CRC32',
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

    test('未识别值回退原文（logLevel / stringOperator / 4 新类型）', () {
      expect(paramValueText(_param(ScriptParamType.logLevel), 'debug'), 'debug');
      expect(
        paramValueText(_param(ScriptParamType.stringOperator), 'startsWith'),
        'startsWith',
      );
      expect(
        paramValueText(_param(ScriptParamType.mathOperator), 'pow'),
        'pow',
      );
      expect(
        paramValueText(_param(ScriptParamType.bitwiseOperator), 'nand'),
        'nand',
      );
      expect(
        paramValueText(_param(ScriptParamType.numberOperator), 'bogus'),
        'bogus',
      );
      expect(
        paramValueText(_param(ScriptParamType.hashAlgorithm), 'sha3'),
        'sha3',
      );
    });

    test('非字符串值以 toString 输出（兜底路径）', () {
      expect(paramValueText(_param(ScriptParamType.text), 42), '42');
      expect(paramValueText(_param(ScriptParamType.number), '5'), '5');
      expect(paramValueText(_param(ScriptParamType.boolean), 'true'), '否');
    });

    // ScriptParamType 为封闭枚举，`paramValueText` 的 switch 已按全部枚举值
    // 穷尽（编译期强制），未知类型值无法构造；「未识别值回退原文」用例覆盖
    // 值不在已知集合时的运行时兜底。
  });

  group('公共标签 map', () {
    test('逐 map 锁定键序与显示文本', () {
      expect(logLevelLabels, <String, String>{
        'info': '信息',
        'warn': '警告',
        'error': '错误',
      });
      expect(stringOperatorLabels, <String, String>{
        'eq': '等于',
        'ne': '不等于',
        'contains': '包含',
      });
      expect(mathOperatorLabels, <String, String>{
        'add': '加',
        'subtract': '减',
        'multiply': '乘',
        'divide': '除',
        'modulo': '取模',
      });
      expect(bitwiseOperatorLabels, <String, String>{
        'and': '与',
        'or': '或',
        'xor': '异或',
        'shiftLeft': '左移',
        'shiftRight': '右移',
      });
      expect(numberOperatorLabels, <String, String>{
        'lt': '<',
        'le': '≤',
        'gt': '>',
        'ge': '≥',
        'eq': '=',
        'ne': '≠',
      });
      expect(hashAlgorithmLabels, <String, String>{
        'sha256': 'SHA256',
        'sha1': 'SHA1',
        'sha512': 'SHA512',
        'md5': 'MD5',
        'crc32': 'CRC32',
      });
    });

    test('值与 paramValueText 输出一致', () {
      for (final MapEntry<String, String> entry in mathOperatorLabels.entries) {
        expect(
          paramValueText(_param(ScriptParamType.mathOperator), entry.key),
          entry.value,
        );
      }
      for (final MapEntry<String, String> entry
          in bitwiseOperatorLabels.entries) {
        expect(
          paramValueText(_param(ScriptParamType.bitwiseOperator), entry.key),
          entry.value,
        );
      }
      for (final MapEntry<String, String> entry
          in numberOperatorLabels.entries) {
        expect(
          paramValueText(_param(ScriptParamType.numberOperator), entry.key),
          entry.value,
        );
      }
      for (final MapEntry<String, String> entry
          in hashAlgorithmLabels.entries) {
        expect(
          paramValueText(_param(ScriptParamType.hashAlgorithm), entry.key),
          entry.value,
        );
      }
    });
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
