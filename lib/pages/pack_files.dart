import 'package:fluent_ui/fluent_ui.dart';

class PackFiles extends StatefulWidget {
  const PackFiles({super.key});

  @override
  State<PackFiles> createState() => _PackFilesState();
}

class _PackFilesState extends State<PackFiles> {
  @override
  Widget build(BuildContext context) {
    final res = FluentTheme.of(context).resources;
    return Table(
      border: TableBorder.all(color: res.dividerStrokeColorDefault, width: 0.5),
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2), 2: FlexColumnWidth(1)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: res.controlFillColorSecondary),
          children: const [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('文件名', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('路径', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('大小', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        for (var i = 0; i < 10; i++)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8.0), child: Text('文件$i.txt')),
              Padding(padding: const EdgeInsets.all(8.0), child: Text('/path/to/file$i.txt')),
              Padding(padding: const EdgeInsets.all(8.0), child: Text('${(i + 1) * 10} KB')),
            ],
          ),
      ],
    );
  }
}
