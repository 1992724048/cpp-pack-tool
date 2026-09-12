import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:flutter_test/flutter_test.dart';

const Set<String> _expectedTypeKeys = <String>{
  'flow.entry',
  'flow.branch',
  'flow.foreach',
  'flow.while',
  'file.copy',
  'file.move',
  'file.delete',
  'file.makeDirectory',
  'file.list',
  'file.exists',
  'process.run',
  'context.macro',
  'context.environment',
  'context.packageFile',
  'value.text',
  'value.boolean',
  'value.number',
  'string.concat',
  'string.replace',
  'string.lowerCase',
  'string.fileName',
  'string.directoryName',
  'path.join',
  'log.message',
  'logic.compareString',
  'logic.not',
};

ScriptParamDescriptor _param(String typeKey, String paramKey) {
  return NodeRegistry.byType(typeKey)!.params
      .singleWhere((ScriptParamDescriptor param) => param.key == paramKey);
}

ScriptPinDescriptor _pin(String typeKey, String pinId) {
  return NodeRegistry.byType(typeKey)!.pins
      .singleWhere((ScriptPinDescriptor pin) => pin.id == pinId);
}

void main() {
  group('NodeRegistry 注册表自洽性', () {
    test('总数 26 且类型键唯一', () {
      expect(NodeRegistry.all, hasLength(26));
      expect(
        NodeRegistry.all
            .map((ScriptNodeTypeDescriptor type) => type.typeKey)
            .toSet(),
        hasLength(26),
      );
    });

    test('类型键集合与 spec §3.3 节点目录一致', () {
      expect(
        NodeRegistry.all
            .map((ScriptNodeTypeDescriptor type) => type.typeKey)
            .toSet(),
        _expectedTypeKeys,
      );
    });

    test('每个节点引脚 id 唯一且 exec/data 与 dataType 对应', () {
      for (final ScriptNodeTypeDescriptor type in NodeRegistry.all) {
        expect(type.displayName, isNotEmpty, reason: '${type.typeKey} 缺少显示名');
        expect(
          type.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
          hasLength(type.pins.length),
          reason: '${type.typeKey} 引脚 id 重复',
        );
        for (final ScriptPinDescriptor pin in type.pins) {
          expect(
            pin.label,
            isNotEmpty,
            reason: '${type.typeKey}.${pin.id} 缺少引脚标签',
          );
          if (pin.kind == ScriptPinKind.exec) {
            expect(
              pin.dataType,
              isNull,
              reason: '${type.typeKey}.${pin.id} exec 引脚不应有数据类型',
            );
          } else {
            expect(
              pin.dataType,
              isNotNull,
              reason: '${type.typeKey}.${pin.id} data 引脚缺少数据类型',
            );
          }
        }
      }
    });

    test('每个参数均有默认值、键与标签非空', () {
      for (final ScriptNodeTypeDescriptor type in NodeRegistry.all) {
        for (final ScriptParamDescriptor param in type.params) {
          expect(
            param.defaultValue,
            isNotNull,
            reason: '${type.typeKey}.${param.key} 缺默认值',
          );
          expect(param.key, isNotEmpty, reason: '${type.typeKey} 存在空参数键');
          expect(
            param.label,
            isNotEmpty,
            reason: '${type.typeKey}.${param.key} 缺少参数标签',
          );
        }
      }
    });

    test('输入引脚除 process.run 两个可选参数外全部必填', () {
      final Set<String> optionalInputs = <String>{};
      for (final ScriptNodeTypeDescriptor type in NodeRegistry.all) {
        for (final ScriptPinDescriptor pin in type.pins) {
          if (pin.isInput && !pin.required) {
            optionalInputs.add('${type.typeKey}.${pin.id}');
          }
        }
      }
      expect(optionalInputs, <String>{
        'process.run.arguments',
        'process.run.workingDirectory',
      });
    });

    test('未知类型键返回 null', () {
      expect(NodeRegistry.byType('nope.unknown'), isNull);
      expect(NodeRegistry.byType(''), isNull);
    });

    test('byCategory 分组与计数', () {
      const Map<ScriptNodeCategory, int> expectedCounts =
          <ScriptNodeCategory, int>{
            ScriptNodeCategory.flow: 4,
            ScriptNodeCategory.file: 6,
            ScriptNodeCategory.process: 1,
            ScriptNodeCategory.context: 3,
            ScriptNodeCategory.value: 3,
            ScriptNodeCategory.string: 6,
            ScriptNodeCategory.log: 1,
            ScriptNodeCategory.logic: 2,
          };
      final List<ScriptNodeTypeDescriptor> collected =
          <ScriptNodeTypeDescriptor>[];
      for (final MapEntry<ScriptNodeCategory, int> entry
          in expectedCounts.entries) {
        final List<ScriptNodeTypeDescriptor> types = NodeRegistry.byCategory(
          entry.key,
        );
        expect(
          types,
          hasLength(entry.value),
          reason: '${entry.key.name} 分组数量不符',
        );
        expect(
          types.every(
            (ScriptNodeTypeDescriptor type) => type.category == entry.key,
          ),
          isTrue,
          reason: '${entry.key.name} 分组混入其他分类',
        );
        collected.addAll(types);
      }
      expect(
        collected.map((ScriptNodeTypeDescriptor type) => type.typeKey).toSet(),
        hasLength(26),
      );
    });

    test('分类中文标签', () {
      expect(ScriptNodeCategory.flow.label, '流控');
      expect(ScriptNodeCategory.file.label, '文件');
      expect(ScriptNodeCategory.process.label, '进程');
      expect(ScriptNodeCategory.context.label, '上下文');
      expect(ScriptNodeCategory.value.label, '常量');
      expect(ScriptNodeCategory.string.label, '字符串');
      expect(ScriptNodeCategory.log.label, '日志');
      expect(ScriptNodeCategory.logic.label, '逻辑');
    });
  });

  group('关键节点逐项断言', () {
    test('flow.entry：无输入、单 exec 输出 out', () {
      final ScriptNodeTypeDescriptor entry = NodeRegistry.byType('flow.entry')!;
      expect(entry.category, ScriptNodeCategory.flow);
      expect(entry.pins, hasLength(1));
      expect(entry.pins.single.id, 'out');
      expect(entry.pins.single.isInput, isFalse);
      expect(entry.pins.single.kind, ScriptPinKind.exec);
      expect(entry.params, isEmpty);
    });

    test('flow.branch：exec/condition → then/else', () {
      final ScriptNodeTypeDescriptor branch = NodeRegistry.byType(
        'flow.branch',
      )!;
      expect(
        branch.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'condition', 'then', 'else'},
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'condition')
            .dataType,
        ScriptDataType.boolean,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'condition')
            .isInput,
        isTrue,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'condition')
            .required,
        isTrue,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'exec')
            .kind,
        ScriptPinKind.exec,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'exec')
            .isInput,
        isTrue,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'exec')
            .required,
        isTrue,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'then')
            .isInput,
        isFalse,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'then')
            .kind,
        ScriptPinKind.exec,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'else')
            .isInput,
        isFalse,
      );
      expect(
        branch.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'else')
            .kind,
        ScriptPinKind.exec,
      );
      expect(branch.params, isEmpty);
    });

    test('flow.foreach：exec/list → body/item/completed', () {
      final ScriptNodeTypeDescriptor foreach = NodeRegistry.byType(
        'flow.foreach',
      )!;
      expect(
        foreach.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'list', 'body', 'item', 'completed'},
      );
      expect(
        foreach.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'list')
            .dataType,
        ScriptDataType.listString,
      );
      expect(
        foreach.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'list')
            .required,
        isTrue,
      );
      expect(
        foreach.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'item')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        foreach.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'item')
            .isInput,
        isFalse,
      );
      expect(
        foreach.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'body')
            .kind,
        ScriptPinKind.exec,
      );
      expect(
        foreach.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'completed')
            .kind,
        ScriptPinKind.exec,
      );
      expect(foreach.params, isEmpty);
    });

    test('flow.while：exec/condition → body/completed', () {
      final ScriptNodeTypeDescriptor whileType = NodeRegistry.byType(
        'flow.while',
      )!;
      expect(
        whileType.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'condition', 'body', 'completed'},
      );
      expect(
        whileType.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'condition')
            .dataType,
        ScriptDataType.boolean,
      );
      expect(
        whileType.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'body')
            .kind,
        ScriptPinKind.exec,
      );
      expect(
        whileType.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'completed')
            .kind,
        ScriptPinKind.exec,
      );
      expect(whileType.params, isEmpty);
    });

    test('file.copy：exec/源/目标 → exec', () {
      final ScriptNodeTypeDescriptor copy = NodeRegistry.byType('file.copy')!;
      expect(copy.category, ScriptNodeCategory.file);
      expect(
        copy.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'source', 'destination', 'out'},
      );
      expect(
        copy.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'source')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        copy.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'source')
            .required,
        isTrue,
      );
      expect(
        copy.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'destination')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        copy.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'destination')
            .required,
        isTrue,
      );
      expect(
        copy.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'out')
            .kind,
        ScriptPinKind.exec,
      );
      expect(
        copy.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'out')
            .isInput,
        isFalse,
      );
      expect(copy.params, isEmpty);
    });

    test('file.move / file.delete / file.makeDirectory 引脚', () {
      final ScriptNodeTypeDescriptor move = NodeRegistry.byType('file.move')!;
      expect(
        move.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'source', 'destination', 'out'},
      );
      expect(move.params, isEmpty);

      final ScriptNodeTypeDescriptor delete = NodeRegistry.byType(
        'file.delete',
      )!;
      expect(
        delete.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'path', 'out'},
      );
      expect(
        delete.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'path')
            .dataType,
        ScriptDataType.string,
      );
      expect(delete.params.single.key, 'missingIgnored');

      final ScriptNodeTypeDescriptor makeDirectory = NodeRegistry.byType(
        'file.makeDirectory',
      )!;
      expect(
        makeDirectory.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'path', 'out'},
      );
      expect(makeDirectory.params, isEmpty);
    });

    test('file.list：目录 → 文件列表，筛选与递归参数', () {
      final ScriptNodeTypeDescriptor list = NodeRegistry.byType('file.list')!;
      expect(
        list.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'directory', 'result'},
      );
      expect(
        list.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'directory')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        list.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'directory')
            .required,
        isTrue,
      );
      expect(
        list.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'result')
            .dataType,
        ScriptDataType.listString,
      );
      expect(
        list.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'result')
            .isInput,
        isFalse,
      );
      expect(
        list.pins.every(
          (ScriptPinDescriptor pin) => pin.kind == ScriptPinKind.data,
        ),
        isTrue,
      );
      expect(
        list.params.map((ScriptParamDescriptor param) => param.key),
        containsAll(<String>['filter', 'recursive']),
      );
    });

    test('file.exists：路径 → bool', () {
      final ScriptNodeTypeDescriptor exists = NodeRegistry.byType(
        'file.exists',
      )!;
      expect(
        exists.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'path', 'result'},
      );
      expect(
        exists.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'path')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        exists.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'path')
            .required,
        isTrue,
      );
      expect(
        exists.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'result')
            .dataType,
        ScriptDataType.boolean,
      );
      expect(exists.params, isEmpty);
    });

    test('process.run：程序必填、参数与工作目录可选', () {
      final ScriptNodeTypeDescriptor run = NodeRegistry.byType('process.run')!;
      expect(run.category, ScriptNodeCategory.process);
      expect(
        run.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'program', 'arguments', 'workingDirectory', 'out'},
      );
      expect(
        run.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'program')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        run.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'program')
            .required,
        isTrue,
      );
      expect(
        run.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'arguments')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        run.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'arguments')
            .required,
        isFalse,
      );
      expect(
        run.pins
            .singleWhere(
              (ScriptPinDescriptor pin) => pin.id == 'workingDirectory',
            )
            .dataType,
        ScriptDataType.string,
      );
      expect(
        run.pins
            .singleWhere(
              (ScriptPinDescriptor pin) => pin.id == 'workingDirectory',
            )
            .required,
        isFalse,
      );
      expect(
        _param('process.run', 'abortOnFailure').type,
        ScriptParamType.boolean,
      );
    });

    test('context 三节点为纯数据生产者', () {
      for (final String typeKey in <String>[
        'context.macro',
        'context.environment',
        'context.packageFile',
      ]) {
        final ScriptNodeTypeDescriptor type = NodeRegistry.byType(typeKey)!;
        expect(type.category, ScriptNodeCategory.context);
        expect(type.pins, hasLength(1));
        expect(type.pins.single.id, 'result');
        expect(type.pins.single.isInput, isFalse);
        expect(type.pins.single.kind, ScriptPinKind.data);
        expect(type.pins.single.dataType, ScriptDataType.string);
      }
    });

    test('value 三节点输出类型', () {
      final ScriptNodeTypeDescriptor text = NodeRegistry.byType('value.text')!;
      expect(text.category, ScriptNodeCategory.value);
      expect(text.pins.single.id, 'result');
      expect(text.pins.single.dataType, ScriptDataType.string);
      final ScriptNodeTypeDescriptor boolean = NodeRegistry.byType(
        'value.boolean',
      )!;
      expect(boolean.category, ScriptNodeCategory.value);
      expect(boolean.pins.single.id, 'result');
      expect(boolean.pins.single.dataType, ScriptDataType.boolean);
      final ScriptNodeTypeDescriptor number = NodeRegistry.byType(
        'value.number',
      )!;
      expect(number.category, ScriptNodeCategory.value);
      expect(number.pins.single.id, 'result');
      expect(number.pins.single.isInput, isFalse);
      expect(number.pins.single.dataType, ScriptDataType.number);
    });

    test('string / path 六节点引脚', () {
      expect(
        NodeRegistry.byType('string.concat')!.pins
            .map((ScriptPinDescriptor pin) => pin.id)
            .toSet(),
        <String>{'a', 'b', 'result'},
      );
      expect(
        NodeRegistry.byType('string.replace')!.pins
            .map((ScriptPinDescriptor pin) => pin.id)
            .toSet(),
        <String>{'input', 'find', 'replace', 'result'},
      );
      expect(
        NodeRegistry.byType('string.lowerCase')!.pins
            .map((ScriptPinDescriptor pin) => pin.id)
            .toSet(),
        <String>{'input', 'result'},
      );
      expect(
        NodeRegistry.byType('string.fileName')!.pins
            .map((ScriptPinDescriptor pin) => pin.id)
            .toSet(),
        <String>{'path', 'result'},
      );
      expect(
        NodeRegistry.byType('string.directoryName')!.pins
            .map((ScriptPinDescriptor pin) => pin.id)
            .toSet(),
        <String>{'path', 'result'},
      );
      final ScriptNodeTypeDescriptor join = NodeRegistry.byType('path.join')!;
      expect(join.category, ScriptNodeCategory.string);
      expect(
        join.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'left', 'right', 'result'},
      );
      for (final String typeKey in <String>[
        'string.concat',
        'string.replace',
        'string.lowerCase',
        'string.fileName',
        'string.directoryName',
        'path.join',
      ]) {
        expect(
          NodeRegistry.byType(typeKey)!.pins
              .where((ScriptPinDescriptor pin) => pin.isInput)
              .every((ScriptPinDescriptor pin) => pin.required),
          isTrue,
          reason: '$typeKey 数据输入应全部必填',
        );
        expect(
          NodeRegistry.byType(typeKey)!.pins
              .singleWhere((ScriptPinDescriptor pin) => !pin.isInput)
              .dataType,
          ScriptDataType.string,
        );
      }
    });

    test('log.message：exec/message → exec 与级别参数', () {
      final ScriptNodeTypeDescriptor log = NodeRegistry.byType('log.message')!;
      expect(log.category, ScriptNodeCategory.log);
      expect(
        log.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'exec', 'message', 'out'},
      );
      expect(
        log.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'message')
            .dataType,
        ScriptDataType.string,
      );
      expect(
        log.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'message')
            .required,
        isTrue,
      );
      expect(
        log.pins.singleWhere((ScriptPinDescriptor pin) => pin.id == 'out').kind,
        ScriptPinKind.exec,
      );
      expect(_pin('log.message', 'message').isInput, isTrue);
    });

    test('logic 两节点', () {
      final ScriptNodeTypeDescriptor compare = NodeRegistry.byType(
        'logic.compareString',
      )!;
      expect(compare.category, ScriptNodeCategory.logic);
      expect(
        compare.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'a', 'b', 'result'},
      );
      expect(
        compare.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'result')
            .dataType,
        ScriptDataType.boolean,
      );
      expect(
        compare.pins.every(
          (ScriptPinDescriptor pin) => pin.kind == ScriptPinKind.data,
        ),
        isTrue,
      );

      final ScriptNodeTypeDescriptor not = NodeRegistry.byType('logic.not')!;
      expect(
        not.pins.map((ScriptPinDescriptor pin) => pin.id).toSet(),
        <String>{'input', 'result'},
      );
      expect(
        not.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'input')
            .dataType,
        ScriptDataType.boolean,
      );
      expect(
        not.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'input')
            .isInput,
        isTrue,
      );
      expect(
        not.pins
            .singleWhere((ScriptPinDescriptor pin) => pin.id == 'result')
            .dataType,
        ScriptDataType.boolean,
      );
    });
  });

  group('参数清单 / 默认值 / 类型', () {
    test('仅计划内节点携带参数且清单一致', () {
      const Map<String, List<String>> expected = <String, List<String>>{
        'file.delete': <String>['missingIgnored'],
        'file.list': <String>['filter', 'recursive'],
        'process.run': <String>['abortOnFailure'],
        'log.message': <String>['level'],
        'logic.compareString': <String>['operator', 'ignoreCase'],
        'value.text': <String>['value'],
        'value.boolean': <String>['value'],
        'value.number': <String>['value'],
        'context.macro': <String>['macro'],
        'context.environment': <String>['name'],
        'context.packageFile': <String>['path'],
      };
      for (final ScriptNodeTypeDescriptor type in NodeRegistry.all) {
        final List<String> expectedKeys = expected[type.typeKey] ?? <String>[];
        expect(
          type.params.map((ScriptParamDescriptor param) => param.key).toList(),
          expectedKeys,
          reason: '${type.typeKey} 参数清单不符',
        );
      }
    });

    test('参数默认值按计划清单锁定', () {
      expect(_param('file.delete', 'missingIgnored').defaultValue, isTrue);
      expect(_param('file.list', 'filter').defaultValue, '');
      expect(_param('file.list', 'recursive').defaultValue, isFalse);
      expect(_param('process.run', 'abortOnFailure').defaultValue, isTrue);
      expect(_param('log.message', 'level').defaultValue, 'info');
      expect(_param('logic.compareString', 'operator').defaultValue, 'eq');
      expect(_param('logic.compareString', 'ignoreCase').defaultValue, isFalse);
      expect(_param('value.text', 'value').defaultValue, '');
      expect(_param('value.boolean', 'value').defaultValue, isFalse);
      expect(_param('value.number', 'value').defaultValue, 0);
      expect(_param('context.macro', 'macro').defaultValue, 'OutDir');
      expect(_param('context.environment', 'name').defaultValue, '');
      expect(_param('context.packageFile', 'path').defaultValue, '');
    });

    test('参数类型映射', () {
      expect(_param('context.macro', 'macro').type, ScriptParamType.macroKey);
      expect(_param('log.message', 'level').type, ScriptParamType.logLevel);
      expect(
        _param('logic.compareString', 'operator').type,
        ScriptParamType.stringOperator,
      );
      expect(
        _param('context.packageFile', 'path').type,
        ScriptParamType.packageFilePath,
      );
      expect(_param('file.list', 'filter').type, ScriptParamType.text);
      expect(_param('file.list', 'recursive').type, ScriptParamType.boolean);
      expect(
        _param('file.delete', 'missingIgnored').type,
        ScriptParamType.boolean,
      );
      expect(
        _param('process.run', 'abortOnFailure').type,
        ScriptParamType.boolean,
      );
      expect(
        _param('logic.compareString', 'ignoreCase').type,
        ScriptParamType.boolean,
      );
      expect(_param('value.text', 'value').type, ScriptParamType.text);
      expect(_param('value.boolean', 'value').type, ScriptParamType.boolean);
      expect(_param('value.number', 'value').type, ScriptParamType.number);
      expect(_param('context.environment', 'name').type, ScriptParamType.text);
    });
  });
}
