import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../util/file_image.dart';
import '../util/format.dart';
import '../util/svgs.dart';
import 'pack_manage.dart';

/// 侧栏条目的仓库徽标状态：有远程仓库显示 git，检测到新版本时替换为更新图标。
enum RepoBadge { git, update }

class PackList {
  PackList._();

  static List<NavigationPaneItem> buildCards(
    List<PackModel> packs, {
    required Future<bool> Function(PackModel pack) onSave,
    required Future<String?> Function() pickDirectory,
    Future<void> Function(PackModel pack)? onBuildPack,
    PackageBuilder? packagingBuilder,
    ValueChanged<PackageBuilder>? onPackagingBuilderChanged,
    Future<String?> Function(String repoUrl)? loadLatestVersion,
    RepoBadge? Function(PackModel pack)? repoBadgeFor,
    Future<BuildScriptHeader?> Function(PackModel pack)? loadHeader,
  }) {
    return [
      for (final PackModel pack in packs)
        LibraryItem(
          icon: _iconFor(pack),
          title: pack.name,
          version: pack.version,
          badge: _badgeFor(pack, repoBadgeFor?.call(pack)),
          body: PackManage(
            pack: pack,
            allPacks: packs,
            onSave: onSave,
            pickDirectory: pickDirectory,
            onBuildPack: onBuildPack,
            packagingBuilder: packagingBuilder,
            onPackagingBuilderChanged: onPackagingBuilderChanged,
            loadLatestVersion: loadLatestVersion,
            loadHeader: loadHeader,
          ),
        ),
    ];
  }

  static Widget? _badgeFor(PackModel pack, RepoBadge? badge) {
    return switch (badge) {
      RepoBadge.git => Tooltip(
        message: '远程仓库',
        child: Icon(
          key: Key('repoBadge_${pack.name}'),
          FluentIcons.git_graph,
          size: 12,
          color: UCColors.flavor.subtext0,
        ),
      ),
      RepoBadge.update => Tooltip(
        message: '有新版本',
        child: Icon(
          key: Key('repoUpdateBadge_${pack.name}'),
          FluentIcons.update_restore,
          size: 12,
          color: UCColors.flavor.green,
        ),
      ),
      null => null,
    };
  }

  static Widget? _iconFor(PackModel pack) {
    final String? iconPath = pack.iconPath;
    final String? sourcePath = pack.sourcePath;
    if (iconPath == null || sourcePath == null) {
      return null;
    }
    return buildFileImage(
      joinPath(sourcePath, iconPath),
      size: 20,
      fallback: Svgs.cardboardBox,
    );
  }
}
