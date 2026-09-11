import 'package:cpp_nuget_pack/models/build_model.dart';

class LibraryModel {
  const LibraryModel({required this.name, this.buildModel = BuildModel.all});

  final String name;
  final BuildModel buildModel;

  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'buildModel': buildModel.name,
  };

  factory LibraryModel.fromMap(Map<String, Object?> map) {
    final Object? name = map['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('附加库缺少 name 字段');
    }
    return LibraryModel(
      name: name,
      buildModel: BuildModel.fromName(map['buildModel']),
    );
  }
}
