import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/file_image.dart';

/// 文件快照对比结果：路径大小写不敏感，大小为字节总量。
class PackFilesDiff {
  const PackFilesDiff({
    required this.added,
    required this.removed,
    required this.oldSize,
    required this.newSize,
  });

  final int added;
  final int removed;
  final int oldSize;
  final int newSize;

  bool get hasChanges => added != 0 || removed != 0 || oldSize != newSize;
}

int totalFileSize(List<FileModel> files) =>
    files.fold<int>(0, (int sum, FileModel file) => sum + file.size);

/// 对比新旧文件快照：按小写路径集统计新增/移除，并汇总两侧字节总量。
PackFilesDiff comparePackFiles(
  List<FileModel> oldFiles,
  List<FileModel> newFiles,
) {
  final Set<String> oldPaths = <String>{
    for (final FileModel file in oldFiles) file.path.toLowerCase(),
  };
  final Set<String> newPaths = <String>{
    for (final FileModel file in newFiles) file.path.toLowerCase(),
  };
  return PackFilesDiff(
    added: newPaths.difference(oldPaths).length,
    removed: oldPaths.difference(newPaths).length,
    oldSize: totalFileSize(oldFiles),
    newSize: totalFileSize(newFiles),
  );
}

/// 以 [files] 替换文件列表的整包拷贝：图标按新快照重新识别，其余字段原样保留。
PackModel copyPackWithFiles(PackModel pack, List<FileModel> files) {
  return PackModel(
      name: pack.name,
      version: pack.version,
      author: pack.author,
      description: pack.description,
      license: pack.license,
      iconPath: findIconFile(files)?.path,
      sourcePath: pack.sourcePath,
      sourceVersion: pack.sourceVersion,
    )
    ..files = files
    ..commands = pack.commands
    ..dependencies = pack.dependencies
    ..macros = pack.macros
    ..libDirectories = pack.libDirectories
    ..libraries = pack.libraries
    ..history = pack.history
    ..scripts = pack.scripts
    ..buildOptions = pack.buildOptions
    ..enabledFormats = pack.enabledFormats;
}
