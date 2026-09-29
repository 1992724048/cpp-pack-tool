import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';

const String _preScriptName = 'pre.bat';
const String _postScriptName = 'post.bat';

/// 系统条目同步结果。
class SystemEntriesUpdate {
  const SystemEntriesUpdate({required this.pack, required this.changed});

  /// 写回用包模型；无新增条目时与入参为同一实例。
  final PackModel pack;

  /// 是否新增了系统条目。
  final bool changed;
}

/// 依据包内约定同步构建管线系统条目：
///
/// - 根级 `pre.bat` / `post.bat`（大小写不敏感）→ 编译前/后命令，命令以
///   `"$(MSBuildThisFileDirectory)files\<脚本>" "$(TargetPath)"` 引用，脚本
///   通过 `%~1` 取目标路径。
///
/// 已存在同命令（无论是否系统条目）时不重复添加，也不改动已有条目。返回新包模型
/// （全字段拷贝）；无新增条目时返回入参实例。
SystemEntriesUpdate applySystemEntries(PackModel pack) {
  final List<CmdModel> commands = <CmdModel>[...pack.commands];
  if (!_appendScriptCommands(pack.files, commands)) {
    return SystemEntriesUpdate(pack: pack, changed: false);
  }
  return SystemEntriesUpdate(pack: _copyPack(pack, commands: commands), changed: true);
}

bool _appendScriptCommands(List<FileModel> files, List<CmdModel> commands) {
  final bool preAdded = _appendScriptCommand(
    files,
    commands,
    _preScriptName,
    CmdType.preBuild,
  );
  final bool postAdded = _appendScriptCommand(
    files,
    commands,
    _postScriptName,
    CmdType.postBuild,
  );
  return preAdded || postAdded;
}

bool _appendScriptCommand(
  List<FileModel> files,
  List<CmdModel> commands,
  String scriptName,
  CmdType type,
) {
  if (!_hasRootScript(files, scriptName)) {
    return false;
  }
  final String command = _systemCommand(scriptName);
  if (_hasCommand(commands, command)) {
    return false;
  }
  commands.add(CmdModel(command: command, type: type, system: true));
  return true;
}

bool _hasRootScript(List<FileModel> files, String scriptName) {
  return files.any(
    (FileModel file) => _isRootFileNamed(file.path, scriptName),
  );
}

bool _isRootFileNamed(String path, String lowerName) {
  if (path.contains('/') || path.contains('\\')) {
    return false;
  }
  return path.toLowerCase() == lowerName;
}

bool _hasCommand(List<CmdModel> commands, String command) {
  final String normalized = command.toLowerCase();
  return commands.any(
    (CmdModel item) => item.command.toLowerCase() == normalized,
  );
}

String _systemCommand(String scriptName) =>
    '"\$(MSBuildThisFileDirectory)files\\$scriptName" "\$(TargetPath)"';

PackModel _copyPack(PackModel pack, {required List<CmdModel> commands}) {
  return pack.copyWith(commands: commands);
}
