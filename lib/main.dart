import 'package:cpp_nuget_pack/pack_list.dart';
import 'package:cpp_nuget_pack/pack_manage.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mdi_icons/flutter_mdi_icons.dart';

void main() {
  runApp(const PackTool());
}

ValueNotifier<ThemeMode> _themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

class PackTool extends StatelessWidget {
  const PackTool({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'C++ Pack Tool',
          themeMode: themeMode,
          theme: ThemeData(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['HarmonyOS_Sans_SC', 'Noto Sans', 'Arial', 'sans-serif'],
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
          ),
          darkTheme: ThemeData(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['HarmonyOS_Sans_SC', 'Noto Sans', 'Arial', 'sans-serif'],
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
          ),
          home: const MainLayout(),
        );
      },
    );
  }
}

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        shape: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline)),
        actions: [
          IconButton(
            tooltip: '切换主题',
            onPressed: () {
              _themeNotifier.value = _themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
            icon: _themeNotifier.value == ThemeMode.light ? Icon(Icons.brightness_4) : Icon(Icons.brightness_5),
          ),
          IconButton(tooltip: '设置', onPressed: null, icon: Icon(Icons.settings)),
          IconButton(tooltip: '帮助', onPressed: null, icon: Icon(Icons.help)),
        ],
        title: Row(
          children: [
            Icon(Mdi.packageVariantClosed, size: 32),
            const SizedBox(width: 10),
            const Text('VCPKG 打包工具'),
            const SizedBox(width: 10),
            Tag(text: '26.0.0'),
          ],
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: PackList()),
          const VerticalDivider(width: 0),
          Expanded(flex: 7, child: PackManage()),
        ],
      ),
    );
  }
}
