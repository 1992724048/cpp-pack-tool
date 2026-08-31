/// 打包 Tab：模式切换（一键/仅生成文件）、全局输出目录（只读显示）、nuget 路径、
/// 打包按钮状态机。
///
/// 输出目录统一取自全局设置 [AppSettings.defaultOutputDir]（仅设置对话框可改）；
/// 此处只读显示，点击跳转设置。对照 `docs/ui-spec.md` §3.6 与 §5.2。打包采用
/// UI 侧独立 `Process.start` 流式输出到日志面板（不改 `packer.dart`，仅复用其
/// `buildPackArgs`）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../../services/cmake_generator.dart';
import '../../services/msbuild_generator.dart';
import '../../services/nuspec_generator.dart';
import '../../services/package_registry.dart';
import '../../services/packer.dart';
import '../../services/path_utils.dart';
import '../../services/settings.dart';
import '../tokens.dart';
import '../io_picker.dart';
import '../log_controller.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/form_fields.dart';

/// 打包模式。
enum PackMode { generateOnly, pack }

/// 版本策略可选值（与 `package_registry.suggestVersion` 的 strategy 一致）。
const List<(String, String)> _kVersionStrategies = <(String, String)>[
  ('manual', '手动'),
  ('timestamp', '时间戳自动'),
  ('bump', '自动递进'),
];

/// 打包页。
class PackPage extends StatefulWidget {
  const PackPage({
    super.key,
    required this.project,
    required this.onChanged,
    required this.settings,
    required this.onSettingsChanged,
    required this.onOpenSettings,
    required this.log,
    required this.onNotify,
    required this.onPacked,
  });

  final PackProject? project;
  final ValueChanged<PackProject> onChanged;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  /// 点击输出目录（或跳设置入口）时打开设置对话框。
  final VoidCallback onOpenSettings;
  final LogController log;

  /// 一次性操作结果提示（SnackBar 文案）。
  final void Function(String message, {bool isError}) onNotify;

  /// 一键打包成功后回调（用于登记输出目录注册表）。
  final void Function(PackProject project) onPacked;

  @override
  State<PackPage> createState() => _PackPageState();
}

class _PackPageState extends State<PackPage> {
  PackMode _mode = PackMode.pack;
  bool _busy = false;

  /// 版本策略（手动/时间戳自动/自动递进）；默认「手动」（值取输入版本原样）。
  String _versionStrategy = 'manual';

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
          _modeSelector(),
          const SizedBox(height: AppSpacing.s3),
          _versionStrategyField(project),
          const SizedBox(height: AppSpacing.s2),
          _outputDirField(),
          const SizedBox(height: AppSpacing.s2),
          _nugetField(),
          const SizedBox(height: AppSpacing.s2),
          _buildScriptSection(project),
          const SizedBox(height: AppSpacing.s3),
          _packButton(project, enabled),
          const SizedBox(height: AppSpacing.s2),
          if (missing.isNotEmpty) _missingText(missing),
        ],
      ),
    );
  }

  /// 版本策略区：当前版本（只读，来自「包信息」）+ 版本策略下拉。
  Widget _versionStrategyField(PackProject project) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '版本策略',
          style: TextStyle(
            color: AppColors.textSemantic,
            fontSize: AppFontSizes.small,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                '当前版本：${project.version}',
                style: monoTextStyle(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            DropdownButton<String>(
              value: _versionStrategy,
              underline: const SizedBox.shrink(),
              items: [
                for (final (value, label) in _kVersionStrategies)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _versionStrategy = value);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          '打包/仅生成前按此策略自动更新「包信息」中的版本（非手动时）。',
          style: TextStyle(
            color: AppColors.textDisabled,
            fontSize: AppFontSizes.caption,
          ),
        ),
      ],
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

  Widget _outputDirField() {
    final outputDir = widget.settings.defaultOutputDir.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '输出目录',
          style: TextStyle(
            color: AppColors.textSemantic,
            fontSize: AppFontSizes.small,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SyncedField(
          value: outputDir,
          readOnly: true,
          hint: '未设置，点击设置',
          mono: true,
          onTap: widget.onOpenSettings,
          suffix: IconButton(
            onPressed: widget.onOpenSettings,
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined, size: 18),
            iconSize: 18,
            color: AppColors.textSemantic,
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _generateConsumerConfig,
            icon: const Icon(Icons.settings_ethernet, size: 16),
            label: const Text('生成消费方 nuget.config'),
          ),
        ),
      ],
    );
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

  /// 构建脚本区：构建前/构建后两个输入框（含浏览按钮）。
  Widget _buildScriptSection(PackProject project) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '构建脚本',
          style: TextStyle(
            color: AppColors.textSemantic,
            fontSize: AppFontSizes.small,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SyncedField(
          value: project.preBuildCommand,
          readOnly: false,
          hint: '构建前执行，如 clean.bat 或 .\\sign.ps1',
          mono: true,
          onChanged: (value) =>
              _updateProject(project.copyWith(preBuildCommand: value)),
          suffix: TextButton(
            onPressed: () => _pickScript(project, pre: true),
            child: const Text('浏览'),
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        _SyncedField(
          value: project.postBuildCommand,
          readOnly: false,
          hint: '构建后执行，如 .\\sign.ps1',
          mono: true,
          onChanged: (value) =>
              _updateProject(project.copyWith(postBuildCommand: value)),
          suffix: TextButton(
            onPressed: () => _pickScript(project, pre: false),
            child: const Text('浏览'),
          ),
        ),
      ],
    );
  }

  Future<void> _pickScript(PackProject project, {required bool pre}) async {
    final path = await pickScript();
    if (path == null || path.trim().isEmpty) return;
    if (pre) {
      _updateProject(project.copyWith(preBuildCommand: path.trim()));
    } else {
      _updateProject(project.copyWith(postBuildCommand: path.trim()));
    }
  }

  void _updateProject(PackProject project) => widget.onChanged(project);

  /// 在全局输出目录生成消费方 `nuget.config`。
  Future<void> _generateConsumerConfig() async {
    final outputDir = widget.settings.defaultOutputDir.trim();
    if (outputDir.isEmpty) {
      widget.log.error('输出目录未设置，无法生成消费方 nuget.config');
      widget.onNotify('输出目录未设置', isError: true);
      return;
    }
    try {
      final content = generateConsumerNugetConfig(
        outputDir: outputDir,
        globalCacheDir: widget.settings.nugetGlobalCacheDir,
      );
      final path = joinPath([outputDir, 'nuget.config']);
      File(path).writeAsStringSync(content);
      widget.log.info('已生成消费方 nuget.config：$path');
      widget.onNotify('已生成 nuget.config：$path');
    } on Object catch (e) {
      widget.log.error('生成 nuget.config 失败：$e');
      widget.onNotify('生成 nuget.config 失败', isError: true);
    }
  }

  Widget _packButton(PackProject project, bool enabled) {
    final label = _mode == PackMode.pack ? '打包' : '生成文件';
    // 预览/生成 CMake 包依赖输出目录与包 id；不依赖 nuget 路径（'enabled' 已含 nuget）。
    final secondaryEnabled =
        !_busy &&
        widget.settings.defaultOutputDir.trim().isNotEmpty &&
        project.packageId.trim().isNotEmpty;
    return Row(
      children: [
        Tooltip(
          message: '预览生成文件',
          child: OutlinedButton.icon(
            onPressed: secondaryEnabled ? () => _previewFiles(project) : null,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('预览'),
          ),
        ),
        const SizedBox(width: AppSpacing.s1),
        Tooltip(
          message:
              '生成 CMake 包配置（建议使用具体文件映射；'
              '含通配符的 glob 会生成通配符文件名）',
          child: OutlinedButton.icon(
            onPressed: secondaryEnabled ? () => _generateCmake(project) : null,
            icon: const Icon(Icons.code, size: 16),
            label: const Text('生成 CMake 包'),
          ),
        ),
        const SizedBox(width: AppSpacing.s1),
        Expanded(
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
        ),
      ],
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
    if (widget.settings.defaultOutputDir.trim().isEmpty) {
      missing.add('输出目录未设置');
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
      final effective = _applyVersionStrategy(project);
      if (effective == null) return; // 版本解析失败，错误已提示。
      if (!await _confirmDependenciesPresent(effective)) return; // 用户取消。
      _warnMissingFiles(effective);
      // 构建前脚本：失败即中止，不进入生成/打包流程。
      if (!await _runPreBuild(effective)) return;
      final paths = await _generateFiles(effective);
      widget.log.info('已生成：${paths.join('；')}');
      if (_mode == PackMode.pack) {
        final packed = await _packWithNuget(effective);
        if (packed) {
          widget.onPacked(effective);
          await _runPostBuild(effective);
        }
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

  /// 按版本策略推导实际版本：手动取输入版本原样；其他策略调用
  /// [suggestVersion]。成功返回更新后的项目（并回写 onChanged），失败返回 null。
  PackProject? _applyVersionStrategy(PackProject project) {
    if (_versionStrategy == 'manual') return project;
    final outputDir = widget.settings.defaultOutputDir.trim();
    final registered = _registeredVersions(outputDir, project.packageId);
    final suggested = suggestVersion(
      currentVersion: project.version,
      registeredVersions: registered,
      strategy: _versionStrategy,
    );
    if (suggested == null) {
      widget.log.error('版本解析失败');
      widget.onNotify('版本解析失败', isError: true);
      return null;
    }
    final updated = project.copyWith(version: suggested);
    if (updated.version != project.version) {
      widget.onChanged(updated);
      widget.log.info(
        '版本策略「${_versionStrategyLabel(_versionStrategy)}」生成版本：$suggested',
      );
    }
    return updated;
  }

  /// 收集输出目录注册表里该包历史版本 + 当前注册表版本（用于 bump 基线）。
  List<String> _registeredVersions(String outputDir, String packageId) {
    if (outputDir.isEmpty) return const <String>[];
    final result = loadRegistry(outputDir);
    for (final pkg in result.packages) {
      if (pkg.project.packageId == packageId) {
        final versions = <String>{
          for (final entry in pkg.history) entry.version,
          if (pkg.project.version.trim().isNotEmpty) pkg.project.version.trim(),
        };
        return versions.toList();
      }
    }
    return const <String>[];
  }

  String _versionStrategyLabel(String strategy) {
    for (final (value, label) in _kVersionStrategies) {
      if (value == strategy) return label;
    }
    return strategy;
  }

  /// 打包/仅生成前检查依赖是否已在输出目录注册表登记；缺失时弹警告对话框，
  /// 用户取消返回 false（中止），继续返回 true（warn 日志后继续）。
  Future<bool> _confirmDependenciesPresent(PackProject project) async {
    if (project.dependencies.isEmpty) return true;
    final outputDir = widget.settings.defaultOutputDir.trim();
    if (outputDir.isEmpty) return true;
    final missing = <String>[
      for (final dep in project.dependencies)
        if (!isPackagePresent(outputDir, dep.id))
          '${dep.id} ${dep.version}'.trim(),
    ];
    if (missing.isEmpty) return true;
    final proceed = await confirmMissingDependencies(context, missing: missing);
    if (proceed) {
      widget.log.warn('依赖缺失警告，用户选择继续打包：${missing.join('；')}');
    }
    return proceed;
  }

  /// 打开「预览生成文件」对话框。
  void _previewFiles(PackProject project) {
    final outputDir = widget.settings.defaultOutputDir.trim();
    if (outputDir.isEmpty) {
      widget.log.error('输出目录未设置，无法预览生成文件');
      widget.onNotify('输出目录未设置', isError: true);
      return;
    }
    final buildDir = joinPath([outputDir, 'build']);
    previewFilesDialog(context, project: project, buildDir: buildDir);
  }

  /// 生成 CMake 包配置文件并写入 `{输出目录}\cmake\{packageId}\`。
  void _generateCmake(PackProject project) {
    final outputDir = widget.settings.defaultOutputDir.trim();
    if (outputDir.isEmpty) {
      widget.log.error('输出目录未设置，无法生成 CMake 包');
      widget.onNotify('输出目录未设置', isError: true);
      return;
    }
    try {
      final entries = generateCmakeEntries(project);
      final id = project.packageId.trim();
      final cmakeDir = joinPath([outputDir, 'cmake', id]);
      Directory(cmakeDir).createSync(recursive: true);
      final written = <String>[];
      for (final entry in entries) {
        final path = joinPath([cmakeDir, entry.path]);
        File(path).writeAsStringSync(entry.content);
        written.add(path);
      }
      widget.log.info('已生成 CMake 包文件：${written.join('；')}');
      widget.onNotify('已生成 ${entries.length} 个 CMake 文件');
    } on Object catch (e) {
      widget.log.error('生成 CMake 包失败：$e');
      widget.onNotify('生成 CMake 包失败', isError: true);
    }
  }

  /// 执行构建前脚本（`cmd /c`）。成功返回 true；失败或异常返回 false（中止打包）。
  Future<bool> _runPreBuild(PackProject project) async {
    final command = project.preBuildCommand.trim();
    if (command.isEmpty) return true;
    final workingDir = _commandWorkingDir(project);
    widget.log.info('执行构建前脚本：$command');
    try {
      final result = await Process.run('cmd', [
        '/c',
        command,
      ], workingDirectory: workingDir.isEmpty ? null : workingDir);
      _logProcessOutput(result);
      if (result.exitCode != 0) {
        final message = '构建前脚本失败（退出码 ${result.exitCode}），已中止打包';
        widget.log.error(message);
        widget.onNotify('构建前脚本失败，已中止', isError: true);
        return false;
      }
      widget.log.info('构建前脚本执行完成');
      return true;
    } on ProcessException catch (e) {
      widget.log.error('无法执行构建前脚本：${e.message}');
      widget.onNotify('无法执行构建前脚本', isError: true);
      return false;
    }
  }

  /// 执行构建后脚本（`cmd /c`）。失败仅记录 warn 日志，不改变打包结果。
  Future<void> _runPostBuild(PackProject project) async {
    final command = project.postBuildCommand.trim();
    if (command.isEmpty) return;
    final workingDir = _commandWorkingDir(project);
    widget.log.info('执行构建后脚本：$command');
    try {
      final result = await Process.run('cmd', [
        '/c',
        command,
      ], workingDirectory: workingDir.isEmpty ? null : workingDir);
      _logProcessOutput(result);
      if (result.exitCode != 0) {
        widget.log.warn('构建后脚本失败（退出码 ${result.exitCode}），打包已完成');
      } else {
        widget.log.info('构建后脚本执行完成');
      }
    } on ProcessException catch (e) {
      widget.log.warn('无法执行构建后脚本：${e.message}（打包已完成）');
    }
  }

  /// 构建脚本工作目录：首个存在的源目录，否则用全局输出目录。
  String _commandWorkingDir(PackProject project) {
    for (final sourceDir in project.sourceDirs) {
      final path = sourceDir.path.trim();
      if (path.isNotEmpty && Directory(path).existsSync()) return path;
    }
    return widget.settings.defaultOutputDir.trim();
  }

  /// 将脚本进程的 stdout/stderr 截断前 2000 字符，stdout→info、stderr→warn。
  void _logProcessOutput(ProcessResult result) {
    final stdout = _truncate(_resultText(result.stdout));
    final stderr = _truncate(_resultText(result.stderr));
    if (stdout.trim().isNotEmpty) widget.log.info(stdout);
    if (stderr.trim().isNotEmpty) widget.log.warn(stderr);
  }

  String _truncate(String value) =>
      value.length <= 2000 ? value : '${value.substring(0, 2000)}…（已截断）';

  String _resultText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List<int>) return systemEncoding.decode(value);
    return value.toString();
  }

  /// 生成 nuspec/props/targets 并写入全局输出目录下的 `build` 子目录；返回写入的文件路径列表。
  ///
  /// 布局：`build\{id}.nuspec`、`build\native\{id}.props`、`build\native\{id}.targets`。
  /// nuspec 的 `baseDir` 传其所在目录（build），使集成条目 src（`native\...`）与
  /// 文件映射相对路径均相对 nuspec 解析，保证 nuget pack 工作目录正确。
  Future<List<String>> _generateFiles(PackProject project) async {
    final outputDir = widget.settings.defaultOutputDir.trim();
    if (outputDir.isEmpty) {
      throw const FormatException('输出目录未设置');
    }
    final id = project.packageId.trim();
    final buildDir = joinPath([outputDir, 'build']);
    final buildNativeDir = joinPath([buildDir, 'native']);
    Directory(buildNativeDir).createSync(recursive: true);

    final nuspecPath = joinPath([buildDir, '$id.nuspec']);
    final propsPath = joinPath([buildNativeDir, '$id.props']);
    final targetsPath = joinPath([buildNativeDir, '$id.targets']);

    // `generate` 已在 files 段头部输出 props/targets 的 `<file>` 条目，
    // 此处直接使用其结果，避免重复追加导致 nuget pack 异常。
    final nuspec = generate(project, baseDir: buildDir);
    File(nuspecPath).writeAsStringSync(nuspec);
    File(propsPath).writeAsStringSync(generateProps(project));
    File(targetsPath).writeAsStringSync(generateTargets(project));

    return <String>[nuspecPath, propsPath, targetsPath];
  }

  /// 打包/仅生成文件前的存在性校验：对每条映射按源目录解析实际路径，
  /// 缺失的文件逐条向日志面板追加 warn 级日志并继续执行（不中断）。
  void _warnMissingFiles(PackProject project) {
    for (final sourceDir in project.sourceDirs) {
      final sourcePath = sourceDir.path.trim();
      if (sourcePath.isEmpty) continue;
      for (final mapping in sourceDir.mappings) {
        final glob = mapping.srcGlob.trim();
        if (glob.isEmpty) continue;
        final resolved = _joinSourceGlob(sourcePath, glob);
        if (!_pathExists(resolved)) {
          widget.log.warn('警告：文件不存在，将影响打包：$resolved');
        }
      }
    }
  }

  /// 拼接源目录与映射 glob（归一化分隔符，避免重复斜杠）。
  String _joinSourceGlob(String dir, String glob) {
    final dirNorm = normalizeSeparators(dir.trim());
    final globNorm = normalizeSeparators(glob.trim());
    if (dirNorm.isEmpty) return globNorm;
    if (globNorm.isEmpty) return dirNorm;
    if (dirNorm.endsWith(pathSeparator)) return '$dirNorm$globNorm';
    return '$dirNorm$pathSeparator$globNorm';
  }

  /// 判断 [candidate] 是否存在。
  ///
  /// glob 含通配符（`*`/`?`）时做目录存在性探测（取通配符前的静态前缀目录）；
  /// 否则做精确文件存在性检查。
  bool _pathExists(String candidate) {
    final normalized = normalizeSeparators(candidate);
    final wildcardIdx = _firstWildcard(normalized);
    if (wildcardIdx >= 0) {
      final dir = _probeDirectory(normalized, wildcardIdx);
      return Directory(dir).existsSync();
    }
    return File(normalized).existsSync();
  }

  /// 取通配符前的静态前缀目录（用于目录存在性探测）。
  String _probeDirectory(String normalized, int wildcardIdx) {
    final prefix = normalized.substring(0, wildcardIdx);
    if (prefix.endsWith(pathSeparator)) {
      final trimmed = prefix.replaceAll(RegExp(r'[\\/]+$'), '');
      if (trimmed.isNotEmpty) return trimmed;
    }
    final dir = dirnameOf(prefix);
    if (dir.isNotEmpty) return dir;
    return dirnameOf(normalized);
  }

  /// 返回字符串中首个通配符位置；无通配符返回 -1。
  int _firstWildcard(String value) {
    final star = value.indexOf('*');
    final question = value.indexOf('?');
    if (star < 0) return question;
    if (question < 0) return star;
    return star < question ? star : question;
  }

  /// 执行一键打包；返回是否成功（退出码 0）。
  Future<bool> _packWithNuget(PackProject project) async {
    final nugetExe = (widget.settings.nugetExePath ?? '').trim();
    if (nugetExe.isEmpty) {
      throw const FormatException('nuget.exe 路径未配置');
    }
    final outputDir = widget.settings.defaultOutputDir.trim();
    final id = project.packageId.trim();
    final buildDir = joinPath([outputDir, 'build']);
    final nuspecPath = joinPath([buildDir, '$id.nuspec']);

    widget.log.info('开始打包：nuget.exe $nugetExe');
    final args = buildPackArgs(nuspecPath: nuspecPath, outputDir: outputDir);
    try {
      final process = await Process.start(
        nugetExe,
        args,
        workingDirectory: buildDir,
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
        return true;
      } else {
        widget.log.error('nuget pack 退出码 $exitCode');
        widget.onNotify('nuget pack 失败（退出码 $exitCode）', isError: true);
        return false;
      }
    } on ProcessException catch (e) {
      widget.log.error('无法启动 nuget.exe：${e.message}');
      widget.onNotify('无法启动 nuget.exe', isError: true);
      return false;
    }
  }

  String? _lastNupkgPath;

  Future<void> _forwardStream(Stream<List<int>> stream, LogLevel level) {
    // Windows 中文系统下 nuget.exe 的 stdout/stderr 为系统 ANSI（GBK）编码，
    // 且 chunk 边界可能截断多字节序列——若按 UTF-8 解码会抛出
    // FormatException 导致打包崩溃。改用 `systemEncoding.decoder`（系统代码页），
    // 并对整体解码链路追加兜底 catch，异常只记日志、不中断打包。
    return stream
        .transform(systemEncoding.decoder)
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
        })
        .catchError((Object e) {
          widget.log.warn('解码打包输出时出错：$e');
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
