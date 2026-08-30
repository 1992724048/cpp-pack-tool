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
