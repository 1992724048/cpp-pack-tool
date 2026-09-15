import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

export 'package:cpp_nuget_pack/models/compiler_model.dart';

final RegExp _icxVersionPattern = RegExp(r'Compiler\s+(\d+\.\d+\.\d+)');
final RegExp _clangVersionPattern = RegExp(r'clang version (\d+\.\d+\.\d+)');
final RegExp _lineSeparator = RegExp(r'\r?\n');
const String _vcToolsComponent =
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64';

/// 检测 Intel oneAPI ICX：取 `<oneApiRoot>/compiler/<最高版本|latest>/` 下
/// `bin/icx-cl.exe`（2024+ 布局）或 `windows/bin/icx-cl.exe`（旧布局）。
///
/// [environment] 为版本探测子进程的环境（如注入受控 `TMP`/`TEMP`）；null 时
/// 继承宿主环境。探测只认退出码 0 且 stdout 命中版本：ICX 在临时目录不可用时
/// 会以 1 退出（`error #10026`，stdout 为空、横幅与错误写 stderr），不为其放行
/// ——该文本形态与 stdout 正常输出不同且放行会掩盖真实失败；此失败模式由构建
/// 环境准备注入受控 `TMP`/`TEMP` 解决。
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

/// 检测 `<llvmBinDir>/clang.exe`（GNU 驱动）的版本。
///
/// R23 起使用 GNU 驱动（`clang`/`clang++`）而非 MSVC 兼容的 clang-cl：CMake+Ninja
/// 下 `ID=Clang`、`FRONTEND_VARIANT=GNU` 已实证（构建旗标走 GNU 风，见
/// `cnp_build_support.py`）。LLVM 发行版同时含 clang-cl.exe，仅供配方按需使用。
/// [environment] 为版本探测子进程的环境；null 时继承宿主环境。
Future<DetectedCompiler?> detectClang({
  PackProcessRunner runner = Process.run,
  required String llvmBinDir,
  Map<String, String>? environment,
}) async {
  final String executable = joinPath(llvmBinDir, 'clang.exe');
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
    kind: CompilerKind.clang,
    version: version,
    executablePath: executable,
    environmentScript: null,
    extraPathEntries: <String>[llvmBinDir],
  );
}

/// 检测 MSVC：`vswhere` 取安装路径，工具集版本取
/// `VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt`。
///
/// [environment] 为 vswhere 探测子进程的环境；null 时继承宿主环境。
Future<DetectedCompiler?> detectMsvc({
  PackProcessRunner runner = Process.run,
  required String vswherePath,
  Map<String, String>? environment,
}) async {
  final String? installPath = await _queryVswhereInstallation(
    runner,
    vswherePath,
    environment: environment,
  );
  if (installPath == null) {
    return null;
  }
  final String? version = _readVcToolsVersion(installPath);
  if (version == null) {
    return null;
  }
  final String executable = joinPath(
    installPath,
    'VC/Tools/MSVC/$version/bin/HostX64/x64/cl.exe',
  );
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

/// 检测本机可用编译器，顺序固定为 ICX → clang → MSVC。
///
/// 默认查找位置（`%ONEAPI_ROOT%`、`ProgramFiles(x86)`/`ProgramFiles` 下的
/// oneAPI 与 LLVM、vswhere）从 [environment]（缺省 `Platform.environment`）
/// 推导，并作为各版本探测子进程的环境透传（如受控 `TMP`/`TEMP`）；
/// [oneApiRoot]/[llvmBinDir]/[vswherePath] 用于测试或自定义位置覆盖。
Future<List<DetectedCompiler>> detectCompilers({
  PackProcessRunner runner = Process.run,
  String? oneApiRoot,
  String? llvmBinDir,
  String? vswherePath,
  Map<String, String>? environment,
}) async {
  final Map<String, String> env = environment ?? Platform.environment;
  final List<DetectedCompiler> compilers = <DetectedCompiler>[];

  final List<String> oneApiRoots = oneApiRoot == null
      ? _defaultOneApiRoots(env)
      : <String>[oneApiRoot];
  for (final String root in oneApiRoots) {
    final DetectedCompiler? icx = await detectIcx(
      runner: runner,
      oneApiRoot: root,
      environment: env,
    );
    if (icx != null) {
      compilers.add(icx);
      break;
    }
  }

  final String? llvmBin = llvmBinDir ?? _defaultLlvmBinDir(env);
  if (llvmBin != null) {
    final DetectedCompiler? clang = await detectClang(
      runner: runner,
      llvmBinDir: llvmBin,
      environment: env,
    );
    if (clang != null) {
      compilers.add(clang);
    }
  }

  final String? vswhere = vswherePath ?? _defaultVswherePath(env);
  if (vswhere != null) {
    final DetectedCompiler? msvc = await detectMsvc(
      runner: runner,
      vswherePath: vswhere,
      environment: env,
    );
    if (msvc != null) {
      compilers.add(msvc);
    }
  }

  return _inheritMsvcEnvironmentForClang(compilers);
}

/// MSVC 的 `vcvars64.bat` 同时提供 clang 所需的 INCLUDE/LIB；检测结果中 clang
/// 无环境脚本且存在带非空脚本的 MSVC 条目时，clang 继承该脚本。
List<DetectedCompiler> _inheritMsvcEnvironmentForClang(
  List<DetectedCompiler> compilers,
) {
  String? msvcScript;
  for (final DetectedCompiler compiler in compilers) {
    final String? script = compiler.environmentScript;
    if (compiler.kind == CompilerKind.msvc &&
        script != null &&
        script.isNotEmpty) {
      msvcScript = script;
      break;
    }
  }
  if (msvcScript == null) {
    return compilers;
  }
  return <DetectedCompiler>[
    for (final DetectedCompiler compiler in compilers)
      if (compiler.kind == CompilerKind.clang &&
          compiler.environmentScript == null)
        DetectedCompiler(
          kind: compiler.kind,
          version: compiler.version,
          executablePath: compiler.executablePath,
          environmentScript: msvcScript,
          extraPathEntries: compiler.extraPathEntries,
        )
      else
        compiler,
  ];
}

/// 按 [priority]（id 顺序，如 `['icx', 'clang', 'msvc']`）返回首个可用编译器。
DetectedCompiler? selectCompiler(
  List<DetectedCompiler> available,
  List<String> priority,
) {
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

/// 缓存条目是否仍可用：可执行文件存在，且声明了环境脚本时脚本也存在。
///
/// 探测路径在命中时已确认可执行文件存在，但缓存要跨会话复用；安装被移除/升级
/// 换路径后旧条目必须判失效，交由重检刷新，而不是把失效路径写进子进程环境。
bool isCompilerUsable(DetectedCompiler compiler) {
  if (compiler.executablePath.isEmpty) {
    return false;
  }
  if (!File(compiler.executablePath).existsSync()) {
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

  versionDirectories.sort(
    (String first, String second) => _compareVersionNames(second, first),
  );
  if (versionDirectories.isNotEmpty) {
    return _icxExecutableIn(oneApiRoot, versionDirectories.first);
  }
  return latestExecutable;
}

/// 新布局（2024+）为 `compiler/<目录>/bin/icx-cl.exe`，旧布局为
/// `compiler/<目录>/windows/bin/icx-cl.exe`；两者都探测，取先命中的布局。
String? _icxExecutableIn(String oneApiRoot, String compilerDirectoryName) {
  for (final String layout in const <String>['bin', 'windows/bin']) {
    final String executable = joinPath(
      oneApiRoot,
      'compiler/$compilerDirectoryName/$layout/icx-cl.exe',
    );
    if (File(executable).existsSync()) {
      return executable;
    }
  }
  return null;
}

int _compareVersionNames(String first, String second) {
  final List<String> firstParts = first.split('.');
  final List<String> secondParts = second.split('.');
  final int partCount = firstParts.length > secondParts.length
      ? firstParts.length
      : secondParts.length;
  for (var index = 0; index < partCount; index++) {
    final int firstValue = index < firstParts.length
        ? int.tryParse(firstParts[index]) ?? 0
        : 0;
    final int secondValue = index < secondParts.length
        ? int.tryParse(secondParts[index]) ?? 0
        : 0;
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
  final File versionFile = File(
    joinPath(
      installPath,
      'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt',
    ),
  );
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
  for (final String key in const <String>[
    'ProgramFiles(x86)',
    'ProgramFiles',
  ]) {
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
  return base == null || base.isEmpty
      ? null
      : joinPath(base, 'Microsoft Visual Studio/Installer/vswhere.exe');
}

/// 大小写不敏感的环境取值：`Platform.environment` 的 `[]` 在 Windows 上大小写
/// 不敏感、但其键迭代为全大写，经 `Map.of` 复制后普通 map 的精确查找会落空
/// （如 `ProgramFiles(x86)`）；这里显式做不敏感匹配，[environment] 可为副本。
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
