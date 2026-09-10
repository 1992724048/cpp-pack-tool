import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../util/svgs.dart';
import 'pack_manage.dart';

class PackList {
  PackList._();

  static List<NavigationPaneItem> buildCards(List<PackModel> packs) {
    return [
      for (final PackModel pack in packs)
        LibraryItem(
          icon: Svgs.cardboardBox,
          title: pack.name,
          version: pack.version,
          body: PackManage(pack: pack),
        ),
    ];
  }
}
