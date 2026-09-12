import 'dart:io';

import 'package:cpp_nuget_pack/build/build_runner.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 编译器类型；设置页优先级与 `CNP_COMPILER_KIND` 使用 [compilerKindId] 的标识。
enum CompilerKind { icx, clangCl, msvc }

/// 编译器在设置页与 `CNP_COMPILER_KIND` 中使用的稳定标识。
String compilerKindId(CompilerKind kind) => switch (kind) {
  CompilerKind.icx => 'icx',
  CompilerKind.clangCl => 'clang-cl',
  CompilerKind.msvc => 'msvc',
};

/// 编译器在构建对话框与设置页中展示的名称。
String compilerKindLabel(CompilerKind kind) => switch (kind) {
  CompilerKind.icx => 'ICX',
  CompilerKind.clangCl => 'clang-cl',
  CompilerKind.msvc => 'MSVC',
};

/// 检测到的编译器实例。
class DetectedCompiler {
  const DetectedCompiler({
    required this.kind,
    required this.version,
    required this.executablePath,
    required this.environmentScript,
    this.extraPathEntries = const <String>[],
  });

  final CompilerKind kind;

  /// 版本号，如 `2026.1.1` / `23.1.1` / `14.44.35207`。
  final String version;

  /// 编译器驱动全路径。
  final String executablePath;

  /// 初始化环境的脚本（`setvars.bat` / `vcvars64.bat`）；无需则为 null。
  final String? environmentScript;

  /// 需要补入 PATH 的目录（如 LLVM bin）。
  final List<String> extraPathEntries;
}

final RegExp _icxVersionPattern = RegExp(r'Compiler\s+(\d+\.\d+\.\d+)');
final RegExp _clangVersionPattern = RegExp(r'clang version (\d+\.\d+\.\d+)');
final RegExp _lineSeparator = RegExp(r'\r?\n');
const String _vcToolsComponent =
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64';

/// 检测 Intel oneAPI ICX：取 `<oneApiRoot>/compiler/<最高版本|latest>/bin/icx-cl.exe`。
Future<DetectedCompiler?> detectIcx({
  PackProcessRunner runner = Process.run,
  required String oneApiRoot,
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

/// 检测 `<llvmBinDir>/clang-cl.exe` 的版本。
Future<DetectedCompiler?> detectClangCl({
  PackProcessRunner runner = Process.run,
  required String llvmBinDir,
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
Future<DetectedCompiler?> detectMsvc({
  PackProcessRunner runner = Process.run,
  required String vswherePath,
}) async {
  final String? installPath = await _queryVswhereInstallation(
    runner,
    vswherePath,
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

/// 检测本机可用编译器，顺序固定为 ICX → clang-cl → MSVC。
///
/// 默认路径从 `ProgramFiles`/`ProgramFiles(x86)` 环境推导；
/// [oneApiRoot]/[llvmBinDir]/[vswherePath] 用于测试或自定义位置覆盖。
Future<List<DetectedCompiler>> detectCompilers({
  PackProcessRunner runner = Process.run,
  String? oneApiRoot,
  String? llvmBinDir,
  String? vswherePath,
}) async {
  final List<DetectedCompiler> compilers = <DetectedCompiler>[];

  final List<String> oneApiRoots = oneApiRoot == null
      ? _defaultOneApiRoots()
      : <String>[oneApiRoot];
  for (final String root in oneApiRoots) {
    final DetectedCompiler? icx = await detectIcx(
      runner: runner,
      oneApiRoot: root,
    );
    if (icx != null) {
      compilers.add(icx);
      break;
    }
  }

  final String? llvmBin = llvmBinDir ?? _defaultLlvmBinDir();
  if (llvmBin != null) {
    final DetectedCompiler? clangCl = await detectClangCl(
      runner: runner,
      llvmBinDir: llvmBin,
    );
    if (clangCl != null) {
      compilers.add(clangCl);
    }
  }

  final String? vswhere = vswherePath ?? _defaultVswherePath();
  if (vswhere != null) {
    final DetectedCompiler? msvc = await detectMsvc(
      runner: runner,
      vswherePath: vswhere,
    );
    if (msvc != null) {
      compilers.add(msvc);
    }
  }

  return _inheritMsvcEnvironmentForClangCl(compilers);
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
    final String executable = joinPath(
      oneApiRoot,
      'compiler/$name/bin/icx-cl.exe',
    );
    if (!File(executable).existsSync()) {
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
    return joinPath(
      oneApiRoot,
      'compiler/${versionDirectories.first}/bin/icx-cl.exe',
    );
  }
  return latestExecutable;
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
}) async {
  final ProcessResult result;
  try {
    result = await runner(executable, arguments);
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
  String vswherePath,
) async {
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
    ]);
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

List<String> _defaultOneApiRoots() {
  final Map<String, String> environment = Platform.environment;
  final List<String> roots = <String>[];
  for (final String key in const <String>[
    'ProgramFiles(x86)',
    'ProgramFiles',
  ]) {
    final String? base = environment[key];
    if (base != null && base.isNotEmpty) {
      roots.add(joinPath(base, 'Intel/oneAPI'));
    }
  }
  return roots;
}

String? _defaultLlvmBinDir() {
  final String? base = Platform.environment['ProgramFiles'];
  return base == null || base.isEmpty ? null : joinPath(base, 'LLVM/bin');
}

String? _defaultVswherePath() {
  final String? base = Platform.environment['ProgramFiles(x86)'];
  return base == null || base.isEmpty
      ? null
      : joinPath(base, 'Microsoft Visual Studio/Installer/vswhere.exe');
}
