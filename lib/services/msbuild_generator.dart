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
/// - 链接依赖与源码/模块注入（BeforeTargets="SelectClCompile" + 防重复标志），条目
///   来自 `isSourceMapping`（`fileKind == 'source' || 'module'`）的映射。
/// - 硬链接 Target 到 `$(OutDir)`（`mklink /H` 优先 + 防重复标志），条目来自
///   `fileKind == 'data' || 'dynamicLibrary' || 'executable'` 的映射。
/// - 编译前/后命令 Target（`BeforeTargets="Build"` / `AfterTargets="Build"` + 防重复
///   标志 + `$(MSBuildThisFileDirectory)` 工作目录），条目来自映射的 pre/post 命令。
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

  // 语言标准：仅在消费者未指定时设置。C 语言标准（如有）与 LanguageStandard 并列。
  sb.writeln('  <PropertyGroup>');
  sb.writeln(
    '    <LanguageStandard Condition="\'\$(LanguageStandard)\' == \'\'">'
    '${xmlEscape(compile.languageStandard)}</LanguageStandard>',
  );
  if (compile.clanguageStandard.trim().isNotEmpty) {
    sb.writeln(
      '    <CLanguageStandard Condition="\'\$(CLanguageStandard)\' == \'\'">'
      '${xmlEscape(compile.clanguageStandard)}</CLanguageStandard>',
    );
  }
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

  _appendHardlinkTargets(sb, project, prefix, usedIds);
  _appendCommandTargets(sb, project, prefix);

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
///
/// 遍历全部源码目录中 `isSourceMapping`（`fileKind == 'source' || 'module'`）的映射，
/// 为其生成 `<ClCompile>` 注入（引用 `$(MSBuildThisFileDirectory)src\{相对段}\{glob}\`）；
/// target 若已带 `build\native\src` 前缀则剥离，避免与 `$(MSBuildThisFileDirectory)` 重复。
/// C++ Module（.ixx/.cppm/.mpp）与源码共用注入逻辑，无额外 MSBuild 属性——模块语义由
/// 编译器 `/std:c++20` 或 `/std:c++latest` 按扩展名解析（`.ixx` 模块接口单元尤其如此）。
void _appendInjectedSources(
  StringBuffer sb,
  PackProject project,
  String prefix,
  Set<String> usedIds,
) {
  final sourceMappings = <FileMapping>[];
  for (final sourceDir in project.sourceDirs) {
    for (final mapping in sourceDir.mappings) {
      if (mapping.isSourceMapping) sourceMappings.add(mapping);
    }
  }
  if (sourceMappings.isEmpty) return;

  sb.writeln(
    '  <Target Name="${prefix}AddInjectedCompile" '
    'BeforeTargets="SelectClCompile">',
  );
  for (final mapping in sourceMappings) {
    final glob = basenameOf(mapping.srcGlob);
    final fileId = _uniqueFileId(glob, usedIds);
    final relTarget = stripMsBuildSourceRoot(mapping.target);
    final src = _sourceCompileInclude(relTarget, glob);
    sb.writeln(
      '    <ItemGroup Condition="\'\$(${prefix}_${fileId}_Injected)\' != \'true\'">',
    );
    sb.writeln(
      '      <ClCompile Include="\$(MSBuildThisFileDirectory)$src" />',
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

/// 拼接源码注入的 `$(MSBuildThisFileDirectory)` 相对引用段（`src\...`）。
///
/// [relTarget] 为剥离 `build\native\src` 前缀后的目标段；为空时直接指向 `src\`。
String _sourceCompileInclude(String relTarget, String glob) {
  final dir = relTarget.isEmpty ? '' : '$relTarget\\';
  return 'src\\$dir$glob';
}

/// 追加硬链接 Target（数据/动态库/可执行文件硬链接到 `$(OutDir)` + 防重复标志）。
///
/// 遍历全部源码目录中 `fileKind == 'data' || 'dynamicLibrary' || 'executable'`
/// 的映射。采用硬链接优先（`mklink /H`），失败时回退到 `copy /y`（`||` 链），且仅当
/// 目标不存在时才执行（`!Exists(...)` 条件 + 防重复标志）。源路径 =
/// `$(MSBuildThisFileDirectory)` 拼接映射目标（target 为包内目录，位于
/// `build\native` 下则取其相对段）。
void _appendHardlinkTargets(
  StringBuffer sb,
  PackProject project,
  String prefix,
  Set<String> usedIds,
) {
  final hardlinkMappings = <FileMapping>[];
  for (final sourceDir in project.sourceDirs) {
    for (final mapping in sourceDir.mappings) {
      final kind = mapping.fileKind;
      if (kind == 'data' || kind == 'dynamicLibrary' || kind == 'executable') {
        hardlinkMappings.add(mapping);
      }
    }
  }
  if (hardlinkMappings.isEmpty) return;

  for (final mapping in hardlinkMappings) {
    final fileName = basenameOf(mapping.srcGlob);
    final fileId = _uniqueFileId(fileName, usedIds);
    final dst = '\$(OutDir)\\${xmlEscape(fileName)}';
    final src = _hardlinkSource(mapping.target, fileName);
    sb.writeln(
      '  <Target Name="${prefix}Copy$fileId" BeforeTargets="Build" '
      "Condition=\"'\$(${prefix}_${fileId}_Copied)' != 'true'\">",
    );
    sb.writeln(
      '    <Exec Command="cmd /c mklink /H &quot;$dst&quot; &quot;$src&quot; 2&gt;nul '
      '|| copy /y &quot;$src&quot; &quot;$dst&quot; &gt;nul" '
      "Condition=\"!Exists('$dst')\" />",
    );
    sb.writeln('    <PropertyGroup>');
    sb.writeln(
      '      <${prefix}_${fileId}_Copied>true</${prefix}_${fileId}_Copied>',
    );
    sb.writeln('    </PropertyGroup>');
    sb.writeln('  </Target>');
  }
}

/// 追加编译前/后命令 Target（[FileMapping.preBuildCommand]/[postBuildCommand]）。
///
/// 遍历全部源码目录中任一命令非空的映射。pre 用 `BeforeTargets="Build"`、post 用
/// `AfterTargets="Build"`，均带防重复标志（`{prefix}_{fileId}_{Pre|Post}Cmd_Run`）。
/// 工作目录 = `$(MSBuildThisFileDirectory)`（包安装目录）；命令中的 MSBuild 变量
/// （如 `$(...)`）原样输出，交由 MSBuild 展开；命令本体做 XML 转义。
void _appendCommandTargets(
  StringBuffer sb,
  PackProject project,
  String prefix,
) {
  // 命令 Target 使用独立的目标名命名空间（名称带 PreCmd/PostCmd 后缀），
  // 不与硬链接/源码注入的 Copy/Injected 目标共享 fileId，避免被已用的 id 挤占出 _2 后缀。
  final commandIds = <String>{};
  for (final sourceDir in project.sourceDirs) {
    for (final mapping in sourceDir.mappings) {
      final pre = mapping.preBuildCommand.trim();
      final post = mapping.postBuildCommand.trim();
      if (pre.isEmpty && post.isEmpty) continue;
      final fileId = _uniqueFileId(basenameOf(mapping.srcGlob), commandIds);
      if (pre.isNotEmpty) {
        _appendCommandTarget(sb, prefix, fileId, 'Pre', pre, before: true);
      }
      if (post.isNotEmpty) {
        _appendCommandTarget(sb, prefix, fileId, 'Post', post, before: false);
      }
    }
  }
}

/// 生成一条编译前/后命令 Target 并写入 [sb]。
///
/// [phase] 为 `Pre`/`Post`（用于目标名与防重复标志），[command] 为原始命令文本。
void _appendCommandTarget(
  StringBuffer sb,
  String prefix,
  String fileId,
  String phase,
  String command, {
  required bool before,
}) {
  final when = before ? 'BeforeTargets="Build"' : 'AfterTargets="Build"';
  final flag = '${prefix}_${fileId}_${phase}Cmd_Run';
  final targetName =
      '$prefix$fileId$phase'
      'Cmd';
  sb.writeln(
    '  <Target Name="$targetName" $when '
    "Condition=\"'\$($flag)' != 'true'\">",
  );
  sb.writeln(
    '    <Exec Command="${xmlEscape(command)}" '
    'WorkingDirectory="\$(MSBuildThisFileDirectory)" />',
  );
  sb.writeln('    <PropertyGroup>');
  sb.writeln(
    '      <$flag Condition="\'\$($flag)\' != \'true\'">'
    'true</$flag>',
  );
  sb.writeln('    </PropertyGroup>');
  sb.writeln('  </Target>');
}

/// 拼接硬链接映射的包内源路径（`$(MSBuildThisFileDirectory)` 相对段）。
///
/// 目标位于 `build\native\` 下时取其相对段（如 `lib\x64\Debug`）；否则回退到
/// 包根（`build\native` 上两级 `..\..`）再进入目标目录。
String _hardlinkSource(String target, String fileName) {
  final t = target.trim();
  final stripped = stripMsBuildNativeRoot(t);
  if (stripped != t) {
    final dir = stripped.isEmpty ? '' : '$stripped\\';
    return '\$(MSBuildThisFileDirectory)$dir$fileName';
  }
  if (t.isEmpty) return '\$(MSBuildThisFileDirectory)$fileName';
  return '\$(MSBuildThisFileDirectory)..\\..\\$t\\$fileName';
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
      final sub = _includeSubPath(mapping);
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

/// 从文件映射目标提取 `include\...` 子路径；非头文件映射返回 null。
///
/// 基于新语义：头文件映射（`mapping.isHeaderMapping`）的 target 即为「最终
/// `#include` 路径」，子路径 = `include\{target}`（含 `build\native\include\`
/// 前缀的旧配置自动剥离以免重复）。
String? _includeSubPath(FileMapping mapping) {
  if (!mapping.isHeaderMapping) return null;
  var target = mapping.target.trim();
  if (target.isEmpty) return 'include';
  target = stripMsBuildIncludeRoot(target);
  return 'include\\$target';
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
