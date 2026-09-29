import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart' as toolchain;
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_card.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_group.dart';
import 'package:cpp_nuget_pack/widgets/settings/settings_page.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

class Setting extends StatefulWidget {
  const Setting({
    super.key,
    required this.settings,
    required this.onSave,
    this.pickDirectory = getDirectoryPath,
    this.detectCompilers = detectCompilersReadOnly,
  });

  final SettingsModel settings;
  final Future<void> Function(SettingsModel settings) onSave;
  final Future<String?> Function() pickDirectory;
  final Future<List<toolchain.DetectedCompiler>> Function() detectCompilers;

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  static const Map<ThemeModeSetting, String> _themeModeLabels = <ThemeModeSetting, String>{
    ThemeModeSetting.system: '系统',
    ThemeModeSetting.dark: '深色',
    ThemeModeSetting.light: '浅色',
  };

  List<toolchain.DetectedCompiler> _detected = const <toolchain.DetectedCompiler>[];
  bool _detecting = true;

  @override
  void initState() {
    super.initState();
    final List<toolchain.DetectedCompiler> cached = widget.settings.detectedCompilers;
    if (cached.isEmpty) {
      _detectCompilers(showLoading: false);
    } else {
      _detected = cached;
      _detecting = false;
    }
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

  SettingsModel _directorySettings({required String? outputDirectory}) {
    return widget.settings.copyWith(outputDirectory: outputDirectory);
  }

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
    await _apply(_directorySettings(outputDirectory: path));
  }

  Future<void> _clearDirectory() => _apply(_directorySettings(outputDirectory: null));

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: '设置',
      description: const Text('配置打包输出目录、外观与编译器优先级。'),
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
          ],
        ),
        SettingsGroup(header: '外观', children: <Widget>[_buildThemeModeCard()]),
        SettingsGroup(header: '编译器', children: <Widget>[_buildCompilerCard()]),
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
