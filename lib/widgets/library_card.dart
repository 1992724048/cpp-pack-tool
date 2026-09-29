import 'package:cpp_nuget_pack/shared/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../shared/svgs.dart';

class LibraryItem extends PaneItem {
  LibraryItem({super.key, required Widget? icon, required String title, String? version, required Widget body})
    : super(
        icon: icon ?? Svgs.cardboardBox,
        title: Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            version != null
                ? Tag(text: version, fontSize: 10, maxWidth: 96, tooltip: version)
                : const SizedBox(width: 8),
          ],
        ),
        body: body,
      );
}
