import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart' as toolchain;
import 'package:cpp_nuget_pack/main.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/pack/pack_store.dart';
import 'package:cpp_nuget_pack/settings/settings_model.dart';
import 'package:cpp_nuget_pack/shared/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 应用根部件：加载设置、选定主题，把 [MainLayout] 挂到 [FluentApp] 下。
///
/// 与 MainLayout 同文件并非本意，而是 FLUTTER_TARGET 钉死 lib/main.dart、
/// 且 MainLayout 本体过大不宜同批搬迁所致：main() 必须留在 lib/main.dart，
/// MainLayout 留在原地，本部件才能从 main.dart 侧被构造出来。
class PackTool extends StatefulWidget {
  const PackTool({super.key, this.store = const PackStore()});

  final PackStore store;

  @override
  State<PackTool> createState() => _PackToolState();
}

class _PackToolState extends State<PackTool> {
  SettingsModel _settings = const SettingsModel();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SettingsModel settings;
    try {
      settings = await widget.store.loadSettings();
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
  }

  Future<void> _saveSettings(SettingsModel next) async {
    setState(() => _settings = next);
    await widget.store.saveSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'C++ Pack',
      themeMode: switch (_settings.themeMode) {
        ThemeModeSetting.system => ThemeMode.system,
        ThemeModeSetting.dark => ThemeMode.dark,
        ThemeModeSetting.light => ThemeMode.light,
      },
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: MainLayout(store: widget.store, settings: _settings, onSaveSettings: _saveSettings),
    );
  }
}

typedef PackBuildEnvironmentPreparer = Future<BuildEnvironment> Function(
  PackModel pack, {
  required List<String> compilerPriority,
  required List<toolchain.DetectedCompiler> cachedCompilers,
  required CompilerDetectionCallback onCompilersDetected,
});

Future<BuildEnvironment> preparePackBuildEnvironmentDefault(
  PackModel pack, {
  required List<String> compilerPriority,
  required List<toolchain.DetectedCompiler> cachedCompilers,
  required CompilerDetectionCallback onCompilersDetected,
}) {
  return preparePackBuildEnvironment(
    pack,
    priority: compilerPriority,
    cachedCompilers: cachedCompilers,
    onCompilersDetected: onCompilersDetected,
  );
}
