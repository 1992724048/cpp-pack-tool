import 'package:flutter/material.dart';

import 'ui/main_shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(const PackTool());
}

/// 应用根组件：深色专用主题 + 主工作台。
class PackTool extends StatelessWidget {
  const PackTool({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'C++ NuGet打包工具',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      home: const MainShell(),
    );
  }
}
