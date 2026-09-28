import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../util/file_image.dart';
import '../util/format.dart';
import '../util/svgs.dart';
import 'pack_manage.dart';

class PackList {
  PackList._();

  static List<NavigationPaneItem> buildCards(
    List<PackModel> packs, {
    required Future<bool> Function(PackModel pack) onSave,
    required Future<String?> Function() pickDirectory,
    Future<void> Function(PackModel pack)? onBuildPack,
    Future<BuildScriptHeader?> Function(PackModel pack)? loadHeader,
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
            loadHeader: loadHeader,
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
    return buildFileImage(
      joinPath(sourcePath, iconPath),
      size: 20,
      fallback: Svgs.cardboardBox,
    );
  }
}
