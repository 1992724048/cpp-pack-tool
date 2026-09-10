import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

class Setting extends StatefulWidget {
  const Setting({
    super.key,
    required this.settings,
    required this.onSave,
    this.pickDirectory = getDirectoryPath,
  });

  final SettingsModel settings;
  final Future<void> Function(SettingsModel settings) onSave;
  final Future<String?> Function() pickDirectory;

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

  Future<void> _apply(SettingsModel next) async {
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
    if (!mounted) {
      return;
    }
    showFloatingToast(context, '已保存');
  }

  SettingsModel _directorySettings(String? outputDirectory) {
    final SettingsModel current = widget.settings;
    return SettingsModel(
      outputDirectory: outputDirectory,
      themeMode: current.themeMode,
      darkFlavor: current.darkFlavor,
      accent: current.accent,
    );
  }

  SettingsModel _themeSettings({
    ThemeModeSetting? themeMode,
    String? darkFlavor,
    String? accent,
  }) {
    final SettingsModel current = widget.settings;
    return SettingsModel(
      outputDirectory: current.outputDirectory,
      themeMode: themeMode ?? current.themeMode,
      darkFlavor: darkFlavor ?? current.darkFlavor,
      accent: accent ?? current.accent,
    );
  }

  Future<void> _pickDirectory() async {
    final String? path = await widget.pickDirectory();
    if (path == null || !mounted) {
      return;
    }
    await _apply(_directorySettings(path));
  }

  Future<void> _clearDirectory() => _apply(_directorySettings(null));

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
                _buildOutputDirectoryField(context),
                const SizedBox(height: 24),
                _buildSectionTitle(context, '主题'),
                const SizedBox(height: 12),
                InfoLabel(label: '主题模式', child: _buildThemeModeField()),
                const SizedBox(height: 12),
                InfoLabel(label: '深色主题配色', child: _buildDarkFlavorField()),
                const SizedBox(height: 12),
                InfoLabel(label: '强调色', child: _buildAccentField()),
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

  Widget _buildOutputDirectoryField(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final String? outputDirectory = widget.settings.outputDirectory;
    return Row(
      children: [
        Expanded(
          child: Text(
            outputDirectory ?? '未设置',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.resources.textFillColorSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Button(
          key: const Key('settingPickDirButton'),
          onPressed: _pickDirectory,
          child: const Text('选择目录…'),
        ),
        const SizedBox(width: 8),
        Button(
          key: const Key('settingClearDirButton'),
          onPressed: outputDirectory == null ? null : _clearDirectory,
          child: const Text('清除'),
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

  Widget _buildDarkFlavorField() {
    return _comboBoxFrame(
      ComboBox<String>(
        key: const Key('settingDarkFlavorField'),
        value: widget.settings.darkFlavor,
        isExpanded: true,
        onChanged: (String? value) {
          if (value != null && value != widget.settings.darkFlavor) {
            _apply(_themeSettings(darkFlavor: value));
          }
        },
        items: <ComboBoxItem<String>>[
          for (final String name in darkFlavorNames)
            ComboBoxItem<String>(value: name, child: Text(_capitalize(name))),
        ],
      ),
    );
  }

  Widget _buildAccentField() {
    return _comboBoxFrame(
      ComboBox<String>(
        key: const Key('settingAccentField'),
        value: widget.settings.accent,
        isExpanded: true,
        onChanged: (String? value) {
          if (value != null && value != widget.settings.accent) {
            _apply(_themeSettings(accent: value));
          }
        },
        items: <ComboBoxItem<String>>[
          for (final String name in accentColorNames)
            ComboBoxItem<String>(
              value: name,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accentColorFor(UCColors.flavor, name),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_capitalize(name)),
                ],
              ),
            ),
        ],
      ),
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

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
