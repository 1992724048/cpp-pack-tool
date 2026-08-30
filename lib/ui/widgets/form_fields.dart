/// 表单通用小组件：分区标题、带标签的字段容器、等宽文本样式。
///
/// 减少各页面重复布局代码；输入控件本身由各页 State 持有 controller，
/// 统一走 `TextFormField`（样式已由 theme.dart 的 [InputDecorationTheme] 配置）。
library;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Tab 内分区标题（16px，h3）。
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: AppFontSizes.h3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 带标签的表单字段容器（标签在上，控件在下）。
class LabeledFormField extends StatelessWidget {
  const LabeledFormField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.small,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 等宽文本样式（路径 / glob / 命令 / 宏等数据类文本）。
TextStyle monoTextStyle({
  double fontSize = AppFontSizes.small,
  Color color = AppColors.textPrimary,
}) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.monoFallback,
  );
}

/// 文件类型徽标（头文件/源码/数据/库/其他），用于文件映射表与映射建议预览。
///
/// 悬停展示各类的自动处理说明；[kind] 为映射分类字符串（header/source/data/library/other）。
class FileKindBadge extends StatelessWidget {
  const FileKindBadge({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final (label, color, tip) = switch (kind) {
      'header' => (
        '头文件',
        AppColors.accent,
        '头文件：展开到 include 路径（#include <目标>）',
      ),
      'source' => ('源码', AppColors.success, '源码：自动注入消费方编译（ClCompile）'),
      'data' => ('数据', AppColors.textSemantic, '数据：自动硬链接到消费方输出目录'),
      'library' => ('库', AppColors.accent, '库：参与链接依赖'),
      _ => ('其他', AppColors.textDisabled, '其他：按包内目标路径输出'),
    };
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s1,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: AppFontSizes.caption),
        ),
      ),
    );
  }
}
