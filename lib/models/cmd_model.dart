import 'package:cpp_nuget_pack/models/build_model.dart';

enum CmdType { preBuild, postBuild }

class CmdModel {
  const CmdModel({
    required this.command,
    required this.type,
    this.buildModel = BuildModel.all,
    this.system = false,
  });

  final String command;
  final CmdType type;
  final BuildModel buildModel;

  /// 构建管线自动注册的系统条目；UI 禁止编辑/删除。
  final bool system;

  Map<String, Object?> toMap() => <String, Object?>{
    'command': command,
    'type': type.name,
    'buildModel': buildModel.name,
    if (system) 'system': true,
  };

  factory CmdModel.fromMap(Map<String, Object?> map) {
    final Object? command = map['command'];
    if (command is! String || command.isEmpty) {
      throw const FormatException('命令缺少 command 字段');
    }
    final Object? typeName = map['type'];
    if (typeName is! String) {
      throw const FormatException('命令缺少 type 字段');
    }
    CmdType? type;
    for (final CmdType candidate in CmdType.values) {
      if (candidate.name == typeName) {
        type = candidate;
      }
    }
    if (type == null) {
      throw FormatException('命令 type 字段值非法：$typeName');
    }
    return CmdModel(
      command: command,
      type: type,
      buildModel: BuildModel.fromName(map['buildModel']),
      system: map['system'] == true,
    );
  }
}
