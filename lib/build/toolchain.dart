import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:cpp_nuget_pack/shared/format.dart';

export 'package:cpp_nuget_pack/models/compiler_model.dart';

final RegExp _icxVersionPattern = RegExp(r'Compiler\s+(\d+\.\d+\.\d+)');
final RegExp _clangVersionPattern = RegExp(r'clang version (\d+\.\d+\.\d+)');
final RegExp _lineSeparator = RegExp(r'\r?\n');
const String _vcToolsComponent = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64';

Future<DetectedCompiler?> detectIcx({
  PackProcessRunner runner = Process.run,
  required String oneApiRoot,
  Map<String, String>? environment,
}) async {
  final String? executable = _findIcxExecutable(oneApiRoot);
  if (executable == null) {
    return null;
  }
  final String? version = await _probeVersion(
    runner: runner,
    executable: executable,
    arguments: const <String>['--version'],
    pattern: _icxVersionPattern,
    environment: environment,
  );
  if (version == null) {
    return null;
  }
  return DetectedCompiler(
    kind: CompilerKind.icx,
    version: version,
    executablePath: executable,
    environmentScript: joinPath(oneApiRoot, 'setvars.bat'),
  );
}

Future<DetectedCompiler?> detectClangCl({
  PackProcessRunner runner = Process.run,
  required String llvmBinDir,
  Map<String, String>? environment,
}) async {
  final String executable = joinPath(llvmBinDir, 'clang-cl.exe');
  if (!File(executable).existsSync()) {
    return null;
  }
  final String? version = await _probeVersion(
    runner: runner,
    executable: executable,
    arguments: const <String>['--version'],
    pattern: _clangVersionPattern,
    environment: environment,
  );
  if (version == null) {
    return null;
  }
  return DetectedCompiler(
    kind: CompilerKind.clangCl,
    version: version,
    executablePath: executable,
    environmentScript: null,
    extraPathEntries: <String>[llvmBinDir],
  );
}

Future<DetectedCompiler?> detectMsvc({
  PackProcessRunner runner = Process.run,
  required String vswherePath,
  Map<String, String>? environment,
}) async {
  final String? installPath = await _queryVswhereInstallation(runner, vswherePath, environment: environment);
  if (installPath == null) {
    return null;
  }
  final String? version = _readVcToolsVersion(installPath);
  if (version == null) {
    return null;
  }
  final String executable = joinPath(installPath, 'VC/Tools/MSVC/$version/bin/HostX64/x64/cl.exe');
  if (!File(executable).existsSync()) {
    return null;
  }
  return DetectedCompiler(
    kind: CompilerKind.msvc,
    version: version,
    executablePath: executable,
    environmentScript: joinPath(installPath, 'VC/Auxiliary/Build/vcvars64.bat'),
  );
}

Future<List<DetectedCompiler>> detectCompilers({
  PackProcessRunner runner = Process.run,
  String? oneApiRoot,
  String? llvmBinDir,
  String? vswherePath,
  Map<String, String>? environment,
}) async {
  final Map<String, String> env = environment ?? Platform.environment;
  final List<DetectedCompiler> compilers = <DetectedCompiler>[];

  final List<String> oneApiRoots = oneApiRoot == null ? _defaultOneApiRoots(env) : <String>[oneApiRoot];
  for (final String root in oneApiRoots) {
    final DetectedCompiler? icx = await detectIcx(runner: runner, oneApiRoot: root, environment: env);
    if (icx != null) {
      compilers.add(icx);
      break;
    }
  }

  final String? llvmBin = llvmBinDir ?? _defaultLlvmBinDir(env);
  if (llvmBin != null) {
    final DetectedCompiler? clangCl = await detectClangCl(runner: runner, llvmBinDir: llvmBin, environment: env);
    if (clangCl != null) {
      compilers.add(clangCl);
    }
  }

  final String? vswhere = vswherePath ?? _defaultVswherePath(env);
  if (vswhere != null) {
    final DetectedCompiler? msvc = await detectMsvc(runner: runner, vswherePath: vswhere, environment: env);
    if (msvc != null) {
      compilers.add(msvc);
    }
  }

  return _inheritMsvcEnvironmentForClangCl(compilers);
}

List<DetectedCompiler> _inheritMsvcEnvironmentForClangCl(List<DetectedCompiler> compilers) {
  String? msvcScript;
  for (final DetectedCompiler compiler in compilers) {
    final String? script = compiler.environmentScript;
    if (compiler.kind == CompilerKind.msvc && script != null && script.isNotEmpty) {
      msvcScript = script;
      break;
    }
  }
  if (msvcScript == null) {
    return compilers;
  }
  return <DetectedCompiler>[
    for (final DetectedCompiler compiler in compilers)
      if (compiler.kind == CompilerKind.clangCl && compiler.environmentScript == null)
        DetectedCompiler(
          kind: compiler.kind,
          version: compiler.version,
          executablePath: compiler.executablePath,
          cxxExecutablePath: compiler.cxxExecutablePath,
          environmentScript: msvcScript,
          extraPathEntries: compiler.extraPathEntries,
        )
      else
        compiler,
  ];
}

DetectedCompiler? selectCompiler(List<DetectedCompiler> available, List<String> priority) {
  for (final String id in priority) {
    final String normalized = id.trim().toLowerCase();
    for (final DetectedCompiler compiler in available) {
      if (compilerKindId(compiler.kind).toLowerCase() == normalized) {
        return compiler;
      }
    }
  }
  return null;
}

bool isCompilerUsable(DetectedCompiler compiler) {
  if (compiler.executablePath.isEmpty) {
    return false;
  }
  if (!File(compiler.executablePath).existsSync()) {
    return false;
  }
  final String? cxxExecutable = compiler.cxxExecutablePath;
  if (cxxExecutable != null && cxxExecutable.isNotEmpty && !File(cxxExecutable).existsSync()) {
    return false;
  }
  final String? script = compiler.environmentScript;
  if (script != null && script.isNotEmpty && !File(script).existsSync()) {
    return false;
  }
  return true;
}

String? _findIcxExecutable(String oneApiRoot) {
  final Directory compilerRoot = Directory(joinPath(oneApiRoot, 'compiler'));
  final List<FileSystemEntity> entries;
  try {
    entries = compilerRoot.listSync();
  } on FileSystemException {
    return null;
  }

  final List<String> versionDirectories = <String>[];
  String? latestExecutable;
  for (final FileSystemEntity entity in entries) {
    final String name = baseName(entity.path);
    final String? executable = _icxExecutableIn(oneApiRoot, name);
    if (executable == null) {
      continue;
    }
    if (name.toLowerCase() == 'latest') {
      latestExecutable = executable;
    } else {
      versionDirectories.add(name);
    }
  }

  versionDirectories.sort((String first, String second) => _compareVersionNames(second, first));
  if (versionDirectories.isNotEmpty) {
    return _icxExecutableIn(oneApiRoot, versionDirectories.first);
  }
  return latestExecutable;
}

String? _icxExecutableIn(String oneApiRoot, String compilerDirectoryName) {
  for (final String layout in const <String>['bin', 'windows/bin']) {
    for (final String name in const <String>['icx.exe', 'icx-cl.exe']) {
      final String executable = joinPath(oneApiRoot, 'compiler/$compilerDirectoryName/$layout/$name');
      if (File(executable).existsSync()) {
        return executable;
      }
    }
  }
  return null;
}

int _compareVersionNames(String first, String second) {
  final List<String> firstParts = first.split('.');
  final List<String> secondParts = second.split('.');
  final int partCount = firstParts.length > secondParts.length ? firstParts.length : secondParts.length;
  for (var index = 0; index < partCount; index++) {
    final int firstValue = index < firstParts.length ? int.tryParse(firstParts[index]) ?? 0 : 0;
    final int secondValue = index < secondParts.length ? int.tryParse(secondParts[index]) ?? 0 : 0;
    if (firstValue != secondValue) {
      return firstValue.compareTo(secondValue);
    }
  }
  return first.compareTo(second);
}

Future<String?> _probeVersion({
  required PackProcessRunner runner,
  required String executable,
  required List<String> arguments,
  required RegExp pattern,
  Map<String, String>? environment,
}) async {
  final ProcessResult result;
  try {
    result = await runner(executable, arguments, environment: environment);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) {
    return null;
  }
  final RegExpMatch? match = pattern.firstMatch('${result.stdout}');
  return match?.group(1);
}

Future<String?> _queryVswhereInstallation(
  PackProcessRunner runner,
  String vswherePath, {
  Map<String, String>? environment,
}) async {
  final ProcessResult result;
  try {
    result = await runner(vswherePath, const <String>[
      '-latest',
      '-products',
      '*',
      '-requires',
      _vcToolsComponent,
      '-property',
      'installationPath',
    ], environment: environment);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) {
    return null;
  }
  final String installPath = _firstNonEmptyLine('${result.stdout}');
  return installPath.isEmpty ? null : installPath;
}

String? _readVcToolsVersion(String installPath) {
  final File versionFile = File(joinPath(installPath, 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'));
  if (!versionFile.existsSync()) {
    return null;
  }
  final String version;
  try {
    version = _firstNonEmptyLine(versionFile.readAsStringSync());
  } on FileSystemException {
    return null;
  }
  return version.isEmpty ? null : version;
}

String _firstNonEmptyLine(String text) {
  for (final String line in text.split(_lineSeparator)) {
    final String trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

List<String> _defaultOneApiRoots(Map<String, String> environment) {
  final List<String> roots = <String>[];
  final String? declaredRoot = _environmentValue(environment, 'ONEAPI_ROOT');
  if (declaredRoot != null && declaredRoot.isNotEmpty) {
    roots.add(declaredRoot);
  }
  for (final String key in const <String>['ProgramFiles(x86)', 'ProgramFiles']) {
    final String? base = _environmentValue(environment, key);
    if (base == null || base.isEmpty) {
      continue;
    }
    final String root = joinPath(base, 'Intel/oneAPI');
    if (roots.any((String item) => item.toLowerCase() == root.toLowerCase())) {
      continue;
    }
    roots.add(root);
  }
  return roots;
}

String? _defaultLlvmBinDir(Map<String, String> environment) {
  final String? base = _environmentValue(environment, 'ProgramFiles');
  return base == null || base.isEmpty ? null : joinPath(base, 'LLVM/bin');
}

String? _defaultVswherePath(Map<String, String> environment) {
  final String? base = _environmentValue(environment, 'ProgramFiles(x86)');
  return base == null || base.isEmpty ? null : joinPath(base, 'Microsoft Visual Studio/Installer/vswhere.exe');
}

String? _environmentValue(Map<String, String> environment, String key) {
  final String? direct = environment[key];
  if (direct != null) {
    return direct;
  }
  final String normalized = key.toLowerCase();
  for (final MapEntry<String, String> entry in environment.entries) {
    if (entry.key.toLowerCase() == normalized) {
      return entry.value;
    }
  }
  return null;
}
