/// 编译器类型；设置页优先级与 `CNP_COMPILER_KIND` 使用 [compilerKindId] 的标识。
enum CompilerKind { icx, clangCl, msvc }

/// 编译器在设置页与 `CNP_COMPILER_KIND` 中使用的稳定标识。
String compilerKindId(CompilerKind kind) => switch (kind) {
  CompilerKind.icx => 'icx',
  CompilerKind.clangCl => 'clang-cl',
  CompilerKind.msvc => 'msvc',
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
