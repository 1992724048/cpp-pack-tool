import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:fluent_ui/fluent_ui.dart';

const int _bytesPerUnit = 1024;
const List<String> _sizeUnits = ['B', 'KB', 'MB', 'GB'];

String _formatSize(int size) {
  if (size < _bytesPerUnit) {
    return '$size B';
  }
  var value = size.toDouble();
  var unitIndex = 0;
  while (value >= _bytesPerUnit && unitIndex < _sizeUnits.length - 1) {
    value /= _bytesPerUnit;
    unitIndex++;
  }
  return '${value.toStringAsFixed(1)} ${_sizeUnits[unitIndex]}';
}

class AddDirectoryDialog extends StatelessWidget {
  const AddDirectoryDialog({
    super.key,
    required this.directoryPath,
    required this.scanFuture,
  });

  final String directoryPath;
  final Future<List<FileModel>> scanFuture;

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('已选择目录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('路径：$directoryPath'),
          const SizedBox(height: 12),
          FutureBuilder<List<FileModel>>(
            future: scanFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Row(
                  children: [
                    ProgressRing(),
                    SizedBox(width: 12),
                    Text('正在扫描…'),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Text('扫描失败：${snapshot.error}');
              }
              final List<FileModel> files =
                  snapshot.data ?? const <FileModel>[];
              final int totalSize = files.fold<int>(
                0,
                (int sum, FileModel file) => sum + file.size,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('文件数量：${files.length}'),
                  const SizedBox(height: 4),
                  Text('总大小：${_formatSize(totalSize)}'),
                ],
              );
            },
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
