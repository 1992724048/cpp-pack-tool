import 'package:flutter/material.dart';

import 'base_style.dart';

void main() {
  runApp(const PackTool());
}

class PackTool extends StatelessWidget {
  const PackTool({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'C++ NuGet打包工具',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: "HarmonyOS_Sans_SC",
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: "HarmonyOS_Sans_SC",
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  void _addDirectory() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Row(
          children: [
            
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        shape: Border.all(
          style: BorderStyle.none,
          width: 0,
          strokeAlign: 0,
          color: Colors.transparent,
        ),
        onPressed: _addDirectory,
        tooltip: '添加目录',
        child: const Icon(Icons.add),
      ),
    );
  }
}
