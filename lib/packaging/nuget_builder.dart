import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';

class NuGetPackageBuilder implements PackageBuilder {
  const NuGetPackageBuilder();

  static const String _buildNative = 'build/native';
  static const String _includePrefix = '$_buildNative/include';
  static const String _libPrefix = '$_buildNative/lib';
  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  @override
  String get id => 'nuget';

  @override
  String get displayName => 'NuGet 包';

  @override
  Future<PackagePlan> buildPlan(PackModel pack) async {
    final List<PackageEntry> fileEntries = <PackageEntry>[];
    for (final FileModel file in pack.files) {
      final String? packagePath = _packagePath(file);
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

    return PackagePlan(
      entries: <PackageEntry>[
        ...fileEntries,
        PackageEntry(
          packagePath: '${pack.name}.nuspec',
          source: PackageGeneratedSource(content: _nuspecContent(pack)),
        ),
        PackageEntry(
          packagePath: '$_buildNative/${pack.name}.targets',
          source: PackageGeneratedSource(
            content: _targetsContent(pack, fileEntries),
          ),
        ),
      ],
    );
  }

  static String? _packagePath(FileModel file) {
    final String path = _normalizePath(file.path);
    if (path.isEmpty) {
      return null;
    }
    return switch (file.type) {
      FileType.header || FileType.module =>
        '$_includePrefix/${_withoutLeadingSegment(path, const <String>['include'])}',
      FileType.lib || FileType.dll || FileType.pdb =>
        '$_libPrefix/${_withoutLeadingSegment(path, const <String>['lib', 'bin'])}',
      _ => null,
    };
  }

  static bool _isBinaryType(FileType type) => switch (type) {
    FileType.lib || FileType.dll || FileType.pdb => true,
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

  static String _nuspecContent(PackModel pack) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
        '<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <id>${_escapeXml(pack.name)}</id>')
      ..writeln(
        '    <version>${_escapeXml(normalizedVersion(pack.version))}</version>',
      )
      ..writeln('    <authors>${_escapeXml(pack.author)}</authors>')
      ..writeln(
        '    <description>${_escapeXml(_description(pack))}</description>',
      );

    final String? license = pack.license;
    if (license != null && license.isNotEmpty) {
      buffer.writeln(
        '    <license type="expression">${_escapeXml(license)}</license>',
      );
    }

    buffer
      ..writeln(
        '    <requireLicenseAcceptance>false</requireLicenseAcceptance>',
      )
      ..writeln('    <tags>native C++</tags>');

    if (pack.dependencies.isNotEmpty) {
      buffer
        ..writeln('    <dependencies>')
        ..writeln('      <group targetFramework="native0.0">');
      for (final DependencyModel dependency in pack.dependencies) {
        buffer.writeln(
          '        <dependency id="${_escapeXml(dependency.name)}" '
          'version="${_escapeXml(dependency.version)}" />',
        );
      }
      buffer
        ..writeln('      </group>')
        ..writeln('    </dependencies>');
    }

    buffer
      ..writeln('  </metadata>')
      ..writeln('</package>');
    return buffer.toString();
  }

  static String _description(PackModel pack) {
    final String? description = pack.description;
    if (description == null || description.isEmpty) {
      return pack.name;
    }
    return description;
  }

  /// 去掉 `+build` 元数据后缀，得到 NuGet 接受的版本号。
  static String normalizedVersion(String version) {
    final int metadata = version.indexOf('+');
    if (metadata <= 0) {
      return version;
    }
    return version.substring(0, metadata);
  }

  static String _targetsContent(
    PackModel pack,
    List<PackageEntry> fileEntries,
  ) {
    final _BuildValueGroup macros = _BuildValueGroup();
    for (final MacroModel macro in pack.macros) {
      macros.add(macro.value, macro.buildModel);
    }

    final _BuildValueGroup libDirectories = _BuildValueGroup();
    for (final LibDirModel libDirectory in pack.libDirectories) {
      libDirectories.add(
        libDirectory.path,
        libDirectory.buildModel,
        dedupe: true,
      );
    }
    for (final PackageEntry entry in fileEntries) {
      _addDerivedLibDirectory(libDirectories, entry.packagePath);
    }

    final _BuildValueGroup libraries = _BuildValueGroup();
    for (final LibraryModel library in pack.libraries) {
      libraries.add(library.name, library.buildModel);
    }

    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
      );
    _writeItemDefinitionGroup(
      buffer,
      condition: null,
      includeLine: true,
      macros: macros.all,
      libDirectories: libDirectories.all,
      libraries: libraries.all,
    );
    _writeConfigurationGroup(
      buffer,
      configuration: releaseBuildLabel,
      macros: macros.release,
      libDirectories: libDirectories.release,
      libraries: libraries.release,
    );
    _writeConfigurationGroup(
      buffer,
      configuration: debugBuildLabel,
      macros: macros.debug,
      libDirectories: libDirectories.debug,
      libraries: libraries.debug,
    );
    buffer.writeln('</Project>');
    return buffer.toString();
  }

  static void _addDerivedLibDirectory(
    _BuildValueGroup group,
    String packagePath,
  ) {
    if (!packagePath.toLowerCase().endsWith('.lib')) {
      return;
    }
    final int separator = packagePath.lastIndexOf('/');
    if (separator <= 0) {
      return;
    }
    final String directory = packagePath.substring(0, separator);
    if (!directory.startsWith('$_buildNative/')) {
      return;
    }
    final String relative = directory.substring(_buildNative.length + 1);
    final BuildModel buildModel = switch (inferBuildLabel(relative)) {
      releaseBuildLabel => BuildModel.release,
      debugBuildLabel => BuildModel.debug,
      _ => BuildModel.all,
    };
    group.add(
      r'$(MSBuildThisFileDirectory)' + relative.replaceAll('/', r'\'),
      buildModel,
      dedupe: true,
    );
  }

  static void _writeConfigurationGroup(
    StringBuffer buffer, {
    required String configuration,
    required List<String> macros,
    required List<String> libDirectories,
    required List<String> libraries,
  }) {
    if (macros.isEmpty && libDirectories.isEmpty && libraries.isEmpty) {
      return;
    }
    _writeItemDefinitionGroup(
      buffer,
      condition: "'\$(Configuration)'=='$configuration'",
      includeLine: false,
      macros: macros,
      libDirectories: libDirectories,
      libraries: libraries,
    );
  }

  static void _writeItemDefinitionGroup(
    StringBuffer buffer, {
    required String? condition,
    required bool includeLine,
    required List<String> macros,
    required List<String> libDirectories,
    required List<String> libraries,
  }) {
    final String attribute = condition == null ? '' : ' Condition="$condition"';
    buffer
      ..writeln('  <ItemDefinitionGroup$attribute>')
      ..writeln('    <ClCompile>');
    if (includeLine) {
      _writeProperty(buffer, 'AdditionalIncludeDirectories', const <String>[
        r'$(MSBuildThisFileDirectory)include',
      ]);
    }
    _writeProperty(buffer, 'PreprocessorDefinitions', macros);
    _writeProperty(buffer, 'AdditionalLibraryDirectories', libDirectories);
    _writeProperty(buffer, 'AdditionalDependencies', libraries);
    buffer
      ..writeln('    </ClCompile>')
      ..writeln('  </ItemDefinitionGroup>');
  }

  static void _writeProperty(
    StringBuffer buffer,
    String name,
    List<String> values,
  ) {
    if (values.isEmpty) {
      return;
    }
    final String joined = <String>[
      for (final String value in values) _escapeXml(value),
      '%($name)',
    ].join(';');
    buffer.writeln('      <$name>$joined</$name>');
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _BuildValueGroup {
  final List<String> all = <String>[];
  final List<String> release = <String>[];
  final List<String> debug = <String>[];

  void add(String value, BuildModel buildModel, {bool dedupe = false}) {
    final List<String> values = switch (buildModel) {
      BuildModel.all => all,
      BuildModel.release => release,
      BuildModel.debug => debug,
    };
    if (dedupe &&
        values.any(
          (String existing) => existing.toLowerCase() == value.toLowerCase(),
        )) {
      return;
    }
    values.add(value);
  }
}
