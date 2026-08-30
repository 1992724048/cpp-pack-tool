/// 编译配置 Tab：C++ 标准、全局宏、分配置宏表、附加包含/库目录、附加依赖、
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
];

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
  late TextEditingController _defines;
  late TextEditingController _includeDirs;
  late TextEditingController _libDirs;
  late TextEditingController _deps;
  final Map<String, TextEditingController> _configControllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    final compile = widget.project?.compileConfig;
    _defines = TextEditingController(text: compile?.preprocessorDefines ?? '');
    _includeDirs = TextEditingController(
      text: compile?.additionalIncludeDirectories ?? '',
    );
    _libDirs = TextEditingController(
      text: compile?.additionalLibraryDirectories ?? '',
    );
    _deps = TextEditingController(text: compile?.additionalDependencies ?? '');
    _syncConfigControllers();
  }

  @override
  void didUpdateWidget(BuildConfigPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncConfigControllers();
    _syncText(
      widget.project?.compileConfig.preprocessorDefines,
      _defines,
      oldWidget.project?.compileConfig.preprocessorDefines,
    );
    _syncText(
      widget.project?.compileConfig.additionalIncludeDirectories,
      _includeDirs,
      oldWidget.project?.compileConfig.additionalIncludeDirectories,
    );
    _syncText(
      widget.project?.compileConfig.additionalLibraryDirectories,
      _libDirs,
      oldWidget.project?.compileConfig.additionalLibraryDirectories,
    );
    _syncText(
      widget.project?.compileConfig.additionalDependencies,
      _deps,
      oldWidget.project?.compileConfig.additionalDependencies,
    );
  }

  @override
  void dispose() {
    _defines.dispose();
    _includeDirs.dispose();
    _libDirs.dispose();
    _deps.dispose();
    for (final controller in _configControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncText(
    String? value,
    TextEditingController controller,
    String? oldValue,
  ) {
    final next = value ?? '';
    if (next != controller.text && next != oldValue) {
      controller.text = next;
    }
  }

  void _syncConfigControllers() {
    final configs = widget.project?.configurations ?? const <String>[];
    final wanted = configs.toSet();
    final stale = _configControllers.keys
        .where((c) => !wanted.contains(c))
        .toList();
    for (final key in stale) {
      _configControllers.remove(key)?.dispose();
    }
    for (final config in configs) {
      if (!_configControllers.containsKey(config)) {
        _configControllers[config] = TextEditingController(
          text: widget.project?.compileConfig.configDefines[config] ?? '',
        );
      }
    }
  }

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
          LabeledFormField(
            label: '全局宏（分号分隔）',
            child: TextFormField(
              controller: _defines,
              style: monoTextStyle(),
              onChanged: (value) => _update(
                project.copyWith(
                  compileConfig: compile.copyWith(preprocessorDefines: value),
                ),
              ),
              decoration: const InputDecoration(
                hintText: '如 NOMINMAX;V8_ENABLE_WEBASSEMBLY',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _configDefinesSection(project, compile),
          const SizedBox(height: AppSpacing.s2),
          _pathSection(
            label: '附加包含目录（分号分隔）',
            controller: _includeDirs,
            hint: '如 \$(MSBuildThisFileDirectory)include;..\\include',
            onChanged: (value) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(
                  additionalIncludeDirectories: value,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _pathSection(
            label: '附加库目录（分号分隔）',
            controller: _libDirs,
            hint: '如 ..\\lib\\x64',
            onChanged: (value) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(
                  additionalLibraryDirectories: value,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _pathSection(
            label: '附加依赖（分号分隔）',
            controller: _deps,
            hint: '如 ws2_32.lib;ntdll.lib',
            onChanged: (value) => _update(
              project.copyWith(
                compileConfig: compile.copyWith(additionalDependencies: value),
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
            DropdownMenuItem(value: standard, child: Text(standard)),
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
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    config,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppFontSizes.body,
                    ),
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _configController(config),
                    style: monoTextStyle(),
                    onChanged: (value) => _update(
                      project.copyWith(
                        compileConfig: compile.copyWith(
                          configDefines: {
                            ...compile.configDefines,
                            config: value,
                          },
                        ),
                      ),
                    ),
                    decoration: const InputDecoration(
                      hintText: '该配置追加的宏，如 V8_ENABLE_CHECKS',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  TextEditingController _configController(String config) =>
      _configControllers[config]!;

  Widget _pathSection({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return LabeledFormField(
      label: label,
      child: TextFormField(
        controller: controller,
        style: monoTextStyle(),
        onChanged: onChanged,
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }

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

/// 字符串列表编辑器（数据拷贝清单 / 注入源码清单共用）。
class StringListEditor extends StatefulWidget {
  const StringListEditor({
    super.key,
    required this.values,
    required this.hint,
    required this.onChanged,
  });

  final List<String> values;
  final String hint;
  final ValueChanged<List<String>> onChanged;

  @override
  State<StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<StringListEditor> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  Widget _itemRow(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.values[index],
              style: monoTextStyle(),
              overflow: TextOverflow.ellipsis,
            ),
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

  void _add() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.onChanged([...widget.values, text]);
    _input.clear();
  }

  void _removeAt(int index) {
    final next = List<String>.of(widget.values)..removeAt(index);
    widget.onChanged(next);
  }
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
