/// 编译配置 Tab：C++ 标准、全局宏、分配置宏折叠列表、附加包含/库目录、附加依赖、
/// 数据文件拷贝清单、消费者源码注入清单。
///
/// 对照 `docs/ui-spec.md` §3.4 与任务清单「编译配置表单」。路径/宏等数据
/// 用等宽字体；表单错误以内联 errorText 呈现。
library;

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../tokens.dart';
import '../widgets/form_fields.dart';

/// C++ 标准可选值。
const List<String> _kLanguageStandards = <String>[
  'stdcpp14',
  'stdcpp17',
  'stdcpp20',
  'stdcpp23',
  'stdcpplatest',
];

/// C 语言标准可选值（空 = 不设置）。
const List<String> _kCLanguageStandards = <String>['', 'c11', 'c17'];

/// 编译配置页。
class BuildConfigPage extends StatefulWidget {
  const BuildConfigPage({
    super.key,
    required this.project,
    required this.onChanged,
  });

  final PackProject? project;
  final ValueChanged<PackProject> onChanged;

  @override
  State<BuildConfigPage> createState() => _BuildConfigPageState();
}

class _BuildConfigPageState extends State<BuildConfigPage> {
  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    if (project == null) {
      return const _ConfigPlaceholder();
    }
    final compile = project.compileConfig;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '编译配置'),
          _standardField(project, compile),
          const SizedBox(height: AppSpacing.s2),
          _cStandardField(project, compile),
          const SizedBox(height: AppSpacing.s2),
          _listEditorSection(
            label: '全局宏',
            values: _splitSemis(compile.preprocessorDefines),
            hint: '如 NOMINMAX、V8_ENABLE_WEBASSEMBLY',
            onChanged: (values) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(
                  preprocessorDefines: _joinSemis(values),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _configDefinesSection(project, compile),
          const SizedBox(height: AppSpacing.s2),
          _listEditorSection(
            label: '附加包含目录',
            values: _splitSemis(compile.additionalIncludeDirectories),
            hint: '如 \$(MSBuildThisFileDirectory)include、..\\include',
            onChanged: (values) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(
                  additionalIncludeDirectories: _joinSemis(values),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _listEditorSection(
            label: '附加库目录',
            values: _splitSemis(compile.additionalLibraryDirectories),
            hint: '如 ..\\lib\\x64',
            onChanged: (values) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(
                  additionalLibraryDirectories: _joinSemis(values),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _listEditorSection(
            label: '附加依赖',
            values: _splitSemis(compile.additionalDependencies),
            hint: '如 ws2_32.lib、ntdll.lib',
            onChanged: (values) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(
                  additionalDependencies: _joinSemis(values),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _listEditorSection(
            label: '数据文件拷贝到消费方 OutDir',
            values: compile.dataFilesToCopy,
            hint: '如 icudtl.dat',
            onChanged: (values) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(dataFilesToCopy: values),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _listEditorSection(
            label: '消费者源码注入清单',
            values: compile.injectedSources,
            hint: '如 src\\v8wrap\\win32.cpp',
            onChanged: (values) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(injectedSources: values),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _standardField(PackProject project, CompileConfig compile) {
    return LabeledFormField(
      label: 'C++ 标准',
      child: DropdownButtonFormField<String>(
        initialValue: compile.languageStandard,
        items: [
          for (final standard in _kLanguageStandards)
            DropdownMenuItem(
              value: standard,
              child: Text(_standardLabel(standard)),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          _update(
            project.copyWith(
              compileConfig: compile.copyWith(languageStandard: value),
            ),
          );
        },
        decoration: const InputDecoration(),
      ),
    );
  }

  Widget _cStandardField(PackProject project, CompileConfig compile) {
    return LabeledFormField(
      label: 'C 语言标准',
      child: DropdownButtonFormField<String>(
        initialValue: compile.clanguageStandard,
        items: [
          for (final standard in _kCLanguageStandards)
            DropdownMenuItem(
              value: standard,
              child: Text(standard.isEmpty ? '不设置' : standard),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          _update(
            project.copyWith(
              compileConfig: compile.copyWith(clanguageStandard: value),
            ),
          );
        },
        decoration: const InputDecoration(),
      ),
    );
  }

  String _standardLabel(String value) {
    if (value == 'stdcpplatest') return 'Latest（最新）';
    return value;
  }

  Widget _configDefinesSection(PackProject project, CompileConfig compile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '分配置宏',
          style: TextStyle(
            color: AppColors.textSemantic,
            fontSize: AppFontSizes.small,
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        for (final config in project.configurations)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s1),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s1,
                ),
                shape: const Border(),
                collapsedShape: const Border(),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$config 宏',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: AppFontSizes.body,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s1),
                    _configBadge(config, compile),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.s2,
                      right: AppSpacing.s2,
                      bottom: AppSpacing.s2,
                    ),
                    child: StringListEditor(
                      values: _splitSemis(compile.configDefines[config] ?? ''),
                      hint: '该配置追加的宏，如 V8_ENABLE_CHECKS',
                      onChanged: (values) => _update(
                        project.copyWith(
                          compileConfig: compile.copyWith(
                            configDefines: {
                              ...compile.configDefines,
                              config: _joinSemis(values),
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 分配置宏折叠块左侧的已配置数量徽标；未配置显示「未配置」。
  Widget _configBadge(String config, CompileConfig compile) {
    final count = _splitSemis(compile.configDefines[config] ?? '').length;
    final label = count == 0 ? '未配置' : '$count 项';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s1,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSemantic,
          fontSize: AppFontSizes.caption,
        ),
      ),
    );
  }

  /// 按 `;` 拆分并去除空项（用于编辑分号分隔字符串的列表）。
  List<String> _splitSemis(String value) =>
      value.split(';').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  /// 用 `;` 连接已拆分的非空项。
  String _joinSemis(Iterable<String> parts) =>
      parts.where((t) => t.trim().isNotEmpty).join(';');

  Widget _listEditorSection({
    required String label,
    required List<String> values,
    required String hint,
    required ValueChanged<List<String>> onChanged,
  }) {
    return LabeledFormField(
      label: label,
      child: StringListEditor(values: values, hint: hint, onChanged: onChanged),
    );
  }

  void _update(PackProject project) => widget.onChanged(project);
}

/// 字符串列表编辑器（分号分隔字段 / 数据拷贝清单 / 注入源码清单共用）。
///
/// 每条目为「单行输入 + 删除按钮」，底部为新增输入框；[onChanged] 收到的是去空项
/// 后的列表（不保留空串）。[allowDuplicates] 为 false 时新增同名条目被忽略。
class StringListEditor extends StatefulWidget {
  const StringListEditor({
    super.key,
    required this.values,
    required this.hint,
    required this.onChanged,
    this.allowDuplicates = true,
  });

  final List<String> values;
  final String hint;
  final ValueChanged<List<String>> onChanged;
  final bool allowDuplicates;

  @override
  State<StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<StringListEditor> {
  final TextEditingController _input = TextEditingController();
  final List<TextEditingController> _itemControllers =
      <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    _syncItemControllers();
  }

  @override
  void didUpdateWidget(StringListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncItemControllers();
  }

  @override
  void dispose() {
    _input.dispose();
    for (final controller in _itemControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 使条目控制器数量与 [widget.values] 对齐并同步文本（仅文本不同才重置，
  /// 避免打字输入时光标跳回起点）。
  void _syncItemControllers() {
    final count = widget.values.length;
    while (_itemControllers.length < count) {
      _itemControllers.add(TextEditingController(text: ''));
    }
    while (_itemControllers.length > count) {
      _itemControllers.removeLast().dispose();
    }
    for (var i = 0; i < count; i++) {
      final value = widget.values[i];
      if (_itemControllers[i].text != value) {
        _itemControllers[i].text = value;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.values.isEmpty) _emptyPlaceholder(),
        for (var i = 0; i < widget.values.length; i++) _itemRow(i),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                style: monoTextStyle(),
                decoration: InputDecoration(hintText: widget.hint),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: AppSpacing.s1),
            OutlinedButton(onPressed: _add, child: const Text('添加')),
          ],
        ),
      ],
    );
  }

  Widget _emptyPlaceholder() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s1),
      child: Text(
        '未配置',
        style: const TextStyle(
          color: AppColors.textDisabled,
          fontSize: AppFontSizes.small,
        ),
      ),
    );
  }

  Widget _itemRow(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _itemControllers[index],
              style: monoTextStyle(),
              onChanged: (value) => _editItem(index, value),
            ),
          ),
          const SizedBox(width: AppSpacing.s1),
          IconButton(
            onPressed: () => _editItemDialog(index),
            tooltip: '修改',
            icon: const Icon(Icons.edit_outlined, size: 16),
            iconSize: 16,
            color: AppColors.textSemantic,
          ),
          IconButton(
            onPressed: () => _removeAt(index),
            tooltip: '移除',
            icon: const Icon(Icons.close, size: 16),
            iconSize: 16,
            color: AppColors.textSemantic,
          ),
        ],
      ),
    );
  }

  void _editItem(int index, String value) {
    final next = List<String>.of(widget.values);
    next[index] = value;
    widget.onChanged(_cleaned(next));
  }

  /// 打开单行输入对话框修改第 [index] 条；空值不保存并提示。
  Future<void> _editItemDialog(int index) async {
    final current = widget.values[index];
    final newValue = await _promptEditValue(
      context,
      initial: current,
      hint: widget.hint,
    );
    if (newValue == null || !mounted) return;
    if (!widget.allowDuplicates && widget.values.contains(newValue)) {
      return;
    }
    final next = List<String>.of(widget.values);
    next[index] = newValue;
    widget.onChanged(_cleaned(next));
  }

  Future<String?> _promptEditValue(
    BuildContext context, {
    required String initial,
    required String hint,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: monoTextStyle(),
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => _submitEdit(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => _submitEdit(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _submitEdit(BuildContext dialogContext, String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(dialogContext)
          .showSnackBar(const SnackBar(content: Text('内容不能为空')));
      return;
    }
    Navigator.of(dialogContext).pop(value);
  }

  void _add() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (!widget.allowDuplicates && widget.values.contains(text)) {
      _input.clear();
      return;
    }
    widget.onChanged(_cleaned([...widget.values, text]));
    _input.clear();
  }

  void _removeAt(int index) {
    final next = List<String>.of(widget.values)..removeAt(index);
    widget.onChanged(_cleaned(next));
  }

  List<String> _cleaned(List<String> values) =>
      values.where((t) => t.trim().isNotEmpty).toList();
}

class _ConfigPlaceholder extends StatelessWidget {
  const _ConfigPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '从左侧选择一个库项目开始编辑',
        style: TextStyle(
          color: AppColors.textSemantic,
          fontSize: AppFontSizes.body,
        ),
      ),
    );
  }
}
