import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/version_range.dart';

const String _preScriptName = 'pre.bat';
const String _postScriptName = 'post.bat';
const String _fallbackDependencyVersion = '[0.0.0,)';

/// 系统条目同步结果。
class SystemEntriesUpdate {
  const SystemEntriesUpdate({
    required this.pack,
    required this.changed,
    this.notes = const <String>[],
  });

  /// 写回用包模型；无新增条目时与入参为同一实例。
  final PackModel pack;

  /// 是否新增了系统条目。
  final bool changed;

  /// 需要向调用方说明的情况（如依赖包本地缺失，版本回退为 `[0.0.0,)`）。
  final List<String> notes;
}

/// 依据包内约定同步构建管线系统条目：
///
/// - 根级 `pre.bat` / `post.bat`（大小写不敏感）→ 编译前/后命令，命令以
///   `"$(MSBuildThisFileDirectory)files\<脚本>" "$(TargetPath)"` 引用，脚本
///   通过 `%~1` 取目标路径；
/// - [header] 的 `# depends:` 声明 → 系统依赖（显式版本范围优先；缺省时按
///   [resolvePackVersion] 提供的本地包版本生成 `[<版本>,)`，本地缺失回退
///   `[0.0.0,)` 并在 [SystemEntriesUpdate.notes] 注明）。
///
/// 已存在同命令/同名条目（无论是否系统条目）时不重复添加，也不改动已有条目；
/// 自依赖跳过。返回新包模型（全字段拷贝）；无新增条目时返回入参实例。
SystemEntriesUpdate applySystemEntries(
  PackModel pack, {
  BuildScriptHeader? header,
  String? Function(String name)? resolvePackVersion,
}) {
  final List<CmdModel> commands = <CmdModel>[...pack.commands];
  final List<DependencyModel> dependencies = <DependencyModel>[
    ...pack.dependencies,
  ];
  final List<String> notes = <String>[];
  final bool commandsAdded = _appendScriptCommands(pack.files, commands);
  final bool dependenciesAdded = _appendHeaderDependencies(
    header,
    packageName: pack.name,
    dependencies: dependencies,
    notes: notes,
    resolvePackVersion: resolvePackVersion,
  );
  if (!commandsAdded && !dependenciesAdded) {
    return SystemEntriesUpdate(pack: pack, changed: false);
  }
  return SystemEntriesUpdate(
    pack: _copyPack(pack, commands: commands, dependencies: dependencies),
    changed: true,
    notes: notes,
  );
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

bool _appendHeaderDependencies(
  BuildScriptHeader? header, {
  required String packageName,
  required List<DependencyModel> dependencies,
  required List<String> notes,
  String? Function(String name)? resolvePackVersion,
}) {
  if (header == null) {
    return false;
  }
  final Set<String> existingNames = <String>{
    for (final DependencyModel dependency in dependencies)
      dependency.name.toLowerCase(),
  };
  final String selfName = packageName.toLowerCase();
  bool changed = false;
  for (final BuildScriptDependency declared in header.dependencies) {
    final String lowerName = declared.name.toLowerCase();
    if (lowerName == selfName || !existingNames.add(lowerName)) {
      continue;
    }
    final String? version = declared.version;
    dependencies.add(
      DependencyModel(
        name: declared.name,
        version: version ??
            _defaultDependencyVersion(declared.name, resolvePackVersion, notes),
        system: true,
      ),
    );
    changed = true;
  }
  return changed;
}

String _defaultDependencyVersion(
  String name,
  String? Function(String name)? resolvePackVersion,
  List<String> notes,
) {
  final String? localVersion = resolvePackVersion?.call(name);
  if (localVersion != null &&
      localVersion.isNotEmpty &&
      isValidVersionRange(localVersion)) {
    return '[$localVersion,)';
  }
  notes.add('依赖「$name」未在本地找到，版本回退为 $_fallbackDependencyVersion');
  return _fallbackDependencyVersion;
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

PackModel _copyPack(
  PackModel pack, {
  required List<CmdModel> commands,
  required List<DependencyModel> dependencies,
}) {
  return PackModel(
      name: pack.name,
      version: pack.version,
      author: pack.author,
      description: pack.description,
      license: pack.license,
      iconPath: pack.iconPath,
      sourcePath: pack.sourcePath,
      sourceVersion: pack.sourceVersion,
    )
    ..files = pack.files
    ..commands = commands
    ..dependencies = dependencies
    ..macros = pack.macros
    ..libDirectories = pack.libDirectories
    ..libraries = pack.libraries
    ..history = pack.history
    ..scripts = pack.scripts
    ..buildOptions = pack.buildOptions
    ..enabledFormats = pack.enabledFormats;
}
