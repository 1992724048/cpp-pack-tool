import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/format.dart';

class NuGetPackageBuilder implements PackageBuilder {
  const NuGetPackageBuilder();

  static const String _buildNative = 'build/native';
  static const String _includePrefix = '$_buildNative/include';
  static const String _libPrefix = '$_buildNative/lib';
  static const String _filesPrefix = '$_buildNative/files';
  static const String _masmImportCondition =
      r"'$(MASMBeforeTargets)' == '' And '$(VCTargetsPath)' != '' "
      r"And Exists('$(VCTargetsPath)\BuildCustomizations\masm.props') "
      r"And Exists('$(VCTargetsPath)\BuildCustomizations\masm.targets')";
  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  @override
  String get id => 'nuget';

  @override
  String get displayName => 'NuGet 包';

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

  static String? _packagePath(PackModel pack, FileModel file) {
    final String path = _normalizePath(file.path);
    if (path.isEmpty) {
      return null;
    }
    return switch (file.type) {
      FileType.header || FileType.module =>
        '$_includePrefix/${_includeNamespace(pack)}/${_withoutLeadingSegment(path, const <String>['include'])}',
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

    final _BuildValueGroup libraries = _BuildValueGroup();
    for (final LibraryModel library in pack.libraries) {
      libraries.add(library.name, library.buildModel);
    }

    final _BuildValueGroup runtimeBinaries = _BuildValueGroup();
    final List<String> asmFiles = <String>[];
    final List<String> resourceFiles = <String>[];
    for (final PackageEntry entry in fileEntries) {
      _addDerivedLibEntries(libDirectories, libraries, entry.packagePath);
      final String? relative = _relativeUnderBuildNative(entry.packagePath);
      if (relative == null) {
        continue;
      }
      final String lower = relative.toLowerCase();
      if (lower.startsWith('files/') && lower.endsWith('.asm')) {
        asmFiles.add(relative);
      } else if (lower.startsWith('files/') && lower.endsWith('.rc')) {
        resourceFiles.add(relative);
      } else if (lower.startsWith('lib/') &&
          (lower.endsWith('.dll') || lower.endsWith('.pdb'))) {
        runtimeBinaries.add(
          _msbuildPath(relative),
          _buildModelOf(relative),
          dedupe: true,
        );
      }
    }

    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
      );
    if (asmFiles.isNotEmpty) {
      _writeMasmImportGroup(buffer);
    }
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
    _writeCommandGroups(buffer, pack);
    _writeAsmItems(buffer, asmFiles);
    _writeResourceItems(buffer, resourceFiles);
    _writeRuntimeBinaryItems(buffer, runtimeBinaries);
    _writeDeployTarget(buffer, runtimeBinaries);
    buffer.writeln('</Project>');
    return buffer.toString();
  }

  static void _addDerivedLibEntries(
    _BuildValueGroup libDirectories,
    _BuildValueGroup libraries,
    String packagePath,
  ) {
    final String lower = packagePath.toLowerCase();
    if (!lower.endsWith('.lib') || !lower.startsWith('$_libPrefix/')) {
      return;
    }
    final String relative = packagePath.substring(_buildNative.length + 1);
    final String relativeDirectory = relative.substring(
      0,
      relative.lastIndexOf('/'),
    );
    final BuildModel buildModel = _buildModelOf(relative);
    libDirectories.add(
      _msbuildPath(relativeDirectory),
      buildModel,
      dedupe: true,
    );
    libraries.add(baseName(packagePath), buildModel, dedupe: true);
  }

  static String? _relativeUnderBuildNative(String packagePath) {
    if (!packagePath.startsWith('$_buildNative/')) {
      return null;
    }
    return packagePath.substring(_buildNative.length + 1);
  }

  static BuildModel _buildModelOf(String relativePath) {
    return switch (inferBuildLabel(relativePath)) {
      releaseBuildLabel => BuildModel.release,
      debugBuildLabel => BuildModel.debug,
      _ => BuildModel.all,
    };
  }

  static String _msbuildPath(String relativePath) =>
      r'$(MSBuildThisFileDirectory)' + relativePath.replaceAll('/', r'\');

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
      condition: _configurationCondition(configuration),
      includeLine: false,
      macros: macros,
      libDirectories: libDirectories,
      libraries: libraries,
    );
  }

  static String _configurationCondition(String configuration) =>
      "'\$(Configuration)'=='$configuration'";

  static void _writeCommandGroups(StringBuffer buffer, PackModel pack) {
    final _CommandGroup commands = _CommandGroup();
    for (final CmdModel command in pack.commands) {
      commands.add(command);
    }
    _writeCommandPropertyGroup(buffer, commands.all);
    _writeCommandPropertyGroup(
      buffer,
      commands.release,
      condition: _configurationCondition(releaseBuildLabel),
    );
    _writeCommandPropertyGroup(
      buffer,
      commands.debug,
      condition: _configurationCondition(debugBuildLabel),
    );
  }

  static void _writeCommandPropertyGroup(
    StringBuffer buffer,
    _CommandBuildGroup commands, {
    String? condition,
  }) {
    if (commands.isEmpty) {
      return;
    }
    final String attribute = condition == null ? '' : ' Condition="$condition"';
    buffer.writeln('  <PropertyGroup$attribute>');
    _writeCommandEvent(buffer, 'PreBuildEvent', commands.preBuild);
    _writeCommandEvent(buffer, 'PostBuildEvent', commands.postBuild);
    buffer.writeln('  </PropertyGroup>');
  }

  static void _writeCommandEvent(
    StringBuffer buffer,
    String name,
    List<String> commands,
  ) {
    if (commands.isEmpty) {
      return;
    }
    final String value = <String>[
      '\$($name)',
      for (final String command in commands) _escapeXml(command),
    ].join('&#x0D;&#x0A;');
    buffer.writeln('    <$name>$value</$name>');
  }

  static void _writeMasmImportGroup(StringBuffer buffer) {
    buffer
      ..writeln('  <ImportGroup Condition="$_masmImportCondition">')
      ..writeln(
        r'    <Import Project="$(VCTargetsPath)\BuildCustomizations\masm.props" />',
      )
      ..writeln(
        r'    <Import Project="$(VCTargetsPath)\BuildCustomizations\masm.targets" />',
      )
      ..writeln('  </ImportGroup>');
  }

  static void _writeAsmItems(StringBuffer buffer, List<String> asmFiles) {
    if (asmFiles.isEmpty) {
      return;
    }
    buffer.writeln('  <ItemGroup>');
    for (final String path in asmFiles) {
      final String objectName = path.replaceAll(_pathSeparator, '_');
      buffer
        ..writeln('    <MASM Include="${_escapeXml(_msbuildPath(path))}">')
        ..writeln(
          '      <ObjectFileName>\$(IntDir)asm_${_escapeXml(objectName)}.obj</ObjectFileName>',
        )
        ..writeln('    </MASM>');
    }
    buffer.writeln('  </ItemGroup>');
  }

  static void _writeResourceItems(
    StringBuffer buffer,
    List<String> resourceFiles,
  ) {
    if (resourceFiles.isEmpty) {
      return;
    }
    buffer.writeln('  <ItemGroup>');
    for (final String path in resourceFiles) {
      final int separator = path.lastIndexOf('/');
      final String directory = separator < 0
          ? ''
          : path.substring(0, separator);
      buffer
        ..writeln(
          '    <ResourceCompile Include="${_escapeXml(_msbuildPath(path))}">',
        )
        ..writeln(
          '      <AdditionalIncludeDirectories>${_escapeXml(_msbuildPath(directory))};%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
        )
        ..writeln('    </ResourceCompile>');
    }
    buffer.writeln('  </ItemGroup>');
  }

  static void _writeRuntimeBinaryItems(
    StringBuffer buffer,
    _BuildValueGroup runtimeBinaries,
  ) {
    _writeBinaryItemGroup(buffer, runtimeBinaries.all);
    _writeBinaryItemGroup(
      buffer,
      runtimeBinaries.release,
      condition: _configurationCondition(releaseBuildLabel),
    );
    _writeBinaryItemGroup(
      buffer,
      runtimeBinaries.debug,
      condition: _configurationCondition(debugBuildLabel),
    );
  }

  static void _writeBinaryItemGroup(
    StringBuffer buffer,
    List<String> binaries, {
    String? condition,
  }) {
    if (binaries.isEmpty) {
      return;
    }
    final String attribute = condition == null ? '' : ' Condition="$condition"';
    buffer.writeln('  <ItemGroup$attribute>');
    for (final String binary in binaries) {
      buffer.writeln(
        '    <PkgRuntimeBinary Include="${_escapeXml(binary)}" />',
      );
    }
    buffer.writeln('  </ItemGroup>');
  }

  static void _writeDeployTarget(
    StringBuffer buffer,
    _BuildValueGroup runtimeBinaries,
  ) {
    if (runtimeBinaries.isEmpty) {
      return;
    }
    buffer
      ..writeln(
        '  <Target Name="DeployPkgRuntimeBinaries" AfterTargets="Build" '
        "Condition=\"'@(PkgRuntimeBinary)' != ''\">",
      )
      ..writeln(
        '    <Copy SourceFiles="@(PkgRuntimeBinary)" '
        'DestinationFolder="\$(OutDir)" SkipUnchangedFiles="true" '
        'UseHardlinksIfPossible="true" />',
      )
      ..writeln('    <ItemGroup>')
      ..writeln(
        "      <FileWrites Include=\"@(PkgRuntimeBinary->'\$(OutDir)%(Filename)%(Extension)')\" />",
      )
      ..writeln('    </ItemGroup>')
      ..writeln('  </Target>');
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

  bool get isEmpty => all.isEmpty && release.isEmpty && debug.isEmpty;

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

class _CommandGroup {
  final _CommandBuildGroup all = _CommandBuildGroup();
  final _CommandBuildGroup release = _CommandBuildGroup();
  final _CommandBuildGroup debug = _CommandBuildGroup();

  void add(CmdModel command) {
    final _CommandBuildGroup group = switch (command.buildModel) {
      BuildModel.all => all,
      BuildModel.release => release,
      BuildModel.debug => debug,
    };
    switch (command.type) {
      case CmdType.preBuild:
        group.preBuild.add(command.command);
      case CmdType.postBuild:
        group.postBuild.add(command.command);
    }
  }
}

class _CommandBuildGroup {
  final List<String> preBuild = <String>[];
  final List<String> postBuild = <String>[];

  bool get isEmpty => preBuild.isEmpty && postBuild.isEmpty;
}
