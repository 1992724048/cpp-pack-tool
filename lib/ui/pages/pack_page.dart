/// 打包 Tab：模式切换（一键/仅生成文件）、输出目录、nuget 路径、打包按钮状态机。
///
/// 对照 `docs/ui-spec.md` §3.6 与 §5.2。打包采用 UI 侧独立 `Process.start`
/// 流式输出到日志面板（不改 `packer.dart`，仅复用其 `buildPackArgs`）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../../services/msbuild_generator.dart';
import '../../services/nuspec_generator.dart';
import '../../services/packer.dart';
import '../../services/path_utils.dart';
import '../../services/settings.dart';
import '../tokens.dart';
import '../io_picker.dart';
import '../log_controller.dart';
import '../widgets/form_fields.dart';

/// 打包模式。
enum PackMode { generateOnly, pack }

/// 打包页。
class PackPage extends StatefulWidget {
  const PackPage({
    super.key,
    required this.project,
    required this.onChanged,
    required this.settings,
    required this.onSettingsChanged,
    required this.log,
    required this.onNotify,
  });

  final PackProject? project;
  final ValueChanged<PackProject> onChanged;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final LogController log;

  /// 一次性操作结果提示（SnackBar 文案）。
  final void Function(String message, {bool isError}) onNotify;

  @override
  State<PackPage> createState() => _PackPageState();
}

class _PackPageState extends State<PackPage> {
  PackMode _mode = PackMode.pack;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    if (project == null) {
      return const _PackPlaceholder();
    }

    final missing = _missingConditions(project);
    final enabled = missing.isEmpty && !_busy;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '打包'),
          _modeSelector(),
          const SizedBox(height: AppSpacing.s3),
          _outputDirField(project),
          const SizedBox(height: AppSpacing.s2),
          _nugetField(),
          const SizedBox(height: AppSpacing.s3),
          _packButton(project, enabled),
          const SizedBox(height: AppSpacing.s2),
          if (missing.isNotEmpty) _missingText(missing),
        ],
      ),
    );
  }

  Widget _modeSelector() {
    return SegmentedButton<PackMode>(
      segments: const [
        ButtonSegment(value: PackMode.pack, label: Text('一键打包')),
        ButtonSegment(value: PackMode.generateOnly, label: Text('仅生成文件')),
      ],
      selected: <PackMode>{_mode},
      onSelectionChanged: (selection) =>
          setState(() => _mode = selection.first),
      showSelectedIcon: false,
    );
  }

  Widget _outputDirField(PackProject project) {
    return _SyncedField(
      value: project.outputDirectory,
      readOnly: true,
      hint: '未选择',
      mono: true,
      onTap: _pickOutputDir,
      suffix: IconButton(
        onPressed: _pickOutputDir,
        tooltip: '选择输出目录',
        icon: const Icon(Icons.folder_open, size: 18),
        iconSize: 18,
        color: AppColors.textSemantic,
      ),
    );
  }

  Future<void> _pickOutputDir() async {
    final project = widget.project;
    if (project == null) return;
    final path = await pickDirectory(initialDirectory: project.outputDirectory);
    if (path == null || path.trim().isEmpty) return;
    widget.onChanged(project.copyWith(outputDirectory: path.trim()));
  }

  Widget _nugetField() {
    final settings = widget.settings;
    final nugetPath = settings.nugetExePath ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'nuget.exe 路径',
          style: TextStyle(
            color: AppColors.textSemantic,
            fontSize: AppFontSizes.small,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SyncedField(
          value: nugetPath,
          readOnly: false,
          hint: '如 C:\\tools\\nuget.exe',
          mono: true,
          onChanged: (value) => _setNugetPath(value),
          suffix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _autoDetectNuget,
                child: const Text('自动检测'),
              ),
              IconButton(
                onPressed: _pickNuget,
                tooltip: '浏览',
                icon: const Icon(Icons.search, size: 18),
                iconSize: 18,
                color: AppColors.textSemantic,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickNuget() async {
    final path = await pickExecutable();
    if (path == null || path.trim().isEmpty) return;
    _setNugetPath(path.trim());
  }

  Future<void> _autoDetectNuget() async {
    try {
      final found = findNuGetExe(<String>[widget.settings.nugetExePath ?? '']);
      if (found == null || found.isEmpty) {
        widget.log.error('未找到 nuget.exe，请在 PATH 或常见安装位置中配置');
        widget.onNotify('未找到 nuget.exe', isError: true);
        return;
      }
      _setNugetPath(found);
      widget.log.info('已自动检测到 nuget.exe：$found');
    } catch (e) {
      widget.log.error('自动检测 nuget.exe 失败：$e');
      widget.onNotify('自动检测 nuget.exe 失败', isError: true);
    }
  }

  void _setNugetPath(String path) {
    final settings = widget.settings;
    widget.onSettingsChanged(
      settings.copyWith(nugetExePath: path.isEmpty ? null : path),
    );
  }

  Widget _packButton(PackProject project, bool enabled) {
    final label = _mode == PackMode.pack ? '打包' : '生成文件';
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? () => _run(project) : null,
        child: _busy
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.s1),
                  Text(_labelBusy()),
                ],
              )
            : Text(label),
      ),
    );
  }

  String _labelBusy() => _mode == PackMode.pack ? '正在打包…' : '正在生成…';

  Widget _missingText(List<String> missing) {
    return Text(
      '无法执行：${missing.join('；')}',
      style: const TextStyle(
        color: AppColors.textSemantic,
        fontSize: AppFontSizes.small,
      ),
    );
  }

  List<String> _missingConditions(PackProject project) {
    final missing = <String>[];
    if (project.packageId.trim().isEmpty) {
      missing.add('包 ID 未填写');
    }
    if (project.version.trim().isEmpty) {
      missing.add('版本未填写');
    }
    if (project.outputDirectory.trim().isEmpty) {
      missing.add('输出目录未选择');
    }
    if (_mode == PackMode.pack &&
        (widget.settings.nugetExePath ?? '').trim().isEmpty) {
      missing.add('nuget.exe 路径未配置');
    }
    return missing;
  }

  Future<void> _run(PackProject project) async {
    setState(() => _busy = true);
    try {
      final paths = await _generateFiles(project);
      widget.log.info('已生成：${paths.join('；')}');
      if (_mode == PackMode.pack) {
        await _packWithNuget(project);
      } else {
        widget.onNotify('文件已生成到输出目录');
      }
    } on Object catch (e) {
      widget.log.error('打包/生成失败：$e');
      widget.onNotify('操作失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 生成 nuspec/props/targets 并写入输出目录；返回写入的文件路径列表。
  Future<List<String>> _generateFiles(PackProject project) async {
    final outputDir = project.outputDirectory.trim();
    if (outputDir.isEmpty) {
      throw const FormatException('输出目录为空');
    }
    final id = project.packageId.trim();
    final buildNativeDir = joinPath([outputDir, 'build', 'native']);
    Directory(buildNativeDir).createSync(recursive: true);

    final nuspecPath = joinPath([outputDir, '$id.nuspec']);
    final propsPath = joinPath([buildNativeDir, '$id.props']);
    final targetsPath = joinPath([buildNativeDir, '$id.targets']);

    // `generate` 已在 files 段头部输出 props/targets 的 `<file>` 条目，
    // 此处直接使用其结果，避免重复追加导致 nuget pack 异常。
    final nuspec = generate(project);
    File(nuspecPath).writeAsStringSync(nuspec);
    File(propsPath).writeAsStringSync(generateProps(project));
    File(targetsPath).writeAsStringSync(generateTargets(project));

    return <String>[nuspecPath, propsPath, targetsPath];
  }

  Future<void> _packWithNuget(PackProject project) async {
    final nugetExe = (widget.settings.nugetExePath ?? '').trim();
    if (nugetExe.isEmpty) {
      throw const FormatException('nuget.exe 路径未配置');
    }
    final outputDir = project.outputDirectory.trim();
    final id = project.packageId.trim();
    final nuspecPath = joinPath([outputDir, '$id.nuspec']);

    widget.log.info('开始打包：nuget.exe $nugetExe');
    final args = buildPackArgs(nuspecPath: nuspecPath, outputDir: outputDir);
    try {
      final process = await Process.start(
        nugetExe,
        args,
        workingDirectory: outputDir,
      );
      final stdoutDone = _forwardStream(process.stdout, LogLevel.info);
      final stderrDone = _forwardStream(process.stderr, LogLevel.error);
      final exitCode = await process.exitCode;
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);

      if (exitCode == 0) {
        final outputPath = _lastNupkgPath;
        _lastNupkgPath = null;
        widget.log.info('打包成功');
        if (outputPath != null) {
          widget.log.info('生成包：$outputPath');
          widget.onNotify('打包成功：$outputPath');
        } else {
          widget.onNotify('打包成功');
        }
      } else {
        widget.log.error('nuget pack 退出码 $exitCode');
        widget.onNotify('nuget pack 失败（退出码 $exitCode）', isError: true);
      }
    } on ProcessException catch (e) {
      widget.log.error('无法启动 nuget.exe：${e.message}');
      widget.onNotify('无法启动 nuget.exe', isError: true);
    }
  }

  String? _lastNupkgPath;

  Future<void> _forwardStream(Stream<List<int>> stream, LogLevel level) {
    return stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          final trimmed = line.trimRight();
          if (trimmed.trim().isEmpty) return;
          if (level == LogLevel.error) {
            widget.log.error(trimmed);
          } else {
            widget.log.info(trimmed);
            final parsed = parseNupkgOutputPath(trimmed);
            if (parsed != null) _lastNupkgPath = parsed;
          }
        });
  }
}

/// 带值同步的文本字段（只读时点按回调、可编辑时回调 onChanged）。
class _SyncedField extends StatefulWidget {
  const _SyncedField({
    required this.value,
    required this.readOnly,
    required this.hint,
    required this.mono,
    this.onChanged,
    this.onTap,
    this.suffix,
  });

  final String value;
  final bool readOnly;
  final String hint;
  final bool mono;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final Widget? suffix;

  @override
  State<_SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<_SyncedField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_SyncedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value;
    if (next != _controller.text && next != oldWidget.value) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            readOnly: widget.readOnly,
            onChanged: widget.readOnly ? null : widget.onChanged,
            onTap: widget.readOnly ? widget.onTap : null,
            style: widget.mono
                ? monoTextStyle()
                : const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppFontSizes.body,
                  ),
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ),
        if (widget.suffix != null) ...[
          const SizedBox(width: AppSpacing.s1),
          widget.suffix!,
        ],
      ],
    );
  }
}

class _PackPlaceholder extends StatelessWidget {
  const _PackPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '从左侧选择一个库项目开始打包',
        style: TextStyle(
          color: AppColors.textSemantic,
          fontSize: AppFontSizes.body,
        ),
      ),
    );
  }
}
