import 'dart:io';

import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/repo_icon.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    RepoIconSource Function(PackModel pack)? repoIconFor,
    Future<BuildScriptHeader?> Function(PackModel pack)? loadHeader,
  }) {
    return [
      for (final PackModel pack in packs)
        LibraryItem(
          icon: _iconFor(pack, repoIconFor?.call(pack)),
          title: pack.name,
          version: pack.sourceVersion ?? pack.version,
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
        child: Builder(
          builder: (BuildContext context) => Icon(
            key: Key('repoBadge_${pack.name}'),
            FluentIcons.git_graph,
            size: 12,
            color: FluentTheme.of(context).resources.textFillColorTertiary,
          ),
        ),
      ),
      RepoBadge.update => Tooltip(
        message: '有新版本',
        child: Icon(
          key: Key('repoUpdateBadge_${pack.name}'),
          FluentIcons.update_restore,
          size: 12,
          color: MarkerColors.green,
        ),
      ),
      null => null,
    };
  }

  /// 侧栏图标解析链：远程头像 → 平台回退 → 本地 iconPath → 纸箱。
  static Widget? _iconFor(PackModel pack, RepoIconSource? source) {
    final String? avatarPath = source?.avatarPath;
    if (avatarPath != null) {
      return Image.file(
        File(avatarPath),
        key: Key('repoAvatar_${pack.name}'),
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                _platformIcon(
                  pack,
                  source?.platform,
                  _fallbackIconColor(context),
                ),
      );
    }
    final RepoPlatform? platform = source?.platform;
    if (platform != null) {
      return Builder(
        builder: (BuildContext context) =>
            _platformIcon(pack, platform, _fallbackIconColor(context)),
      );
    }
    return _localIcon(pack);
  }

  static Color _fallbackIconColor(BuildContext context) =>
      FluentTheme.of(context).resources.textFillColorTertiary;

  static Widget _platformIcon(
    PackModel pack,
    RepoPlatform? platform,
    Color color,
  ) {
    final String assetPath = platform == RepoPlatform.github
        ? Svgs.repoGithubPath
        : Svgs.repoRemotePath;
    return SvgPicture.asset(
      assetPath,
      key: Key('repoFallbackIcon_${pack.name}'),
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: '开源仓库图标',
      errorBuilder:
          (BuildContext context, Object error, StackTrace stackTrace) =>
              _localIcon(pack) ?? Svgs.cardboardBox,
    );
  }

  static Widget? _localIcon(PackModel pack) {
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
