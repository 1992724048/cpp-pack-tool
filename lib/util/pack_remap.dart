import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/file_image.dart';

class PackFilesDiff {
  const PackFilesDiff({required this.added, required this.removed, required this.oldSize, required this.newSize});

  final int added;
  final int removed;
  final int oldSize;
  final int newSize;

  bool get hasChanges => added != 0 || removed != 0 || oldSize != newSize;
}

int totalFileSize(List<FileModel> files) => files.fold<int>(0, (int sum, FileModel file) => sum + file.size);

PackFilesDiff comparePackFiles(List<FileModel> oldFiles, List<FileModel> newFiles) {
  final Set<String> oldPaths = <String>{for (final FileModel file in oldFiles) file.path.toLowerCase()};
  final Set<String> newPaths = <String>{for (final FileModel file in newFiles) file.path.toLowerCase()};
  return PackFilesDiff(
    added: newPaths.difference(oldPaths).length,
    removed: oldPaths.difference(newPaths).length,
    oldSize: totalFileSize(oldFiles),
    newSize: totalFileSize(newFiles),
  );
}

PackModel copyPackWithFiles(PackModel pack, List<FileModel> files) {
  return pack.copyWith(files: files, iconPath: findIconFile(files)?.path);
}
