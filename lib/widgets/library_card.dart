import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../util/svgs.dart';

class LibraryItem extends PaneItem {
  LibraryItem({
    super.key,
    required Widget? icon,
    required String title,
    String? version,
    Widget? badge,
    required Widget body,
  }) : super(
         icon: icon ?? Svgs.cardboardBox,
         title: Row(
           mainAxisAlignment: .spaceBetween,
           children: [
             Text(title),
             const SizedBox(width: 8),
             Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                 version != null
                     ? Tag(text: version, fontSize: 10)
                     : const SizedBox(width: 8),
                 if (badge != null) ...[const SizedBox(width: 4), badge],
               ],
             ),
           ],
         ),
         body: body,
       );
}
