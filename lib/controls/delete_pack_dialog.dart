import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

typedef PackDependent = ({String name, String version});
typedef DeletePackResult = ({bool confirmed});

const double _versionColumnWidth = 120;

Future<DeletePackResult> showDeletePackDialog(
  BuildContext context, {
  required String packName,
  List<PackDependent> dependents = const <PackDependent>[],
}) async {
  final DeletePackResult? result = await showDialog<DeletePackResult>(
    context: context,
    builder: (BuildContext dialogContext) => _DeletePackDialog(packName: packName, dependents: dependents),
  );
  return result ?? (confirmed: false);
}

class _DeletePackDialog extends StatefulWidget {
  const _DeletePackDialog({required this.packName, required this.dependents});

  final String packName;
  final List<PackDependent> dependents;

  @override
  State<_DeletePackDialog> createState() => _DeletePackDialogState();
}

class _DeletePackDialogState extends State<_DeletePackDialog> {
  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return ContentDialog(
      key: const Key('deletePackDialog'),
      title: const Text('删除包'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要删除包「${widget.packName}」吗？'),
          const SizedBox(height: 8),
          const Text('将移除其配置文件，此操作不可恢复；源目录中的文件不会被删除。'),
          if (widget.dependents.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDependentsSection(context, widget.dependents),
          ],
        ],
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FilledButton(
              key: const Key('deletePackConfirmButton'),
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(AppColors.critical(theme.brightness)),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              ),
              onPressed: () => Navigator.pop(context, (confirmed: true)),
              child: const Text('删除'),
            ),
            Button(
              key: const Key('deletePackCancelButton'),
              onPressed: () => Navigator.pop(context, (confirmed: false)),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }
}

Widget _buildDependentsSection(BuildContext context, List<PackDependent> dependents) {
  final FluentThemeData theme = FluentTheme.of(context);
  final DividerThemeData dividerTheme = theme.dividerTheme;
  final TextStyle style = TextStyle(fontSize: 12, color: theme.resources.textFillColorSecondary);
  final Color valueColor = theme.resources.textFillColorSecondary;
  return Column(
    key: const Key('deletePackDependents'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('以下包依赖它：', style: TextStyle(color: AppColors.critical(theme.brightness))),
      const SizedBox(height: 6),
      FluentTheme(
        data: theme.copyWith(
          dividerTheme: DividerThemeData(
            decoration: dividerTheme.decoration,
            verticalMargin: dividerTheme.verticalMargin,
            horizontalMargin: EdgeInsets.zero,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text('包名', style: style)),
                  SizedBox(
                    width: _versionColumnWidth,
                    child: Text('版本范围', style: style),
                  ),
                ],
              ),
            ),
            const Divider(),
            for (int index = 0; index < dependents.length; index++) ...[
              if (index > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(dependents[index].name, overflow: TextOverflow.ellipsis)),
                    SizedBox(
                      width: _versionColumnWidth,
                      child: Text(
                        dependents[index].version,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: valueColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Text('删除后这些依赖将显示为「缺失」。'),
    ],
  );
}
