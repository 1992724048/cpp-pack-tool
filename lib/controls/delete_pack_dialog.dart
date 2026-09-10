import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

Future<bool> showDeletePackDialog(
  BuildContext context, {
  required String packName,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => ContentDialog(
      key: const Key('deletePackDialog'),
      title: const Text('删除包'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要删除包「$packName」吗？'),
          const SizedBox(height: 8),
          const Text('将移除其配置文件，此操作不可恢复；源目录中的文件不会被删除。'),
        ],
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FilledButton(
              key: const Key('deletePackConfirmButton'),
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(UCColors.flavor.red),
                foregroundColor: WidgetStatePropertyAll(Colors.white),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
            Button(
              key: const Key('deletePackCancelButton'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
