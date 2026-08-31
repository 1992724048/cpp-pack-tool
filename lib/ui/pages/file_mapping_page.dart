/// 文件映射 Tab：映射表（源文件模式/目标路径/平台·配置条件/操作）+ 增删改 + 空态。
///
/// 对照 `docs/ui-spec.md` §3.5。行级技术列用等宽字体；删除为危险操作，
/// 删除前用确认弹窗（见 `confirmDelete`）。按钮 disabled 时整表占位。
library;

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../../services/scanner.dart';
import '../io_picker.dart';
import '../tokens.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/form_fields.dart';
import '../widgets/mapping_suggestion_list.dart';

const List<String> _kPlatforms = <String>['x64', 'x86', 'arm64'];
const List<String> _kConfigs = <String>['Debug', 'Release'];

/// 映射表可排序列。
enum _SortColumn { srcGlob, target, fileKind }

/// 「添加映射」对话框返回结果：新增的映射列表 + 是否来自目录扫描。
///
/// 手动输入恒为单条（[fromScan] false）；扫描目录可批量（[fromScan] true），
/// 供调用方记录「从目录扫描添加 N 条映射」日志。
class MappingAddResult {
  const MappingAddResult({required this.mappings, required this.fromScan});

  /// 新增的映射列表。
  final List<FileMapping> mappings;

  /// 是否来自目录扫描（批量）。
  final bool fromScan;
}

/// 文件映射页。
class FileMappingPage extends StatefulWidget {
  const FileMappingPage({
    super.key,
    required this.project,
    required this.onChanged,
    this.onLogInfo,
  });

  final PackProject? project;
  final ValueChanged<PackProject> onChanged;

  /// 追加 info 级日志的回调（由 MainShell 绑定到日志控制器）。用于记录
  /// 「从目录扫描添加 N 条映射」等来源信息；为 null 时静默跳过。
  final ValueChanged<String>? onLogInfo;

  @override
  State<FileMappingPage> createState() => _FileMappingPageState();
}

class _FileMappingPageState extends State<FileMappingPage> {
  int _sourceIndex = 0;

  /// 当前排序列；默认按源文件模式升序。
  _SortColumn _sortColumn = _SortColumn.srcGlob;

  /// 是否升序。
  bool _sortAscending = true;

  /// 按当前排序列与方向对映射列表排序（返回 `(原始下标, 映射)` 对，仅影响显示，
  /// 不修改底层数据；编辑/删除仍按原始下标定位）。
  List<(int, FileMapping)> _sortedMappings(SourceDir sourceDir) {
    final indexed = <(int, FileMapping)>[
      for (var i = 0; i < sourceDir.mappings.length; i++)
        (i, sourceDir.mappings[i]),
    ];
    indexed.sort((a, b) {
      final int comparison = switch (_sortColumn) {
        _SortColumn.srcGlob => a.$2.srcGlob.compareTo(b.$2.srcGlob),
        _SortColumn.target => a.$2.target.compareTo(b.$2.target),
        _SortColumn.fileKind => a.$2.fileKind.compareTo(b.$2.fileKind),
      };
      return _sortAscending ? comparison : -comparison;
    });
    return indexed;
  }

  void _toggleSort(_SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

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
          _sortableHeader(_SortColumn.srcGlob, '源文件模式', flex: 3),
          _sortableHeader(_SortColumn.target, '目标路径', flex: 3),
          _sortableHeader(_SortColumn.fileKind, '类型', flex: 2),
          _headerText('平台 · 配置', flex: 2),
          const SizedBox(width: 88),
        ],
      ),
    );
  }

  /// 可排序的表头：点击切换排序列；再次点击切换升降序，当前列显示箭头指示。
  Widget _sortableHeader(_SortColumn column, String text, {int flex = 1}) {
    final active = _sortColumn == column;
    final arrow = !active
        ? null
        : (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward);
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _toggleSort(column),
        child: Row(
          children: [
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? AppColors.textAccent : AppColors.textSemantic,
                  fontSize: AppFontSizes.small,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (arrow != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(arrow, size: 12, color: AppColors.textAccent),
            ],
          ],
        ),
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
    final sorted = _sortedMappings(sourceDir);
    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final item = sorted[index];
        return _MappingRow(
          mapping: item.$2,
          onEdit: () => _editMapping(project, sourceIndex, item.$1),
          onDelete: () => _deleteMapping(project, sourceIndex, item.$1),
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
    final result = await showDialog<MappingAddResult>(
      context: context,
      builder: (_) => const MappingEditDialog(),
    );
    if (result == null || result.mappings.isEmpty) return;
    final updated = sourceDir.copyWith(
      mappings: [...sourceDir.mappings, ...result.mappings],
    );
    _commit(project, sourceIndex, updated);
    _logAddSource(result);
  }

  void _logAddSource(MappingAddResult result) {
    final onLogInfo = widget.onLogInfo;
    if (onLogInfo == null) return;
    if (result.fromScan) {
      onLogInfo('从目录扫描添加 ${result.mappings.length} 条映射');
    } else {
      onLogInfo('添加映射：${result.mappings.map((m) => m.srcGlob).join('，')}');
    }
  }

  Future<void> _editMapping(
    PackProject project,
    int sourceIndex,
    int mappingIndex,
  ) async {
    final sourceDir = project.sourceDirs[sourceIndex];
    final current = sourceDir.mappings[mappingIndex];
    final result = await showDialog<MappingAddResult>(
      context: context,
      builder: (_) => MappingEditDialog(initial: current),
    );
    if (result == null || result.mappings.isEmpty) return;
    final nextMappings = List<FileMapping>.of(sourceDir.mappings);
    nextMappings[mappingIndex] = result.mappings.first;
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

  Widget _buildConditionChips() {
    final platforms = widget.mapping.platforms;
    final configs = widget.mapping.configurations;
    if (platforms.isEmpty && configs.isEmpty) {
      return Text(
        '全部',
        style: const TextStyle(
          color: AppColors.textSemantic,
          fontSize: AppFontSizes.small,
        ),
      );
    }
    final chips = <Widget>[];
    for (final p in platforms) {
      chips.add(_conditionChip(p, AppColors.accent));
    }
    for (final c in configs) {
      chips.add(_conditionChip(c, AppColors.warn));
    }
    return Wrap(spacing: AppSpacing.s1, children: chips);
  }

  Widget _conditionChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: AppFontSizes.small),
      ),
    );
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: FileKindBadge(kind: widget.mapping.fileKind),
              ),
            ),
            Expanded(
             flex: 2,
             child: Align(
               alignment: Alignment.centerLeft,
               child: _buildConditionChips(),
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

/// 「添加映射」模式：手动输入单条，或扫描目录批量添加。
enum _AddMappingMode { manual, scan }

/// 映射编辑对话框（新增/编辑共用）。
///
/// 新增（[initial] 为 null）时支持两种模式（见 [_AddMappingMode]）：
/// - 「手动输入」：填写单条源 glob/目标路径；
/// - 「扫描目录」：选择目录后复用 [scanSourceDir] 扫描，勾选建议映射批量添加
///   （扫描目录本身不会作为新源目录，仅把文件映射追加到映射表）。
/// 编辑（[initial] 非 null）恒为单条手动编辑。
/// 结果统一为 `List<FileMapping>`（手动=单元素；扫描=勾选的多条）；取消返回 null。
class MappingEditDialog extends StatefulWidget {
  const MappingEditDialog({super.key, this.initial});

  final FileMapping? initial;

  @override
  State<MappingEditDialog> createState() => _MappingEditDialogState();
}

class _MappingEditDialogState extends State<MappingEditDialog> {
  late _AddMappingMode _mode;
  late TextEditingController _srcGlob;
  late TextEditingController _target;
  late TextEditingController _scanDirController;
  late TextEditingController _preBuild;
  late TextEditingController _postBuild;
  late Set<String> _platforms;
  late Set<String> _configs;

  String? _scanDir;
  bool _scanning = false;
  String? _scanError;
  ScanResult? _scanResult;
  Set<int> _scanChecked = <int>{};

  bool get _isAdd => widget.initial == null;

  @override
  void initState() {
    super.initState();
    _mode = _AddMappingMode.manual;
    _srcGlob = TextEditingController(text: widget.initial?.srcGlob ?? '');
    _target = TextEditingController(text: widget.initial?.target ?? '');
    _scanDirController = TextEditingController();
    _preBuild = TextEditingController(
      text: widget.initial?.preBuildCommand ?? '',
    );
    _postBuild = TextEditingController(
      text: widget.initial?.postBuildCommand ?? '',
    );
    _platforms = (widget.initial?.platforms ?? const <String>[]).toSet();
    _configs = (widget.initial?.configurations ?? const <String>[]).toSet();
  }

  @override
  void dispose() {
    _srcGlob.dispose();
    _target.dispose();
    _scanDirController.dispose();
    _preBuild.dispose();
    _postBuild.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanMode = _isAdd && _mode == _AddMappingMode.scan;
    return ActionDialog(
      title: _isAdd ? '添加映射' : '编辑映射',
      onConfirm: _save,
      confirmLabel: scanMode ? '添加选中' : '保存',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isAdd) _modeBar(),
            const SizedBox(height: AppSpacing.s2),
            if (scanMode) ..._scanFields() else ..._manualFields(),
            const SizedBox(height: AppSpacing.s2),
            _buildCommandSection(),
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

  /// 顶部分组工具条：扫描目录 / 手动输入 模式切换（与打包页模式切换一致的 SegmentedButton）。
  Widget _modeBar() {
    return SegmentedButton<_AddMappingMode>(
      segments: [
        ButtonSegment(
          value: _AddMappingMode.scan,
          label: Text('扫描目录', style: monoTextStyle()),
          icon: const Icon(Icons.folder_open, size: 16),
        ),
        ButtonSegment(
          value: _AddMappingMode.manual,
          label: Text('手动输入', style: monoTextStyle()),
          icon: const Icon(Icons.edit_outlined, size: 16),
        ),
      ],
      selected: <_AddMappingMode>{_mode},
      onSelectionChanged: (selection) =>
          setState(() => _mode = selection.first),
      showSelectedIcon: false,
    );
  }

  List<Widget> _manualFields() {
    return [
      LabeledFormField(
        label: '源文件模式',
        child: TextField(
          controller: _srcGlob,
          style: monoTextStyle(),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '如 include/**/*.h 或 x64/Release/*.lib',
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.s2),
      LabeledFormField(
        label: '#include 路径（头文件）/ 包内路径（其他）',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _target,
              style: monoTextStyle(),
              decoration: const InputDecoration(
                hintText:
                    '头文件如 v8\\cppgc（#include <v8\\cppgc/x.h>）；'
                    '库/数据文件如 lib\\x64\\Debug',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _autoHandlingNote(),
          ],
        ),
      ),
    ];
  }

  List<Widget> _scanFields() {
    return [
      LabeledFormField(
        label: '扫描目录（仅添加文件映射，不加入源目录）',
        child: Row(
          children: [
            Expanded(
              child: TextField(
                readOnly: true,
                controller: _scanDirController,
                onTap: _pickAndScan,
                style: monoTextStyle(),
                decoration: const InputDecoration(hintText: '点击选择要扫描的目录'),
              ),
            ),
            const SizedBox(width: AppSpacing.s1),
            OutlinedButton.icon(
              style: TextButton.styleFrom(minimumSize: Size(67, 35)),
              onPressed: _pickAndScan,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('浏览', style: TextStyle(fontFamily: 'HarmonyOS_Sans_SC'),),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.s2),
      _scanStatus(),
      if (_scanResult != null) ...[
        const SizedBox(height: AppSpacing.s2),
        MappingSuggestionList(
          suggestions: _scanResult!.suggestedMappings,
          checked: _scanChecked,
          onToggle: _toggleScan,
        ),
      ],
    ];
  }

  Widget _scanStatus() {
    if (_scanning) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.s1),
          Text(
            '正在扫描目录…',
            style: TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.small,
            ),
          ),
        ],
      );
    }
    if (_scanError != null) {
      return Text(
        _scanError!,
        style: const TextStyle(
          color: AppColors.error,
          fontSize: AppFontSizes.small,
        ),
      );
    }
    if (_scanResult != null) {
      final count = _scanChecked.length;
      return Text(
        '扫描完成，勾选 $count 条映射将追加到当前映射表；'
        '「其他」类文件默认不加入建议。',
        style: const TextStyle(
          color: AppColors.success,
          fontSize: AppFontSizes.small,
        ),
      );
    }
    return const Text(
      '选择目录后将自动扫描并列出映射建议。',
      style: TextStyle(
        color: AppColors.textSemantic,
        fontSize: AppFontSizes.small,
      ),
    );
  }

  Future<void> _pickAndScan() async {
    final path = await pickDirectory(initialDirectory: _scanDir);
    if (path == null || !mounted) return;
    setState(() {
      _scanDir = path;
      _scanDirController.text = path;
      _scanning = true;
      _scanError = null;
      _scanResult = null;
      _scanChecked = <int>{};
    });
    try {
      final result = await Future<ScanResult>(() => scanSourceDir(path));
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanResult = result;
        _scanChecked = {
          for (var i = 0; i < result.suggestedMappings.length; i++) i,
        };
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanResult = null;
        _scanError = '扫描失败：$e';
      });
    }
  }

  void _toggleScan(int index) {
    setState(() {
      if (_scanChecked.contains(index)) {
        _scanChecked.remove(index);
      } else {
        _scanChecked.add(index);
      }
    });
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

  /// 按当前 `srcGlob` 的 [FileMapping.fileKind] 动态呈现目标路径自动处理说明。
  Widget _autoHandlingNote() {
    final kind = FileMapping(srcGlob: _srcGlob.text).fileKind;
    final note = switch (kind) {
      'header' =>
        '头文件：该值为最终 #include 路径（不含 build\\native\\include\\ 前缀），'
            '如 v8\\cppgc 对应 #include <v8\\cppgc/x.h>。',
      'source' =>
        '源码：该值为包内相对 src 段（如 v8wrap）或完整 build\\native\\src\\...；'
            '打包后自动注入消费方编译。',
      'module' =>
        '模块（C++20）：该值为包内相对 src 段（同源码）；打包后自动注入消费方编译，'
            '需 C++20 或 Latest 标准（/std:c++latest）解析模块语义。',
      'data' =>
        '数据：该值为包内目录（如 build\\native\\lib\\x64\\Debug）；'
            '打包后自动硬链接到消费方输出目录。',
      'staticLibrary' =>
        '静态库：该值为包内目录（如 build\\native\\lib\\x64\\Debug），参与链接依赖。',
      'dynamicLibrary' =>
        '动态库：该值为包内目录（如 build\\native\\lib\\x64\\Debug）；'
            '打包后自动硬链接到消费方输出目录。',
      'executable' =>
        '可执行文件：该值为包内目录（如 build\\native\\tools\\Debug）；'
            '打包后自动硬链接到消费方输出目录。',
      _ => '其他：该值为包内目标路径。',
    };
    return Text(
      note,
      style: const TextStyle(
        color: AppColors.textSemantic,
        fontSize: AppFontSizes.caption,
      ),
    );
  }

  /// 构建命令区（构建前/构建后两个输入框；任意映射类型可配）。
  ///
  /// 当当前 `srcGlob` 的 [FileMapping.fileKind] 为 executable/dynamicLibrary 时
  /// 显示强提示（常见 .exe 注入场景），其他类型不隐藏、照常可配。
  Widget _buildCommandSection() {
    final kind = FileMapping(srcGlob: _srcGlob.text).fileKind;
    final isDynamicExe = kind == 'executable' || kind == 'dynamicLibrary';
    final kindLabel = kind == 'executable' ? '可执行文件' : '动态库';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDynamicExe)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '该映射为 $kindLabel，可配置编译前/后命令实现注入（如将本映射的 .exe 复制/运行）；'
              '工作目录为包安装目录，可引用其同级文件。',
              style: const TextStyle(
                color: AppColors.warn,
                fontSize: AppFontSizes.caption,
              ),
            ),
          ),
        _chipGroupLabel('构建命令（构建前 / 构建后，可选）'),
        LabeledFormField(
          label: '构建前命令',
          child: TextField(
            controller: _preBuild,
            style: monoTextStyle(),
            decoration: const InputDecoration(
              hintText: '如在消费方构建前注入；工作目录为包安装目录；任意映射类型可配',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        LabeledFormField(
          label: '构建后命令',
          child: TextField(
            controller: _postBuild,
            style: monoTextStyle(),
            decoration: const InputDecoration(hintText: '消费方构建后执行；工作目录为包安装目录'),
          ),
        ),
      ],
    );
  }

  void _save() {
    if (_isAdd && _mode == _AddMappingMode.scan) {
      _saveScanned();
      return;
    }
    final base = widget.initial ?? FileMapping();
    final platforms = _platforms.toList()..sort();
    final configs = _configs.toList()..sort();
    Navigator.of(context).pop(
      MappingAddResult(
        mappings: [
          base.copyWith(
            srcGlob: _srcGlob.text.trim(),
            target: _target.text.trim(),
            preBuildCommand: _preBuild.text.trim(),
            postBuildCommand: _postBuild.text.trim(),
            platforms: platforms,
            configurations: configs,
          ),
        ],
        fromScan: false,
      ),
    );
  }

  void _saveScanned() {
    final result = _scanResult;
    if (result == null) return;
    final platforms = _platforms.toList()..sort();
    final configs = _configs.toList()..sort();
    final picked = <FileMapping>[];
    final preCommand = _preBuild.text.trim();
    final postCommand = _postBuild.text.trim();
    for (final index in _scanChecked) {
      if (index < 0 || index >= result.suggestedMappings.length) continue;
      picked.add(
        result.suggestedMappings[index].copyWith(
          preBuildCommand: preCommand,
          postBuildCommand: postCommand,
          platforms: platforms.isEmpty ? const <String>[] : platforms,
          configurations: configs.isEmpty ? const <String>[] : configs,
        ),
      );
    }
    if (picked.isEmpty) return;
    Navigator.of(context)
        .pop(MappingAddResult(mappings: picked, fromScan: true));
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
            '请通过左侧「添加库项目」添加源目录，扫描后自动生成映射',
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
