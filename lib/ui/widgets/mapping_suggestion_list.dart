/// 映射建议勾选列表：供「添加源目录」与「添加映射→扫描目录」等场景复用。
///
/// 逐条展示建议映射（源 glob → 目标路径）与文件类型徽标，支持勾选/取消；
/// [onToggle] 传 null 时为只读展示（不可勾选）。样式与 `AddSourceDirDialog`
/// 的建议预览保持一致（带边框、等宽路径、FileKindBadge）。
library;

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../tokens.dart';
import 'form_fields.dart';

/// 映射建议勾选列表。
///
/// 列表为可滚动（高度上限 [_kMaxPreviewHeight]），扫描结果多时可滚动查看，
/// 勾选与底部操作按钮不受影响；[onToggle] 传 null 时为只读展示。
class MappingSuggestionList extends StatelessWidget {
  const MappingSuggestionList({
    super.key,
    required this.suggestions,
    required this.checked,
    required this.onToggle,
  });

  /// 预览列表最大高度（超出后内部滚动）。
  static const double _kMaxPreviewHeight = 320;

  /// 待展示的建议映射。
  final List<FileMapping> suggestions;

  /// 已勾选的下标集合（与 [suggestions] 索引对应）。
  final Set<int> checked;

  /// 勾选切换回调；传 null 时列表为只读展示。
  final ValueChanged<int>? onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: _kMaxPreviewHeight),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final mapping = suggestions[index];
          final enabled = onToggle != null;
          return InkWell(
            onTap: enabled ? () => onToggle!(index) : null,
            child: Row(
              children: [
                Checkbox(
                  value: checked.contains(index),
                  onChanged: enabled ? (_) => onToggle!(index) : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mapping.srcGlob, style: monoTextStyle()),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '→ ${mapping.target}',
                              style: monoTextStyle(color: AppColors.textSemantic),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s1),
                          if (mapping.platforms.isEmpty && mapping.configurations.isEmpty)
                            Text(
                              '全部',
                              style: const TextStyle(
                                color: AppColors.textSemantic,
                                fontSize: AppFontSizes.small,
                              ),
                            )
                          else
                            Wrap(
                              spacing: AppSpacing.s1,
                              children: [
                                for (final p in mapping.platforms)
                                  _smallChip(p, AppColors.accent),
                                for (final c in mapping.configurations)
                                  _smallChip(c, AppColors.warn),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s1),
                FileKindBadge(kind: mapping.fileKind),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _smallChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: AppFontSizes.small)),
    );
  }
}
