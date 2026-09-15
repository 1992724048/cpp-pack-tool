/// 编译器类型；设置页优先级与 `CNP_COMPILER_KIND` 使用 [compilerKindId] 的标识。
enum CompilerKind { icx, clangCl, msvc, mingw }

/// 编译器在设置页与 `CNP_COMPILER_KIND` 中使用的稳定标识。
String compilerKindId(CompilerKind kind) => switch (kind) {
  CompilerKind.icx => 'icx',
  CompilerKind.clangCl => 'clang-cl',
  CompilerKind.msvc => 'msvc',
  CompilerKind.mingw => 'mingw',
};

/// [compilerKindId] 的逆向映射（大小写不敏感、容忍首尾空白）；未知标识返回 null。
CompilerKind? compilerKindFromId(String id) {
  final String normalized = id.trim().toLowerCase();
  for (final CompilerKind kind in CompilerKind.values) {
    if (compilerKindId(kind) == normalized) {
      return kind;
    }
  }
  return null;
}

/// R23 曾短暂使用的 clang 驱动标识：该版本把 clang 系驱动换成 GNU `clang.exe`
/// （CXX 取 `clang++.exe`）并作为 `CNP_COMPILER_KIND`；现恢复 MSVC 兼容驱动
/// clang-cl（`clang-cl.exe`），标识 `clang-cl`。
///
/// 仅供配置迁移识别：R23 缓存条目指向 GNU 驱动，与 clang-cl 旗标体系不兼容
/// （`-mavx2`/`-O3` 等 GNU 风参数会被 clang-cl 拒绝），读回时必须丢弃并重检，
/// 不得映射为 [CompilerKind.clangCl]。
const String legacyGnuClangKindId = 'clang';

/// 标识是否为 R23 的 GNU clang 驱动（大小写不敏感、容忍首尾空白）。
bool isLegacyCompilerKindId(String id) =>
    id.trim().toLowerCase() == legacyGnuClangKindId;

/// 编译器在构建对话框与设置页中展示的名称。
///
/// MinGW 一个种类覆盖 MSYS2 多个子环境（UCRT64 / CLANG64 的 GCC 与 GNU ABI
/// clang、已弃用的 MINGW64），标签只署名家族、不署驱动；具体子环境由版本串的
/// 环境标注区分（如 `14.2.0（UCRT64）`）。
String compilerKindLabel(CompilerKind kind) => switch (kind) {
  CompilerKind.icx => 'ICX',
  CompilerKind.clangCl => 'clang-cl',
  CompilerKind.msvc => 'MSVC',
  CompilerKind.mingw => 'MinGW',
};

/// 检测到的编译器实例。
class DetectedCompiler {
  const DetectedCompiler({
    required this.kind,
    required this.version,
    required this.executablePath,
    this.cxxExecutablePath,
    required this.environmentScript,
    this.extraPathEntries = const <String>[],
  });

  final CompilerKind kind;

  /// 版本号，如 `2026.1.1` / `23.1.1` / `14.44.35207`。
  ///
  /// MinGW 条目的版本串附带 MSYS2 子环境标注（如 `14.2.0（UCRT64）`、
  /// `14.2.0（MINGW64，已弃用）`），供设置页与构建对话框识别具体环境；
  /// 其余种类为纯版本号。
  final String version;

  /// C 编译器驱动全路径。
  final String executablePath;

  /// C++ 编译器驱动全路径；null 表示与 [executablePath] 相同。
  ///
  /// ICX / clang-cl / MSVC 单驱动即双语言；MinGW 分设 `gcc.exe` / `g++.exe`
  /// （或 `clang.exe` / `clang++.exe`），C++ 目标必须用 C++ 驱动，否则链接
  /// 阶段不会带上 C++ 标准库。
  final String? cxxExecutablePath;

  /// 初始化环境的脚本（`setvars.bat` / `vcvars64.bat`）；无需则为 null。
  final String? environmentScript;

  /// 需要补入 PATH 的目录（如 LLVM bin、MSYS2 工具链 bin）。
  final List<String> extraPathEntries;

  /// 下发的 C++ 编译器路径（[cxxExecutablePath] 缺省回退 [executablePath]）。
  String get cxxCompilerPath => cxxExecutablePath ?? executablePath;
}
