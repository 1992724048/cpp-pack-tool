import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:flutter/material.dart';

class PackList extends StatefulWidget {
  const PackList({super.key});

  @override
  State<PackList> createState() => _PackListState();
}

class _PackListState extends State<PackList> {
  bool _inProject = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Padding(
            padding: EdgeInsetsGeometry.all(4),
            child: Row(
              children: [
                IconButton(onPressed: null, icon: Icon(Icons.create_new_folder), tooltip: '添加文件夹'),
                IconButton(onPressed: null, icon: Icon(Icons.refresh), tooltip: '刷新'),
                Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _inProject = !_inProject;
                    });
                  },
                  icon: _inProject ? Icon(Icons.keyboard_double_arrow_left) : Icon(Icons.keyboard_double_arrow_right),
                  tooltip: _inProject ? '项目设置' : '包设置',
                ),
              ],
            ),
          ),
          Divider(height: 0),
          LibraryCard(title: '测试', onTap: (isSelected) {}),
          Divider(height: 0),
          LibraryCard(title: '测试', onTap: (isSelected) {}),
        ],
      ),
    );
  }
}
