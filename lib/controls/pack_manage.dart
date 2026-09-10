import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../pages/pack_files.dart';
import '../pages/pack_info.dart';

class PackManage extends StatefulWidget {
  const PackManage({super.key, required this.pack, required this.onSave});

  final PackModel pack;
  final Future<bool> Function(PackModel pack) onSave;

  @override
  State<PackManage> createState() => _PackManageState();
}

class _PackManageState extends State<PackManage> {
  int _index = 0;
  late final ValueNotifier<PackModel> _pack;
  late final List<Tab> _tabs;

  @override
  void initState() {
    super.initState();
    _pack = ValueNotifier<PackModel>(widget.pack);
    _tabs = <Tab>[
      Tab(
        icon: Svgs.showPermitCard,
        text: const Text('包信息'),
        body: _body(_packInfoBody()),
      ),
      Tab(
        icon: Svgs.fileExplorer,
        text: const Text('文件管理'),
        body: _body(_packFilesBody()),
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
    ];
  }

  @override
  void didUpdateWidget(covariant PackManage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pack != widget.pack) {
      _pack.value = widget.pack;
    }
  }

  @override
  void dispose() {
    _pack.dispose();
    super.dispose();
  }

  Widget _packInfoBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          PackInfo(pack: pack, onSave: widget.onSave),
    );
  }

  Widget _packFilesBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          PackFiles(pack: pack),
    );
  }

  Widget _body(Widget child) {
    return Builder(
      builder: (BuildContext context) {
        final theme = FluentTheme.of(context);
        return Container(
          decoration: BoxDecoration(color: theme.cardColor),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: TabView(
        currentIndex: _index,
        onChanged: (int index) => setState(() => _index = index),
        tabs: _tabs,
      ),
    );
  }
}
