import 'package:cpp_nuget_pack/models/build_model.dart';

class LibDirModel {
  const LibDirModel({required this.path, this.buildModel = BuildModel.all});

  final String path;
  final BuildModel buildModel;

  Map<String, Object?> toMap() => <String, Object?>{
    'path': path,
    'buildModel': buildModel.name,
  };

  factory LibDirModel.fromMap(Map<String, Object?> map) {
    final Object? path = map['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('附加库目录缺少 path 字段');
    }
    return LibDirModel(
      path: path,
      buildModel: BuildModel.fromName(map['buildModel']),
    );
  }
}
