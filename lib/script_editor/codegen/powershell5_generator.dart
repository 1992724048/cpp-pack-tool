import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/code_writer.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/prelude.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/graph_validation.dart';
import 'package:cpp_nuget_pack/script_editor/msbuild_macros.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/node_type.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:flutter/foundation.dart';

const String _packageRootEnvExpression = r'$env:CNP_PackageRoot';

/// 数字字面量：int 直出；double 取 invariant 文本并将指数记号的 `e+` 归一为 `e`
/// （canonical 归一，PowerShell 5.1 亦接受 `e+` 写法）；负数整体加括号。
String numberLiteral(num value) {
  final String text = value.toString().replaceFirst('e+', 'e');
  return value.isNegative ? '($text)' : text;
}

/// prelude 片段注册回调（键 → 片段文本；`content` 缺省时取 [preludeLibrary]）。
typedef PreludeRegistrar = void Function(String key, {String? content});

class PowerShell5Generator implements ScriptCodeGenerator {
  final Map<String, String> _registeredPrelude = <String, String>{};

  @override
  String get fileExtension => 'ps1';

  @override
  ScriptCompileResult compile(
    ScriptProjectModel project, {
    required String packName,
  }) {
    // 注册表为编译期状态：同一实例可能被重复使用（如 ScriptPackaging 的默认生成器）。
    _registeredPrelude.clear();
    return _compileProject(project, packName: packName);
  }

  /// 测试入口：编译前经 [preludeCollector] 调用真实注册 API 预注册片段
  /// （生产路径由节点发射按需注册，M4.2 T5–T7 接入）。
  @visibleForTesting
  ScriptCompileResult compileWithPrelude(
    ScriptProjectModel project, {
    required String packName,
    required void Function(PreludeRegistrar register) preludeCollector,
  }) {
    _registeredPrelude.clear();
    preludeCollector(_registerPrelude);
    return _compileProject(project, packName: packName);
  }

  /// 注册 prelude 片段（幂等：同键仅首次生效；`content` 覆盖
  /// [preludeLibrary]，供 crc32 与变量初始化等动态内容使用）。
  void _registerPrelude(String key, {String? content}) {
    if (_registeredPrelude.containsKey(key)) {
      return;
    }
    final String? block = content ?? preludeLibrary[key];
    if (block == null) {
      throw ArgumentError.value(key, 'key', '未知的 prelude 片段键');
    }
    _registeredPrelude[key] = block
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }

  ScriptCompileResult _compileProject(
    ScriptProjectModel project, {
    required String packName,
  }) {
    final List<ScriptDiagnostic> diagnostics = GraphValidator.validate(project);
    if (diagnostics.any((ScriptDiagnostic diagnostic) => diagnostic.isError)) {
      return ScriptCompileResult(code: null, diagnostics: diagnostics);
    }

    final CodeWriter body = CodeWriter();
    final _PowerShellEmitter emitter = _PowerShellEmitter(
      project: project,
      writer: body,
      registerPrelude: _registerPrelude,
    );
    body.indent(emitter.emitEntryChain);

    final CodeWriter prefix = CodeWriter();
    prefix.writeln(
      '# 由 cpp_nuget_pack 生成 — $packName / ${project.name}。请使用节点编辑器修改，勿手工编辑本文件。',
    );
    prefix.writeln(r"$ErrorActionPreference = 'Stop'");
    _writePrelude(prefix);
    prefix.writeln('try {');

    final CodeWriter suffix = CodeWriter();
    suffix.writeln('} catch {');
    suffix.indent(() {
      suffix.writeln(
        r'Write-Host "脚本执行失败: $($_.Exception.Message)" -ForegroundColor Red',
      );
      suffix.writeln('exit 1');
    });
    suffix.writeln('}');

    return ScriptCompileResult(
      code: '\uFEFF${prefix.toString()}${body.toString()}${suffix.toString()}',
      diagnostics: diagnostics,
    );
  }

  /// 按 [preludeOrder] 输出已注册片段：列 0、片段间与前后各空一行（LF）。
  void _writePrelude(CodeWriter writer) {
    final List<String> fragments = <String>[
      for (final String key in preludeOrder)
        if (_registeredPrelude.containsKey(key)) _registeredPrelude[key]!,
    ];
    if (fragments.isEmpty) {
      return;
    }
    writer.writeln();
    for (final String line in fragments.join('\n\n').split('\n')) {
      writer.writeln(line);
    }
    writer.writeln();
  }
}

class _PowerShellEmitter {
  _PowerShellEmitter({
    required ScriptProjectModel project,
    required this.writer,
    required this.registerPrelude,
  }) : _index = _GraphIndex(project);

  final CodeWriter writer;
  final _GraphIndex _index;
  final PreludeRegistrar registerPrelude;
  final Map<String, String> _itemVariableByNodeId = <String, String>{};
  int _itemCounter = 0;
  int _processCounter = 0;

  void emitEntryChain() {
    final ScriptNodeModel? entry = _index.firstNodeOfType(entryTypeKey);
    if (entry == null) {
      return; // 校验保证恰好一个入口；此处仅防御
    }
    _emitChain(_index.execTarget(entry.id, defaultExecPinId));
  }

  void _emitChain(String? startNodeId) {
    String? nodeId = startNodeId;
    while (nodeId != null) {
      final ScriptNodeModel? node = _index.nodeById[nodeId];
      if (node == null) {
        return; // 校验保证边指向存在的节点；此处仅防御
      }
      _emitNode(node);
      nodeId = _continuationNodeId(node);
    }
  }

  /// 线性链默认沿 `out` 续接；循环沿 `completed` 续接，分支无续接出口。
  String? _continuationNodeId(ScriptNodeModel node) {
    switch (node.type) {
      case 'flow.branch':
        return null;
      case 'flow.foreach':
      case 'flow.while':
        return _index.execTarget(node.id, 'completed');
      default:
        return _index.execTarget(node.id, defaultExecPinId);
    }
  }

  void _emitNode(ScriptNodeModel node) {
    switch (node.type) {
      case 'log.message':
        _emitLogMessage(node);
      case 'file.copy':
        _emitFileCopy(node);
      case 'file.move':
        _emitFileMove(node);
      case 'file.delete':
        _emitFileDelete(node);
      case 'file.makeDirectory':
        _emitFileMakeDirectory(node);
      case 'file.hardLink':
        _emitFileHardLink(node);
      case 'file.writeHex':
        _emitFileWriteHex(node);
      case 'process.run':
        _emitProcessRun(node);
      case 'flow.branch':
        _emitBranch(node);
      case 'flow.foreach':
        _emitForeach(node);
      case 'flow.while':
        _emitWhile(node);
      default:
        // 校验器已拒绝未知类型；此处仅防御未登记的节点类型
        throw UnsupportedError('节点类型「${node.type}」的代码生成尚未实现');
    }
  }

  void _emitLogMessage(ScriptNodeModel node) {
    final String message = _expression(node, 'message');
    switch (_param(node, 'level')) {
      case 'warn':
        writer.writeln(
          "Write-Host ('[警告] ' + $message) -ForegroundColor Yellow",
        );
      case 'error':
        writer.writeln("Write-Host ('[错误] ' + $message) -ForegroundColor Red");
      default:
        writer.writeln('Write-Host $message');
    }
  }

  void _emitFileCopy(ScriptNodeModel node) {
    final String source = _expression(node, 'source');
    final String destination = _expression(node, 'destination');
    writer.writeln(
      'Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force',
    );
  }

  void _emitFileMove(ScriptNodeModel node) {
    final String source = _expression(node, 'source');
    final String destination = _expression(node, 'destination');
    writer.writeln(
      'Move-Item -LiteralPath $source -Destination $destination -Force',
    );
  }

  void _emitFileDelete(ScriptNodeModel node) {
    final String path = _expression(node, 'path');
    final String ignoreMissing = _param(node, 'missingIgnored') == true
        ? ' -ErrorAction SilentlyContinue'
        : '';
    writer.writeln(
      'Remove-Item -LiteralPath $path -Recurse -Force$ignoreMissing',
    );
  }

  void _emitFileMakeDirectory(ScriptNodeModel node) {
    final String path = _expression(node, 'path');
    writer.writeln('New-Item -ItemType Directory -Force -Path $path');
  }

  void _emitFileHardLink(ScriptNodeModel node) {
    final String source = _expression(node, 'source');
    final String destination = _expression(node, 'destination');
    writer.writeln(
      'New-Item -ItemType HardLink -Path $destination -Target $source '
      '-Force -ErrorAction Stop',
    );
  }

  void _emitFileWriteHex(ScriptNodeModel node) {
    registerPrelude('ConvertFrom-CnpHex');
    final String path = _expression(node, 'path');
    final String hex = _expression(node, 'hex');
    writer.writeln(
      '[IO.File]::WriteAllBytes($path, (ConvertFrom-CnpHex ($hex)))',
    );
  }

  void _emitProcessRun(ScriptNodeModel node) {
    final int index = ++_processCounter;
    final String process = '\$proc_$index';
    final String argumentsName = 'args_$index';
    final String arguments = '\$$argumentsName';
    final String? argumentsExpression = _optionalExpression(node, 'arguments');
    final String? workingDirectory = _optionalExpression(
      node,
      'workingDirectory',
    );
    writer.writeln('$process = ${_expression(node, 'program')}');
    writer.writeln(
      argumentsExpression == null
          ? '$arguments = @()'
          : '$arguments = @($argumentsExpression -split "\\r?\\n" | '
                'Where-Object { \$_ -ne \'\' })',
    );
    if (workingDirectory != null) {
      writer.writeln('Push-Location -LiteralPath $workingDirectory');
    }
    writer.writeln('& $process @$argumentsName');
    if (workingDirectory != null) {
      writer.writeln('Pop-Location');
    }
    if (_param(node, 'abortOnFailure') == true) {
      writer.writeln(
        r'if ($LASTEXITCODE -ne 0) { throw "外部程序退出码 $LASTEXITCODE" }',
      );
    } else {
      writer.writeln(
        r"Write-Host ('[警告] 外部程序退出码 ' + $LASTEXITCODE) -ForegroundColor Yellow",
      );
    }
  }

  void _emitBranch(ScriptNodeModel node) {
    final String condition = _expression(node, 'condition');
    writer.writeln('if ($condition) {');
    writer.indent(() => _emitChain(_index.execTarget(node.id, 'then')));
    writer.writeln('} else {');
    writer.indent(() => _emitChain(_index.execTarget(node.id, 'else')));
    writer.writeln('}');
  }

  void _emitForeach(ScriptNodeModel node) {
    final String itemVariable = _itemVariable(node);
    final String list = _expression(node, 'list');
    writer.writeln('foreach ($itemVariable in $list) {');
    writer.indent(() => _emitChain(_index.execTarget(node.id, 'body')));
    writer.writeln('}');
  }

  void _emitWhile(ScriptNodeModel node) {
    final String condition = _expression(node, 'condition');
    writer.writeln('while ($condition) {');
    writer.indent(() => _emitChain(_index.execTarget(node.id, 'body')));
    writer.writeln('}');
  }

  /// 循环变量按首次使用顺序分配，全局唯一（`$item_1`、`$item_2`…），保证生成确定性。
  String _itemVariable(ScriptNodeModel node) {
    return _itemVariableByNodeId.putIfAbsent(
      node.id,
      () => '\$item_${++_itemCounter}',
    );
  }

  /// 内联 `node` 输入引脚处的数据表达式（递归展开上游数据节点）。
  String _expression(ScriptNodeModel node, String pinId) {
    final ScriptEdgeModel? edge = _index.incomingEdge(node.id, pinId);
    if (edge == null) {
      throw StateError('输入引脚「${node.id}.$pinId」未连接，无法生成表达式');
    }
    return _outputExpression(_index.nodeById[edge.from.node]!, edge.from.pin);
  }

  /// 可选输入引脚的表达式；未连接时返回 null（可选输入不参与必填校验）。
  String? _optionalExpression(ScriptNodeModel node, String pinId) {
    if (_index.incomingEdge(node.id, pinId) == null) {
      return null;
    }
    return _expression(node, pinId);
  }

  /// 数据节点输出引脚的表达式（递归内联上游数据节点）。
  String _outputExpression(ScriptNodeModel node, String pinId) {
    switch (node.type) {
      case 'value.text':
        return _textLiteral(_param(node, 'value'));
      case 'value.boolean':
        return _param(node, 'value') == true ? r'$true' : r'$false';
      case 'value.number':
        // 数值参数校验已阻断生成，此处防直接调用：非 num 或非有限值回退 0。
        final Object? value = _param(node, 'value');
        return numberLiteral(value is num && value.isFinite ? value : 0);
      case 'file.list':
        return _fileListExpression(node);
      case 'file.exists':
        return '(Test-Path -LiteralPath ${_expression(node, 'path')} '
            '-PathType Any)';
      case 'file.readHex':
        return '([BitConverter]::ToString('
            '[IO.File]::ReadAllBytes(${_expression(node, 'path')}))'
            ".Replace('-','').ToLowerInvariant())";
      case 'flow.foreach':
        if (pinId != 'item') {
          throw UnsupportedError('节点类型「${node.type}」的引脚「$pinId」不支持数据表达式');
        }
        return _itemVariable(node);
      case 'context.macro':
        return _macroExpression(node);
      case 'context.environment':
        return _environmentExpression(node);
      case 'context.packageFile':
        return _packageFileExpression(node);
      case 'string.concat':
        return '(${_expression(node, 'a')} + ${_expression(node, 'b')})';
      case 'string.replace':
        return '(${_expression(node, 'input')}.Replace('
            '${_expression(node, 'find')}, ${_expression(node, 'replace')}))';
      case 'string.lowerCase':
        return '(${_expression(node, 'input')}.ToLowerInvariant())';
      case 'string.upperCase':
        return '(${_expression(node, 'value')}.ToUpperInvariant())';
      case 'string.fileName':
        return '(Split-Path -Leaf ${_expression(node, 'path')})';
      case 'string.directoryName':
        return '(Split-Path -Parent ${_expression(node, 'path')})';
      case 'path.join':
        return '(Join-Path ${_expression(node, 'left')} '
            '${_expression(node, 'right')})';
      case 'logic.compareString':
        return _compareStringExpression(node);
      case 'logic.compareNumber':
        return _compareNumberExpression(node);
      case 'logic.not':
        return '(-not (${_expression(node, 'input')}))';
      case 'math.arithmetic':
        return _arithmeticExpression(node);
      case 'math.bitwise':
        return _bitwiseExpression(node);
      case 'math.bitNot':
        return '(-bnot [long](${_expression(node, 'value')}))';
      case 'math.numberToString':
        return '(Convert.ToString(${_expression(node, 'value')}, '
            '[Globalization.CultureInfo]::InvariantCulture))';
      case 'math.stringToNumber':
        return '([double]::Parse(${_expression(node, 'value')}, '
            '[Globalization.CultureInfo]::InvariantCulture))';
      default:
        // 校验器已拒绝未知类型；此处仅防御未登记的节点类型
        throw UnsupportedError('节点类型「${node.type}」的表达式生成尚未实现');
    }
  }

  String _fileListExpression(ScriptNodeModel node) {
    final String directory = _expression(node, 'directory');
    final Object? filterValue = _param(node, 'filter');
    final String filter = filterValue == null ? '' : '$filterValue';
    final String filterPart = filter.isEmpty
        ? ''
        : ' -Filter ${_textLiteral(filter)}';
    final String recursePart = _param(node, 'recursive') == true
        ? ' -Recurse'
        : '';
    return '@(Get-ChildItem -LiteralPath $directory$filterPart$recursePart '
        '-File | Select-Object -ExpandProperty FullName)';
  }

  String _macroExpression(ScriptNodeModel node) {
    final String macroKey = '${_param(node, 'macro')}';
    return '\$env:${macroEnvName(macroKey)}';
  }

  String _environmentExpression(ScriptNodeModel node) {
    return '\$env:${_param(node, 'name')}';
  }

  String _packageFileExpression(ScriptNodeModel node) {
    final String relativePath = '${_param(node, 'path')}'.replaceAll('/', r'\');
    return '(Join-Path $_packageRootEnvExpression '
        '${_textLiteral(relativePath)})';
  }

  String _compareStringExpression(ScriptNodeModel node) {
    final String left = _expression(node, 'a');
    final String right = _expression(node, 'b');
    final bool ignoreCase = _param(node, 'ignoreCase') == true;
    switch (_param(node, 'operator')) {
      case 'ne':
        return '($left ${ignoreCase ? '-ine' : '-cne'} $right)';
      case 'contains':
        if (ignoreCase) {
          return '($left.IndexOf($right, '
              '[System.StringComparison]::OrdinalIgnoreCase) -ge 0)';
        }
        return '($left.Contains($right))';
      default:
        return '($left ${ignoreCase ? '-ieq' : '-ceq'} $right)';
    }
  }

  String _compareNumberExpression(ScriptNodeModel node) {
    final String psOperator = switch (_param(node, 'operator')) {
      'le' => '-le',
      'gt' => '-gt',
      'ge' => '-ge',
      'eq' => '-eq',
      'ne' => '-ne',
      _ => '-lt',
    };
    return '(${_expression(node, 'a')} $psOperator '
        '${_expression(node, 'b')})';
  }

  String _arithmeticExpression(ScriptNodeModel node) {
    final String symbol = switch (_param(node, 'operator')) {
      'subtract' => '-',
      'multiply' => '*',
      'divide' => '/',
      'modulo' => '%',
      _ => '+',
    };
    return '(${_expression(node, 'a')} $symbol ${_expression(node, 'b')})';
  }

  String _bitwiseExpression(ScriptNodeModel node) {
    final String psOperator = switch (_param(node, 'operator')) {
      'or' => '-bor',
      'xor' => '-bxor',
      'shiftLeft' => '-shl',
      'shiftRight' => '-shr',
      _ => '-band',
    };
    return '([long](${_expression(node, 'a')}) $psOperator '
        '[long](${_expression(node, 'b')}))';
  }

  Object? _param(ScriptNodeModel node, String key) {
    final Object? value = node.params[key];
    if (value != null) {
      return value;
    }
    final ScriptNodeTypeDescriptor? descriptor = NodeRegistry.byType(node.type);
    for (final ScriptParamDescriptor param
        in descriptor?.params ?? const <ScriptParamDescriptor>[]) {
      if (param.key == key) {
        return param.defaultValue;
      }
    }
    return null;
  }

  String _textLiteral(Object? value) {
    final String text = value == null ? '' : '$value';
    return "'${text.replaceAll("'", "''")}'";
  }
}

class _GraphIndex {
  _GraphIndex(ScriptProjectModel project) {
    for (final ScriptNodeModel node in project.nodes) {
      nodeById[node.id] = node;
    }
    for (final ScriptEdgeModel edge in project.edges) {
      incomingEdges[(nodeId: edge.to.node, pinId: edge.to.pin)] = edge;
      outgoingEdges
          .putIfAbsent((
            nodeId: edge.from.node,
            pinId: edge.from.pin,
          ), () => <ScriptEdgeModel>[])
          .add(edge);
    }
  }

  final Map<String, ScriptNodeModel> nodeById = <String, ScriptNodeModel>{};
  final Map<PinKey, ScriptEdgeModel> incomingEdges =
      <PinKey, ScriptEdgeModel>{};
  final Map<PinKey, List<ScriptEdgeModel>> outgoingEdges =
      <PinKey, List<ScriptEdgeModel>>{};

  ScriptNodeModel? firstNodeOfType(String typeKey) {
    for (final ScriptNodeModel node in nodeById.values) {
      if (node.type == typeKey) {
        return node;
      }
    }
    return null;
  }

  ScriptEdgeModel? incomingEdge(String nodeId, String pinId) {
    return incomingEdges[(nodeId: nodeId, pinId: pinId)];
  }

  String? execTarget(String nodeId, String pinId) {
    final List<ScriptEdgeModel> edges =
        outgoingEdges[(nodeId: nodeId, pinId: pinId)] ??
        const <ScriptEdgeModel>[];
    return edges.isEmpty ? null : edges.first.to.node;
  }
}
