import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../pages/pack_files.dart';
import '../pages/pack_info.dart';

class PackManage extends StatefulWidget {
  const PackManage({super.key, required this.pack});

  final PackModel pack;

  @override
  State<PackManage> createState() => _PackManageState();
}

class _PackManageState extends State<PackManage> {
  int _index = 0;

  Widget _body(Widget child) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(color: theme.cardColor),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: TabView(
        currentIndex: _index,
        onChanged: (i) => setState(() => _index = i),
        tabs: [
          Tab(
            icon: Svgs.showPermitCard,
            text: const Text('包信息'),
            body: _body(PackInfo(pack: widget.pack)),
          ),
          Tab(
            icon: Svgs.fileExplorer,
            text: const Text('文件管理'),
            body: _body(PackFiles(pack: widget.pack)),
          ),
          Tab(
            icon: Svgs.inventoryFlow,
            text: const Text('依赖管理'),
            body: _body(const Center(child: Text('依赖管理内容'))),
          ),
          Tab(
            icon: Svgs.projectSetup,
            text: const Text('编译设置'),
            body: _body(const Center(child: Text('编译设置内容'))),
          ),
          Tab(
            icon: Svgs.boxSettings,
            text: const Text('打包设置'),
            body: _body(const Center(child: Text('打包设置内容'))),
          ),
        ],
      ),
    );
  }
}
