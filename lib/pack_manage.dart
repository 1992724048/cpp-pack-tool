import 'package:flutter/material.dart';

class PackManage extends StatefulWidget {
  const PackManage({super.key});

  @override
  State<PackManage> createState() => _PackManageState();
}

class _PackManageState extends State<PackManage> with SingleTickerProviderStateMixin {
  late TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: '包信息'),
            Tab(text: '文件管理'),
            Tab(text: '依赖管理'),
            Tab(text: '编译设置'),
            Tab(text: '打包设置'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: const [
              Center(child: Text('包信息内容')),
              Center(child: Text('文件管理内容')),
              Center(child: Text('依赖管理内容')),
              Center(child: Text('编译设置内容')),
              Center(child: Text('打包设置内容')),
            ],
          ),
        ),
      ],
    );
  }
}
