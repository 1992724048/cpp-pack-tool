import 'package:cpp_nuget_pack/shared/svgs.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PackToolbar extends StatelessWidget {
  const PackToolbar({
    super.key,
    required this.onAddFolder,
    required this.onDeleteFolder,
    required this.onRemap,
    required this.onPackFolder,
    required this.onHistory,
    required this.onDependencyGraph,
    required this.onCreatePackageStructure,
    required this.createPackageStructureIcon,
  });

  final VoidCallback? onAddFolder;
  final VoidCallback? onDeleteFolder;
  final VoidCallback? onRemap;
  final VoidCallback? onPackFolder;
  final VoidCallback? onHistory;
  final VoidCallback? onDependencyGraph;
  final VoidCallback? onCreatePackageStructure;
  final Widget createPackageStructureIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      spacing: 0,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Tooltip(
              message: '添加文件夹',
              child: IconButton(icon: Svgs.addFolder, onPressed: onAddFolder),
            ),
            Tooltip(
              message: '删除文件夹',
              child: IconButton(icon: Svgs.deleteFolder, onPressed: onDeleteFolder),
            ),
            Tooltip(
              message: '重新映射',
              child: IconButton(icon: Svgs.mapAsDrive, onPressed: onRemap),
            ),
            Tooltip(
              message: '打包文件夹',
              child: IconButton(icon: Svgs.moveToFolder, onPressed: onPackFolder),
            ),
            Tooltip(
              message: '历史记录',
              child: IconButton(
                icon: Svgs.historyFolder,
                onPressed: onHistory,
              ),
            ),
            Tooltip(
              message: '依赖关系图',
              child: IconButton(
                icon: Svgs.internetConnection,
                onPressed: onDependencyGraph,
              ),
            ),
            Tooltip(
              message: '创建包结构',
              child: IconButton(
                icon: createPackageStructureIcon,
                onPressed: onCreatePackageStructure,
              ),
            ),
          ],
        ),
        Divider(style: DividerThemeData(horizontalMargin: .fromLTRB(0, 3, 8, 0))),
      ],
    );
  }
}
