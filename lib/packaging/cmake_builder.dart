import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// CMake find_package 配置包构建器。
///
/// 头文件与模块映射到 `include/<源目录名>/`；lib/dll/pdb 映射到 `lib/`；
/// 其余文件映射到 `files/`。另生成 `lib/cmake/<包名>/` 下的 Config、Targets
/// 与（版本号为数字时的）ConfigVersion 三件套。
class CMakePackageBuilder implements PackageBuilder {
  const CMakePackageBuilder();

  static const String _includePrefix = 'include';
  static const String _libPrefix = 'lib';
  static const String _filesPrefix = 'files';
  static final RegExp _pathSeparator = RegExp(r'[/\\]');
  static final RegExp _numericVersion = RegExp(r'^\d+(\.\d+){1,3}$');

  @override
  String get id => 'cmake';

  @override
  String get displayName => 'CMake';

  @override
  Future<PackagePlan> buildPlan(PackModel pack) async {
    final List<PackageEntry> fileEntries = <PackageEntry>[];
    for (final FileModel file in pack.files) {
      final String? packagePath = _packagePath(pack, file);
      if (packagePath == null) {
        continue;
      }
      fileEntries.add(
        PackageEntry(
          packagePath: packagePath,
          source: PackageFileSource(
            path: file.path,
            isBinary: _isBinaryType(file.type),
            size: file.size,
          ),
        ),
      );
    }

    final String version = NuGetPackageBuilder.normalizedVersion(pack.version);
    return PackagePlan(
      entries: <PackageEntry>[
        ...fileEntries,
        PackageEntry(
          packagePath: _cmakePath(pack.name, 'Config.cmake'),
          source: PackageGeneratedSource(content: _configContent(pack.name)),
        ),
        PackageEntry(
          packagePath: _cmakePath(pack.name, 'Targets.cmake'),
          source: PackageGeneratedSource(
            content: _targetsContent(pack.name, fileEntries),
          ),
        ),
        if (_numericVersion.hasMatch(version))
          PackageEntry(
            packagePath: _cmakePath(pack.name, 'ConfigVersion.cmake'),
            source: PackageGeneratedSource(
              content: _configVersionContent(version),
            ),
          ),
      ],
    );
  }

  static String? _packagePath(PackModel pack, FileModel file) {
    final String path = _normalizePath(file.path);
    if (path.isEmpty) {
      return null;
    }
    return switch (file.type) {
      FileType.header || FileType.module =>
        '$_includePrefix/${_includeNamespace(pack)}/'
            '${_withoutLeadingSegment(path, const <String>['include'])}',
      FileType.lib || FileType.dll || FileType.pdb =>
        '$_libPrefix/${_withoutLeadingSegment(path, const <String>['lib', 'bin'])}',
      _ => '$_filesPrefix/$path',
    };
  }

  /// 头文件顶层命名空间目录：源目录文件夹名，缺失时回退为包名。
  static String _includeNamespace(PackModel pack) {
    final String sourcePath = pack.sourcePath ?? '';
    final String folder = sourcePath.isEmpty ? '' : baseName(sourcePath);
    return folder.isEmpty ? pack.name : folder;
  }

  static bool _isBinaryType(FileType type) => switch (type) {
    FileType.lib || FileType.dll || FileType.pdb || FileType.executable => true,
    _ => false,
  };

  static String _normalizePath(String path) => path
      .split(_pathSeparator)
      .where((String segment) => segment.isNotEmpty)
      .join('/');

  static String _withoutLeadingSegment(String path, List<String> prefixes) {
    final int separator = path.indexOf('/');
    if (separator <= 0) {
      return path;
    }
    if (!prefixes.contains(path.substring(0, separator).toLowerCase())) {
      return path;
    }
    return path.substring(separator + 1);
  }

  static String _cmakePath(String name, String fileName) =>
      'lib/cmake/$name/$name$fileName';

  static String _configContent(String name) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('macro(check_required_components _NAME)')
      ..writeln(r'  foreach(comp ${${_NAME}_FIND_COMPONENTS})')
      ..writeln(r'    if(NOT ${_NAME}_${comp}_FOUND)')
      ..writeln(r'      if(${_NAME}_FIND_REQUIRED_${comp})')
      ..writeln(r'        set(${_NAME}_FOUND FALSE)')
      ..writeln('      endif()')
      ..writeln('    endif()')
      ..writeln('  endforeach()')
      ..writeln('endmacro()')
      ..writeln()
      ..writeln('if(NOT TARGET $name::$name)')
      ..writeln('  include("\${CMAKE_CURRENT_LIST_DIR}/${name}Targets.cmake")')
      ..writeln('endif()')
      ..writeln()
      ..writeln('check_required_components($name)');
    return buffer.toString();
  }

  static String _targetsContent(String name, List<PackageEntry> fileEntries) {
    final List<String> debugLibraries = <String>[];
    final List<String> releaseLibraries = <String>[];
    for (final PackageEntry entry in fileEntries) {
      if (!entry.packagePath.toLowerCase().endsWith('.lib')) {
        continue;
      }
      final String library = '\${_IMPORT_PREFIX}/${entry.packagePath}';
      if (inferBuildLabel(entry.packagePath) == debugBuildLabel) {
        debugLibraries.add(library);
      } else {
        releaseLibraries.add(library);
      }
    }
    debugLibraries.sort(comparePackagePaths);
    releaseLibraries.sort(comparePackagePaths);

    final StringBuffer buffer = StringBuffer()
      ..writeln(
        r'get_filename_component(_IMPORT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)',
      )
      ..writeln(
        r'get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)',
      )
      ..writeln(
        r'get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)',
      )
      ..writeln(
        r'get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)',
      )
      ..writeln('if(_IMPORT_PREFIX STREQUAL "/")')
      ..writeln(r'  set(_IMPORT_PREFIX "")')
      ..writeln('endif()')
      ..writeln()
      ..writeln('add_library($name::$name INTERFACE IMPORTED)')
      ..writeln()
      ..writeln('# DLL 需消费方自行拷贝（INTERFACE 目标不支持自动运行时收集）')
      ..writeln('set_target_properties($name::$name PROPERTIES')
      ..writeln(r'  INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"');
    final String? libraries = _linkLibraries(debugLibraries, releaseLibraries);
    if (libraries != null) {
      buffer.writeln('  INTERFACE_LINK_LIBRARIES "$libraries"');
    }
    buffer
      ..writeln(')')
      ..writeln()
      ..writeln('set(_IMPORT_PREFIX)');
    return buffer.toString();
  }

  static String? _linkLibraries(
    List<String> debugLibraries,
    List<String> releaseLibraries,
  ) {
    if (debugLibraries.isEmpty && releaseLibraries.isEmpty) {
      return null;
    }
    if (debugLibraries.isEmpty) {
      return releaseLibraries.join(';');
    }
    if (releaseLibraries.isEmpty) {
      return debugLibraries.join(';');
    }
    return '\$<\$<CONFIG:Debug>:${debugLibraries.join(';')}>'
        '\$<\$<NOT:\$<CONFIG:Debug>>:${releaseLibraries.join(';')}>';
  }

  static String _configVersionContent(String version) {
    // find_package 不向版本文件提供 PACKAGE_VERSION_MAJOR，需自行设置才能完成同主版本比较。
    final String major = _majorVersion(version);
    final StringBuffer buffer = StringBuffer()
      ..writeln('set(PACKAGE_VERSION "$version")')
      ..writeln('set(PACKAGE_VERSION_MAJOR "$major")')
      ..writeln()
      ..writeln('if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)')
      ..writeln('  set(PACKAGE_VERSION_COMPATIBLE FALSE)')
      ..writeln('else()')
      ..writeln(
        '  if(PACKAGE_FIND_VERSION_MAJOR STREQUAL PACKAGE_VERSION_MAJOR)',
      )
      ..writeln('    set(PACKAGE_VERSION_COMPATIBLE TRUE)')
      ..writeln('  else()')
      ..writeln('    set(PACKAGE_VERSION_COMPATIBLE FALSE)')
      ..writeln('  endif()')
      ..writeln('  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)')
      ..writeln('    set(PACKAGE_VERSION_EXACT TRUE)')
      ..writeln('  endif()');
    buffer.writeln('endif()');
    return buffer.toString();
  }

  /// 数字版本的主版本号，并规范化前导零（`01` → `1`），与 CMake 版本组件比较规则一致。
  static String _majorVersion(String version) =>
      version.split('.').first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
}
