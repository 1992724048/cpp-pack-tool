/// 应用对话框：添加源目录（扫描 + 映射建议预览）与确认删除。
///
/// 对照 `docs/ui-spec.md` §3.8。对话框内进度与状态内联呈现，不用 SnackBar
/// 贯穿长流程；错误/状态以文字呈现，成功以 [success] 色、失败以 [error] 色。
library;

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../../services/scanner.dart';
import '../tokens.dart';
import '../io_picker.dart';
import 'form_fields.dart';

/// 平台候选。
const List<String> _kPlatforms = <String>['x64', 'x86', 'arm64'];

/// 配置候选。
const List<String> _kConfigs = <String>['Debug', 'Release'];

/// 添加源目录对话框。
///
/// 流程：选择目录 → 扫描 → 映射建议预览（勾选）→ 确认添加返回 [SourceDir]。
/// 取消返回 null。
class AddSourceDirDialog extends StatefulWidget {
  const AddSourceDirDialog({super.key, this.initialDirectory});

  final String? initialDirectory;

  @override
  State<AddSourceDirDialog> createState() => _AddSourceDirDialogState();
}

class _AddSourceDirDialogState extends State<AddSourceDirDialog> {
  String? _dirPath;
  bool _scanning = false;
  bool _scanDone = false;
  String? _scanError;
  ScanResult? _result;
  Set<int> _checked = <int>{};
  final Set<String> _selectedPlatforms = <String>{};
  final Set<String> _selectedConfigs = <String>{};
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _dirPath = _trimmed(widget.initialDirectory);
    _pathController = TextEditingController(text: _dirPath ?? '');
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _browse() async {
    final path = await pickDirectory(initialDirectory: _dirPath);
    if (path == null || !mounted) return;
    setState(() {
      _dirPath = path;
      _pathController.text = path;
      _scanDone = false;
      _scanError = null;
      _result = null;
    });
  }

  Future<void> _startScan() async {
    final dir = _dirPath;
    if (dir == null) {
      setState(() => _scanError = '请先选择要扫描的目录');
      return;
    }
    setState(() {
      _scanning = true;
      _scanDone = false;
      _scanError = null;
      _checked = <int>{};
    });
    try {
      final result = await Future<ScanResult>(() => scanSourceDir(dir));
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanDone = true;
        _result = result;
        _checked = {
          for (var i = 0; i < result.suggestedMappings.length; i++) i,
        };
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanDone = false;
        _result = null;
        _scanError = '扫描失败：$e';
      });
    }
  }

  void _confirm() {
    final result = _result;
    final dir = _dirPath;
    if (result == null || dir == null || _checked.isEmpty) return;
    final selectedPlatforms = _selectedPlatforms.toList();
    final selectedConfigs = _selectedConfigs.toList();
    final mappings = <FileMapping>[];
    for (final index in _checked) {
      if (index < 0 || index >= result.suggestedMappings.length) continue;
      final base = result.suggestedMappings[index];
      mappings.add(
        base.copyWith(
          platforms: selectedPlatforms.isEmpty
              ? const <String>[]
              : selectedPlatforms,
          configurations: selectedConfigs.isEmpty
              ? const <String>[]
              : selectedConfigs,
        ),
      );
    }
    Navigator.of(context).pop(SourceDir(path: dir, mappings: mappings));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.s4),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '添加源目录',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppFontSizes.h3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              _directoryRow(),
              const SizedBox(height: AppSpacing.s2),
              _filterChips(),
              const SizedBox(height: AppSpacing.s2),
              _statusArea(),
              const SizedBox(height: AppSpacing.s2),
              Flexible(child: _previewList()),
              const SizedBox(height: AppSpacing.s3),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _directoryRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            readOnly: true,
            controller: _pathController,
            onTap: _browse,
            style: monoTextStyle(),
            decoration: const InputDecoration(
              labelText: '目录路径',
              hintText: '点击选择或右侧浏览',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s1),
        OutlinedButton.icon(
          onPressed: _browse,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('浏览'),
        ),
      ],
    );
  }

  Widget _filterChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chipGroup('平台', _kPlatforms, _selectedPlatforms),
        const SizedBox(height: AppSpacing.sm),
        _chipGroup('配置', _kConfigs, _selectedConfigs),
      ],
    );
  }

  Widget _chipGroup(String label, List<String> options, Set<String> selected) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.small,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
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
          ),
        ),
      ],
    );
  }

  Widget _statusArea() {
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
    if (_scanDone && _result != null) {
      final count = _result!.suggestedMappings.length;
      final truncated = _result!.truncated;
      final text = truncated
          ? '扫描完成，发现 $count 项可映射文件（部分目录被跳过）'
          : '扫描完成，发现 $count 项可映射文件';
      return Text(
        text,
        style: const TextStyle(
          color: AppColors.success,
          fontSize: AppFontSizes.small,
        ),
      );
    }
    return const Text(
      '选择目录后点击「开始扫描」生成映射建议',
      style: TextStyle(
        color: AppColors.textSemantic,
        fontSize: AppFontSizes.small,
      ),
    );
  }

  Widget _previewList() {
    final result = _result;
    if (result == null) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            '尚未扫描',
            style: TextStyle(
              color: AppColors.textDisabled,
              fontSize: AppFontSizes.body,
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: result.suggestedMappings.length,
        itemBuilder: (context, index) {
          final mapping = result.suggestedMappings[index];
          return InkWell(
            onTap: () => _toggle(index),
            child: Row(
              children: [
                Checkbox(
                  value: _checked.contains(index),
                  onChanged: (_) => _toggle(index),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mapping.srcGlob, style: monoTextStyle()),
                      Text(
                        '→ ${mapping.target}',
                        style: monoTextStyle(color: AppColors.textSemantic),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _toggle(int index) {
    setState(() {
      if (_checked.contains(index)) {
        _checked.remove(index);
      } else {
        _checked.add(index);
      }
    });
  }

  Widget _actions() {
    final canConfirm = _scanDone && _checked.isNotEmpty;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: _scanning || _dirPath == null ? null : _startScan,
          child: const Text('开始扫描'),
        ),
        const SizedBox(width: AppSpacing.s2),
        FilledButton(
          onPressed: canConfirm ? _confirm : null,
          child: const Text('确认添加'),
        ),
        const SizedBox(width: AppSpacing.s2),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 确认删除对话框，用户确认返回 true，否则 false。
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 删除库项目时的可选清理项。
class DeleteProjectOptions {
  const DeleteProjectOptions({
    required this.removeFromRegistry,
    required this.deleteSourceDirConfig,
    required this.deleteNupkg,
  });

  /// 是否从输出目录包注册表移除。
  final bool removeFromRegistry;

  /// 是否删除各源目录下的 `.cpp_nuget_pack.json` 包配置文件。
  final bool deleteSourceDirConfig;

  /// 是否删除输出目录下当前版本的 `.nupkg` 文件。
  final bool deleteNupkg;
}

/// 删除库项目确认对话框；用户取消返回 null。
///
/// 默认三个清理项全部勾选。「从输出目录包注册表移除」仅在 [inRegistry] 为真时
/// 可用（否则置灰且不可选），其余两项始终可用。
Future<DeleteProjectOptions?> confirmDeleteProject(
  BuildContext context, {
  required String packageId,
  required bool inRegistry,
}) async {
  var removeFromRegistry = inRegistry;
  var deleteSourceDirConfig = true;
  var deleteNupkg = true;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('删除库项目'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '确定删除库项目「$packageId」吗？源文件不会被删除，'
                  '仅移除应用内的项目配置与对应产物。',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppFontSizes.body,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                CheckboxListTile(
                  value: removeFromRegistry,
                  onChanged: inRegistry
                      ? (v) => setState(() => removeFromRegistry = v ?? false)
                      : null,
                  title: const Text('从输出目录包注册表移除'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: deleteSourceDirConfig,
                  onChanged: (v) =>
                      setState(() => deleteSourceDirConfig = v ?? false),
                  title: const Text('删除源目录包配置文件'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: deleteNupkg,
                  onChanged: (v) => setState(() => deleteNupkg = v ?? false),
                  title: const Text('删除已输出的 NuGet 包'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    ),
  );
  if (result != true) return null;
  return DeleteProjectOptions(
    removeFromRegistry: removeFromRegistry,
    deleteSourceDirConfig: deleteSourceDirConfig,
    deleteNupkg: deleteNupkg,
  );
}

/// 文本输入对话框，确认返回输入文本，取消返回 null。
Future<String?> promptTextInput(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: hint),
        autofocus: true,
        onSubmitted: (value) => Navigator.of(ctx).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
