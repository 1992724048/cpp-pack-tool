enum CompilerKind { icx, clangCl, msvc }

String compilerKindId(CompilerKind kind) => switch (kind) {
  CompilerKind.icx => 'icx',
  CompilerKind.clangCl => 'clang-cl',
  CompilerKind.msvc => 'msvc',
};

CompilerKind? compilerKindFromId(String id) {
  final String normalized = id.trim().toLowerCase();
  for (final CompilerKind kind in CompilerKind.values) {
    if (compilerKindId(kind) == normalized) {
      return kind;
    }
  }
  return null;
}

const String legacyGnuClangKindId = 'clang';

bool isLegacyCompilerKindId(String id) => id.trim().toLowerCase() == legacyGnuClangKindId;

String compilerKindLabel(CompilerKind kind) => switch (kind) {
  CompilerKind.icx => 'ICX',
  CompilerKind.clangCl => 'clang-cl',
  CompilerKind.msvc => 'MSVC',
};

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
  final String version;
  final String executablePath;
  final String? cxxExecutablePath;
  final String? environmentScript;
  final List<String> extraPathEntries;

  String get cxxCompilerPath => cxxExecutablePath ?? executablePath;
}
