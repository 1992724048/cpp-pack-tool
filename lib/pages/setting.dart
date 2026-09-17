import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart' as toolchain;
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_card.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_group.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_page.dart';
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
  static const Map<ThemeModeSetting, String> _themeModeLabels = <ThemeModeSetting, String>{
    ThemeModeSetting.system: '系统',
    ThemeModeSetting.dark: '深色',
    ThemeModeSetting.light: '浅色',
  };

  static const Map<ProxyModeSetting, String> _proxyModeLabels = <ProxyModeSetting, String>{
    ProxyModeSetting.off: '关闭',
    ProxyModeSetting.auto: '自动检测',
    ProxyModeSetting.manual: '手动设置',
  };

  List<toolchain.DetectedCompiler> _detected = const <toolchain.DetectedCompiler>[];
  bool _detecting = true;
  late final TextEditingController _defaultAuthorController;
  late final FocusNode _defaultAuthorFocusNode;
  late final TextEditingController _proxyHostController;
  late final FocusNode _proxyHostFocusNode;
  late final TextEditingController _proxyPortController;
  late final FocusNode _proxyPortFocusNode;
  String? _proxyPortError;

  @override
  void initState() {
    super.initState();
    _defaultAuthorController = TextEditingController(text: widget.settings.defaultAuthor);
    _defaultAuthorFocusNode = FocusNode()..addListener(_onAuthorFocusChanged);
    _proxyHostController = TextEditingController(text: widget.settings.proxyHost);
    _proxyHostFocusNode = FocusNode()..addListener(_onProxyHostFocusChanged);
    _proxyPortController = TextEditingController(text: widget.settings.proxyPort?.toString() ?? '');
    _proxyPortFocusNode = FocusNode()..addListener(_onProxyPortFocusChanged);
    final List<toolchain.DetectedCompiler> cached = widget.settings.detectedCompilers;
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
    if (oldWidget.settings.defaultAuthor != widget.settings.defaultAuthor && !_defaultAuthorFocusNode.hasFocus) {
      _defaultAuthorController.text = widget.settings.defaultAuthor;
    }
    if (oldWidget.settings.proxyHost != widget.settings.proxyHost && !_proxyHostFocusNode.hasFocus) {
      _proxyHostController.text = widget.settings.proxyHost;
    }
    if (oldWidget.settings.proxyPort != widget.settings.proxyPort && !_proxyPortFocusNode.hasFocus) {
      _proxyPortController.text = widget.settings.proxyPort?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _defaultAuthorFocusNode
      ..removeListener(_onAuthorFocusChanged)
      ..dispose();
    _defaultAuthorController.dispose();
    _proxyHostFocusNode
      ..removeListener(_onProxyHostFocusChanged)
      ..dispose();
    _proxyHostController.dispose();
    _proxyPortFocusNode
      ..removeListener(_onProxyPortFocusChanged)
      ..dispose();
    _proxyPortController.dispose();
    super.dispose();
  }

  void _onAuthorFocusChanged() {
    if (_defaultAuthorFocusNode.hasFocus) {
      return;
    }
    _saveDefaultAuthor();
  }

  void _onProxyHostFocusChanged() {
    if (_proxyHostFocusNode.hasFocus) {
      return;
    }
    _saveProxyHost();
  }

  void _onProxyPortFocusChanged() {
    if (_proxyPortFocusNode.hasFocus) {
      return;
    }
    _saveProxyPort();
  }

  /// 失焦或回车时保存默认作者；值未变化不触发（防重复写盘 / 重复 toast）。
  void _saveDefaultAuthor() {
    final String value = _defaultAuthorController.text.trim();
    if (value == widget.settings.defaultAuthor) {
      return;
    }
    _apply(_defaultAuthorSettings(value));
  }

  Future<void> _saveProxyMode(ProxyModeSetting mode) {
    if (mode == widget.settings.proxyMode) {
      return Future<void>.value();
    }
    return _apply(widget.settings.copyWith(proxyMode: mode));
  }

  /// 手动代理地址失焦/回车保存；值未变化不写盘。地址允许 `http://host` 前缀
  /// （保存原样），空值视为未设置（运行侧退直连）。
  void _saveProxyHost() {
    final String value = _proxyHostController.text.trim();
    if (value == widget.settings.proxyHost) {
      return;
    }
    _apply(widget.settings.copyWith(proxyHost: value));
  }

  /// 手动代理端口失焦/回车保存；空值清除端口（可回退地址中声明的端口），
  /// 非 1–65535 的整数时显示内联错误且不写盘。
  void _saveProxyPort() {
    final String text = _proxyPortController.text.trim();
    if (text.isEmpty) {
      setState(() => _proxyPortError = null);
      if (widget.settings.proxyPort != null) {
        _apply(widget.settings.copyWith(proxyPort: null));
      }
      return;
    }
    final int? port = int.tryParse(text);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _proxyPortError = '端口需为 1–65535 的整数');
      return;
    }
    setState(() => _proxyPortError = null);
    if (port == widget.settings.proxyPort) {
      return;
    }
    _apply(widget.settings.copyWith(proxyPort: port));
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

  SettingsModel _directorySettings({required String? outputDirectory, required String? cmakeOutputDirectory}) {
    return widget.settings.copyWith(outputDirectory: outputDirectory, cmakeOutputDirectory: cmakeOutputDirectory);
  }

  SettingsModel _defaultAuthorSettings(String defaultAuthor) => widget.settings.copyWith(defaultAuthor: defaultAuthor);

  SettingsModel _themeSettings({ThemeModeSetting? themeMode}) => widget.settings.copyWith(themeMode: themeMode);

  SettingsModel _compilerSettings(List<String> compilerPriority) =>
      widget.settings.copyWith(compilerPriority: compilerPriority);

  SettingsModel _detectedSettings(List<toolchain.DetectedCompiler> detected) =>
      widget.settings.copyWith(detectedCompilers: detected);

  void _moveCompiler(int index, int offset) {
    final List<String> priority = List<String>.of(widget.settings.compilerPriority);
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
    await _apply(_directorySettings(outputDirectory: path, cmakeOutputDirectory: widget.settings.cmakeOutputDirectory));
  }

  Future<void> _clearDirectory() =>
      _apply(_directorySettings(outputDirectory: null, cmakeOutputDirectory: widget.settings.cmakeOutputDirectory));

  Future<void> _pickCmakeDirectory() async {
    final String? path = await widget.pickDirectory();
    if (path == null || !mounted) {
      return;
    }
    await _apply(_directorySettings(outputDirectory: widget.settings.outputDirectory, cmakeOutputDirectory: path));
  }

  Future<void> _clearCmakeDirectory() =>
      _apply(_directorySettings(outputDirectory: widget.settings.outputDirectory, cmakeOutputDirectory: null));

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
    final bool manualProxy = widget.settings.proxyMode == ProxyModeSetting.manual;
    return SettingsPage(
      title: '设置',
      description: const Text('配置打包输出目录、默认作者、外观、编译器优先级、网络代理与 AI 技能输出。'),
      children: <Widget>[
        SettingsGroup(
          header: '打包',
          first: true,
          children: <Widget>[
            _buildDirectoryCard(
              header: 'NuGet 打包输出目录',
              path: widget.settings.outputDirectory,
              pickKey: const Key('settingPickDirButton'),
              clearKey: const Key('settingClearDirButton'),
              onPick: _pickDirectory,
              onClear: _clearDirectory,
            ),
            _buildDirectoryCard(
              header: 'CMake 打包输出目录',
              path: widget.settings.cmakeOutputDirectory,
              pickKey: const Key('settingPickCmakeDirButton'),
              clearKey: const Key('settingClearCmakeDirButton'),
              onPick: _pickCmakeDirectory,
              onClear: _clearCmakeDirectory,
            ),
          ],
        ),
        SettingsGroup(header: '新包默认值', children: <Widget>[_buildDefaultAuthorCard()]),
        SettingsGroup(header: '外观', children: <Widget>[_buildThemeModeCard()]),
        SettingsGroup(header: '编译器', children: <Widget>[_buildCompilerCard()]),
        SettingsGroup(
          header: '网络',
          children: <Widget>[_buildProxyModeCard(), if (manualProxy) _buildProxyManualCard()],
        ),
        SettingsGroup(header: 'AI 技能', children: <Widget>[_buildSkillCard()]),
      ],
    );
  }

  Widget _buildDirectoryCard({
    required String header,
    required String? path,
    required Key pickKey,
    required Key clearKey,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return SettingsCard(
      padding: const .fromLTRB(8, 8, 8, 8),
      header: Text(header),
      content: _buildPathControls(path: path, pickKey: pickKey, clearKey: clearKey, onPick: onPick, onClear: onClear),
    );
  }

  Widget _buildPathControls({
    required String? path,
    required Key pickKey,
    required Key clearKey,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final FluentThemeData theme = FluentTheme.of(context);
    final String label = path ?? '未设置';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Tooltip(
            message: label,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.resources.textFillColorSecondary),
            ),
          ),
        ),
        Button(key: pickKey, onPressed: onPick, child: const Text('选择目录…')),
        Button(key: clearKey, onPressed: path == null ? null : onClear, child: const Text('清除')),
      ],
    );
  }

  Widget _buildDefaultAuthorCard() {
    return SettingsCard(
      padding: const .fromLTRB(8, 8, 8, 8),
      header: const Text('默认作者'),
      description: const Text('新包将预填此值；作者为空或占位（「无」「未知」等）的包将自动替换为默认作者。'),
      content: SizedBox(
        width: 320,
        child: TextBox(
          key: const Key('settingDefaultAuthorField'),
          controller: _defaultAuthorController,
          focusNode: _defaultAuthorFocusNode,
          onSubmitted: (String _) => _saveDefaultAuthor(),
        ),
      ),
    );
  }

  Widget _buildThemeModeCard() {
    return SettingsCard(
      header: const Text('主题模式'),
      padding: const .fromLTRB(8, 8, 8, 8),
      content: _comboBoxField(
        width: 160,
        child: ComboBox<ThemeModeSetting>(
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
              ComboBoxItem<ThemeModeSetting>(value: mode, child: Text(_themeModeLabels[mode]!)),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyModeCard() {
    return SettingsCard(
      padding: const .fromLTRB(8, 8, 8, 8),
      header: const Text('代理模式'),
      description: const Text(
        '自动检测：使用 Windows 系统代理设置，不可用时自动直连。'
        '手动设置：填写本机代理服务器，代理不可用时自动直连。',
      ),
      content: _comboBoxField(
        width: 160,
        child: ComboBox<ProxyModeSetting>(
          key: const Key('settingProxyModeField'),
          value: widget.settings.proxyMode,
          isExpanded: true,
          onChanged: (ProxyModeSetting? value) {
            if (value != null) {
              _saveProxyMode(value);
            }
          },
          items: <ComboBoxItem<ProxyModeSetting>>[
            for (final ProxyModeSetting mode in ProxyModeSetting.values)
              ComboBoxItem<ProxyModeSetting>(value: mode, child: Text(_proxyModeLabels[mode]!)),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyManualCard() {
    final FluentThemeData theme = FluentTheme.of(context);
    return SettingsCard(
      padding: const .fromLTRB(8, 8, 8, 8),
      header: const Text('手动设置'),
      description: const Text(
        '服务器地址支持 host:port 或 http://host:port，端口留空时使用地址中声明的端口'
        '（均未声明时默认 1080）。',
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 240,
                  child: TextBox(
                    key: const Key('settingProxyHostField'),
                    controller: _proxyHostController,
                    focusNode: _proxyHostFocusNode,
                    placeholder: '127.0.0.1',
                    onSubmitted: (String _) => _saveProxyHost(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: TextBox(
                    key: const Key('settingProxyPortField'),
                    controller: _proxyPortController,
                    focusNode: _proxyPortFocusNode,
                    placeholder: '7890',
                    onSubmitted: (String _) => _saveProxyPort(),
                  ),
                ),
              ],
            ),
            if (_proxyPortError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _proxyPortError!,
                  style: TextStyle(fontSize: 12, color: AppColors.critical(theme.brightness)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompilerCard() {
    final List<String> priority = widget.settings.compilerPriority;
    final bool hideRows = _detecting && _detected.isEmpty;
    return SettingsCard(
      padding: const .fromLTRB(8, 8, 8, 8),
      header: const Text('编译器优先级'),
      description: const Text('优先使用的编译器（自上而下）'),
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (_detecting) ...<Widget>[
                  const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  const Text('正在检测编译器…'),
                ],
                const Spacer(),
                Button(
                  key: const Key('settingCompilerRefreshButton'),
                  onPressed: _detecting ? null : () => _detectCompilers(showLoading: true),
                  child: const Text('重新检测'),
                ),
              ],
            ),
            if (!hideRows)
              for (var index = 0; index < priority.length; index++) _buildCompilerRow(priority[index], index),
          ],
        ),
      ),
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
              style: compiler == null ? TextStyle(color: theme.resources.textFillColorSecondary) : null,
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
            onPressed: index < widget.settings.compilerPriority.length - 1 ? () => _moveCompiler(index, 1) : null,
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
        child: IconButton(key: key, icon: Icon(icon, size: 14), onPressed: onPressed),
      ),
    );
  }

  Widget _buildSkillCard() {
    return SettingsCard(
      padding: const .fromLTRB(8, 8, 8, 8),
      header: const Text('SKILL.md'),
      description: const Text('生成 build.py 编写技能文档（SKILL.md），可放入 AI 插件的技能目录使用。'),
      content: Button(
        key: const Key('settingGenerateSkillButton'),
        onPressed: _generateSkill,
        child: const Text('生成 SKILL.md…'),
      ),
    );
  }

  Widget _comboBoxField({required double width, required Widget child}) {
    return SizedBox(
      width: width,
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
  final FileSaveLocation? location = await getSaveLocation(suggestedName: suggestedName);
  return location?.path;
}

Future<String> _loadSkillTemplateAsset() => rootBundle.loadString(_skillAssetPath);
