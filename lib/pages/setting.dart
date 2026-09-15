import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart' as toolchain;
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class Setting extends StatefulWidget {
  const Setting({
    super.key,
    required this.settings,
    required this.onSave,
    this.pickDirectory = getDirectoryPath,
    this.detectCompilers = detectCompilersWithControlledTemp,
    this.pickSaveFile = _pickSkillSaveLocation,
    this.loadSkillTemplate = _loadSkillTemplateAsset,
  });

  final SettingsModel settings;
  final Future<void> Function(SettingsModel settings) onSave;
  final Future<String?> Function() pickDirectory;
  final Future<List<toolchain.DetectedCompiler>> Function() detectCompilers;
  final Future<String?> Function(String suggestedName) pickSaveFile;
  final Future<String> Function() loadSkillTemplate;

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  static const Map<ThemeModeSetting, String> _themeModeLabels =
      <ThemeModeSetting, String>{
        ThemeModeSetting.system: '系统',
        ThemeModeSetting.dark: '深色',
        ThemeModeSetting.light: '浅色',
      };

  List<toolchain.DetectedCompiler> _detected =
      const <toolchain.DetectedCompiler>[];
  bool _detecting = true;
  late final TextEditingController _defaultAuthorController;
  late final FocusNode _defaultAuthorFocusNode;

  @override
  void initState() {
    super.initState();
    _defaultAuthorController = TextEditingController(
      text: widget.settings.defaultAuthor,
    );
    _defaultAuthorFocusNode = FocusNode()..addListener(_onAuthorFocusChanged);
    final List<toolchain.DetectedCompiler> cached =
        widget.settings.detectedCompilers;
    if (cached.isEmpty) {
      _detectCompilers(showLoading: false);
    } else {
      _detected = cached;
      _detecting = false;
    }
  }

  @override
  void didUpdateWidget(covariant Setting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.defaultAuthor == widget.settings.defaultAuthor) {
      return;
    }
    if (!_defaultAuthorFocusNode.hasFocus) {
      _defaultAuthorController.text = widget.settings.defaultAuthor;
    }
  }

  @override
  void dispose() {
    _defaultAuthorFocusNode
      ..removeListener(_onAuthorFocusChanged)
      ..dispose();
    _defaultAuthorController.dispose();
    super.dispose();
  }

  void _onAuthorFocusChanged() {
    if (_defaultAuthorFocusNode.hasFocus) {
      return;
    }
    _saveDefaultAuthor();
  }

  /// 失焦或回车时保存默认作者；值未变化不触发（防重复写盘 / 重复 toast）。
  void _saveDefaultAuthor() {
    final String value = _defaultAuthorController.text.trim();
    if (value == widget.settings.defaultAuthor) {
      return;
    }
    _apply(_defaultAuthorSettings(value));
  }

  Future<void> _detectCompilers({required bool showLoading}) async {
    if (showLoading) {
      setState(() => _detecting = true);
    }
    List<toolchain.DetectedCompiler>? detected;
    try {
      detected = await widget.detectCompilers();
    } catch (error) {
      if (mounted) {
        showFloatingToast(
          context,
          '编译器检测失败：${formatError(error)}',
          type: FloatingToastType.error,
          duration: const Duration(seconds: 5),
        );
      }
    }
    if (!mounted) {
      return;
    }
    final List<toolchain.DetectedCompiler>? result = detected;
    if (result == null) {
      // 检测失败保留原显示与缓存，不写回空结果。
      setState(() => _detecting = false);
      return;
    }
    setState(() {
      _detected = result;
      _detecting = false;
    });
    await _apply(_detectedSettings(result), showSavedToast: false);
  }

  Future<void> _apply(SettingsModel next, {bool showSavedToast = true}) async {
    try {
      await widget.onSave(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showFloatingToast(
        context,
        '保存失败：${formatError(error)}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (!mounted || !showSavedToast) {
      return;
    }
    showFloatingToast(context, '已保存');
  }

  SettingsModel _directorySettings({
    required String? outputDirectory,
    required String? cmakeOutputDirectory,
  }) {
    final SettingsModel current = widget.settings;
    return SettingsModel(
      outputDirectory: outputDirectory,
      cmakeOutputDirectory: cmakeOutputDirectory,
      defaultAuthor: current.defaultAuthor,
      themeMode: current.themeMode,
      compilerPriority: current.compilerPriority,
      detectedCompilers: current.detectedCompilers,
    );
  }

  SettingsModel _defaultAuthorSettings(String defaultAuthor) {
    final SettingsModel current = widget.settings;
    return SettingsModel(
      outputDirectory: current.outputDirectory,
      cmakeOutputDirectory: current.cmakeOutputDirectory,
      defaultAuthor: defaultAuthor,
      themeMode: current.themeMode,
      compilerPriority: current.compilerPriority,
      detectedCompilers: current.detectedCompilers,
    );
  }

  SettingsModel _themeSettings({ThemeModeSetting? themeMode}) {
    final SettingsModel current = widget.settings;
    return SettingsModel(
      outputDirectory: current.outputDirectory,
      cmakeOutputDirectory: current.cmakeOutputDirectory,
      defaultAuthor: current.defaultAuthor,
      themeMode: themeMode ?? current.themeMode,
      compilerPriority: current.compilerPriority,
      detectedCompilers: current.detectedCompilers,
    );
  }

  SettingsModel _compilerSettings(List<String> compilerPriority) {
    final SettingsModel current = widget.settings;
    return SettingsModel(
      outputDirectory: current.outputDirectory,
      cmakeOutputDirectory: current.cmakeOutputDirectory,
      defaultAuthor: current.defaultAuthor,
      themeMode: current.themeMode,
      compilerPriority: compilerPriority,
      detectedCompilers: current.detectedCompilers,
    );
  }

  SettingsModel _detectedSettings(List<toolchain.DetectedCompiler> detected) {
    final SettingsModel current = widget.settings;
    return SettingsModel(
      outputDirectory: current.outputDirectory,
      cmakeOutputDirectory: current.cmakeOutputDirectory,
      defaultAuthor: current.defaultAuthor,
      themeMode: current.themeMode,
      compilerPriority: current.compilerPriority,
      detectedCompilers: detected,
    );
  }

  void _moveCompiler(int index, int offset) {
    final List<String> priority = List<String>.of(
      widget.settings.compilerPriority,
    );
    final int target = index + offset;
    if (target < 0 || target >= priority.length) {
      return;
    }
    final String moved = priority.removeAt(index);
    priority.insert(target, moved);
    _apply(_compilerSettings(priority));
  }

  Future<void> _pickDirectory() async {
    final String? path = await widget.pickDirectory();
    if (path == null || !mounted) {
      return;
    }
    await _apply(
      _directorySettings(
        outputDirectory: path,
        cmakeOutputDirectory: widget.settings.cmakeOutputDirectory,
      ),
    );
  }

  Future<void> _clearDirectory() => _apply(
    _directorySettings(
      outputDirectory: null,
      cmakeOutputDirectory: widget.settings.cmakeOutputDirectory,
    ),
  );

  Future<void> _pickCmakeDirectory() async {
    final String? path = await widget.pickDirectory();
    if (path == null || !mounted) {
      return;
    }
    await _apply(
      _directorySettings(
        outputDirectory: widget.settings.outputDirectory,
        cmakeOutputDirectory: path,
      ),
    );
  }

  Future<void> _clearCmakeDirectory() => _apply(
    _directorySettings(
      outputDirectory: widget.settings.outputDirectory,
      cmakeOutputDirectory: null,
    ),
  );

  Future<void> _generateSkill() async {
    final String? path = await widget.pickSaveFile(_skillFileName);
    if (path == null || !mounted) {
      return;
    }
    try {
      final String template = await widget.loadSkillTemplate();
      await File(path).writeAsString(template, flush: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showFloatingToast(
        context,
        '生成失败：${formatError(error)}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    showFloatingToast(context, '已生成 SKILL.md');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(color: FluentTheme.of(context).cardColor),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(context, '打包输出目录'),
                const SizedBox(height: 12),
                InfoLabel(
                  label: 'NuGet 打包输出目录',
                  child: _buildDirectoryRow(
                    path: widget.settings.outputDirectory,
                    pickKey: const Key('settingPickDirButton'),
                    clearKey: const Key('settingClearDirButton'),
                    onPick: _pickDirectory,
                    onClear: _clearDirectory,
                  ),
                ),
                const SizedBox(height: 12),
                InfoLabel(
                  label: 'CMake 打包输出目录',
                  child: _buildDirectoryRow(
                    path: widget.settings.cmakeOutputDirectory,
                    pickKey: const Key('settingPickCmakeDirButton'),
                    clearKey: const Key('settingClearCmakeDirButton'),
                    onPick: _pickCmakeDirectory,
                    onClear: _clearCmakeDirectory,
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle(context, '默认作者'),
                const SizedBox(height: 12),
                _buildDefaultAuthorField(context),
                const SizedBox(height: 24),
                _buildSectionTitle(context, '主题'),
                const SizedBox(height: 12),
                InfoLabel(label: '主题模式', child: _buildThemeModeField()),
                const SizedBox(height: 24),
                _buildSectionTitle(context, '编译器'),
                const SizedBox(height: 12),
                _buildCompilerSection(context),
                const SizedBox(height: 24),
                _buildSectionTitle(context, 'SKILL.md'),
                const SizedBox(height: 12),
                _buildSkillSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: FluentTheme.of(context).typography.body?.color,
      ),
    );
  }

  Widget _buildDirectoryRow({
    required String? path,
    required Key pickKey,
    required Key clearKey,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            path ?? '未设置',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.resources.textFillColorSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Button(key: pickKey, onPressed: onPick, child: const Text('选择目录…')),
        const SizedBox(width: 8),
        Button(
          key: clearKey,
          onPressed: path == null ? null : onClear,
          child: const Text('清除'),
        ),
      ],
    );
  }

  Widget _buildDefaultAuthorField(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320,
          child: TextBox(
            key: const Key('settingDefaultAuthorField'),
            controller: _defaultAuthorController,
            focusNode: _defaultAuthorFocusNode,
            onSubmitted: (String _) => _saveDefaultAuthor(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '新包将预填此值；作者为空或占位（「无」「未知」等）的包将自动替换为默认作者。',
          style: TextStyle(color: theme.resources.textFillColorSecondary),
        ),
      ],
    );
  }

  Widget _buildThemeModeField() {
    return _comboBoxFrame(
      ComboBox<ThemeModeSetting>(
        key: const Key('settingThemeModeField'),
        value: widget.settings.themeMode,
        isExpanded: true,
        onChanged: (ThemeModeSetting? value) {
          if (value != null && value != widget.settings.themeMode) {
            _apply(_themeSettings(themeMode: value));
          }
        },
        items: <ComboBoxItem<ThemeModeSetting>>[
          for (final ThemeModeSetting mode in ThemeModeSetting.values)
            ComboBoxItem<ThemeModeSetting>(
              value: mode,
              child: Text(_themeModeLabels[mode]!),
            ),
        ],
      ),
    );
  }

  Widget _buildCompilerSection(BuildContext context) {
    if (_detecting && _detected.isEmpty) {
      return const Row(
        children: [
          SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('正在检测编译器…'),
        ],
      );
    }
    final List<String> priority = widget.settings.compilerPriority;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '优先使用的编译器（自上而下）',
                style: TextStyle(
                  color: FluentTheme.of(context)
                      .resources
                      .textFillColorSecondary,
                ),
              ),
            ),
            Button(
              key: const Key('settingCompilerRefreshButton'),
              onPressed: _detecting
                  ? null
                  : () => _detectCompilers(showLoading: true),
              child: const Text('重新检测'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < priority.length; index++)
          _buildCompilerRow(priority[index], index),
      ],
    );
  }

  Widget _buildCompilerRow(String id, int index) {
    final toolchain.DetectedCompiler? compiler = _findCompiler(id);
    final FluentThemeData theme = FluentTheme.of(context);
    return SizedBox(
      key: Key('settingCompilerRow_$id'),
      height: 32,
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(_compilerLabel(id))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              compiler?.version ?? '未检测到',
              overflow: TextOverflow.ellipsis,
              style: compiler == null
                  ? TextStyle(color: theme.resources.textFillColorSecondary)
                  : null,
            ),
          ),
          _buildMoveButton(
            key: Key('settingCompilerMoveUp_$id'),
            icon: FluentIcons.chevron_up,
            tooltip: '上移',
            onPressed: index > 0 ? () => _moveCompiler(index, -1) : null,
          ),
          _buildMoveButton(
            key: Key('settingCompilerMoveDown_$id'),
            icon: FluentIcons.chevron_down,
            tooltip: '下移',
            onPressed: index < widget.settings.compilerPriority.length - 1
                ? () => _moveCompiler(index, 1)
                : null,
          ),
        ],
      ),
    );
  }

  toolchain.DetectedCompiler? _findCompiler(String id) {
    for (final toolchain.DetectedCompiler compiler in _detected) {
      if (toolchain.compilerKindId(compiler.kind) == id) {
        return compiler;
      }
    }
    return null;
  }

  String _compilerLabel(String id) {
    for (final toolchain.CompilerKind kind in toolchain.CompilerKind.values) {
      if (toolchain.compilerKindId(kind) == id) {
        return toolchain.compilerKindLabel(kind);
      }
    }
    return id;
  }

  Widget _buildMoveButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
          key: key,
          icon: Icon(icon, size: 14),
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget _buildSkillSection(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '生成 build.py 编写技能文档（SKILL.md），可放入 AI 插件的技能目录使用。',
            style: TextStyle(
              color: FluentTheme.of(context).resources.textFillColorSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Button(
          key: const Key('settingGenerateSkillButton'),
          onPressed: _generateSkill,
          child: const Text('生成 SKILL.md…'),
        ),
      ],
    );
  }

  Widget _comboBoxFrame(Widget child) {
    return SizedBox(
      width: 240,
      child: FluentTheme(
        data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
        child: child,
      ),
    );
  }
}

const String _skillFileName = 'SKILL.md';
const String _skillAssetPath = 'assets/build/SKILL.md';

Future<String?> _pickSkillSaveLocation(String suggestedName) async {
  final FileSaveLocation? location = await getSaveLocation(
    suggestedName: suggestedName,
  );
  return location?.path;
}

Future<String> _loadSkillTemplateAsset() =>
    rootBundle.loadString(_skillAssetPath);
