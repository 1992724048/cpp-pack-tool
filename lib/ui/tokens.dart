/// 设计令牌：颜色 / 字体 / 间距 / 圆角 / 字号。
///
/// 对照 `docs/ui-spec.md` 第二部分「设计令牌」，供主题（theme.dart）与
/// 页面组件共用。此文件只放常量，不放逻辑。
library;

import 'package:flutter/widgets.dart';

/// 颜色令牌（深色专业工具风，基准 VS Code 深色）。
abstract final class AppColors {
  /// 窗口根背景 / 内容区 / 日志区。
  static const Color bgApp = Color(0xFF1E1E1E);

  /// 工具栏 / 左栏 / 右栏 Tab 区背景。
  static const Color bgPanel = Color(0xFF252526);

  /// 输入框 / 表头 / 表格奇行 / 弹窗背景。
  static const Color bgSurface = Color(0xFF2D2D30);

  /// 行 / 项悬停背景。
  static const Color bgHover = Color(0xFF2A2D2E);

  /// 列表选中背景。
  static const Color bgSel = Color(0xFF094771);

  /// 失焦选中背景。
  static const Color bgSelInactive = Color(0xFF37373D);

  /// 禁用项背景（叠加 .4 透明度）。
  static const Color bgDisabled = Color(0xFF2D2D30);

  /// 常规分隔 / 输入边框。
  static const Color border = Color(0xFF3C3C3C);

  /// 强调分隔线（左右栏边界、表头下边线）。
  static const Color borderStrong = Color(0xFF454545);

  /// 主文本。
  static const Color textPrimary = Color(0xFFD4D4D4);

  /// 次文本 / 表头 / 说明 / disabled 说明。
  static const Color textSemantic = Color(0xFF9D9D9D);

  /// 禁用文本（WCAG 禁用豁免）。
  static const Color textDisabled = Color(0xFF6A6A6A);

  /// 强调 / 成功背景上的文字。
  static const Color textOnDark = Color(0xFFFFFFFF);

  /// 强调填充（选中项 / 主按钮底部色 / 指示条）。
  static const Color accent = Color(0xFF007ACC);

  /// 强调填充悬停。
  static const Color accentHover = Color(0xFF0E639C);

  /// 主按钮底色。
  static const Color accentStrong = Color(0xFF0E639C);

  /// 强调色文字（比 accent 更亮以满足 AA）。
  static const Color textAccent = Color(0xFF4FC1FF);

  /// 键盘焦点描边。
  static const Color focus = Color(0xFF007FD4);

  /// 成功 / 通过。
  static const Color success = Color(0xFF3FB950);

  /// 警告信息。
  static const Color warn = Color(0xFFE0AF68);

  /// 错误信息 / 危险边框。
  static const Color error = Color(0xFFF47067);

  /// 危险按钮悬停浅底 / 错误提示浅底（rgba(244,112,103,.12)）。
  static const Color errorBg = Color(0x1FF47067);
}

/// 字体令牌。
abstract final class AppFonts {
  /// UI 正文字体（全文本按钮/标签/标题）。
  static const String body = 'HarmonyOS_Sans_SC';

  /// 数据类等宽字体（路径 / glob / 日志 / 命令输出）。
  static const String mono = 'Consolas';

  /// 等宽字体回退链。
  static const List<String> monoFallback = <String>['Consolas', 'monospace'];
}

/// 字号阶梯（对照 ui-spec.md §2.2）。
abstract final class AppFontSizes {
  /// 日志行内时间戳、表内次要注解。
  static const double caption = 11;

  /// 表头、按钮文字、表单体。
  static const double small = 12;

  /// 正文、输入框。
  static const double body = 13;

  /// 输入框焦点文案 / 关键值。
  static const double input = 14;

  /// Tab 页内分区标题、弹窗标题。
  static const double h3 = 16;

  /// 应用标题、主页面标题。
  static const double h1 = 20;
}

/// 间距令牌（4/8/12/16/24）。
abstract final class AppSpacing {
  /// 图标与文字间距、紧凑内边距。
  static const double sm = 4;

  /// 组件间水平 micro 间距。
  static const double s1 = 8;

  /// 表单行内子元素间距、Tab 内容区 padding。
  static const double s2 = 12;

  /// 分区之间、分栏与内容间距、Table 行内。
  static const double s3 = 16;

  /// 页面级大区块之间。
  static const double s4 = 24;
}

/// 圆角令牌。
abstract final class AppRadius {
  /// 密集单元格、小 chip、状态标签。
  static const double sm = 2;

  /// 输入框、按钮、下拉、TabBar 选中段。
  static const double md = 3;

  /// 弹窗、卡片、面板容器。
  static const double lg = 4;
}

/// 控件常见尺寸（高信息密度）。
abstract final class AppDims {
  /// 顶部工具栏高度。
  static const double toolbarHeight = 40;

  /// TabBar 高度。
  static const double tabBarHeight = 40;

  /// 底部日志面板默认高度。
  static const double logPanelHeight = 200;

  /// 日志面板折叠后仅头部高度。
  static const double logHeaderHeight = 32;

  /// 左栏宽度。
  static const double libraryWidth = 280;

  /// 文本输入框高度。
  static const double fieldHeight = 34;
}
