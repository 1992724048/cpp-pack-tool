/// 顶部工具栏：应用标题 + 设置按钮。
///
/// 对照 `docs/ui-spec.md` §3.1：高 40px、背景 `bg.panel`、下边框
/// `border.strong`；图标按钮 18px、带 Tooltip。
library;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// 顶部工具栏。
class TopToolbar extends StatelessWidget {
  const TopToolbar({super.key, required this.onOpenSettings});

  /// 点击设置按钮回调。
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDims.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: AppColors.textSemantic,
          ),
          const SizedBox(width: AppSpacing.s1),
          const Text(
            'C++ NuGet 打包工具',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppFontSizes.h1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onOpenSettings,
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined, size: 18),
            color: AppColors.textSemantic,
            iconSize: 18,
          ),
        ],
      ),
    );
  }
}
