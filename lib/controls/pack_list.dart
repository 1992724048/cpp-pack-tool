import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../util/svgs.dart';
import 'pack_manage.dart';

class PackList {
  PackList._();

  static List<NavigationPaneItem> buildCards() {
    return [for (var i = 0; i < 100; i++) LibraryItem(icon: Svgs.cardboardBox, title: '测试$i', version: '1.0.$i', body: PackManage())];
  }
}
