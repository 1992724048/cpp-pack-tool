import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
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
    this.packagingBuilder,
    this.onPackagingBuilderChanged,
  });

  final PackModel pack;
  final List<PackModel> allPacks;
  final Future<bool> Function(PackModel pack) onSave;
  final Future<String?> Function() pickDirectory;
  final Future<void> Function(PackModel pack)? onBuildPack;
  final PackageBuilder? packagingBuilder;
  final ValueChanged<PackageBuilder>? onPackagingBuilderChanged;

  @override
  State<PackManage> createState() => _PackManageState();
}

class _PackManageState extends State<PackManage> {
  int _index = 0;
  late final ValueNotifier<PackModel> _pack;
  late final ValueNotifier<PackageBuilder?> _packagingBuilder;
  late final List<Tab> _tabs;

  @override
  void initState() {
    super.initState();
    _pack = ValueNotifier<PackModel>(widget.pack);
    _packagingBuilder = ValueNotifier<PackageBuilder?>(widget.packagingBuilder);
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
        body: _body(_packDependenciesBody()),
      ),
      Tab(
        icon: Svgs.projectSetup,
        text: const Text('编译设置'),
        body: _body(_packCompileBody()),
      ),
      Tab(
        icon: Svgs.boxSettings,
        text: const Text('打包设置'),
        body: _body(_packPackagingBody()),
      ),
    ];
  }

  @override
  void didUpdateWidget(covariant PackManage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pack != widget.pack) {
      _pack.value = widget.pack;
    }
    if (oldWidget.packagingBuilder != widget.packagingBuilder) {
      _packagingBuilder.value = widget.packagingBuilder;
    }
  }

  @override
  void dispose() {
    _pack.dispose();
    _packagingBuilder.dispose();
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
          PackFiles(pack: pack, onBuildPack: widget.onBuildPack),
    );
  }

  Widget _packDependenciesBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          PackDependencies(
            pack: pack,
            allPacks: widget.allPacks,
            onSave: widget.onSave,
          ),
    );
  }

  Widget _packCompileBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          PackCompileSettings(
            pack: pack,
            onSave: widget.onSave,
            pickDirectory: widget.pickDirectory,
          ),
    );
  }

  Widget _packPackagingBody() {
    return ValueListenableBuilder<PackModel>(
      valueListenable: _pack,
      builder: (BuildContext context, PackModel pack, Widget? child) =>
          ValueListenableBuilder<PackageBuilder?>(
            valueListenable: _packagingBuilder,
            builder:
                (
                  BuildContext context,
                  PackageBuilder? builder,
                  Widget? child,
                ) => PackPackaging(
                  pack: pack,
                  selectedBuilder: builder,
                  onBuilderChanged: widget.onPackagingBuilderChanged,
                ),
          ),
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
