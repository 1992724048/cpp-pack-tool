import 'package:flutter_svg/flutter_svg.dart';

class Svgs {
  /// GitHub 官方标志（`assets/icons/repo_github.svg`，原文未修改）。
  static const String repoGithubPath = 'assets/icons/repo_github.svg';

  /// 自绘通用远程仓库图标（GitLab 等平台回退；单色由调用方染色）。
  static const String repoRemotePath = 'assets/icons/repo_remote.svg';

  static final openBox = SvgPicture.asset('assets/icons/open_box.svg', semanticsLabel: '打开文件夹', width: 20, height: 20);
  static final settings = SvgPicture.asset('assets/icons/settings.svg', semanticsLabel: '设置', width: 20, height: 20);
  static final help = SvgPicture.asset('assets/icons/help.svg', semanticsLabel: '帮助', width: 20, height: 20);
  static final home = SvgPicture.asset('assets/icons/home.svg', semanticsLabel: '主页', width: 20, height: 20);
  static final cardboardBox = SvgPicture.asset('assets/icons/cardboard_box.svg', semanticsLabel: '纸箱', width: 20, height: 20);
  static final showPermitCard = SvgPicture.asset('assets/icons/show_permit_card.svg', semanticsLabel: '显示许可证卡片', width: 20, height: 20);
  static final fileExplorer = SvgPicture.asset('assets/icons/file_explorer.svg', semanticsLabel: '文件资源管理器', width: 20, height: 20);
  static final inventoryFlow = SvgPicture.asset('assets/icons/inventory_flow.svg', semanticsLabel: '库存流程', width: 20, height: 20);
  static final projectSetup = SvgPicture.asset('assets/icons/project_setup.svg', semanticsLabel: '项目设置', width: 20, height: 20);
  static final boxSettings = SvgPicture.asset('assets/icons/box_settings.svg', semanticsLabel: '盒子设置', width: 20, height: 20);
  static final addFolder = SvgPicture.asset('assets/icons/add_folder.svg', semanticsLabel: '添加文件夹', width: 20, height: 20);
  static final deleteFolder = SvgPicture.asset('assets/icons/delete_folder.svg', semanticsLabel: '删除文件夹', width: 20, height: 20);
  static final mapAsDrive = SvgPicture.asset('assets/icons/map_as_drive.svg', semanticsLabel: '映射为驱动器', width: 20, height: 20);
  static final moveToFolder = SvgPicture.asset('assets/icons/move_to_folder.svg', semanticsLabel: '移动到文件夹', width: 20, height: 20);
  static final historyFolder = SvgPicture.asset('assets/icons/history_folder.svg', semanticsLabel: '历史文件夹', width: 20, height: 20);
  static final SvgPicture internetConnection = SvgPicture.asset('assets/icons/internet_connection.svg', semanticsLabel: '依赖关系图', width: 20, height: 20);
  static final save = SvgPicture.asset('assets/icons/save.svg', semanticsLabel: '保存', width: 20, height: 20);
  static final info = SvgPicture.asset('assets/icons/info.svg', semanticsLabel: '信息', width: 20, height: 20);
}
