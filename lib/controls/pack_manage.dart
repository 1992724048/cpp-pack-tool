import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/shared/svgs.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../pages/pack_compile_settings.dart';
import '../pages/pack_dependencies.dart';
import '../pages/pack_files.dart';
import '../pages/pack_info.dart';
import '../pages/pack_packaging.dart';

class PackManage extends StatefulWidget {
  const PackManage({
    super.key,
    required this.pack,
    required this.allPacks,
    required this.onSave,
    required this.pickDirectory,
    this.onBuildPack,
  });

  final PackModel pack;
  final List<PackModel> allPacks;
  final Future<bool> Function(PackModel pack) onSave;
  final Future<String?> Function() pickDirectory;
  final Future<void> Function(PackModel pack)? onBuildPack;

  @override
  State<PackManage> createState() => _PackManageState();
}

class _PackManageState extends State<PackManage> {
  int _index = 0;
  late final ValueNotifier<PackModel> _pack;
  List<Tab>? _tabs;

  @override
  void initState() {
    super.initState();
    _pack = ValueNotifier<PackModel>(widget.pack);
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
      builder: (BuildContext context, PackModel pack, Widget? child) => PackInfo(pack: pack, onSave: widget.onSave),
    );
  }

  Widget _packFilesBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          PackFiles(pack: pack, onBuildPack: widget.onBuildPack),
    );
  }

  Widget _packDependenciesBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          PackDependencies(pack: pack, allPacks: widget.allPacks, onSave: widget.onSave),
    );
  }

  Widget _packCompileBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          PackCompileSettings(pack: pack, onSave: widget.onSave, pickDirectory: widget.pickDirectory),
    );
  }

  Widget _packPackagingBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) => PackPackaging(pack: pack),
    );
  }

  Widget _body(Widget child) {
    return _KeepAliveTabBody(child: child);
  }

  List<Tab> _buildTabs(BuildContext context) {
    return <Tab>[
      Tab(
        icon: Svgs.showPermitCard,
        text: const Text('包信息'),
        body: _body(_packInfoBody()),
        selectedBackgroundColor: WidgetStateColor.resolveWith((states) => FluentTheme.of(context).selectionColor),
        selectedForegroundColor: WidgetStateColor.resolveWith((states) => Colors.white),
      ),
      Tab(
        icon: Svgs.fileExplorer,
        text: const Text('文件管理'),
        body: _body(_packFilesBody()),
        selectedBackgroundColor: WidgetStateColor.resolveWith((states) => FluentTheme.of(context).selectionColor),
        selectedForegroundColor: WidgetStateColor.resolveWith((states) => Colors.white),
      ),
      Tab(
        icon: Svgs.inventoryFlow,
        text: const Text('依赖管理'),
        body: _body(_packDependenciesBody()),
        selectedBackgroundColor: WidgetStateColor.resolveWith((states) => FluentTheme.of(context).selectionColor),
        selectedForegroundColor: WidgetStateColor.resolveWith((states) => Colors.white),
      ),
      Tab(
        icon: Svgs.projectSetup,
        text: const Text('编译设置'),
        body: _body(_packCompileBody()),
        selectedBackgroundColor: WidgetStateColor.resolveWith((states) => FluentTheme.of(context).selectionColor),
        selectedForegroundColor: WidgetStateColor.resolveWith((states) => Colors.white),
      ),
      Tab(
        icon: Svgs.boxSettings,
        text: const Text('打包设置'),
        body: _body(_packPackagingBody()),
        selectedBackgroundColor: WidgetStateColor.resolveWith((states) => FluentTheme.of(context).selectionColor),
        selectedForegroundColor: WidgetStateColor.resolveWith((states) => Colors.white),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<Tab> tabs = _tabs ??= _buildTabs(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: TabView(currentIndex: _index, onChanged: (int index) => setState(() => _index = index), tabs: tabs),
    );
  }
}

class _KeepAliveTabBody extends StatefulWidget {
  const _KeepAliveTabBody({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTabBody> createState() => _KeepAliveTabBodyState();
}

class _KeepAliveTabBodyState extends State<_KeepAliveTabBody> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
