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
