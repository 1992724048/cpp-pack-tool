import 'package:cpp_nuget_pack/models/build_model.dart';

class MacroModel {
  final String value;
  BuildModel buildModel = BuildModel.all;

  MacroModel({required this.value});
}
