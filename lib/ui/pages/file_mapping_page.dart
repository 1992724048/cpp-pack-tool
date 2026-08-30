/// 文件映射 Tab：映射表（源 glob/目标路径/平台·配置条件/操作）+ 增删改 + 空态。
///
/// 对照 `docs/ui-spec.md` §3.5。行级技术列用等宽字体；删除为危险操作，
/// 删除前用确认弹窗（见 `confirmDelete`）。按钮 disabled 时整表占位。
library;

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../tokens.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/form_fields.dart';

const List<String> _kPlatforms = <String>['x64', 'x86', 'arm64'];
const List<String> _kConfigs = <String>['Debug', 'Release'];

/// 文件映射页。
class FileMappingPage extends StatefulWidget {
  const FileMappingPage({
    super.key,
    required this.project,
    required this.onChanged,
  });

  final PackProject? project;
  final ValueChanged<PackProject> onChanged;

  @override
  State<FileMappingPage> createState() => _FileMappingPageState();
}

class _FileMappingPageState extends State<FileMappingPage> {
  int _sourceIndex = 0;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    if (project == null) {
      return const _MappingPlaceholder();
    }
    final sourceDirs = project.sourceDirs;
    if (sourceDirs.isEmpty) {
      return const _NoSourceDir();
    }
    final effectiveIndex = _sourceIndex.clamp(0, sourceDirs.length - 1);
    final sourceDir = sourceDirs[effectiveIndex];

    return Column(
      children: [
        _toolbar(project, sourceDirs, effectiveIndex),
        const Divider(height: 1),
        _tableHeader(),
        Expanded(
          child: sourceDir.mappings.isEmpty
              ? _emptyMappings()
              : _mappingList(project, effectiveIndex, sourceDir),
        ),
      ],
    );
  }

  Widget _toolbar(
    PackProject project,
    List<SourceDir> sourceDirs,
    int effectiveIndex,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s1,
      ),
      child: Row(
        children: [
          const Text(
            '源目录',
            style: TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.small,
            ),
          ),
          const SizedBox(width: AppSpacing.s1),
          DropdownButton<int>(
            value: effectiveIndex,
            underline: const SizedBox.shrink(),
            items: [
              for (var i = 0; i < sourceDirs.length; i++)
                DropdownMenuItem(value: i, child: Text(sourceDirs[i].name)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sourceIndex = value);
            },
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => _addMapping(project, effectiveIndex),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加映射'),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      color: AppColors.bgSurface,
      child: Row(
        children: [
          _headerText('源 glob', flex: 3),
          _headerText('目标路径', flex: 3),
          _headerText('平台 · 配置', flex: 2),
          const SizedBox(width: 88),
        ],
      ),
    );
  }

  Widget _headerText(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSemantic,
          fontSize: AppFontSizes.small,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _mappingList(
    PackProject project,
    int sourceIndex,
    SourceDir sourceDir,
  ) {
    return ListView.builder(
      itemCount: sourceDir.mappings.length,
      itemBuilder: (context, index) {
        return _MappingRow(
          mapping: sourceDir.mappings[index],
          onEdit: () => _editMapping(project, sourceIndex, index),
          onDelete: () => _deleteMapping(project, sourceIndex, index),
        );
      },
    );
  }

  Widget _emptyMappings() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.grid_off_outlined,
            size: 36,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSpacing.s2),
          const Text(
            '尚无文件映射',
            style: TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.body,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          OutlinedButton(
            onPressed: () => _addMapping(widget.project!, _effectiveIndex()),
            child: const Text('添加映射'),
          ),
        ],
      ),
    );
  }

  int _effectiveIndex() {
    final count = widget.project?.sourceDirs.length ?? 0;
    if (count == 0) return 0;
    return _sourceIndex.clamp(0, count - 1);
  }

  Future<void> _addMapping(PackProject project, int sourceIndex) async {
    final sourceDir = project.sourceDirs[sourceIndex];
    final mapping = await showDialog<FileMapping>(
      context: context,
      builder: (_) => const MappingEditDialog(),
    );
    if (mapping == null) return;
    final updated = sourceDir.copyWith(
      mappings: [...sourceDir.mappings, mapping],
    );
    _commit(project, sourceIndex, updated);
  }

  Future<void> _editMapping(
    PackProject project,
    int sourceIndex,
    int mappingIndex,
  ) async {
    final sourceDir = project.sourceDirs[sourceIndex];
    final current = sourceDir.mappings[mappingIndex];
    final mapping = await showDialog<FileMapping>(
      context: context,
      builder: (_) => MappingEditDialog(initial: current),
    );
    if (mapping == null) return;
    final nextMappings = List<FileMapping>.of(sourceDir.mappings);
    nextMappings[mappingIndex] = mapping;
    _commit(project, sourceIndex, sourceDir.copyWith(mappings: nextMappings));
  }

  Future<void> _deleteMapping(
    PackProject project,
    int sourceIndex,
    int mappingIndex,
  ) async {
    final sourceDir = project.sourceDirs[sourceIndex];
    final mapping = sourceDir.mappings[mappingIndex];
    final confirmed = await confirmDelete(
      context,
      title: '删除确认',
      message: '确定删除映射「${mapping.srcGlob}」吗？此操作不可撤销。',
    );
    if (!confirmed) return;
    final nextMappings = List<FileMapping>.of(sourceDir.mappings)
      ..removeAt(mappingIndex);
    _commit(project, sourceIndex, sourceDir.copyWith(mappings: nextMappings));
  }

  void _commit(PackProject project, int sourceIndex, SourceDir updated) {
    final nextSourceDirs = List<SourceDir>.of(project.sourceDirs);
    nextSourceDirs[sourceIndex] = updated;
    widget.onChanged(project.copyWith(sourceDirs: nextSourceDirs));
  }
}

class _MappingRow extends StatefulWidget {
  const _MappingRow({
    required this.mapping,
    required this.onEdit,
    required this.onDelete,
  });

  final FileMapping mapping;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_MappingRow> createState() => _MappingRowState();
}

class _MappingRowState extends State<_MappingRow> {
  bool _hovered = false;

  String get _condition {
    if (widget.mapping.platforms.isEmpty &&
        widget.mapping.configurations.isEmpty) {
      return '全部';
    }
    final parts = <String>[
      if (widget.mapping.platforms.isNotEmpty)
        widget.mapping.platforms.join('/'),
      if (widget.mapping.configurations.isNotEmpty)
        widget.mapping.configurations.join('/'),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        color: _hovered ? AppColors.bgHover : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                widget.mapping.srcGlob,
                style: monoTextStyle(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                widget.mapping.target,
                style: monoTextStyle(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _condition,
                style: const TextStyle(
                  color: AppColors.textSemantic,
                  fontSize: AppFontSizes.small,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onEdit,
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    iconSize: 16,
                    color: AppColors.textSemantic,
                  ),
                  IconButton(
                    onPressed: widget.onDelete,
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 16),
                    iconSize: 16,
                    color: AppColors.error,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 映射编辑对话框（新增/编辑共用）。
class MappingEditDialog extends StatefulWidget {
  const MappingEditDialog({super.key, this.initial});

  final FileMapping? initial;

  @override
  State<MappingEditDialog> createState() => _MappingEditDialogState();
}

class _MappingEditDialogState extends State<MappingEditDialog> {
  late TextEditingController _srcGlob;
  late TextEditingController _target;
  late Set<String> _platforms;
  late Set<String> _configs;

  @override
  void initState() {
    super.initState();
    _srcGlob = TextEditingController(text: widget.initial?.srcGlob ?? '');
    _target = TextEditingController(text: widget.initial?.target ?? '');
    _platforms = (widget.initial?.platforms ?? const <String>[]).toSet();
    _configs = (widget.initial?.configurations ?? const <String>[]).toSet();
  }

  @override
  void dispose() {
    _srcGlob.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ActionDialog(
      title: widget.initial == null ? '添加映射' : '编辑映射',
      onConfirm: _save,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabeledFormField(
              label: '源 glob',
              child: TextField(
                controller: _srcGlob,
                style: monoTextStyle(),
                decoration: const InputDecoration(
                  hintText: '如 include/**/*.h 或 x64/Release/*.lib',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            LabeledFormField(
              label: '目标路径',
              child: TextField(
                controller: _target,
                style: monoTextStyle(),
                decoration: const InputDecoration(
                  hintText: '如 build\\native\\lib\\x64\\Debug',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            _chipGroupLabel('平台（空 = 全部）'),
            _chipGroup(_kPlatforms, _platforms),
            const SizedBox(height: AppSpacing.s1),
            _chipGroupLabel('配置（空 = 全部）'),
            _chipGroup(_kConfigs, _configs),
          ],
        ),
      ),
    );
  }

  Widget _chipGroupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSemantic,
          fontSize: AppFontSizes.small,
        ),
      ),
    );
  }

  Widget _chipGroup(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: AppSpacing.s1,
      runSpacing: AppSpacing.s1,
      children: [
        for (final option in options)
          FilterChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (value) => setState(() {
              if (value) {
                selected.add(option);
              } else {
                selected.remove(option);
              }
            }),
            selectedColor: AppColors.accent,
            checkmarkColor: AppColors.textOnDark,
            labelStyle: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppFontSizes.small,
            ),
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
      ],
    );
  }

  void _save() {
    final base = widget.initial ?? FileMapping();
    final platforms = _platforms.toList()..sort();
    final configs = _configs.toList()..sort();
    Navigator.of(context).pop(
      base.copyWith(
        srcGlob: _srcGlob.text.trim(),
        target: _target.text.trim(),
        platforms: platforms,
        configurations: configs,
      ),
    );
  }
}

/// 通用底部动作对话框外壳（标题 + 内容 + 取消/确认）。
class ActionDialog extends StatelessWidget {
  const ActionDialog({
    super.key,
    required this.title,
    required this.child,
    required this.onConfirm,
    this.confirmLabel = '保存',
  });

  final String title;
  final Widget child;
  final VoidCallback onConfirm;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.s4),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppFontSizes.h3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              child,
              const SizedBox(height: AppSpacing.s3),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  FilledButton(onPressed: onConfirm, child: Text(confirmLabel)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MappingPlaceholder extends StatelessWidget {
  const _MappingPlaceholder();

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

class _NoSourceDir extends StatelessWidget {
  const _NoSourceDir();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 36,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSpacing.s2),
          const Text(
            '当前库项目还没有源目录',
            style: TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.body,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          const Text(
            '请点击左栏「+」添加源目录，扫描后自动生成映射',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textDisabled,
              fontSize: AppFontSizes.small,
            ),
          ),
        ],
      ),
    );
  }
}
