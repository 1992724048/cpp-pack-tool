import 'package:cpp_nuget_pack/pack/package_scaffold.dart';
import 'package:cpp_nuget_pack/pack/ui/dialogs/pack_metadata_form.dart';
import 'package:cpp_nuget_pack/shared/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 时序约束：pre.bat / post.bat 不会因为文件被创建就注册进命令列表 ——
/// applySystemEntries 只在构建成功或点「重新映射」后触发，不写在代码注释里，
/// 用户看不到。
const String _remapHint =
    '注意：pre.bat / post.bat 不会因为创建文件就自动注册进命令列表，'
    '需先构建一次或点「重新映射」后才会生效。';

/// 对话框的返回值。规格要求落盘成功后不再弹第二个对话框，因此元数据必须随
/// [ScaffoldOutcome] 一起带回给调用方去构造 PackModel。
class CreatePackageStructureResult {
  const CreatePackageStructureResult({required this.metadata, required this.outcome});

  final PackMetadata metadata;
  final ScaffoldOutcome outcome;
}

class CreatePackageStructureDialog extends StatefulWidget {
  const CreatePackageStructureDialog({
    super.key,
    required this.directoryPath,
    this.preview = previewPackageStructure,
    this.createStructure = createPackageStructure,
  });

  /// 已选定的新包源目录绝对路径。
  final String directoryPath;

  /// 预演与落盘都可注入：widget 测试的 fake_async 区里真实文件 future 永不落定，
  /// 替身让对话框逻辑可测，真实落盘由 package_scaffold_test.dart 覆盖。
  final ScaffoldPreview Function(String rootPath) preview;
  final Future<ScaffoldOutcome> Function(String rootPath) createStructure;

  @override
  State<CreatePackageStructureDialog> createState() => _CreatePackageStructureDialogState();
}

class _CreatePackageStructureDialogState extends State<CreatePackageStructureDialog> {
  late final ScaffoldPreview _preview;
  PackMetadataDraft? _draft;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview(widget.directoryPath);
  }

  bool get _canSubmit => !_submitting && (_draft?.isComplete ?? false);

  Future<void> _submit() async {
    final PackMetadataDraft draft = _draft!;
    setState(() => _submitting = true);

    if (_preview.requiresConfirmation && !await _confirmNonEmptyDirectory()) {
      if (mounted) {
        setState(() => _submitting = false);
      }
      return;
    }

    try {
      final ScaffoldOutcome outcome = await widget.createStructure(widget.directoryPath);
      if (!mounted) {
        return;
      }
      Navigator.pop(context, CreatePackageStructureResult(metadata: draft.metadata, outcome: outcome));
    } on PackageScaffoldException catch (error) {
      if (!mounted) {
        return;
      }
      // 不包装错误消息：它已含失败路径，直接面向用户。
      setState(() => _submitting = false);
      showFloatingToast(context, error.message, type: FloatingToastType.error, duration: const Duration(seconds: 5));
    }
  }

  Future<bool> _confirmNonEmptyDirectory() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _buildConfirmationDialog(dialogContext),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('创建包结构'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('路径：${widget.directoryPath}'),
            const SizedBox(height: 12),
            PackMetadataForm(onChanged: (PackMetadataDraft draft) => setState(() => _draft = draft)),
            const SizedBox(height: 12),
            const Text('已存在的文件不会被覆盖，只补齐缺失项。'),
            const SizedBox(height: 8),
            const Text(_remapHint),
          ],
        ),
      ),
      actions: [
        Button(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _canSubmit ? _submit : null, child: const Text('确定')),
      ],
    );
  }

  Widget _buildConfirmationDialog(BuildContext dialogContext) {
    final List<String> filesToCreate = <String>[
      for (final String name in scaffoldTemplates.keys)
        if (!_preview.existingFiles.contains(name)) name,
    ];
    return ContentDialog(
      title: const Text('目标目录非空'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('目录中已有 ${_preview.existingEntryCount} 个条目。继续创建只补齐缺失项，已存在的文件不会被覆盖。'),
            const SizedBox(height: 12),
            const Text('将创建的目录：'),
            for (final String relative in scaffoldDirectories) Text('  $relative/'),
            const SizedBox(height: 8),
            const Text('将创建的文件：'),
            for (final String name in filesToCreate) Text('  $name'),
            if (_preview.existingFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('已存在，将跳过：${_preview.existingFiles.join('、')}'),
            ],
          ],
        ),
      ),
      actions: [
        Button(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('继续创建')),
      ],
    );
  }
}
