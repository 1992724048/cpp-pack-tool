import 'package:cpp_nuget_pack/models/build_model.dart';

enum CmdType { preBuild, postBuild }

class CmdModel {
  final String command;
  final CmdType type;

  BuildModel buildModel = BuildModel.all;

  CmdModel({required this.command, required this.type});
}
