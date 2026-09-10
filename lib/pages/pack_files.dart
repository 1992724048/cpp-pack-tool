import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PackFiles extends StatelessWidget {
  const PackFiles({super.key, required this.pack});

  final PackModel pack;

  @override
  Widget build(BuildContext context) {
    final res = FluentTheme.of(context).resources;
    final List<FileModel> files = pack.files;
    if (files.isEmpty) {
      return const Center(child: Text('该包暂无文件'));
    }
    return SingleChildScrollView(
      child: Table(
        border: TableBorder.all(
          color: res.dividerStrokeColorDefault,
          width: 0.5,
        ),
        columnWidths: const {
          0: FlexColumnWidth(1),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: res.controlFillColorSecondary),
            children: const [
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  '文件名',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  '路径',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  '大小',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          for (final FileModel file in files)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(file.name),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(file.path),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(formatBytes(file.size)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
