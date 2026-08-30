/// MSBuild `props`/`targets` 生成器：为消费者项目注入编译/链接配置。
///
/// 对标 `D:\CODE\Library\v8\packaging\build\native\V8.Native.props` 与
/// `V8.Native.targets`，产出用于 NuGet 包（`build\native\` 下）的 MSBuild
/// 集成文件。支持：
/// - 语言标准（条件置空时设置）。
/// - 跳过宏标志（当消费者已含本包首个宏时跳过预处理定义注入）。
/// - 分配置的预处理宏展开 + `%(PreprocessorDefinitions)` 追加。
/// - 包含路径（`$(MSBuildThisFileDirectory)include` 及映射目标派生的子路径）。
/// - 平台/配置检查 Target 与 `{id}_LibDir` 组合属性。
/// - 链接依赖与注入源码（BeforeTargets="SelectClCompile" + 防重复标志）。
/// - 数据文件拷贝 Target（`$(OutDir)` + 防重复标志）。
library;

import '../models/pack_project.dart';
import 'nuspec_generator.dart';
import 'path_utils.dart';

/// 将任意输入消毒为可安全用作 MSBuild 属性名/目标名的标识符：
/// 非字母数字下划线替换为 `_`；空则回退 `Pkg`；数字开头加 `_` 前缀。
String sanitizeMsBuildIdentifier(String input) {
  var result = input.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  if (result.isEmpty) result = 'Pkg';
  if (RegExp(r'^[0-9]').hasMatch(result)) result = '_$result';
  return result;
}

/// 生成 `props` 文本。
String generateProps(PackProject project) {
  final prefix = sanitizeMsBuildIdentifier(project.packageId);
  final compile = project.compileConfig;
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
  sb.writeln(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
  );

  // 语言标准：仅在消费者未指定时设置。
  sb.writeln('  <PropertyGroup>');
  sb.writeln(
    '    <LanguageStandard Condition="\'\$(LanguageStandard)\' == \'\'">'
    '${xmlEscape(compile.languageStandard)}</LanguageStandard>',
  );
  sb.writeln('  </PropertyGroup>');

  // 跳过宏标志：当消费者已含本包首个全局宏时，跳过预处理定义注入。
  final firstDefine = _firstDefine(compile.preprocessorDefines);
  if (firstDefine != null) {
    sb.writeln('  <PropertyGroup>');
    sb.writeln(
      '    <${prefix}_SkipDefines '
      "Condition=\"'\$(PreprocessorDefinitions)' != '' and "
      "\$(PreprocessorDefinitions.Contains('${xmlEscape(firstDefine)}'))\""
      '>true</${prefix}_SkipDefines>',
    );
    sb.writeln('  </PropertyGroup>');
  }

  // Compile 级元数据：预处理宏（分配置）+ 包含路径。
  sb.writeln('  <ItemDefinitionGroup>');
  sb.writeln('    <ClCompile>');
  for (final config in project.configurations) {
    sb.writeln(
      '      <PreprocessorDefinitions '
      "Condition=\"'\$(${prefix}_SkipDefines)' != 'true' and "
      "'\$(Configuration)' == '${xmlEscape(config)}'\""
      '>${_buildDefines(compile, config)}</PreprocessorDefinitions>',
    );
  }
  sb.writeln(
    '      <AdditionalIncludeDirectories>'
    '${_buildIncludeDirs(project, compile)}'
    '</AdditionalIncludeDirectories>',
  );
  sb.writeln('    </ClCompile>');
  sb.writeln('  </ItemDefinitionGroup>');
  sb.writeln('</Project>');
  return sb.toString();
}

/// 生成 `targets` 文本。
String generateTargets(PackProject project) {
  final prefix = sanitizeMsBuildIdentifier(project.packageId);
  final compile = project.compileConfig;
  final sb = StringBuffer();
  sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
  sb.writeln(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
  );

  // `{prefix}_LibDir`：按平台 × 配置组合定义，供后续条件引用。
  sb.writeln('  <PropertyGroup>');
  for (final platform in project.platforms) {
    for (final config in project.configurations) {
      sb.writeln(
        '    <${prefix}_LibDir '
        "Condition=\"'\$(Platform)' == '${xmlEscape(platform)}' and "
        "'\$(Configuration.ToLower())' == '${config.toLowerCase()}'\">"
        '\$(MSBuildThisFileDirectory)lib\\${xmlEscape(platform)}\\${xmlEscape(config)}'
        '</${prefix}_LibDir>',
      );
    }
  }
  sb.writeln('  </PropertyGroup>');

  _appendPlatformCheck(sb, project, prefix);
  _appendConfigCheck(sb, project, prefix);

  final usedIds = <String>{};
  _appendInjectedSources(sb, project, prefix, usedIds);

  // 链接级元数据：库路径 + 依赖（仅当匹配到有效的 LibDir 时应用）。
  sb.writeln(
    '  <ItemDefinitionGroup Condition="\'\$(${prefix}_LibDir)\' != \'\'">',
  );
  sb.writeln('    <Link>');
  sb.writeln(
    '      <AdditionalLibraryDirectories>'
    '\$(${prefix}_LibDir);${_semis(compile.additionalLibraryDirectories)}'
    '%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>',
  );
  sb.writeln(
    '      <AdditionalDependencies>${_semis(compile.additionalDependencies)}'
    '%(AdditionalDependencies)</AdditionalDependencies>',
  );
  sb.writeln('    </Link>');
  sb.writeln('  </ItemDefinitionGroup>');

  _appendDataCopyTargets(sb, project, prefix, usedIds);

  sb.writeln('</Project>');
  return sb.toString();
}

/// 追加平台检查 Target。
void _appendPlatformCheck(StringBuffer sb, PackProject project, String prefix) {
  sb.writeln(
    '  <Target Name="${prefix}CheckPlatform" BeforeTargets="ClCompile;Link">',
  );
  final conditions = project.platforms
      .map((p) => "'\$(Platform)' != '${xmlEscape(p)}'")
      .join(' and ');
  final supported = project.platforms.join(', ');
  sb.writeln(
    '    <Error Condition="$conditions" '
    'Text="${xmlEscape(project.packageId)} 包仅支持 $supported 平台；'
    '当前平台 \$(Platform) 不受支持。请将项目平台切换为 $supported。" />',
  );
  sb.writeln('  </Target>');
}

/// 追加配置检查 Target（平台受支持但 LibDir 为空 → 配置不受支持）。
void _appendConfigCheck(StringBuffer sb, PackProject project, String prefix) {
  sb.writeln(
    '  <Target Name="${prefix}CheckConfiguration" '
    'BeforeTargets="ClCompile;Link">',
  );
  final supported = project.configurations.join(', ');
  for (final platform in project.platforms) {
    sb.writeln(
      '    <Error '
      "Condition=\"'\$(Platform)' == '${xmlEscape(platform)}' and "
      "'\$(${prefix}_LibDir)' == ''\" "
      'Text="${xmlEscape(project.packageId)} 包仅提供 $supported 配置的库；'
      '当前配置 \$(Configuration) 不受支持。请将项目配置切换为 $supported。" />',
    );
  }
  sb.writeln('  </Target>');
}

/// 追加注入源码 Target（BeforeTargets="SelectClCompile" + 每个文件防重复标志）。
void _appendInjectedSources(
  StringBuffer sb,
  PackProject project,
  String prefix,
  Set<String> usedIds,
) {
  final sources = project.compileConfig.injectedSources;
  if (sources.isEmpty) return;

  sb.writeln(
    '  <Target Name="${prefix}AddInjectedCompile" '
    'BeforeTargets="SelectClCompile">',
  );
  for (final source in sources) {
    final fileId = _uniqueFileId(basenameOf(source), usedIds);
    sb.writeln(
      '    <ItemGroup Condition="\'\$(${prefix}_${fileId}_Injected)\' != \'true\'">',
    );
    sb.writeln(
      '      <ClCompile Include="\$(MSBuildThisFileDirectory)$source" />',
    );
    sb.writeln('    </ItemGroup>');
    sb.writeln('    <PropertyGroup>');
    sb.writeln(
      '      <${prefix}_${fileId}_Injected '
      "Condition=\"'\$(${prefix}_${fileId}_Injected)' != 'true'\">"
      'true</${prefix}_${fileId}_Injected>',
    );
    sb.writeln('    </PropertyGroup>');
  }
  sb.writeln('  </Target>');
}

/// 追加数据文件拷贝 Target（拷贝到 `$(OutDir)` + 防重复标志）。
void _appendDataCopyTargets(
  StringBuffer sb,
  PackProject project,
  String prefix,
  Set<String> usedIds,
) {
  final files = project.compileConfig.dataFilesToCopy;
  if (files.isEmpty) return;

  for (final file in files) {
    final fileId = _uniqueFileId(basenameOf(file), usedIds);
    sb.writeln(
      '  <Target Name="${prefix}Copy$fileId" BeforeTargets="Build" '
      "Condition=\"'\$(${prefix}_LibDir)' != '' and "
      "'\$(${prefix}_${fileId}_Copied)' != 'true'\">",
    );
    sb.writeln(
      '    <Copy SourceFiles="\$(${prefix}_LibDir)\\$file" '
      'DestinationFolder="\$(OutDir)" SkipUnchangedFiles="true" />',
    );
    sb.writeln('    <PropertyGroup>');
    sb.writeln(
      '      <${prefix}_${fileId}_Copied>true</${prefix}_${fileId}_Copied>',
    );
    sb.writeln('    </PropertyGroup>');
    sb.writeln('  </Target>');
  }
}

/// 计算某配置下的预处理宏值（全局宏 + 配置宏 + `%(PreprocessorDefinitions)`）。
String _buildDefines(CompileConfig compile, String config) {
  final globalDefines = compile.preprocessorDefines;
  final configDefine = compile.configDefines[config];
  final parts = <String>[
    ..._splitSemis(globalDefines),
    ..._splitSemis(configDefine ?? ''),
    '%(PreprocessorDefinitions)',
  ];
  return _joinSemis(parts);
}

/// 计算包含路径（`$(MSBuildThisFileDirectory)include` + 映射目标派生子路径 + 用户额外 + 追加）。
String _buildIncludeDirs(PackProject project, CompileConfig compile) {
  final dirs = <String>['include'];
  for (final sourceDir in project.sourceDirs) {
    for (final mapping in sourceDir.mappings) {
      final sub = _includeSubPath(mapping.target);
      if (sub != null) dirs.add(sub);
    }
  }
  final parts = <String>[
    for (final dir in dirs)
      '\$(MSBuildThisFileDirectory)${_stripTrailingSlash(dir)}',
    ..._splitSemis(compile.additionalIncludeDirectories),
    '%(AdditionalIncludeDirectories)',
  ];
  return _joinSemis(parts);
}

/// 从文件映射目标提取 `include\...` 子路径；非头文件目标返回 null。
String? _includeSubPath(String target) {
  const headerRoot = 'build\\native\\include';
  if (!target.startsWith(headerRoot)) return null;
  final rest = target.length == headerRoot.length
      ? ''
      : target.substring(headerRoot.length + 1);
  if (rest.isEmpty) return 'include';
  return 'include\\$rest';
}

/// 首个全局宏（用于跳过宏标志的哨兵），无则返回 null。
String? _firstDefine(String preprocessorDefines) {
  final tokens = _splitSemis(preprocessorDefines);
  return tokens.isEmpty ? null : tokens.first;
}

/// 拆分分号分隔的字符串并去除空项。
List<String> _splitSemis(String value) =>
    value.split(';').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

/// 用分号连接已拆分的非空项，返回带尾随分号的完整值。
String _semisOf(Iterable<String> parts) {
  final cleaned = parts.where((t) => t.trim().isNotEmpty).toList();
  return cleaned.isEmpty ? '' : '${cleaned.join(';')};';
}

/// 用分号连接已拆分的非空项，无尾随分号（用于以 `%( ... )` 元数据收尾的列表）。
String _joinSemis(Iterable<String> parts) {
  final cleaned = parts.where((t) => t.trim().isNotEmpty).toList();
  return cleaned.join(';');
}

/// 连接以分号分隔的字符串，保留非空项，结尾带分号。
String _semis(String value) => _semisOf(_splitSemis(value));

/// 去除结尾的斜杠。
String _stripTrailingSlash(String value) {
  var result = value;
  while (result.endsWith('/') || result.endsWith('\\')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// 生成唯一且合法的文件标识（防重复标志用），冲突时追加序号。
String _uniqueFileId(String fileName, Set<String> used) {
  final base = sanitizeMsBuildIdentifier(fileName);
  var candidate = base;
  var index = 2;
  while (!used.add(candidate)) {
    candidate = '${base}_$index';
    index++;
  }
  return candidate;
}
