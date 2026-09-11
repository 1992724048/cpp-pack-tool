import 'package:cpp_nuget_pack/models/build_model.dart';

class MacroModel {
  const MacroModel({required this.value, this.buildModel = BuildModel.all});

  final String value;
  final BuildModel buildModel;

  Map<String, Object?> toMap() => <String, Object?>{
    'value': value,
    'buildModel': buildModel.name,
  };

  factory MacroModel.fromMap(Map<String, Object?> map) {
    final Object? value = map['value'];
    if (value is! String || value.isEmpty) {
      throw const FormatException('宏定义缺少 value 字段');
    }
    return MacroModel(
      value: value,
      buildModel: BuildModel.fromName(map['buildModel']),
    );
  }
}
