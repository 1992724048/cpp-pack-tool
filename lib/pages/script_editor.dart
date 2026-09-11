import 'package:cpp_nuget_pack/controls/script_editor/editor_canvas.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/codegen/script_code_generator.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _topBarHeight = 48;
const double _nodeLibraryWidth = 232;
const double _inspectorWidth = 280;
const double _outputPanelCollapsedHeight = 34;
const double _titleMaxWidth = 240;

/// 节点编辑器全屏页（T4 外壳，各面板经后续任务装配）。
///
/// 布局数值与分隔线取自视觉规范 §1/§3（顶栏 48、左 232、右 280、底部收起 34、
/// 1px `surface2` 分隔）；[pack] 无脚本项目时页面为空态（中区占位文案、两侧面板禁用），
/// 返回行为在保存队列（T10）接入前直接 pop。
class ScriptEditorPage extends StatefulWidget {
  const ScriptEditorPage({
    super.key,
    required this.pack,
    required this.onSave,
    this.generator,
    this.packagePaths,
  });

  final PackModel pack;
  final Future<bool> Function(PackModel pack) onSave;

  /// 代码生成器；null 时由生成预览（T9）回退 `PowerShell5Generator()`。
  final ScriptCodeGenerator? generator;

  /// 包内路径建议（检查器 T8 使用）；null 时由页面经 `NuGetBuilder` 计算。
  final List<String>? packagePaths;

  @override
  State<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends State<ScriptEditorPage> {
  GraphEditorController? _controller;

  bool get _hasProject => _controller != null;

  @override
  void initState() {
    super.initState();
    final List<ScriptProjectModel> scripts = widget.pack.scripts;
    _controller = scripts.isEmpty ? null : GraphEditorController(scripts.first);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('nodeEditorPage'),
      color: UCColors.flavor.mantle,
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildBody()),
          _buildOutputBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      key: const Key('editorTopBar'),
      height: _topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: UCColors.flavor.mantle,
        border: Border(bottom: BorderSide(color: UCColors.flavor.surface2)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: '返回包管理',
            child: IconButton(
              icon: const Icon(FluentIcons.back, size: 16),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _titleMaxWidth),
            child: Text(
              '节点编辑器 — ${widget.pack.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: UCColors.flavor.text,
              ),
            ),
          ),
          const Spacer(),
          _buildTopBarActions(),
        ],
      ),
    );
  }

  /// 顶栏动作预留区：项目选择器（T11）、保存状态（T10）、生成预览（T9）逐步追加。
  Widget _buildTopBarActions() {
    return const Row(
      key: Key('editorTopBarActions'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[],
    );
  }

  Widget _buildBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidePanel(
          panelKey: const Key('nodeLibraryPanel'),
          width: _nodeLibraryWidth,
          border: Border(right: BorderSide(color: UCColors.flavor.surface2)),
          child: const SizedBox.expand(),
        ),
        Expanded(child: _buildCanvasArea()),
        _buildSidePanel(
          panelKey: const Key('inspectorPanel'),
          width: _inspectorWidth,
          border: Border(left: BorderSide(color: UCColors.flavor.surface2)),
          child: const SizedBox.expand(),
        ),
      ],
    );
  }

  Widget _buildSidePanel({
    required Key panelKey,
    required double width,
    required Border border,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Opacity(
        key: panelKey,
        opacity: _hasProject ? 1.0 : 0.5,
        child: IgnorePointer(
          ignoring: !_hasProject,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UCColors.flavor.base,
              border: border,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasArea() {
    final GraphEditorController? controller = _controller;
    if (controller == null) {
      return Container(
        color: UCColors.flavor.mantle,
        child: Center(
          child: Text(
            '暂无脚本项目',
            style: TextStyle(fontSize: 12, color: UCColors.flavor.subtext0),
          ),
        ),
      );
    }
    return EditorCanvas(key: const Key('editorCanvas'), controller: controller);
  }

  Widget _buildOutputBar() {
    return Container(
      key: const Key('outputPanel'),
      height: _outputPanelCollapsedHeight,
      decoration: BoxDecoration(
        color: UCColors.flavor.base,
        border: Border(top: BorderSide(color: UCColors.flavor.surface2)),
      ),
    );
  }
}
