import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'controls/pack_list.dart';

void main() {
  runApp(const PackTool());
}

class PackTool extends StatelessWidget {
  const PackTool({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(title: 'C++ Pack Tool', themeMode: ThemeMode.system, theme: buildTheme(Brightness.light), darkTheme: buildTheme(Brightness.dark), home: const MainLayout());
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      titleBar: TitleBar(isBackButtonVisible: false, title: const Center(widthFactor: 1.0, child: Text('C++ NuGet 打包工具'))),
      pane: NavigationPane(
        selected: index,
        onChanged: (int newIndex) => setState(() => index = newIndex),
        header: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Tooltip(
              message: '添加文件夹',
              child: IconButton(icon: Svgs.addFolder, onPressed: () {}),
            ),
            Tooltip(
              message: '删除文件夹',
              child: IconButton(icon: Svgs.deleteFolder, onPressed: () {}),
            ),
            Tooltip(
              message: '重新映射',
              child: IconButton(icon: Svgs.mapAsDrive, onPressed: () {}),
            ),
            Tooltip(
              message: '打包文件夹',
              child: IconButton(icon: Svgs.moveToFolder, onPressed: () {}),
            ),
            Tooltip(
              message: '历史记录',
              child: IconButton(icon: Svgs.historyFolder, onPressed: () {}),
            ),
          ],
        ),
        displayMode: PaneDisplayMode.expanded,
        size: NavigationPaneSize(openMaxWidth: 260, openMinWidth: 260, compactWidth: 50),
        items: [...PackList.buildCards()],
        footerItems: [
          PaneItemSeparator(),
          LibraryItem(
            icon: Svgs.settings,
            title: '设置',
            body: const Center(child: Text('设置内容')),
          ),
          LibraryItem(
            icon: Svgs.info,
            title: '关于',
            version: '26.0.0',
            body: const Center(child: Text('关于内容')),
          ),
        ],
      ),
    );
  }
}
