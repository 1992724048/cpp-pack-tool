import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';

class PackModel {
  final String name;
  final String version;
  final String author;
  final String? description;

  List<FileModel> files = [];
  List<CmdModel> cmds = [];

  static List<PackModel> packs = [];
  
  PackModel({required this.name, required this.version, required this.author, this.description});
}
