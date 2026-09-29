import 'package:cpp_nuget_pack/pack/model/cmd_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';

const String _preScriptName = 'pre.bat';
const String _postScriptName = 'post.bat';

class SystemEntriesUpdate {
  const SystemEntriesUpdate({required this.pack, required this.changed});

  final PackModel pack;
  final bool changed;
}

SystemEntriesUpdate applySystemEntries(PackModel pack) {
  final List<CmdModel> commands = <CmdModel>[...pack.commands];
  if (!_appendScriptCommands(pack.files, commands)) {
    return SystemEntriesUpdate(pack: pack, changed: false);
  }
  return SystemEntriesUpdate(pack: _copyPack(pack, commands: commands), changed: true);
}

bool _appendScriptCommands(List<FileModel> files, List<CmdModel> commands) {
  final bool preAdded = _appendScriptCommand(files, commands, _preScriptName, CmdType.preBuild);
  final bool postAdded = _appendScriptCommand(files, commands, _postScriptName, CmdType.postBuild);
  return preAdded || postAdded;
}

bool _appendScriptCommand(List<FileModel> files, List<CmdModel> commands, String scriptName, CmdType type) {
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
  return files.any((FileModel file) => _isRootFileNamed(file.path, scriptName));
}

bool _isRootFileNamed(String path, String lowerName) {
  if (path.contains('/') || path.contains('\\')) {
    return false;
  }
  return path.toLowerCase() == lowerName;
}

bool _hasCommand(List<CmdModel> commands, String command) {
  final String normalized = command.toLowerCase();
  return commands.any((CmdModel item) => item.command.toLowerCase() == normalized);
}

String _systemCommand(String scriptName) => '"\$(MSBuildThisFileDirectory)files\\$scriptName" "\$(TargetPath)"';

PackModel _copyPack(PackModel pack, {required List<CmdModel> commands}) {
  return pack.copyWith(commands: commands);
}
