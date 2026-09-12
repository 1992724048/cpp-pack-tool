import 'dart:io';

import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 子进程执行器：与 `Process.run` 同形，便于测试注入。
typedef PackProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// UI 层构建入口：以位置参数 `onStage` 调用 [runPackBuild]。
typedef PackBuildRunner = Future<void> Function(
  PackModel pack,
  void Function(PackBuildStage) onStage,
);

/// 构建阶段：下载源码 / 执行构建。
enum PackBuildStage { downloading, building }

/// 构建失败异常：[message] 面向用户展示，[outputTail] 为进程输出末尾片段。
class PackBuildException implements Exception {
  const PackBuildException(this.message, {this.outputTail});

  final String message;
  final String? outputTail;

  @override
  String toString() => message;
}

const int _outputTailLineCount = 20;
const String _gitPromptEnvironmentKey = 'GIT_TERMINAL_PROMPT';

/// 拉取源码并执行包内 `build.py`。
///
/// 流程：解析 `build.py` 首行仓库地址 → 目标目录（`<cacheRoot>/build/<清洗包ID>`）
/// 克隆或拉取 → 以 `SRC_PATH`（目标目录）与 `BUILD_OUT`（包源目录）环境变量
/// 运行 `python build.py`。
Future<void> runPackBuild(
  PackModel pack,
  void Function(PackBuildStage) onStage, {
  PackProcessRunner processRunner = Process.run,
  String cacheRoot = 'cache',
}) async {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null) {
    throw const PackBuildException('该包缺少源目录信息');
  }

  final FileModel? scriptFile = findBuildScript(pack.files);
  if (scriptFile == null) {
    throw const PackBuildException('未找到 build.py');
  }
  final File scriptOnDisk = File(joinPath(sourcePath, scriptFile.path));
  if (!await scriptOnDisk.exists()) {
    throw const PackBuildException('源目录中找不到 build.py（可能已被移动）');
  }
  final String? repository = parseBuildScriptRepo(
    await scriptOnDisk.readAsString(),
  );
  if (repository == null) {
    throw const PackBuildException('build.py 首行缺少 git 仓库地址（格式：# <仓库地址>）');
  }

  onStage(PackBuildStage.downloading);
  final Directory target = Directory(
    joinPath(cacheRoot, 'build/${PackStore.sanitizeFileName(pack.name)}'),
  );
  await target.parent.create(recursive: true);
  if (await _hasGitDirectory(target)) {
    await _pullRepository(processRunner, target);
  } else {
    await _cloneRepository(processRunner, target, repository);
  }

  onStage(PackBuildStage.building);
  await _runBuildScript(processRunner, sourcePath, scriptFile.path, target);
}

Future<bool> _hasGitDirectory(Directory target) async {
  final FileSystemEntityType type = await FileSystemEntity.type(
    '${target.path}/.git',
  );
  return type != FileSystemEntityType.notFound;
}

Future<void> _pullRepository(
  PackProcessRunner processRunner,
  Directory target,
) async {
  final ProcessResult result = await _runGit(processRunner, const <String>[
    'pull',
    '--ff-only',
  ], workingDirectory: target.path);
  if (result.exitCode != 0) {
    throw PackBuildException(
      '拉取源码失败（退出码 ${result.exitCode}）',
      outputTail: _outputTail(result),
    );
  }
}

Future<void> _cloneRepository(
  PackProcessRunner processRunner,
  Directory target,
  String repository,
) async {
  await _deleteResidual(target.path);
  final ProcessResult result = await _runGit(processRunner, <String>[
    'clone',
    repository,
    target.path,
  ]);
  if (result.exitCode == 0) {
    return;
  }
  await _deleteResidual(target.path);
  throw PackBuildException(
    '克隆源码失败（退出码 ${result.exitCode}）',
    outputTail: _outputTail(result),
  );
}

Future<ProcessResult> _runGit(
  PackProcessRunner processRunner,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return processRunner(
    'git',
    arguments,
    workingDirectory: workingDirectory,
    environment: const <String, String>{_gitPromptEnvironmentKey: '0'},
  );
}

Future<void> _deleteResidual(String path) async {
  final FileSystemEntityType type = await FileSystemEntity.type(path);
  if (type == FileSystemEntityType.notFound) {
    return;
  }
  final FileSystemEntity entity = type == FileSystemEntityType.directory
      ? Directory(path)
      : File(path);
  await entity.delete(recursive: true);
}

Future<void> _runBuildScript(
  PackProcessRunner processRunner,
  String sourcePath,
  String scriptPath,
  Directory target,
) async {
  final Map<String, String> environment = <String, String>{
    'SRC_PATH': target.absolute.path,
    'BUILD_OUT': Directory(sourcePath).absolute.path,
  };
  final ProcessResult result = await _runPython(
    processRunner,
    sourcePath,
    scriptPath,
    environment,
  );
  if (result.exitCode != 0) {
    throw PackBuildException(
      '构建失败（退出码 ${result.exitCode}）',
      outputTail: _outputTail(result),
    );
  }
}

Future<ProcessResult> _runPython(
  PackProcessRunner processRunner,
  String sourcePath,
  String scriptPath,
  Map<String, String> environment,
) async {
  try {
    return await processRunner(
      'python',
      <String>[scriptPath],
      workingDirectory: sourcePath,
      environment: environment,
    );
  } on ProcessException {
    return _runFallbackPython(
      processRunner,
      sourcePath,
      scriptPath,
      environment,
    );
  }
}

Future<ProcessResult> _runFallbackPython(
  PackProcessRunner processRunner,
  String sourcePath,
  String scriptPath,
  Map<String, String> environment,
) async {
  try {
    return await processRunner(
      'py',
      <String>['-3', scriptPath],
      workingDirectory: sourcePath,
      environment: environment,
    );
  } on ProcessException {
    throw const PackBuildException('未找到 Python（python / py），无法执行构建');
  }
}

String? _outputTail(ProcessResult result) {
  final List<String> lines = '${result.stdout}\n${result.stderr}'.split(
    RegExp(r'\r?\n'),
  );
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  final List<String> tail = lines.length <= _outputTailLineCount
      ? lines
      : lines.sublist(lines.length - _outputTailLineCount);
  final String text = tail.join('\n').trim();
  return text.isEmpty ? null : text;
}
