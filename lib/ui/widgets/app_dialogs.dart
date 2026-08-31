/// 应用对话框：添加源目录（扫描 + 映射建议预览）与确认删除。
///
/// 对照 `docs/ui-spec.md` §3.8。对话框内进度与状态内联呈现，不用 SnackBar
/// 贯穿长流程；错误/状态以文字呈现，成功以 [success] 色、失败以 [error] 色。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pack_project.dart';
import '../../services/msbuild_generator.dart';
import '../../services/nuspec_generator.dart';
import '../../services/package_registry.dart';
import '../../services/path_utils.dart';
import '../../services/scanner.dart';
import '../../services/shared_project_parser.dart';
import '../tokens.dart';
import '../io_picker.dart';
import 'form_fields.dart';
import 'mapping_suggestion_list.dart';

/// 平台候选。
const List<String> _kPlatforms = <String>['x64', 'x86', 'arm64'];

/// 配置候选。
const List<String> _kConfigs = <String>['Debug', 'Release'];

/// 「添加源目录」对话框的返回结果：源目录 + 可选的共享项目编译配置补丁与导入信息。
class AddSourceDirResult {
  const AddSourceDirResult({
    required this.sourceDir,
    this.compileConfig,
    this.infoMessage,
  });

  /// 勾选后生成的源目录（含映射）。
  final SourceDir sourceDir;

  /// 共享项目解析出的编译配置（含默认值 + 共享项）；null 表示无共享配置或未启用。
  final CompileConfig? compileConfig;

  /// 导入信息（如「已从 xxx.vcxitems 导入 N 条映射」）；null 表示无。
  final String? infoMessage;
}

/// 添加源目录对话框。
///
/// 流程：选择目录 → 扫描 → 映射建议预览（勾选；若检测到共享项目配置文件则提示
/// 是否基于它合并映射与编译配置）→ 确认添加返回 [AddSourceDirResult]。取消返回 null。
class AddSourceDirDialog extends StatefulWidget {
  const AddSourceDirDialog({super.key, this.initialDirectory, this.onLogWarn});

  final String? initialDirectory;

  /// 解析共享项目失败时追加 warn 级日志的回调（由 MainShell 绑定到日志控制器）；
  /// 为 null 时静默跳过。
  final ValueChanged<String>? onLogWarn;

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

  /// 检测到的共享项目配置文件（.vcxitems/.vcxproj/.props/.targets）；null 表示未检测到。
  String? _sharedFile;

  /// 共享项目解析结果（仅当 [sharedFile] 成功解析时非空）。
  SharedProjectInfo? _sharedInfo;

  /// 是否基于共享项目生成映射（合并映射与编译配置）。
  bool _useShared = false;

  /// 当前展示的映射列表：未启用共享时即扫描建议；启用共享时**以共享项目映射
  /// 取代扫描建议**（不做合并——选择「是」即表示用共享项目为准）。
  List<FileMapping> get _displayMappings {
    final info = _sharedInfo;
    if (_useShared && info != null) {
      final cluster = basenameOf(_dirPath ?? '');
      return buildMappingsFromSharedProject(info, cluster);
    }
    return _result?.suggestedMappings ?? const <FileMapping>[];
  }

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
      _sharedFile = null;
      _sharedInfo = null;
      _useShared = false;
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
      final sharedFile = detectSharedProjectFile(dir);
      SharedProjectInfo? sharedInfo;
      if (sharedFile != null) {
        try {
          sharedInfo = parseSharedProject(sharedFile);
        } on Object catch (e) {
          widget.onLogWarn?.call('解析共享项目配置 $sharedFile 失败：$e');
        }
      }
      setState(() {
        _scanning = false;
        _scanDone = true;
        _result = result;
        _sharedFile = sharedFile;
        _sharedInfo = sharedInfo;
        _useShared = false;
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
    if (_result == null || _dirPath == null || _checked.isEmpty) return;
    final dir = _dirPath!;
    final selectedPlatforms = _selectedPlatforms.toList();
    final selectedConfigs = _selectedConfigs.toList();
    final display = _displayMappings;
    final mappings = <FileMapping>[];
    for (final index in _checked) {
      if (index < 0 || index >= display.length) continue;
      final base = display[index];
      mappings.add(
        base.copyWith(
          // If the user didn't pick any platform/config chips, keep the scanner's
          // detected values (do not overwrite with an empty list which means "全部").
          platforms: selectedPlatforms.isEmpty
              ? base.platforms
              : selectedPlatforms,
          configurations: selectedConfigs.isEmpty
              ? base.configurations
              : selectedConfigs,
        ),
      );
    }
    CompileConfig? sharedConfig;
    String? infoMessage;
    final info = _sharedInfo;
    if (_useShared && info != null && _sharedFile != null) {
      sharedConfig = mergeCompileConfigFromSharedProject(CompileConfig(), info);
      final mappingCount = info.headerGlobs.length + info.sourceGlobs.length;
      final commandCount =
          info.preBuildCommands.length + info.postBuildCommands.length;
      infoMessage = '已从 ${basenameOf(_sharedFile!)} 导入 $mappingCount 条映射';
      if (commandCount > 0) infoMessage += '，已导入 $commandCount 条构建命令';
    }
    Navigator.of(context).pop(
      AddSourceDirResult(
        sourceDir: SourceDir(path: dir, mappings: mappings),
        compileConfig: sharedConfig,
        infoMessage: infoMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.s4),
      child: SizedBox(
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
              if (_scanDone && _sharedInfo != null)
                Column(
                  children: [
                    const SizedBox(height: AppSpacing.s2),
                    _sharedPrompt(),
                  ],
                ),
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
          style: OutlinedButton.styleFrom(minimumSize: Size(60, 36)),
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text(
            '浏览',
            style: TextStyle(fontFamily: 'HarmonyOS_Sans_SC'),
          ),
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
      final count = _displayMappings.length;
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

  /// 检测到共享项目配置文件的提示行（「是否基于它生成映射？」+ 是/否）。
  Widget _sharedPrompt() {
    final fileName = basenameOf(_sharedFile ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s1),
      padding: const EdgeInsets.all(AppSpacing.s2),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '检测到共享项目配置文件 $fileName。基于共享项目生成映射将取代文件扫描结果，'
              '是否基于它生成映射？',
              style: const TextStyle(
                color: AppColors.textSemantic,
                fontSize: AppFontSizes.small,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _setUseShared(true),
            child: const Text('是'),
          ),
          const SizedBox(width: AppSpacing.s1),
          TextButton(
            onPressed: () => _setUseShared(false),
            child: const Text('否'),
          ),
        ],
      ),
    );
  }

  /// 切换是否基于共享项目生成映射；切换后重置勾选为全部新列表。
  void _setUseShared(bool value) {
    setState(() {
      _useShared = value;
      _checked = {for (var i = 0; i < _displayMappings.length; i++) i};
    });
  }

  Widget _previewList() {
    if (_result == null) {
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
    final badge = _useShared && _sharedInfo != null ? _sourceBadge() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (badge != null) ...<Widget>[
          badge,
          const SizedBox(height: AppSpacing.s1),
        ],
        Expanded(
          child: MappingSuggestionList(
            suggestions: _displayMappings,
            checked: _checked,
            onToggle: _toggle,
          ),
        ),
      ],
    );
  }

  /// 「基于共享项目」来源徽标（提示当前列表为共享项目解析结果，取代文件扫描）。
  Widget _sourceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s1,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.accent),
      ),
      child: const Text(
        '来源：共享项目',
        style: TextStyle(
          color: AppColors.textAccent,
          fontSize: AppFontSizes.caption,
        ),
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
          style: OutlinedButton.styleFrom(minimumSize: Size(60, 36)),
          onPressed: _scanning || _dirPath == null ? null : _startScan,
          child: const Text(
            '开始扫描',
            style: TextStyle(fontFamily: 'HarmonyOS_Sans_SC'),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        FilledButton(
          onPressed: canConfirm ? _confirm : null,
          child: const Text(
            '确认添加',
            style: TextStyle(fontFamily: 'HarmonyOS_Sans_SC'),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSemantic,
            minimumSize: Size(60, 36),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(fontFamily: 'HarmonyOS_Sans_SC'),
          ),
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

/// 依赖缺失警告对话框：列出 [missing]（`id version` 字符串列表），
/// 用户「仍然继续」返回 true，「取消」返回 false。
Future<bool> confirmMissingDependencies(
  BuildContext context, {
  required List<String> missing,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('依赖缺失'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '以下依赖未在输出目录注册表中找到，继续打包可能导致消费方安装失败：',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppFontSizes.body,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            for (final dep in missing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(dep, style: monoTextStyle()),
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
          child: const Text('仍然继续'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 打开「预览生成文件」对话框：以 [buildDir] 为 nuspec 基准目录，即时生成
/// nuspec/props/targets 三个只读代码视图。
Future<void> previewFilesDialog(
  BuildContext context, {
  required PackProject project,
  required String buildDir,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PreviewFilesDialog(project: project, buildDir: buildDir),
  );
}

/// 预览生成文件对话框。
///
/// 顶部为 nuspec/props/targets 三个 Tab（SegmentedButton），右上角「复制」按钮
/// 复制当前视图完整内容到剪贴板。内容在对话框打开时即时生成（调用
/// `nuspec_generator`/`msbuild_generator`），生成失败在内容区以内联 error 提示。
class _PreviewFilesDialog extends StatefulWidget {
  const _PreviewFilesDialog({required this.project, required this.buildDir});

  final PackProject project;

  /// nuspec 的 `baseDir`（相对路径基准，通常为 `{输出目录}\build`）。
  final String buildDir;

  @override
  State<_PreviewFilesDialog> createState() => _PreviewFilesDialogState();
}

class _PreviewFilesDialogState extends State<_PreviewFilesDialog> {
  static const List<String> _labels = <String>['nuspec', 'props', 'targets'];

  int _tab = 0;
  String? _nuspec;
  String? _props;
  String? _targets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  void _generate() {
    try {
      final project = widget.project;
      _nuspec = generate(project, baseDir: widget.buildDir);
      _props = generateProps(project);
      _targets = generateTargets(project);
      _error = null;
    } on Object catch (e) {
      _nuspec = null;
      _props = null;
      _targets = null;
      _error = '生成预览失败：$e';
    }
  }

  String get _content => switch (_tab) {
    0 => _nuspec ?? '',
    1 => _props ?? '',
    _ => _targets ?? '',
  };

  void _copy() {
    Clipboard.setData(ClipboardData(text: _content));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已复制 ${_labels[_tab]} 内容')));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.s4),
      child: SizedBox(
        width: 760,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '预览生成文件',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppFontSizes.h3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _copy,
                    tooltip: '复制',
                    icon: const Icon(Icons.copy, size: 18),
                    iconSize: 18,
                    color: AppColors.textSemantic,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < _labels.length; i++)
                    ButtonSegment(value: i, label: Text(_labels[i])),
                ],
                selected: <int>{_tab},
                onSelectionChanged: (selection) =>
                    setState(() => _tab = selection.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: AppSpacing.s2),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: AppFontSizes.body,
                          ),
                        ),
                      )
                    : _codeView(),
              ),
              const SizedBox(height: AppSpacing.s2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s2),
      decoration: BoxDecoration(
        color: AppColors.bgApp,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        child: SelectableText(_content, style: monoTextStyle()),
      ),
    );
  }
}

/// 打开「打包历史」时间线对话框：按 [project.packageId] 查询输出目录注册表的
/// 打包历史（[packageHistory]，倒序），以纵向时间线呈现。
Future<void> packHistoryDialog(
  BuildContext context, {
  required PackProject project,
  required String outputDir,
}) {
  final entries = packageHistory(outputDir, project.packageId);
  return showDialog<void>(
    context: context,
    builder: (_) => _PackHistoryDialog(project: project, entries: entries),
  );
}

/// 打包历史时间线对话框。
///
/// 空历史时显示「暂无打包记录」；否则以纵向时间线（左侧节点圆点 + 竖线）列出
/// 每一版打包记录：版本号（粗体主标题）、打包时间、可选摘要。
class _PackHistoryDialog extends StatelessWidget {
  const _PackHistoryDialog({required this.project, required this.entries});

  final PackProject project;
  final List<PackHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '打包历史 — ${project.packageId}',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: AppFontSizes.h3,
        ),
      ),
      content: SizedBox(
        width: 620,
        height: 440,
        child: entries.isEmpty
            ? const Center(
                child: Text(
                  '暂无打包记录',
                  style: TextStyle(
                    color: AppColors.textSemantic,
                    fontSize: AppFontSizes.body,
                  ),
                ),
              )
            : _timeline(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  /// 纵向时间线：左侧贯穿竖线（Stack 底层）+ 顶部节点圆点 + 卡片列表（[ListView]）。
  Widget _timeline() {
    return Stack(
      children: [
        Positioned(
          left: 9,
          top: 0,
          bottom: 0,
          child: Container(width: 2, color: AppColors.borderStrong),
        ),
        ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) =>
              _TimelineEntry(entry: entries[index]),
        ),
      ],
    );
  }
}

/// 单条时间线条目：左侧节点圆点（叠加在竖线上），右侧为卡片（版本/时间/摘要）。
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.entry});

  final PackHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 圆点水平居中于竖线（left:9 宽 2 → 中心 x=10），圆点宽 10 → 左偏移 5。
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(left: 5, top: 10),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.s1),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.s2),
            padding: const EdgeInsets.all(AppSpacing.s2),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.version,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _formatHistoryTime(entry.packedAt),
                  style: const TextStyle(
                    color: AppColors.textSemantic,
                    fontSize: AppFontSizes.caption,
                  ),
                ),
                if (entry.summary != null &&
                    entry.summary!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    entry.summary!,
                    style: const TextStyle(
                      color: AppColors.textSemantic,
                      fontSize: AppFontSizes.small,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 格式化打包时间为 `yyyy-MM-dd HH:mm`。
String _formatHistoryTime(DateTime dt) {
  String pad2(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${pad2(dt.month)}-${pad2(dt.day)} '
      '${pad2(dt.hour)}:${pad2(dt.minute)}';
}
