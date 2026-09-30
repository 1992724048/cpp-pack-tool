import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/pack/ui/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../file_image.dart';
import '../../shared/format.dart';
import '../../shared/svgs.dart';
import 'pack_manage.dart';

class PackList {
  PackList._();

  static List<NavigationPaneItem> buildCards(
    List<PackModel> packs, {
    required Future<bool> Function(PackModel pack) onSave,
    required Future<String?> Function() pickDirectory,
    Future<void> Function(PackModel pack)? onBuildPack,
  }) {
    return [
      for (final PackModel pack in packs)
        LibraryItem(
          icon: _localIcon(pack),
          title: pack.name,
          version: pack.version,
          body: PackManage(
            pack: pack,
            allPacks: packs,
            onSave: onSave,
            pickDirectory: pickDirectory,
            onBuildPack: onBuildPack,
          ),
        ),
    ];
  }

  static Widget? _localIcon(PackModel pack) {
    final String? iconPath = pack.iconPath;
    final String? sourcePath = pack.sourcePath;
    if (iconPath == null || sourcePath == null) {
      return null;
    }
    return buildFileImage(joinPath(sourcePath, iconPath), size: 20, fallback: Svgs.cardboardBox);
  }
}
