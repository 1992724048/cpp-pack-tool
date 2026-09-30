import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/pack/model/build_model.dart';
import 'package:cpp_nuget_pack/pack/model/cmd_model.dart';
import 'package:cpp_nuget_pack/pack/model/dependency_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/lib_dir_model.dart';
import 'package:cpp_nuget_pack/pack/model/library_model.dart';
import 'package:cpp_nuget_pack/pack/model/macro_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/nuget/license_file.dart';
import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:cpp_nuget_pack/pack/build_config.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:cpp_nuget_pack/nuget/sha1.dart';

class NuGetPackageBuilder {
  const NuGetPackageBuilder();

  static const String _buildNative = buildNativeRoot;
  static const String _filesPrefix = filesRoot;
  /// .targets 与包内载荷同层，故搜索根一律相对 build/native/ 而非包根。
  static const String _filesSearchRoot = filesRelativeRoot;
  static final String _librarySubdirectory = filesSubdirectoryOf(FileType.lib)!;
  static final String _assemblySubdirectory = filesSubdirectoryOf(FileType.asm)!;
  static final String _resourceSubdirectory = filesSubdirectoryOf(FileType.resource)!;
  static final String _msbuildSubdirectory = filesSubdirectoryOf(FileType.msbuild)!;
  static const String _masmImportCondition =
      r"'$(MASMBeforeTargets)' == '' And '$(VCTargetsPath)' != '' "
      r"And Exists('$(VCTargetsPath)\BuildCustomizations\masm.props') "
      r"And Exists('$(VCTargetsPath)\BuildCustomizations\masm.targets')";
  static final RegExp _pathSeparator = RegExp(r'[/\\]');
  static final RegExp _invalidTargetNameChar = RegExp(r'[^A-Za-z0-9_]');

  Future<PackagePlan> buildPlan(PackModel pack) async {
    final List<PackageEntry> fileEntries = <PackageEntry>[];
    for (final FileModel file in pack.files) {
      if (isBuildScriptPath(file.path)) {
        continue;
      }
      final String? packagePath = _packagePath(pack, file);
      if (packagePath == null) {
        continue;
      }
      fileEntries.add(
        PackageEntry(
          packagePath: packagePath,
          source: PackageFileSource(
            path: file.path,
            isBinary: isBinaryFileType(file.type, file.extension),
            size: file.size,
          ),
        ),
      );
    }

    final _UserMsbuildFiles msbuildFiles = _userMsbuildFiles(fileEntries);
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
            content: _targetsContent(pack, fileEntries, msbuildFiles),
          ),
        ),
        if (msbuildFiles.props.isNotEmpty)
          PackageEntry(
            packagePath: '$buildRoot/${pack.name}.props',
            source: PackageGeneratedSource(content: _userPropsContent(msbuildFiles.props)),
          ),
      ],
    );
  }

  static String? _packagePath(PackModel pack, FileModel file) {
    final String path = _normalizePath(file.path);
    if (path.isEmpty) {
      return null;
    }
    return buildNativePayloadPath(path, file.type, includeNamespaceOf(pack.sourcePath, pack.name));
  }

  /// 入参是 build/native 相对路径（stripBuildNative 的结果），故前缀不带 build/native/。
  static bool _isRuntimeBinary(String relativeLowerPath) =>
      relativeLowerPath.startsWith('$_filesSearchRoot/$_librarySubdirectory/') &&
      (relativeLowerPath.endsWith('.dll') || relativeLowerPath.endsWith('.pdb'));

  static String _normalizePath(String path) =>
      path.split(_pathSeparator).where((String segment) => segment.isNotEmpty).join('/');

  /// 用户自带的 .props / .targets 走双入口：.props 交包级 build/<包ID>.props 在正文前导入，
  /// .targets 交本包的 .targets 在正文后导入。桶内存相对 [buildNativeRoot] 的路径，
  /// 与既有三桶同坐标系，故发射时直接喂给 [_msbuildPath]。
  static _UserMsbuildFiles _userMsbuildFiles(List<PackageEntry> fileEntries) {
    final List<String> props = <String>[];
    final List<String> targets = <String>[];
    for (final PackageEntry entry in fileEntries) {
      final String? relative = stripBuildNative(entry.packagePath);
      if (relative == null) {
        continue;
      }
      final String lower = relative.toLowerCase();
      if (!lower.startsWith('$_filesSearchRoot/$_msbuildSubdirectory/')) {
        continue;
      }
      if (lower.endsWith('.props')) {
        props.add(relative);
      } else if (lower.endsWith('.targets')) {
        targets.add(relative);
      }
    }
    props.sort();
    targets.sort();
    return _UserMsbuildFiles(props: props, targets: targets);
  }

  static String cleanTargetId(String packName) => packName.replaceAll(_invalidTargetNameChar, '_');

  static String deployTargetName(String packName) =>
      'DeployPkgRuntimeBinaries_${cleanTargetId(packName)}_${hash8(packName)}';

  static String asmObjectName(String packName, String flattenedPath) =>
      r'$(IntDir)' 'asm_${cleanTargetId(packName)}_${hash8(packName)}_$flattenedPath.obj';

  static String _nuspecContent(PackModel pack) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">')
      ..writeln('  <metadata>')..writeln('    <id>${_escapeXml(pack.name)}</id>')..writeln(
          '    <version>${_escapeXml(normalizedVersion(pack.version))}</version>')..writeln(
          '    <authors>${_escapeXml(pack.author)}</authors>')..writeln(
          '    <description>${_escapeXml(_description(pack))}</description>');

    final String? license = pack.license;
    if (license != null && license.isNotEmpty) {
      buffer.writeln('    <license type="expression">${_escapeXml(license)}</license>');
    }
    buffer..writeln(r'    <icon>images\icon.png</icon>')..writeln(
        '    <requireLicenseAcceptance>false</requireLicenseAcceptance>')
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
    _UserMsbuildFiles msbuildFiles,
  ) {
    final _BuildValueGroup macros = _BuildValueGroup();
    for (final MacroModel macro in pack.macros) {
      macros.add(macro.value, macro.buildModel);
    }

    final _BuildValueGroup libDirectories = _BuildValueGroup();
    for (final LibDirModel libDirectory in pack.libDirectories) {
      libDirectories.add(libDirectory.path, libDirectory.buildModel, dedupe: true);
    }

    final _BuildValueGroup libraries = _BuildValueGroup();
    for (final LibraryModel library in pack.libraries) {
      libraries.add(library.name, library.buildModel);
    }

    final _BuildValueGroup runtimeBinaries = _BuildValueGroup();
    final List<String> asmFiles = <String>[];
    final List<String> resourceFiles = <String>[];
    final List<String> relativePayloads = <String>[];
    for (final PackageEntry entry in fileEntries) {
      _addDerivedLibEntries(libDirectories, libraries, entry.packagePath);
      final String? relative = stripBuildNative(entry.packagePath);
      if (relative == null) {
        continue;
      }
      relativePayloads.add(relative);
      final String lower = relative.toLowerCase();
      if (lower.startsWith('$_filesSearchRoot/$_assemblySubdirectory/') &&
          lower.endsWith('.asm')) {
        asmFiles.add(relative);
      } else if (lower.startsWith('$_filesSearchRoot/$_resourceSubdirectory/') &&
          lower.endsWith('.rc')) {
        resourceFiles.add(relative);
      } else if (_isRuntimeBinary(lower)) {
        runtimeBinaries.add(_msbuildPath(relative), BuildModel.all, dedupe: true);
      }
    }

    final List<String> includeRoots = <String>[
      for (final String root in payloadSearchRoots(relativePayloads)) _msbuildPath(root),
    ];

    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">');
    if (asmFiles.isNotEmpty) {
      _writeMasmImportGroup(buffer);
    }
    _writeUserTargetsImportGroup(buffer, msbuildFiles.targets);
    _writeItemDefinitionGroup(
      buffer,
      condition: null,
      includeRoots: includeRoots,
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
    _writeAsmItems(buffer, asmFiles, packName: pack.name);
    _writeResourceItems(buffer, resourceFiles);
    _writeRuntimeBinaryItems(buffer, runtimeBinaries);
    _writeDeployTarget(buffer, runtimeBinaries, packName: pack.name);
    _writeLicenseTarget(buffer, pack);
    buffer.writeln('</Project>');
    return buffer.toString();
  }

  static void _addDerivedLibEntries(_BuildValueGroup libDirectories, _BuildValueGroup libraries, String packagePath) {
    final String lower = packagePath.toLowerCase();
    final bool isStaticLibrary = lower.endsWith('.lib') || lower.endsWith('.a');
    if (!isStaticLibrary || !lower.startsWith('$_filesPrefix/$_librarySubdirectory/')) {
      return;
    }
    final String relative = stripBuildNative(packagePath)!;
    final String relativeDirectory = relative.substring(0, relative.lastIndexOf('/'));
    final BuildModel buildModel = libraryBuildModelOf(relative);
    libDirectories.add(_msbuildPath(relativeDirectory), buildModel, dedupe: true);
    libraries.add(baseName(packagePath), buildModel, dedupe: true);
  }

  /// 按包内路径中的 release / debug 段推断静态库配置。多段命中取最后一个 ——
  /// 越靠近文件的那段语义最强。
  static BuildModel libraryBuildModelOf(String packageRelativePath) {
    BuildModel inferred = BuildModel.all;
    for (final String segment in packageRelativePath.toLowerCase().split('/')) {
      if (segment == 'release') {
        inferred = BuildModel.release;
      } else if (segment == 'debug') {
        inferred = BuildModel.debug;
      }
    }
    return inferred;
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
      includeRoots: const <String>[],
      macros: macros,
      libDirectories: libDirectories,
      libraries: libraries,
    );
  }

  static String _configurationCondition(String configuration) => "'\$(Configuration)'=='$configuration'";

  static void _writeCommandGroups(StringBuffer buffer, PackModel pack) {
    final _CommandGroup commands = _CommandGroup();
    for (final CmdModel command in pack.commands) {
      commands.add(command);
    }
    final String cleanId = cleanTargetId(pack.name);
    final String hash = hash8(pack.name);
    _writeCommandGroupTargets(buffer, cleanId: cleanId, hash: hash, commands: commands.all);
    _writeCommandGroupTargets(
      buffer,
      cleanId: cleanId,
      hash: hash,
      commands: commands.release,
      configuration: releaseBuildLabel,
    );
    _writeCommandGroupTargets(
      buffer,
      cleanId: cleanId,
      hash: hash,
      commands: commands.debug,
      configuration: debugBuildLabel,
    );
  }

  static void _writeCommandGroupTargets(
    StringBuffer buffer, {
    required String cleanId,
    required String hash,
    required _CommandBuildGroup commands,
    String? configuration,
  }) {
    final String suffix = configuration == null ? '' : '_$configuration';
    final String condition = configuration == null ? '' : ' Condition="${_configurationCondition(configuration)}"';
    _writeCommandTarget(
      buffer,
      name: 'CnpPreBuild_${cleanId}_$hash$suffix',
      anchor: 'BeforeTargets="ClCompile"',
      condition: condition,
      commands: commands.preBuild,
    );
    _writeCommandTarget(
      buffer,
      name: 'CnpPostBuild_${cleanId}_$hash$suffix',
      anchor: 'AfterTargets="Build"',
      condition: condition,
      commands: commands.postBuild,
    );
  }

  static void _writeCommandTarget(
    StringBuffer buffer, {
    required String name,
    required String anchor,
    required String condition,
    required List<String> commands,
  }) {
    if (commands.isEmpty) {
      return;
    }
    buffer.writeln('  <Target Name="$name" $anchor$condition>');
    for (final String command in commands) {
      buffer.writeln(
        '    <Exec Command="${_escapeXml(command)}" '
        r'WorkingDirectory="$(ProjectDir)" '
        'IgnoreStandardErrorWarningFormat="true" />',
      );
    }
    buffer.writeln('  </Target>');
  }

  static void _writeMasmImportGroup(StringBuffer buffer) {
    buffer..writeln('  <ImportGroup Condition="$_masmImportCondition">')..writeln(
        r'    <Import Project="$(VCTargetsPath)\BuildCustomizations\masm.props" />')..writeln(
        r'    <Import Project="$(VCTargetsPath)\BuildCustomizations\masm.targets" />')
      ..writeln('  </ImportGroup>');
  }

  /// 不加 Condition：来源是包内文件（打包时已确定存在），不同于 masm 面向外部 MSVC
  /// 文件所需的 Exists 守卫。
  static void _writeUserTargetsImportGroup(StringBuffer buffer, List<String> targets) {
    if (targets.isEmpty) {
      return;
    }
    buffer.writeln('  <ImportGroup>');
    for (final String relative in targets) {
      buffer.writeln('    <Import Project="${_escapeXml(_msbuildPath(relative))}" />');
    }
    buffer.writeln('  </ImportGroup>');
  }

  /// 包级 .props 由 NuGet 在项目正文【前】导入，承载用户自带的 .props —— 它们给的默认值
  /// 必须早于项目正文才有意义。基准是 build/ 而载荷在 build/native/，故比 [_msbuildPath]
  /// 多一段前缀。relativePaths 是相对 [buildNativeRoot] 的路径（[stripBuildNative] 的结果）。
  static String _userPropsContent(List<String> relativePaths) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" TreatAsLocalProperty="Platform">',
      );
    for (final String relative in relativePaths) {
      final String importPath =
          r'$(MSBuildThisFileDirectory)' '$nativeTfmSegment' r'\' + relative.replaceAll('/', r'\');
      buffer.writeln('  <Import Project="${_escapeXml(importPath)}" />');
    }
    buffer.writeln('</Project>');
    return buffer.toString();
  }

  static void _writeAsmItems(StringBuffer buffer, List<String> asmFiles, {
    required String packName,
  }) {
    if (asmFiles.isEmpty) {
      return;
    }
    buffer.writeln('  <ItemGroup>');
    for (final String path in asmFiles) {
      final String objectName = asmObjectName(packName, path.replaceAll(_pathSeparator, '_'));
      buffer
        ..writeln('    <MASM Include="${_escapeXml(_msbuildPath(path))}">')
        ..writeln('      <ObjectFileName>${_escapeXml(objectName)}</ObjectFileName>')
        ..writeln('    </MASM>');
    }
    buffer.writeln('  </ItemGroup>');
  }

  static void _writeResourceItems(StringBuffer buffer, List<String> resourceFiles) {
    if (resourceFiles.isEmpty) {
      return;
    }
    buffer.writeln('  <ItemGroup>');
    for (final String path in resourceFiles) {
      final int separator = path.lastIndexOf('/');
      final String directory = separator < 0 ? '' : path.substring(0, separator);
      buffer
        ..writeln('    <ResourceCompile Include="${_escapeXml(_msbuildPath(path))}">')
        ..writeln(
          '      <AdditionalIncludeDirectories>${_escapeXml(_msbuildPath(directory))};%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>',
        )
        ..writeln('    </ResourceCompile>');
    }
    buffer.writeln('  </ItemGroup>');
  }

  static void _writeRuntimeBinaryItems(StringBuffer buffer, _BuildValueGroup runtimeBinaries) {
    _writeBinaryItemGroup(buffer, runtimeBinaries.all);
  }

  static void _writeBinaryItemGroup(StringBuffer buffer, List<String> binaries) {
    if (binaries.isEmpty) {
      return;
    }
    buffer.writeln('  <ItemGroup>');
    for (final String binary in binaries) {
      buffer.writeln('    <PkgRuntimeBinary Include="${_escapeXml(binary)}" />');
    }
    buffer.writeln('  </ItemGroup>');
  }

  static void _writeDeployTarget(StringBuffer buffer, _BuildValueGroup runtimeBinaries, {
    required String packName,
  }) {
    if (runtimeBinaries.isEmpty) {
      return;
    }
    buffer
      ..writeln(
        '  <Target Name="${deployTargetName(packName)}" AfterTargets="Build" '
        "Condition=\"'@(PkgRuntimeBinary)' != ''\">",
      )
      ..writeln(
        '    <Copy SourceFiles="@(PkgRuntimeBinary)" '
        'DestinationFolder="\$(OutDir)" SkipUnchangedFiles="true" '
        'UseHardlinksIfPossible="true" />',
      )..writeln('    <ItemGroup>')..writeln(
        "      <FileWrites Include=\"@(PkgRuntimeBinary->'\$(OutDir)%(Filename)%(Extension)')\" />")
      ..writeln('    </ItemGroup>')
      ..writeln('  </Target>');
  }

  static void _writeLicenseTarget(StringBuffer buffer, PackModel pack) {
    final List<String> sources = <String>[
      for (final String licensePath in findLicensePaths(pack.files))
        if (_licenseRelativePath(pack, licensePath) case final String relative) _msbuildPath(relative),
    ];
    if (sources.isEmpty) {
      return;
    }
    const String destinationFolder = r'$(OutDir)LICENSES';
    final List<String> destinations = <String>[
      for (final String source in sources)
        '$destinationFolder\\${_escapeXml('${pack.name}_${baseName(source)}')}',
    ];
    buffer.writeln(
      '  <Target Name="DeployPkgLicenses_${cleanTargetId(pack.name)}_${hash8(pack.name)}" '
      'AfterTargets="Build">',
    );
    for (int index = 0; index < sources.length; index++) {
      final String source = _escapeXml(sources[index]);
      buffer
        ..writeln("    <Copy Condition=\"Exists('$source')\" SourceFiles=\"$source\"")
        ..writeln('          DestinationFiles="${destinations[index]}"')
        ..writeln('          SkipUnchangedFiles="true" UseHardlinksIfPossible="true" />');
    }
    buffer.writeln('    <ItemGroup>');
    for (final String destination in destinations) {
      buffer.writeln('      <FileWrites Include="$destination" />');
    }
    buffer
      ..writeln('    </ItemGroup>')
      ..writeln('  </Target>');
  }

  static String? _licenseRelativePath(PackModel pack, String licensePath) {
    for (final FileModel file in pack.files) {
      if (file.path != licensePath) {
        continue;
      }
      final String? packagePath = _packagePath(pack, file);
      if (packagePath != null) {
        return stripBuildNative(packagePath);
      }
    }
    return null;
  }

  static void _writeItemDefinitionGroup(
    StringBuffer buffer, {
    required String? condition,
    required List<String> includeRoots,
    required List<String> macros,
    required List<String> libDirectories,
    required List<String> libraries,
  }) {
    final String attribute = condition == null ? '' : ' Condition="$condition"';
    buffer
      ..writeln('  <ItemDefinitionGroup$attribute>')
      ..writeln('    <ClCompile>');
    _writeProperty(buffer, 'AdditionalIncludeDirectories', includeRoots);
    _writeProperty(buffer, 'PreprocessorDefinitions', macros);
    _writeProperty(buffer, 'AdditionalLibraryDirectories', libDirectories);
    _writeProperty(buffer, 'AdditionalDependencies', libraries);
    buffer
      ..writeln('    </ClCompile>')
      ..writeln('  </ItemDefinitionGroup>');
  }

  static void _writeProperty(StringBuffer buffer, String name, List<String> values) {
    if (values.isEmpty) {
      return;
    }
    final String joined = <String>[for (final String value in values) _escapeXml(value), '%($name)'].join(';');
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

class _UserMsbuildFiles {
  const _UserMsbuildFiles({required this.props, required this.targets});

  final List<String> props;
  final List<String> targets;
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
    if (dedupe && values.any((String existing) => existing.toLowerCase() == value.toLowerCase())) {
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
