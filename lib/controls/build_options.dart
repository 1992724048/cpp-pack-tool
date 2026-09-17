import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 【文件管理】页构建选项分区：头部折叠开关 + 三型选项行（下拉 / 复选 / 多选）。
///
/// 选项按 `build.py` 声明顺序渲染；值变更经 [onChange] 上报（`null` 表示移除保存键）；
/// [saving] 为保存挂起标志，为 true 时全部控件禁用（fluent 禁用态）。
class BuildOptionsPanel extends StatefulWidget {
  const BuildOptionsPanel(
      {super.key, required this.options, required this.values, required this.expanded, required this.onToggleExpanded, required this.saving, required this.onChange});

  final List<BuildScriptOption> options;

  /// 包内已保存的选项值（`PackModel.buildOptions`）。
  final Map<String, String> values;

  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool saving;
  final void Function(String name, String? value) onChange;

  @override
  State<BuildOptionsPanel> createState() => _BuildOptionsPanelState();
}

class _BuildOptionsPanelState extends State<BuildOptionsPanel> {
  static const double _optionFieldWidth = 120;
  static const double _maxListHeight = 168;
  static const double _multiSelectMaxWidth = 420;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Padding(
      key: const Key('buildOptionsSection'),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Card(
            margin: EdgeInsetsGeometry.fromLTRB(0, 3, 0, 0),
            padding: EdgeInsetsGeometry.fromLTRB(5, 2, 5, 2),
            child: Row(
              children: <Widget>[
                Text(
                  '构建选项',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: theme.resources.textFillColorPrimary),
                ),
                SizedBox(width: 5),
                Text(('(${widget.options.length} 项)'), style: TextStyle(color: FluentTheme
                    .of(context)
                    .resources
                    .textFillColorSecondary)),
                const Spacer(),
                _buildToggle(),
              ],
            ),
          ),
          if (widget.expanded) ...<Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxListHeight),
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  key: const Key('buildOptionsScroll'),
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int index = 0; index < widget.options.length; index++) ...<Widget>[
                        Card(margin: EdgeInsetsGeometry.fromLTRB(0, 3, 0, 0), padding: EdgeInsetsGeometry.fromLTRB(
                            0, 0, 0, 0), child: _buildOptionRow(theme, widget.options[index])),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return SizedBox(
      width: 26,
      height: 26,
      child: Tooltip(
        message: widget.expanded ? '收起构建选项' : '展开构建选项',
        child: IconButton(key: const Key('buildOptionsToggle'),
            icon: Icon(widget.expanded ? FluentIcons.chevron_down : FluentIcons.chevron_up, size: 15),
            onPressed: widget.onToggleExpanded),
      ),
    );
  }

  Widget _buildOptionRow(FluentThemeData theme, BuildScriptOption option) {
    switch (option.control) {
      case BuildOptionControl.dropdown:
        return _buildDropdownRow(theme, option);
      case BuildOptionControl.checkbox:
        return _CheckboxOptionRow(option: option,
            value: effectiveBuildOptionValue(option, widget.values),
            enabled: !widget.saving,
            onChanged: widget.onChange);
      case BuildOptionControl.multiselect:
        return _buildMultiSelectRow(theme, option);
    }
  }

  Widget _buildDropdownRow(FluentThemeData theme, BuildScriptOption option) {
    final String value = effectiveBuildOptionValue(option, widget.values);
    return SizedBox(
      key: Key('buildOptionRow_${option.name}'),
      height: 40,
      child: Padding(
        padding: EdgeInsetsGeometry.fromLTRB(5, 0, 5, 0),
        child: Row(
          children: <Widget>[
            Expanded(child: _buildOptionTitle(theme, option.name)),
            SizedBox(
              width: _optionFieldWidth,
              child: FluentTheme(
                data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
                child: ComboBox<String>(
                  key: Key('buildOption_${option.name}'),
                  value: value,
                  isExpanded: true,
                  onChanged: widget.saving
                      ? null
                      : (String? selected) {
                    if (selected != null && selected != value) {
                      widget.onChange(option.name, selected);
                    }
                  },
                  items: <ComboBoxItem<String>>[
                    for (final String item in option.values)
                      ComboBoxItem<String>(
                        value: item,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiSelectRow(FluentThemeData theme, BuildScriptOption option) {
    final Set<String> selected = multiSelectSelection(option.values, widget.values[option.name]);
    return Padding(
      padding: EdgeInsetsGeometry.fromLTRB(5, 0, 5, 0),
      child: ConstrainedBox(
        key: Key('buildOptionRow_${option.name}'),
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: <Widget>[
            Expanded(child: _buildOptionTitle(theme, option.name)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _multiSelectMaxWidth),
              child: Wrap(
                key: Key('buildOption_${option.name}'),
                alignment: WrapAlignment.end,
                spacing: 16,
                runSpacing: 6,
                children: <Widget>[
                  for (final String value in option.values) _buildMultiSelectItem(
                      option, value, selected.contains(value))
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiSelectItem(BuildScriptOption option, String value, bool checked) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Checkbox(
          key: Key('buildOptionValue_${option.name}_$value'),
          checked: checked,
          semanticLabel: value,
          onChanged: widget.saving ? null : (bool? next) => _toggleMultiSelectValue(option, value, next ?? !checked),
        ),
        const SizedBox(width: 8),
        Text(value, style: _optionTextStyle(FluentTheme.of(context))),
      ],
    );
  }

  void _toggleMultiSelectValue(BuildScriptOption option, String value, bool checked) {
    final Set<String> current = multiSelectSelection(option.values, widget.values[option.name]);
    final List<String> selected = <String>[
      for (final String candidate in option.values)
        if (candidate == value ? checked : current.contains(candidate)) candidate,
    ];
    widget.onChange(option.name, selected.join(';'));
  }
}

/// 选项标题 / 多选值文本：13 常规 `textFillColorPrimary`、超宽省略。
TextStyle _optionTextStyle(FluentThemeData theme) =>
    TextStyle(fontSize: 13, color: theme.resources.textFillColorPrimary);

Widget _buildOptionTitle(FluentThemeData theme, String name) =>
    Text(name, overflow: TextOverflow.ellipsis, style: _optionTextStyle(theme));

/// 布尔选项行：整行可点（悬停背景 + click 光标），Checkbox 自身保留键盘切换；
/// 行外层与 Checkbox 手势竞技场由内层胜出，单击只切换一次。
class _CheckboxOptionRow extends StatefulWidget {
  const _CheckboxOptionRow({required this.option, required this.value, required this.enabled, required this.onChanged});

  final BuildScriptOption option;
  final String value;
  final bool enabled;
  final void Function(String name, String? value) onChanged;

  @override
  State<_CheckboxOptionRow> createState() => _CheckboxOptionRowState();
}

class _CheckboxOptionRowState extends State<_CheckboxOptionRow> {
  bool _hovered = false;

  bool get _checked => widget.value == widget.option.values.first;

  void _toggle() {
    if (!widget.enabled) {
      return;
    }
    final List<String> values = widget.option.values;
    widget.onChanged(widget.option.name, _checked ? values[1] : values[0]);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Container(
          margin: EdgeInsetsGeometry.all(0),
          padding: EdgeInsetsGeometry.fromLTRB(5, 0, 5, 0),
          key: Key('buildOptionRow_${widget.option.name}'),
          constraints: const BoxConstraints(minHeight: 40),
          decoration: BoxDecoration(color: _hovered ? theme.resources.controlFillColorSecondary : Colors.transparent,
              borderRadius: BorderRadius.circular(4)),
          child: Row(
            children: <Widget>[
              Expanded(child: _buildOptionTitle(theme, widget.option.name)),
              Checkbox(key: Key('buildOption_${widget.option.name}'),
                  checked: _checked,
                  semanticLabel: widget.option.name,
                  onChanged: widget.enabled ? (bool? _) => _toggle() : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// 运行库家族选择器（工具栏，构建按钮右侧）：默认（跟随配方）/ MD / MT。
///
/// 保存口径：默认 = 键不存在（[onChanged] 收到 null）；MD / MT = 显式写入。
class RuntimeLibrarySelector extends StatelessWidget {
  const RuntimeLibrarySelector({super.key, required this.value, required this.enabled, required this.onChanged});

  /// 当前保存值：`MD` / `MT`；null 显示「默认（跟随配方）」。
  final String? value;

  final bool enabled;
  final ValueChanged<String?> onChanged;

  static const String _defaultItemValue = 'default';
  static const double _width = 75;

  @override
  Widget build(BuildContext context) {
    final TextStyle boldPhrase = const TextStyle(fontWeight: FontWeight.w600);
    return Tooltip(
      richMessage: TextSpan(
        children: <InlineSpan>[
          TextSpan(text: '运行库（MSVC CRT）', style: boldPhrase),
          const TextSpan(text: '\n· '),
          TextSpan(text: '默认', style: boldPhrase),
          const TextSpan(
            text:
            '：由 build.py 配方的编译参数决定；'
                '需要覆盖时再显式选择 MD / MT。',
          ),
          const TextSpan(text: '\n· '),
          TextSpan(text: 'MD（动态运行库）', style: boldPhrase),
          const TextSpan(
            text:
            '：CRT 以共享 dll 提供，多个模块共用同一份，产物体积更小；'
                '运行需目标机器安装匹配的 VC++ Redistributable。',
          ),
          const TextSpan(text: '\n· '),
          TextSpan(text: 'MT（静态运行库）', style: boldPhrase),
          const TextSpan(
            text:
            '：CRT 静态链入每个模块，无运行时依赖、部署最简单；'
                '各模块各自持有一份，总体积更大。',
          ),
          const TextSpan(text: '\n· Debug 构建自动使用 d 变体（MDd / MTd），无需手动切换。'),
          const TextSpan(text: '\n· 推荐：优先 MD 并随包分发共享 dll + lib，可显著减小体积；需要免依赖分发时选 MT。'),
        ],
      ),
      style: const TooltipThemeData(maxWidth: 360, showDuration: Duration(seconds: 30)),
      child: SizedBox(
        width: _width,
        height: 29,
        child: ComboBox<String>(
          key: const Key('buildRuntimeSelector'),
          value: value ?? _defaultItemValue,
          isExpanded: true,
          onChanged: enabled ? (String? selected) =>
              onChanged(selected == null || selected == _defaultItemValue ? null : selected) : null,
          items: const <ComboBoxItem<String>>[
            ComboBoxItem<String>(
              value: _defaultItemValue,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('默认', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            ComboBoxItem<String>(
              value: 'MD',
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('MD', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            ComboBoxItem<String>(
              value: 'MT',
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('MT', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
