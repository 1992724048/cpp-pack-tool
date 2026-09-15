import 'package:cpp_nuget_pack/controls/script_editor/node_card.dart'
    show nodeCardHeight, nodeCardWidth;
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/powershell5_generator.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/node_registry.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// 底部输出面板收起高度（视觉规范 §7.1）。
const double outputPanelCollapsedHeight = 34;

/// 底部输出面板展开高度（视觉规范 §7.1）。
const double outputPanelExpandedHeight = 220;

const Duration _panelAnimationDuration = Duration(milliseconds: 150);

/// 诊断排序（§7.3）：错误在前、警告在后；同级保持校验器输出顺序（稳定）。
List<ScriptDiagnostic> sortedDiagnostics(List<ScriptDiagnostic> diagnostics) {
  final List<ScriptDiagnostic> errors = <ScriptDiagnostic>[];
  final List<ScriptDiagnostic> warnings = <ScriptDiagnostic>[];
  for (final ScriptDiagnostic diagnostic in diagnostics) {
    (diagnostic.isError ? errors : warnings).add(diagnostic);
  }
  return <ScriptDiagnostic>[...errors, ...warnings];
}

/// 输出面板标签（视觉规范 §7.1）。
enum _OutputTab { code, diagnostics }

/// 底部输出面板（视觉规范 §7/§10.8/§10.9）：代码预览与诊断清单，可开合。
///
/// 「生成预览」由页面顶栏按钮经 [OutputPanelState.generatePreview] 触发；
/// 诊断行点击选中节点并将视口居中（直接写入注入的 [TransformationController]）。
/// 面板保持收起 34 / 展开 220 两态，150ms 动画且收起时不构建内容子树。
class OutputPanel extends StatefulWidget {
  const OutputPanel({
    super.key,
    required this.controller,
    required this.pack,
    this.generator,
    this.transformationController,
    this.viewportSizeProvider,
  });

  /// 编辑器控制器；null 表示无脚本项目（计数为空、无法生成）。
  final GraphEditorController? controller;

  /// 当前包（生成预览的 `packName` 来源）。
  final PackModel pack;

  /// 代码生成器；null 时回退 [PowerShell5Generator]。
  final ScriptCodeGenerator? generator;

  /// 画布变换控制器；诊断行居中时改写其变换矩阵（T5 支持注入）。
  final TransformationController? transformationController;

  /// 画布可视视口尺寸读取器；面板高度动画不触发页面重建，故惰性读取
  /// 而非传静态值；null 或返回 null 时仅选中节点、不平移视口。
  final Size? Function()? viewportSizeProvider;

  @override
  State<OutputPanel> createState() => OutputPanelState();
}

class OutputPanelState extends State<OutputPanel> {
  static const TextStyle _monoTextStyle = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: <String>['Courier New', 'monospace'],
    fontSize: 13,
  );

  final ScrollController _codeScrollController = ScrollController();
  late ScriptCodeGenerator _generator =
      widget.generator ?? PowerShell5Generator();

  ScriptProjectModel? _projectRef;
  ScriptCompileResult? _result;
  _OutputTab _tab = _OutputTab.code;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _projectRef = widget.controller?.project;
    widget.controller?.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(OutputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_handleControllerChanged);
      widget.controller?.addListener(_handleControllerChanged);
      _projectRef = widget.controller?.project;
      _result = null;
    }
    if (!identical(oldWidget.generator, widget.generator)) {
      _generator = widget.generator ?? PowerShell5Generator();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerChanged);
    _codeScrollController.dispose();
    super.dispose();
  }

  /// 图变更后即时重建（诊断计数/清单随图刷新）；项目实例变化时旧预览作废。
  void _handleControllerChanged() {
    final GraphEditorController? controller = widget.controller;
    if (identical(controller?.project, _projectRef)) {
      setState(() {});
      return;
    }
    setState(() {
      _projectRef = controller?.project;
      _result = null;
    });
  }

  /// 生成预览（§10.8）：编译当前项目，不弹提示/对话框（面板态即反馈）。
  ///
  /// 无错误 → 展开 + 代码 tab + 滚动到顶；有错误 → 展开 + 诊断 tab。
  /// 无脚本项目时忽略。
  void generatePreview() {
    final GraphEditorController? controller = widget.controller;
    if (controller == null) {
      return;
    }
    final ScriptCompileResult result = _generator.compile(
      controller.project,
      packName: widget.pack.name,
    );
    setState(() {
      _result = result;
      _expanded = true;
      _tab = result.hasErrors ? _OutputTab.diagnostics : _OutputTab.code;
    });
    if (!result.hasErrors) {
      _scrollCodeToTop();
    }
  }

  void _scrollCodeToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_codeScrollController.hasClients) {
        return;
      }
      _codeScrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 顶边分隔线由外层 DecoratedBox 覆盖绘制：AnimatedContainer 的 34/220
    // 高度全额留给「头部 34 + 内容 186」，不被边框挤压。
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FluentTheme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: FluentTheme.of(
                context,
              ).resources.dividerStrokeColorDefault,
            ),
          ),
        ),
        child: AnimatedContainer(
          key: const Key('outputPanel'),
          height: _expanded
              ? outputPanelExpandedHeight
              : outputPanelCollapsedHeight,
          duration: _panelAnimationDuration,
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(),
              if (_expanded) Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: outputPanelCollapsedHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: FluentTheme.of(context).resources.dividerStrokeColorDefault,
          ),
        ),
      ),
      child: _expanded ? _buildExpandedHeader() : _buildCollapsedHeader(),
    );
  }

  Widget _buildCollapsedHeader() {
    final (int errors, int warnings) = _diagnosticCounts();
    return Row(
      children: <Widget>[
        Text(
          '输出',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: FluentTheme.of(context).resources.textFillColorPrimary,
          ),
        ),
        if (errors > 0 || warnings > 0) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            _summaryLabel(errors, warnings),
            style: TextStyle(
              fontSize: 12,
              color: errors > 0 ? AppColors.critical(FluentTheme.of(context).brightness) : AppColors.caution(FluentTheme.of(context).brightness),
            ),
          ),
        ],
        const Spacer(),
        _buildToggleButton(),
      ],
    );
  }

  Widget _buildExpandedHeader() {
    final (int errors, int warnings) = _diagnosticCounts();
    return Row(
      children: <Widget>[
        _TabButton(
          key: const Key('outputTabCode'),
          label: '代码预览',
          active: _tab == _OutputTab.code,
          onTap: () => setState(() => _tab = _OutputTab.code),
        ),
        _TabButton(
          key: const Key('outputTabDiagnostics'),
          label: '诊断',
          count: errors + warnings,
          countColor: _countColor(errors, warnings),
          active: _tab == _OutputTab.diagnostics,
          onTap: () => setState(() => _tab = _OutputTab.diagnostics),
        ),
        const Spacer(),
        Text(
          _statusText(),
          style: TextStyle(fontSize: 12, color: FluentTheme.of(context).resources.textFillColorTertiary),
        ),
        const SizedBox(width: 8),
        _buildCopyButton(),
        const SizedBox(width: 4),
        _buildToggleButton(),
      ],
    );
  }

  Widget _buildToggleButton() {
    return SizedBox(
      width: 24,
      height: 24,
      child: Tooltip(
        message: _expanded ? '收起' : '展开',
        child: IconButton(
          icon: Icon(
            _expanded ? FluentIcons.chevron_down : FluentIcons.chevron_up,
            size: 14,
          ),
          onPressed: () => setState(() => _expanded = !_expanded),
        ),
      ),
    );
  }

  Widget _buildCopyButton() {
    return SizedBox(
      width: 24,
      height: 24,
      child: Tooltip(
        message: '复制代码',
        child: IconButton(
          icon: const Icon(FluentIcons.copy, size: 14),
          onPressed: _result?.code == null ? null : _copyCode,
        ),
      ),
    );
  }

  void _copyCode() {
    final String? code = _result?.code;
    if (code == null) {
      return;
    }
    Clipboard.setData(ClipboardData(text: code));
    showFloatingToast(context, '已复制代码');
  }

  Widget _buildContent() {
    return switch (_tab) {
      _OutputTab.code => _buildCodeView(),
      _OutputTab.diagnostics => _buildDiagnosticsView(),
    };
  }

  /// 代码视图（§7.2）：Consolas 13 代码容器（沿用 `pack_preview_dialog` 先例）。
  Widget _buildCodeView() {
    final ScriptCompileResult? result = _result;
    if (result == null) {
      return _centeredMessage(
        '点击顶栏「生成预览」生成 PowerShell 5.1 代码',
        FluentTheme.of(context).resources.textFillColorTertiary,
      );
    }
    final String? code = result.code;
    if (code == null) {
      return _centeredMessage('存在编译错误，未生成代码；请查看「诊断」', AppColors.critical(FluentTheme.of(context).brightness));
    }
    return Container(
      decoration: BoxDecoration(
        color: FluentTheme.of(
          context,
        ).resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: FluentTheme.of(context).resources.cardStrokeColorDefault,
        ),
      ),
      child: Scrollbar(
        controller: _codeScrollController,
        child: SingleChildScrollView(
          controller: _codeScrollController,
          primary: false,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            code,
            style: _monoTextStyle.copyWith(color: FluentTheme.of(context).resources.textFillColorPrimary),
          ),
        ),
      ),
    );
  }

  /// 诊断清单（§7.3）：错误在前；行可点击时选中节点并居中。
  Widget _buildDiagnosticsView() {
    final List<ScriptDiagnostic> diagnostics = sortedDiagnostics(
      widget.controller?.diagnostics ?? const <ScriptDiagnostic>[],
    );
    if (diagnostics.isEmpty) {
      return _centeredMessage('没有发现错误或警告', FluentTheme.of(context).resources.textFillColorTertiary);
    }
    return ListView.builder(
      primary: false,
      padding: EdgeInsets.zero,
      itemCount: diagnostics.length,
      itemBuilder: (BuildContext context, int index) {
        final ScriptDiagnostic diagnostic = diagnostics[index];
        return _DiagnosticRow(
          key: Key('diagnosticRow_$index'),
          diagnostic: diagnostic,
          chipLabel: _nodeChipLabel(diagnostic.nodeId),
          onTap: _diagnosticTap(diagnostic),
        );
      },
    );
  }

  Widget _centeredMessage(String message, Color color) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }

  /// 头部状态文本（§7.1）：未生成 / 已生成 · N 行 / N 个错误 · M 个警告。
  String _statusText() {
    final ScriptCompileResult? result = _result;
    if (result == null) {
      return '未生成';
    }
    if (result.hasErrors) {
      final (int errors, int warnings) = _resultCounts(result);
      return '$errors 个错误 · $warnings 个警告';
    }
    final String? code = result.code;
    return code == null ? '未生成' : '已生成 · ${_lineCount(code)} 行';
  }

  /// 代码行数：按换行符切分，末尾换行不计入行数。
  int _lineCount(String code) {
    if (code.isEmpty) {
      return 0;
    }
    final int trailingBreak = code.endsWith('\n') ? 1 : 0;
    return code.split('\n').length - trailingBreak;
  }

  (int, int) _diagnosticCounts() {
    return _counts(
      widget.controller?.diagnostics ?? const <ScriptDiagnostic>[],
    );
  }

  (int, int) _resultCounts(ScriptCompileResult result) {
    return _counts(result.diagnostics);
  }

  (int, int) _counts(List<ScriptDiagnostic> diagnostics) {
    int errors = 0;
    int warnings = 0;
    for (final ScriptDiagnostic diagnostic in diagnostics) {
      if (diagnostic.isError) {
        errors++;
      } else {
        warnings++;
      }
    }
    return (errors, warnings);
  }

  /// 计数着色（§7.1）：有错误 red、仅警告 yellow、无问题 subtext0。
  Color _countColor(int errors, int warnings) {
    if (errors > 0) {
      return AppColors.critical(FluentTheme.of(context).brightness);
    }
    if (warnings > 0) {
      return AppColors.caution(FluentTheme.of(context).brightness);
    }
    return FluentTheme.of(context).resources.textFillColorTertiary;
  }

  String _summaryLabel(int errors, int warnings) {
    return errors > 0 ? '$errors 个错误' : '$warnings 个警告';
  }

  VoidCallback? _diagnosticTap(ScriptDiagnostic diagnostic) {
    if (_nodeById(diagnostic.nodeId) == null) {
      return null;
    }
    return () => _handleDiagnosticTap(diagnostic.nodeId);
  }

  void _handleDiagnosticTap(String? nodeId) {
    final GraphEditorController? controller = widget.controller;
    final ScriptNodeModel? node = _nodeById(nodeId);
    if (controller == null || node == null) {
      return;
    }
    controller.selectNode(node.id);
    _centerNode(node);
  }

  ScriptNodeModel? _nodeById(String? nodeId) {
    if (nodeId == null) {
      return null;
    }
    for (final ScriptNodeModel node
        in widget.controller?.project.nodes ?? const <ScriptNodeModel>[]) {
      if (node.id == nodeId) {
        return node;
      }
    }
    return null;
  }

  /// 节点 chip 文案：注册表显示名，未知类型回退原始类型键（§7.3）。
  String? _nodeChipLabel(String? nodeId) {
    final ScriptNodeModel? node = _nodeById(nodeId);
    if (node == null) {
      return null;
    }
    return NodeRegistry.byType(node.type)?.displayName ?? node.type;
  }

  /// 诊断行点击的视口居中（§7.3/§10.9）：节点中心对齐视口中心，缩放不变。
  ///
  /// §7.3 公式以「视口左上角场景坐标」表达；本仓 `TransformationController`
  /// 的平移分量为屏幕空间偏移（T5 约定），换算后实际实现：
  /// `平移 = 视口尺寸 / 2 − 节点中心 × scale`。
  void _centerNode(ScriptNodeModel node) {
    final TransformationController? transformation =
        widget.transformationController;
    final Size? viewportSize = widget.viewportSizeProvider?.call();
    if (transformation == null || viewportSize == null) {
      return;
    }
    final double scale = transformation.value.getMaxScaleOnAxis();
    final double cardHeight = nodeCardHeight(NodeRegistry.byType(node.type));
    transformation.value = Matrix4.identity()
      ..translateByDouble(
        viewportSize.width / 2 - (node.x + nodeCardWidth / 2) * scale,
        viewportSize.height / 2 - (node.y + cardHeight / 2) * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }
}

/// 面板标签按钮（§7.1）：高 34、内边距 H10，激活为 13 `text` + 2px accent 下划线。
class _TabButton extends StatefulWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
    this.countColor,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// 诊断计数；非 null 时以「（N）」紧随标签并单独着色。
  final int? count;
  final Color? countColor;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = widget.active
        ? FluentTheme.of(context).resources.textFillColorPrimary
        : FluentTheme.of(context).resources.textFillColorSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (PointerEnterEvent event) => setState(() => _hovered = true),
      onExit: (PointerExitEvent event) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: outputPanelCollapsedHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered && !widget.active
                ? FluentTheme.of(context).resources.controlFillColorSecondary
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.active
                    ? FluentTheme.of(context).accentColor
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.label,
                style: TextStyle(fontSize: 13, color: labelColor),
              ),
              if (widget.count != null)
                Text(
                  '（${widget.count}）',
                  key: const Key('outputTabDiagnosticsCount'),
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.countColor ?? labelColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 诊断行（§7.3）：级别图标 14（占宽 20）+ 消息（自动换行）+ 节点 chip。
///
/// [onTap] 为 null（节点不存在）时不可点击、光标保持默认。
class _DiagnosticRow extends StatefulWidget {
  const _DiagnosticRow({
    super.key,
    required this.diagnostic,
    required this.chipLabel,
    required this.onTap,
  });

  final ScriptDiagnostic diagnostic;
  final String? chipLabel;
  final VoidCallback? onTap;

  @override
  State<_DiagnosticRow> createState() => _DiagnosticRowState();
}

class _DiagnosticRowState extends State<_DiagnosticRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool clickable = widget.onTap != null;
    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (PointerEnterEvent event) => setState(() => _hovered = true),
      onExit: (PointerExitEvent event) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? FluentTheme.of(context).resources.controlFillColorSecondary : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 20,
                child: Icon(
                  widget.diagnostic.isError
                      ? FluentIcons.error_badge
                      : FluentIcons.warning,
                  size: 14,
                  color: widget.diagnostic.isError
                      ? AppColors.critical(FluentTheme.of(context).brightness)
                      : AppColors.caution(FluentTheme.of(context).brightness),
                ),
              ),
              Expanded(
                child: Text(
                  widget.diagnostic.message,
                  style: TextStyle(fontSize: 12, color: FluentTheme.of(context).resources.textFillColorPrimary),
                ),
              ),
              if (widget.chipLabel != null) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: FluentTheme.of(
                      context,
                    ).resources.solidBackgroundFillColorQuarternary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.chipLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      color: FluentTheme.of(context).resources.textFillColorSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
