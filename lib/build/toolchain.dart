import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';

export 'package:cpp_nuget_pack/models/compiler_model.dart';

final RegExp _icxVersionPattern = RegExp(r'Compiler\s+(\d+\.\d+\.\d+)');
final RegExp _clangVersionPattern = RegExp(r'clang version (\d+\.\d+\.\d+)');
final RegExp _lineSeparator = RegExp(r'\r?\n');

/// `-dumpfullversion` / `-dumpversion` 输出：纯数字点分段（段数不定）。
final RegExp _versionOutputPattern = RegExp(r'^(\d+(?:\.\d+){0,3})$');

/// `--version` 横幅中的版本 token（要求至少含一个点，防误取其它数字）。
final RegExp _versionTokenPattern = RegExp(r'\d+(?:\.\d+)+');
const String _vcToolsComponent =
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64';

/// MSYS2 默认安装根；非标准安装可经环境变量 `MSYS2_ROOT` 或把工具链 bin
/// 加入 PATH 覆盖。
const String _defaultMsys2RootPath = r'C:\msys64';

/// MSYS2 子环境候选（固定顺序）：UCRT64（默认推荐，GCC）→ CLANG64（GNU ABI
/// clang）→ MINGW64（GCC，已弃用）。
///
/// MINGW64 自 2026-03 起被 MSYS2 弃用，仍检测但版本串标注「已弃用」，仅在
/// 前两者缺失时采用。CLANG64 排在 MINGW64 之前：其 clang 为 GNU ABI
/// （`x86_64-w64-windows-gnu`）、接受同一组 GNU 风格构建旗标，且属维护中的
/// 官方环境。
const List<({String prefix, String cExecutable, String tag})>
_msys2Environments = <({String prefix, String cExecutable, String tag})>[
  (prefix: 'ucrt64', cExecutable: 'gcc.exe', tag: 'UCRT64'),
  (prefix: 'clang64', cExecutable: 'clang.exe', tag: 'CLANG64'),
  (prefix: 'mingw64', cExecutable: 'gcc.exe', tag: 'MINGW64，已弃用'),
];

/// 检测 Intel oneAPI ICX：取 `<oneApiRoot>/compiler/<最高版本|latest>/` 下
/// `bin/icx.exe`（2024+ 布局，优先）或 `windows/bin/icx.exe`（旧布局）；驱动缺失时
/// 回退旧名 `icx-cl.exe`（兼容更早安装）。
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

/// 检测 `<llvmBinDir>/clang-cl.exe`（MSVC 兼容驱动）的版本。
///
/// clang-cl 是 MSVC 旗标体系的 clang 驱动：驱动 CMake+Ninja 时与 MSVC 一致
/// （见 `cnp_build_support.py`），GNU `clang.exe`/`clang++` 驱动不作为本入口
/// 的候选（R23 的 GNU 驱动回退记录见 `compiler_model.dart`）；GNU ABI 的
/// clang（MSYS2 CLANG64）由 [detectMingw] 按 MinGW 家族检测。
/// [environment] 为版本探测子进程的环境；null 时继承宿主环境。
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

/// 检测 MinGW / MSYS2 工具链（GCC 或 MSYS2 CLANG64 的 GNU ABI clang）。
///
/// [binDir] 为工具链 bin 目录（如 `C:\msys64\ucrt64\bin`）；[cExecutableName]
/// 为 C 驱动文件名（`gcc.exe` / `clang.exe`）。判定经 `-dumpmachine` 复核目标
/// 三元组必须为 MinGW 家族（x86_64 且含 `w64` 与 `mingw`，或含 `windows-gnu`）
/// ——MSVC 目标的 clang（如 LLVM 官方发行版，`x86_64-pc-windows-msvc`）与
/// CLANG64 中被复制的 `gcc.exe`（实为 clang）都按真实三元组归类，不靠名字猜。
///
/// 版本探测按 `-dumpfullversion`（GCC 恒三段）→ `-dumpversion`（段数不定）→
/// `--version` 首行最后一个版本 token 的顺序回退。C++ 驱动取同目录
/// `g++.exe` / `clang++.exe`（缺失时 [DetectedCompiler.cxxExecutablePath]
/// 留空、回退 C 驱动）。MinGW 无 vcvars 等价脚本（`environmentScript` 恒
/// null、绝不继承 MSVC 环境），工具链 bin 目录经 [DetectedCompiler.extraPathEntries]
/// 前置 PATH（windres 依赖 PATH 解析同目录 gcc）；RC 编译器由环境装配从 C
/// 驱动同目录解析（见 `build_environment.dart`）。
///
/// [environmentTag] 非空时附加到版本串（如 `14.2.0（UCRT64）`），供 UI 区分
/// 具体 MSYS2 子环境；[environment] 为探测子进程的环境，null 时继承宿主环境。
Future<DetectedCompiler?> detectMingw({
  PackProcessRunner runner = Process.run,
  required String binDir,
  String cExecutableName = 'gcc.exe',
  String? environmentTag,
  Map<String, String>? environment,
}) async {
  final String executable = joinPath(binDir, cExecutableName);
  if (!File(executable).existsSync()) {
    return null;
  }
  final String? machine = await _probeOutput(
    runner: runner,
    executable: executable,
    arguments: const <String>['-dumpmachine'],
    environment: environment,
  );
  if (machine == null || !_isMingwMachine(machine)) {
    return null;
  }
  final String? version = await _probeMingwVersion(
    runner: runner,
    executable: executable,
    environment: environment,
  );
  if (version == null) {
    return null;
  }
  return DetectedCompiler(
    kind: CompilerKind.mingw,
    version: environmentTag == null ? version : '$version（$environmentTag）',
    executablePath: executable,
    cxxExecutablePath: _mingwCxxExecutable(binDir, cExecutableName),
    environmentScript: null,
    extraPathEntries: <String>[binDir],
  );
}

/// `-dumpmachine` 输出是否为 x64 MinGW 家族三元组（`x86_64-w64-mingw32`、
/// `x86_64-w64-windows-gnu`）；i686 / aarch64 等架构不适配「只构建 x64」的
/// 管线约定，不接受。
bool _isMingwMachine(String machine) {
  final String normalized = machine.trim().toLowerCase();
  if (!normalized.startsWith('x86_64')) {
    return false;
  }
  if (normalized.contains('windows-gnu')) {
    return true;
  }
  return normalized.contains('w64') && normalized.contains('mingw');
}

/// MinGW 工具链的 C++ 驱动路径：按 C 驱动名映射同目录 `g++.exe` /
/// `clang++.exe`；映射不出或文件缺失时返回 null（调用方回退 C 驱动）。
String? _mingwCxxExecutable(String binDir, String cExecutableName) {
  final String lowered = cExecutableName.toLowerCase();
  final String? cxxName;
  if (lowered == 'gcc.exe' || lowered == 'gcc') {
    cxxName = 'g++.exe';
  } else if (lowered == 'clang.exe' || lowered == 'clang') {
    cxxName = 'clang++.exe';
  } else {
    cxxName = null;
  }
  if (cxxName == null) {
    return null;
  }
  final String cxxExecutable = joinPath(binDir, cxxName);
  return File(cxxExecutable).existsSync() ? cxxExecutable : null;
}

/// 依 `-dumpfullversion` → `-dumpversion` → `--version` 首行解析 MinGW 版本。
Future<String?> _probeMingwVersion({
  required PackProcessRunner runner,
  required String executable,
  Map<String, String>? environment,
}) async {
  for (final String argument in const <String>[
    '-dumpfullversion',
    '-dumpversion',
  ]) {
    final String? output = await _probeOutput(
      runner: runner,
      executable: executable,
      arguments: <String>[argument],
      environment: environment,
    );
    final RegExpMatch? match = output == null
        ? null
        : _versionOutputPattern.firstMatch(output);
    if (match != null) {
      return match.group(1);
    }
  }
  final String? banner = await _probeOutput(
    runner: runner,
    executable: executable,
    arguments: const <String>['--version'],
    environment: environment,
  );
  return banner == null ? null : _lastVersionToken(banner);
}

/// 取文本中最后一个版本 token（要求至少含一个点），如
/// `gcc (Rev2, Built by MSYS2 project) 14.2.0` → `14.2.0`。
String? _lastVersionToken(String text) {
  RegExpMatch? last;
  for (final RegExpMatch match in _versionTokenPattern.allMatches(text)) {
    last = match;
  }
  return last?.group(0);
}

/// 检测本机可用编译器，顺序固定为 ICX → clang-cl → MSVC → MinGW。
///
/// 默认查找位置（`%ONEAPI_ROOT%`、`ProgramFiles(x86)`/`ProgramFiles` 下的
/// oneAPI 与 LLVM、vswhere、`MSYS2_ROOT` 或默认 `C:\msys64`、PATH 兜底）从
/// [environment]（缺省 `Platform.environment`）推导，并作为各版本探测子进程
/// 的环境透传（如受控 `TMP`/`TEMP`）；[oneApiRoot]/[llvmBinDir]/[vswherePath]/
/// [msys2Root] 用于测试或自定义位置覆盖（[msys2Root] 非空时覆盖默认 MSYS2
/// 根；固定子环境全部缺失后仍回退 PATH 扫描）。
Future<List<DetectedCompiler>> detectCompilers({
  PackProcessRunner runner = Process.run,
  String? oneApiRoot,
  String? llvmBinDir,
  String? vswherePath,
  String? msys2Root,
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
    final DetectedCompiler? clangCl = await detectClangCl(
      runner: runner,
      llvmBinDir: llvmBin,
      environment: env,
    );
    if (clangCl != null) {
      compilers.add(clangCl);
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

  await _detectMingwCandidates(
    runner: runner,
    environment: env,
    msys2Root: msys2Root,
    compilers: compilers,
  );

  return _inheritMsvcEnvironmentForClangCl(compilers);
}

/// 追加 MinGW / MSYS2 检测：固定子环境（[msys2Root] 或 `MSYS2_ROOT` 或默认
/// `C:\msys64`，按 `_msys2Environments` 顺序）优先，全部缺失时回退 PATH
/// （`gcc` → `clang`，经 `-dumpmachine` 复核）。
///
/// PATH 兜底不读 `MSYSTEM`：GUI 进程通常不带该变量，且固定顺序更可预期；
/// 非标准安装根可经 `MSYS2_ROOT` 覆盖或把工具链 bin 加入 PATH。
Future<void> _detectMingwCandidates({
  required PackProcessRunner runner,
  required Map<String, String> environment,
  required String? msys2Root,
  required List<DetectedCompiler> compilers,
}) async {
  final String root = msys2Root ?? _defaultMsys2Root(environment);
  for (final ({String prefix, String cExecutable, String tag}) candidate
      in _msys2Environments) {
    final DetectedCompiler? mingw = await detectMingw(
      runner: runner,
      binDir: joinPath(joinPath(root, candidate.prefix), 'bin'),
      cExecutableName: candidate.cExecutable,
      environmentTag: candidate.tag,
      environment: environment,
    );
    if (mingw != null) {
      compilers.add(mingw);
      return;
    }
  }
  for (final String name in const <String>['gcc.exe', 'clang.exe']) {
    final String? executable = _findExecutableInPath(environment, name);
    if (executable == null) {
      continue;
    }
    final DetectedCompiler? mingw = await detectMingw(
      runner: runner,
      binDir: parentDirectory(executable),
      cExecutableName: name,
      environmentTag: _msys2TagForExecutable(executable),
      environment: environment,
    );
    if (mingw != null) {
      compilers.add(mingw);
      return;
    }
  }
}

String _defaultMsys2Root(Map<String, String> environment) {
  final String? declared = _environmentValue(environment, 'MSYS2_ROOT');
  if (declared != null && declared.trim().isNotEmpty) {
    return declared.trim();
  }
  return _defaultMsys2RootPath;
}

/// 在 [environment] 的 PATH 中（大小写不敏感取键、容忍引号条目）查找可执行
/// 文件，返回首个命中的完整路径。
String? _findExecutableInPath(
  Map<String, String> environment,
  String executableName,
) {
  final String? pathValue = _environmentValue(environment, 'Path');
  if (pathValue == null || pathValue.isEmpty) {
    return null;
  }
  for (final String rawEntry in pathValue.split(';')) {
    final String entry = rawEntry.trim().replaceAll('"', '');
    if (entry.isEmpty) {
      continue;
    }
    final String candidate = joinPath(entry, executableName);
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// 从 PATH 解析出的可执行路径推断 MSYS2 子环境标注
/// （`.../ucrt64/bin/gcc.exe` → `UCRT64`）；结构不匹配已知子环境时返回 null
/// （版本串不带标注）。
String? _msys2TagForExecutable(String executablePath) {
  final List<String> segments = executablePath.split(RegExp(r'[/\\]'));
  if (segments.length < 3) {
    return null;
  }
  if (segments[segments.length - 2].toLowerCase() != 'bin') {
    return null;
  }
  return switch (segments[segments.length - 3].toLowerCase()) {
    'ucrt64' => 'UCRT64',
    'clang64' => 'CLANG64',
    'mingw64' => 'MINGW64，已弃用',
    _ => null,
  };
}

/// MSVC 的 `vcvars64.bat` 同时提供 clang-cl 所需的 INCLUDE/LIB；检测结果中
/// clang-cl 无环境脚本且存在带非空脚本的 MSVC 条目时，clang-cl 继承该脚本。
List<DetectedCompiler> _inheritMsvcEnvironmentForClangCl(
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
      if (compiler.kind == CompilerKind.clangCl &&
          compiler.environmentScript == null)
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

/// 按 [priority]（id 顺序，如 `['icx', 'clang-cl', 'msvc']`）返回首个可用编译器。
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
/// MinGW 条目同时校验 C++ 驱动（[DetectedCompiler.cxxExecutablePath]）。
bool isCompilerUsable(DetectedCompiler compiler) {
  if (compiler.executablePath.isEmpty) {
    return false;
  }
  if (!File(compiler.executablePath).existsSync()) {
    return false;
  }
  final String? cxxExecutable = compiler.cxxExecutablePath;
  if (cxxExecutable != null &&
      cxxExecutable.isNotEmpty &&
      !File(cxxExecutable).existsSync()) {
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

/// 新布局（2024+）为 `compiler/<目录>/bin/icx[,-cl].exe`，旧布局为
/// `compiler/<目录>/windows/bin/icx[,-cl].exe`；两者都探测，取先命中的布局。
///
/// R23 起优先 GNU 接口驱动 `icx.exe`（`icx`/`icx-cl` 双风格均兼容，构建旗标
/// `/O3 ...` 已实证）；仅当安装中缺失 `icx.exe` 时回退旧名 `icx-cl.exe`。
String? _icxExecutableIn(String oneApiRoot, String compilerDirectoryName) {
  for (final String layout in const <String>['bin', 'windows/bin']) {
    for (final String name in const <String>['icx.exe', 'icx-cl.exe']) {
      final String executable = joinPath(
        oneApiRoot,
        'compiler/$compilerDirectoryName/$layout/$name',
      );
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

/// 执行探测并返回 stdout 首个非空行（退出码非零、无法启动或输出为空时返回
/// null）——用于 `-dumpmachine`、`--version` 等无固定模式的多步探测。
Future<String?> _probeOutput({
  required PackProcessRunner runner,
  required String executable,
  required List<String> arguments,
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
  final String line = _firstNonEmptyLine('${result.stdout}');
  return line.isEmpty ? null : line;
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
