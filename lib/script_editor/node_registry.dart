import 'package:cpp_nuget_pack/script_editor/node_type.dart';

const ScriptPinDescriptor _execInput = ScriptPinDescriptor(
  id: 'exec',
  label: '执行',
  isInput: true,
  kind: ScriptPinKind.exec,
  required: true,
);

const ScriptPinDescriptor _execOutput = ScriptPinDescriptor(
  id: 'out',
  label: '执行',
  isInput: false,
  kind: ScriptPinKind.exec,
);

class NodeRegistry {
  static const List<ScriptNodeTypeDescriptor> _types =
      <ScriptNodeTypeDescriptor>[
        ScriptNodeTypeDescriptor(
          typeKey: 'flow.entry',
          displayName: '开始',
          category: ScriptNodeCategory.flow,
          pins: <ScriptPinDescriptor>[_execOutput],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'flow.branch',
          displayName: '分支',
          category: ScriptNodeCategory.flow,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'condition',
              label: '条件',
              isInput: true,
              dataType: ScriptDataType.boolean,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'then',
              label: '满足',
              isInput: false,
              kind: ScriptPinKind.exec,
            ),
            ScriptPinDescriptor(
              id: 'else',
              label: '不满足',
              isInput: false,
              kind: ScriptPinKind.exec,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'flow.foreach',
          displayName: '遍历',
          category: ScriptNodeCategory.flow,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'list',
              label: '列表',
              isInput: true,
              dataType: ScriptDataType.listString,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'body',
              label: '循环体',
              isInput: false,
              kind: ScriptPinKind.exec,
            ),
            ScriptPinDescriptor(
              id: 'item',
              label: '当前项',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
            ScriptPinDescriptor(
              id: 'completed',
              label: '完成',
              isInput: false,
              kind: ScriptPinKind.exec,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'flow.while',
          displayName: '当条件',
          category: ScriptNodeCategory.flow,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'condition',
              label: '条件',
              isInput: true,
              dataType: ScriptDataType.boolean,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'body',
              label: '循环体',
              isInput: false,
              kind: ScriptPinKind.exec,
            ),
            ScriptPinDescriptor(
              id: 'completed',
              label: '完成',
              isInput: false,
              kind: ScriptPinKind.exec,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'file.copy',
          displayName: '复制',
          category: ScriptNodeCategory.file,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'source',
              label: '源路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'destination',
              label: '目标路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            _execOutput,
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'file.move',
          displayName: '移动',
          category: ScriptNodeCategory.file,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'source',
              label: '源路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'destination',
              label: '目标路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            _execOutput,
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'file.delete',
          displayName: '删除',
          category: ScriptNodeCategory.file,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'path',
              label: '路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            _execOutput,
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'missingIgnored',
              label: '缺失时忽略',
              type: ScriptParamType.boolean,
              defaultValue: true,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'file.makeDirectory',
          displayName: '创建目录',
          category: ScriptNodeCategory.file,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'path',
              label: '路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            _execOutput,
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'file.list',
          displayName: '列目录',
          category: ScriptNodeCategory.file,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'directory',
              label: '目录',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '文件列表',
              isInput: false,
              dataType: ScriptDataType.listString,
            ),
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'filter',
              label: '筛选',
              type: ScriptParamType.text,
              defaultValue: '',
            ),
            ScriptParamDescriptor(
              key: 'recursive',
              label: '递归',
              type: ScriptParamType.boolean,
              defaultValue: false,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'file.exists',
          displayName: '存在?',
          category: ScriptNodeCategory.file,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'path',
              label: '路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '是否存在',
              isInput: false,
              dataType: ScriptDataType.boolean,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'process.run',
          displayName: '运行程序',
          category: ScriptNodeCategory.process,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'program',
              label: '程序',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'arguments',
              label: '参数',
              isInput: true,
              dataType: ScriptDataType.string,
            ),
            ScriptPinDescriptor(
              id: 'workingDirectory',
              label: '工作目录',
              isInput: true,
              dataType: ScriptDataType.string,
            ),
            _execOutput,
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'abortOnFailure',
              label: '失败中断',
              type: ScriptParamType.boolean,
              defaultValue: true,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'context.macro',
          displayName: 'MSBuild 宏',
          category: ScriptNodeCategory.context,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'result',
              label: '宏值',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'macro',
              label: '宏键',
              type: ScriptParamType.macroKey,
              defaultValue: 'OutDir',
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'context.environment',
          displayName: '环境变量',
          category: ScriptNodeCategory.context,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'result',
              label: '值',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'name',
              label: '变量名',
              type: ScriptParamType.text,
              defaultValue: '',
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'context.packageFile',
          displayName: '包内文件路径',
          category: ScriptNodeCategory.context,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'result',
              label: '路径',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'path',
              label: '相对路径',
              type: ScriptParamType.packageFilePath,
              defaultValue: '',
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'value.text',
          displayName: '文本',
          category: ScriptNodeCategory.value,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'result',
              label: '值',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'value',
              label: '值',
              type: ScriptParamType.text,
              defaultValue: '',
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'value.boolean',
          displayName: '开关',
          category: ScriptNodeCategory.value,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'result',
              label: '值',
              isInput: false,
              dataType: ScriptDataType.boolean,
            ),
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'value',
              label: '值',
              type: ScriptParamType.boolean,
              defaultValue: false,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'string.concat',
          displayName: '拼接',
          category: ScriptNodeCategory.string,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'a',
              label: 'A',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'b',
              label: 'B',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '结果',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'string.replace',
          displayName: '替换',
          category: ScriptNodeCategory.string,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'input',
              label: '输入',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'find',
              label: '查找',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'replace',
              label: '替换',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '结果',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'string.lowerCase',
          displayName: '转小写',
          category: ScriptNodeCategory.string,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'input',
              label: '输入',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '结果',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'string.fileName',
          displayName: '取文件名',
          category: ScriptNodeCategory.string,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'path',
              label: '路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '文件名',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'string.directoryName',
          displayName: '取目录',
          category: ScriptNodeCategory.string,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'path',
              label: '路径',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '目录名',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'path.join',
          displayName: '合并路径',
          category: ScriptNodeCategory.string,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'left',
              label: '前',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'right',
              label: '后',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '结果',
              isInput: false,
              dataType: ScriptDataType.string,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'log.message',
          displayName: '输出信息',
          category: ScriptNodeCategory.log,
          pins: <ScriptPinDescriptor>[
            _execInput,
            ScriptPinDescriptor(
              id: 'message',
              label: '消息',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            _execOutput,
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'level',
              label: '级别',
              type: ScriptParamType.logLevel,
              defaultValue: 'info',
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'logic.compareString',
          displayName: '比较文本',
          category: ScriptNodeCategory.logic,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'a',
              label: 'A',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'b',
              label: 'B',
              isInput: true,
              dataType: ScriptDataType.string,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '结果',
              isInput: false,
              dataType: ScriptDataType.boolean,
            ),
          ],
          params: <ScriptParamDescriptor>[
            ScriptParamDescriptor(
              key: 'operator',
              label: '运算符',
              type: ScriptParamType.stringOperator,
              defaultValue: 'eq',
            ),
            ScriptParamDescriptor(
              key: 'ignoreCase',
              label: '忽略大小写',
              type: ScriptParamType.boolean,
              defaultValue: false,
            ),
          ],
        ),
        ScriptNodeTypeDescriptor(
          typeKey: 'logic.not',
          displayName: '非',
          category: ScriptNodeCategory.logic,
          pins: <ScriptPinDescriptor>[
            ScriptPinDescriptor(
              id: 'input',
              label: '输入',
              isInput: true,
              dataType: ScriptDataType.boolean,
              required: true,
            ),
            ScriptPinDescriptor(
              id: 'result',
              label: '结果',
              isInput: false,
              dataType: ScriptDataType.boolean,
            ),
          ],
        ),
      ];

  static final Map<String, ScriptNodeTypeDescriptor> _byType =
      <String, ScriptNodeTypeDescriptor>{
        for (final ScriptNodeTypeDescriptor type in _types) type.typeKey: type,
      };

  static ScriptNodeTypeDescriptor? byType(String typeKey) => _byType[typeKey];

  static List<ScriptNodeTypeDescriptor> get all => _types;

  static List<ScriptNodeTypeDescriptor> byCategory(
    ScriptNodeCategory category,
  ) => _types
      .where((ScriptNodeTypeDescriptor type) => type.category == category)
      .toList(growable: false);
}
