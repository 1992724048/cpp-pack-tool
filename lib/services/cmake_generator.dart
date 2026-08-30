/// CMake 包配置生成器：将 [PackProject] 渲染为 CMake 包配置文件
/// （`{packageId}Config.cmake`）。为纯函数，可单测；只生成 config 文件内容，
/// 不做 CMake 安装/导出逻辑。
///
/// 生成产物供消费方通过 `find_package({id} CONFIG)` 使用：
/// - 头部用 [CompileConfig] 导出宏（INTERFACE_COMPILE_DEFINITIONS）、附加依赖
///   （INTERFACE_LINK_LIBRARIES，`.lib`/`.a` 转 CMake 名）与语言标准
///   （INTERFACE_COMPILE_FEATURES）。
/// - 头文件统一暴露为 `${CMAKE_CURRENT_LIST_DIR}/include`。
/// - 库映射（静态/动态）按配置输出 `IMPORTED_LOCATION_DEBUG/RELEASE`，路径剥离
///   `build\native\` 前缀后相对 `${CMAKE_CURRENT_LIST_DIR}`。
library;

import '../models/pack_project.dart';
import 'path_utils.dart';

/// CMake 生成产物：包内相对路径 + 内容。
typedef CmakeOutputFile = ({String path, String content});

/// 生成 CMake 包配置文件的包内条目列表（当前仅一条 `{id}Config.cmake`）。
///
/// 供 UI「导出 CMake 包」按钮消费——直接将这些文件写到 `{输出目录}\build\cmake\`
/// 下即可。当前只生成 config 文件，不生成版本文件（`{id}ConfigVersion.cmake`）。
List<CmakeOutputFile> generateCmakeEntries(PackProject project) {
  final id = _safeId(project);
  return [(path: '${id}Config.cmake', content: generateCmakeConfig(project))];
}

/// 生成 `{id}Config.cmake` 文本。
///
/// [id] 取自 [PackProject.packageId]。仅当存在库映射时输出 `add_library(IMPORTED)`；
/// 仅有头文件（无库）时输出 `add_library(INTERFACE IMPORTED)`。数据/可执行/源码
/// 映射不进入 CMake（源码由消费方自行编译或静态链接，数据与可执行文件不适合
/// imported target 表达）。
String generateCmakeConfig(PackProject project) {
  final id = _safeId(project);
  final compile = project.compileConfig;
  final target = '$id::$id';
  final hasHeaders = project.sourceDirs.any(
    (dir) => dir.mappings.any((m) => m.isHeaderMapping),
  );
  final libs = _cmakeLibMappings(project);
  final importedKind = _cmakeImportedKind(libs);

  final sb = StringBuffer()
    ..writeln('# $id CMake 包配置文件（C++ NuGet 打包工具自动生成，请勿手改）');

  if (importedKind == 'STATIC' || importedKind == 'SHARED') {
    sb.writeln('add_library($target $importedKind IMPORTED)');
    final seenConfig = <String>{};
    for (final lib in libs) {
      if (!seenConfig.add(lib.config)) continue;
      final key = _cmakeConfigKey(lib.config);
      sb.writeln(
        'set_target_properties($target PROPERTIES '
        'IMPORTED_LOCATION_$key "${_cmakeLocation(lib.target, lib.fileName)}")',
      );
    }
  } else {
    sb.writeln('add_library($target INTERFACE IMPORTED)');
  }

  sb.writeln('set_target_properties($target PROPERTIES');
  if (hasHeaders) {
    sb.writeln(
      '  INTERFACE_INCLUDE_DIRECTORIES '
      r'"${CMAKE_CURRENT_LIST_DIR}/include"',
    );
  }
  final defines = _cmakeDefines(compile);
  if (defines.isNotEmpty) {
    sb.writeln('  INTERFACE_COMPILE_DEFINITIONS "${defines.join(';')}"');
  }
  final linkLibs = _cmakeLinkLibraries(compile.additionalDependencies);
  if (linkLibs.isNotEmpty) {
    sb.writeln('  INTERFACE_LINK_LIBRARIES "${linkLibs.join(';')}"');
  }
  final feature = _cmakeCompileFeature(compile.languageStandard);
  if (feature != null) {
    sb.writeln('  INTERFACE_COMPILE_FEATURES $feature');
  }
  sb.writeln(')');
  return sb.toString();
}

/// 派生的库映射 tuple：配置名 + 包内 target + 文件名 + 库类别。
typedef _CmakeLibMapping = ({
  String config,
  String target,
  String fileName,
  String kind,
});

/// 收集所有库映射（staticLibrary/dynamicLibrary），并为其推导配置名。
List<_CmakeLibMapping> _cmakeLibMappings(PackProject project) {
  final result = <_CmakeLibMapping>[];
  for (final sourceDir in project.sourceDirs) {
    for (final mapping in sourceDir.mappings) {
      final kind = mapping.fileKind;
      if (kind != 'staticLibrary' && kind != 'dynamicLibrary') continue;
      final config = _configFromTarget(mapping.target) ?? 'Debug';
      result.add((
        config: config,
        target: mapping.target,
        fileName: basenameOf(mapping.srcGlob),
        kind: kind,
      ));
    }
  }
  return result;
}

/// 决定 imported target 的类别：任一动态库 → SHARED；否则有静态库 → STATIC；
/// 都无 → INTERFACE（仅头文件）。
String _cmakeImportedKind(List<_CmakeLibMapping> libs) {
  if (libs.any((l) => l.kind == 'dynamicLibrary')) return 'SHARED';
  if (libs.isNotEmpty) return 'STATIC';
  return 'INTERFACE';
}

/// 从包内 target（如 `build\native\lib\x64\Debug`）推导配置名。
String? _configFromTarget(String target) {
  if (target.trim().isEmpty) return null;
  for (final segment in normalizeSeparators(target.trim()).split('\\')) {
    final s = segment.toLowerCase();
    if (s == 'debug') return 'Debug';
    if (s == 'release' ||
        s == 'reldebug' ||
        s == 'relwithdebinfo' ||
        s == 'minsizerel' ||
        s == 'profile') {
      return 'Release';
    }
  }
  return null;
}

/// 生成 `IMPORTED_LOCATION_<CONFIG>` 属性值：`${CMAKE_CURRENT_LIST_DIR}/{相对段}/{文件}`。
///
/// [target] 为包内路径，剥离 `build\native\` 前缀后得到相对包根的段（如
/// `lib\x64\Debug`），换算为正斜杠后拼到 `${CMAKE_CURRENT_LIST_DIR}` 下。
String _cmakeLocation(String target, String fileName) {
  final stripped = stripMsBuildNativeRoot(target);
  final rel = stripped.isEmpty
      ? fileName
      : '${stripped.replaceAll('\\', '/')}/$fileName';
  const listDir = r'${CMAKE_CURRENT_LIST_DIR}';
  return '$listDir/$rel';
}

/// 配置名 → CMake config 键（`Debug`→`DEBUG`、`Release`→`RELEASE`）。
String _cmakeConfigKey(String config) {
  final lower = config.toLowerCase();
  if (lower == 'debug') return 'DEBUG';
  if (lower == 'release') return 'RELEASE';
  return config.toUpperCase();
}

/// 收集全局 + 分配置的预处理宏（去重、保序）。
List<String> _cmakeDefines(CompileConfig compile) {
  final seen = <String>{};
  final result = <String>[];
  void addAll(String value) {
    for (final token in value.split(';')) {
      final trimmed = token.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) result.add(trimmed);
    }
  }

  addAll(compile.preprocessorDefines);
  for (final configValue in compile.configDefines.values) {
    addAll(configValue);
  }
  return result;
}

/// 附加依赖转 CMake 名：`ws2_32.lib`→`ws2_32`、`lib.a`→`lib`，去重保序。
List<String> _cmakeLinkLibraries(String additionalDependencies) {
  final seen = <String>{};
  final result = <String>[];
  for (final token in additionalDependencies.split(';')) {
    var name = token.trim();
    if (name.isEmpty) continue;
    final lower = name.toLowerCase();
    if (lower.endsWith('.lib')) {
      name = name.substring(0, name.length - 4);
    } else if (lower.endsWith('.a')) {
      name = name.substring(0, name.length - 2);
    }
    if (name.startsWith('"') && name.endsWith('"')) {
      name = name.substring(1, name.length - 1);
    }
    if (name.isNotEmpty && seen.add(name)) result.add(name);
  }
  return result;
}

/// 语言标准 → CMake `INTERFACE_COMPILE_FEATURES`（`stdcpp23`/`stdcpplatest`→
/// `cxx_std_23`）；未知标准返回 null（不输出该属性）。
String? _cmakeCompileFeature(String languageStandard) {
  switch (languageStandard.trim().toLowerCase()) {
    case 'stdcpp14':
      return 'cxx_std_14';
    case 'stdcpp17':
      return 'cxx_std_17';
    case 'stdcpp20':
      return 'cxx_std_20';
    case 'stdcpp23':
    case 'stdcpplatest':
      return 'cxx_std_23';
    default:
      return null;
  }
}

/// 从包 id 派生安全的 target/文件名主体（空白时回退 `Package`）。
String _safeId(PackProject project) {
  final id = project.packageId.trim();
  return id.isEmpty ? 'Package' : id;
}
