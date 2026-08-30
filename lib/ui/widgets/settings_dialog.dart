/// 设置对话框：默认输出目录 + nuget.exe 路径（自动检测/浏览/缓存）。
///
/// 对照 `docs/ui-spec.md` §3.1 行为（设置展开：默认输出目录、nuget 路径缓存）。
library;

import 'package:flutter/material.dart';

import '../../services/packer.dart';
import '../../services/settings.dart';
import '../tokens.dart';
import '../io_picker.dart';
import 'form_fields.dart';

/// 设置对话框，保存后返回更新后的 [AppSettings]，取消返回 null。
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController _outputDir;
  late TextEditingController _nugetPath;

  @override
  void initState() {
    super.initState();
    _outputDir = TextEditingController(text: widget.settings.defaultOutputDir);
    _nugetPath = TextEditingController(
      text: widget.settings.nugetExePath ?? '',
    );
  }

  @override
  void dispose() {
    _outputDir.dispose();
    _nugetPath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _outputDirField(),
            const SizedBox(height: AppSpacing.s2),
            _nugetPathField(),
            const SizedBox(height: AppSpacing.s2),
            const Text(
              '设置会保存到 %APPDATA%\\cpp_nuget_pack\\settings.json，默认输出目录作为打包输出目录。',
              style: TextStyle(
                color: AppColors.textSemantic,
                fontSize: AppFontSizes.caption,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _outputDirField() {
    return _settingRow(
      label: '默认输出目录',
      field: TextField(
        controller: _outputDir,
        style: monoTextStyle(),
        readOnly: true,
        decoration: const InputDecoration(hintText: '未设置'),
      ),
      button: TextButton(onPressed: _browseOutput, child: const Text('浏览')),
    );
  }

  Future<void> _browseOutput() async {
    final path = await pickDirectory(initialDirectory: _outputDir.text);
    if (path == null || path.trim().isEmpty) return;
    _outputDir.text = path.trim();
  }

  Widget _nugetPathField() {
    return _settingRow(
      label: 'nuget.exe 路径',
      field: TextField(
        controller: _nugetPath,
        style: monoTextStyle(),
        decoration: const InputDecoration(hintText: '如 C:\\tools\\nuget.exe'),
      ),
      button: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: _autoDetect, child: const Text('自动检测')),
          TextButton(onPressed: _browseNuget, child: const Text('浏览')),
        ],
      ),
    );
  }

  Future<void> _browseNuget() async {
    final path = await pickExecutable();
    if (path == null || path.trim().isEmpty) return;
    _nugetPath.text = path.trim();
  }

  Future<void> _autoDetect() async {
    final found = findNuGetExe(<String>[_nugetPath.text.trim()]);
    if (found == null || found.isEmpty) {
      _showSnack('未找到 nuget.exe');
      return;
    }
    _nugetPath.text = found;
    _showSnack('已检测到 nuget.exe：$found');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.bgSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _settingRow({
    required String label,
    required Widget field,
    required Widget button,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSemantic,
            fontSize: AppFontSizes.small,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: AppSpacing.s1),
            button,
          ],
        ),
      ],
    );
  }

  void _save() {
    Navigator.of(context).pop(
      widget.settings.copyWith(
        defaultOutputDir: _outputDir.text.trim(),
        nugetExePath: _nugetPath.text.trim().isEmpty
            ? null
            : _nugetPath.text.trim(),
      ),
    );
  }
}
