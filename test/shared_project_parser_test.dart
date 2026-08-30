import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/models/pack_project.dart';
import 'package:cpp_nuget_pack/services/path_utils.dart';
import 'package:cpp_nuget_pack/services/shared_project_parser.dart';

void main() {
  late Directory tempRoot;
  late Directory sourceDir;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('shared_parser_test_');
    sourceDir = Directory(joinPath([tempRoot.path, 'v8']))
      ..createSync(recursive: true);
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // 清理失败不阻塞测试。
    }
  });

  File writeFile(String name, String content) {
    final file = File(joinPath([sourceDir.path, name]));
    file.writeAsStringSync(content);
    return file;
  }

  test('detectSharedProjectFile 按优先级 vcxitems > vcxproj > props > targets', () {
    writeFile('My.props', 'x');
    writeFile('My.targets', 'x');
    writeFile('Shared.vcxproj', 'x');
    final result = detectSharedProjectFile(sourceDir.path);
    expect(result, endsWith(r'Shared.vcxproj'));
  });

  test('detectSharedProjectFile 命中 vcxitems 时不看 vcxproj', () {
    writeFile('A.vcxitems', 'x');
    writeFile('B.vcxproj', 'x');
    expect(detectSharedProjectFile(sourceDir.path), endsWith(r'A.vcxitems'));
  });

  test('detectSharedProjectFile 大小写不敏感', () {
    writeFile('SHARED.VCXPROJ', 'x');
    expect(
      detectSharedProjectFile(sourceDir.path),
      endsWith(r'SHARED.VCXPROJ'),
    );
  });

  test('detectSharedProjectFile 目录不存在或无配置文件返回 null', () {
    expect(detectSharedProjectFile(joinPath([tempRoot.path, 'nope'])), isNull);
    expect(detectSharedProjectFile(sourceDir.path), isNull);
  });

  test('parseSharedProject 解析 ClInclude/ClCompile 与编译配置', () {
    final file = writeFile('Shared.vcxitems', r'''
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <ItemGroup>
    <ClInclude Include="include\v8\api.h" />
    <ClInclude Include="include\v8\version.h" />
    <ClCompile Include="src\v8wrap\win32.cpp" />
    <ClCompile Include="src\v8wrap\module.ixx" />
  </ItemGroup>
  <PropertyGroup>
    <AdditionalIncludeDirectories>include;$(V8_DIR)include</AdditionalIncludeDirectories>
    <PreprocessorDefinitions>NOMINMAX;V8_ENABLE_CHECKS</PreprocessorDefinitions>
  </PropertyGroup>
  <ItemDefinitionGroup>
    <AdditionalDependencies>ws2_32.lib;ntdll.lib</AdditionalDependencies>
  </ItemDefinitionGroup>
</Project>
''');
    final info = parseSharedProject(file.path);

    expect(info.headerGlobs, ['include\\v8\\api.h', 'include\\v8\\version.h']);
    expect(info.sourceGlobs, [
      'src\\v8wrap\\win32.cpp',
      'src\\v8wrap\\module.ixx',
    ]);
    expect(info.additionalDependencies, ['ws2_32.lib', 'ntdll.lib']);
    expect(info.additionalIncludeDirectories, ['include', r'$(V8_DIR)include']);
    expect(info.preprocessorDefinitions, ['NOMINMAX', 'V8_ENABLE_CHECKS']);
  });

  test('parseSharedProject 空文件或不存在文件抛 FormatException', () {
    final empty = writeFile('Empty.vcxitems', '');
    expect(
      () => parseSharedProject(empty.path),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseSharedProject(joinPath([sourceDir.path, 'nope.vcxitems'])),
      throwsA(isA<FormatException>()),
    );
  });

  test('buildMappingsFromSharedProject 生成头/源映射', () {
    final info = SharedProjectInfo(
      headerGlobs: ['include\\v8\\api.h', 'v8.h'],
      sourceGlobs: ['src\\v8wrap\\win32.cpp'],
    );
    final mappings = buildMappingsFromSharedProject(info, 'v8');

    expect(mappings, hasLength(3));
    // 头文件：target 取相对目录（根目录头文件用源目录名）。
    expect(
      mappings.any(
        (m) => m.srcGlob == r'include\v8\api.h' && m.target == r'include\v8',
      ),
      isTrue,
    );
    expect(
      mappings.any((m) => m.srcGlob == 'v8.h' && m.target == 'v8'),
      isTrue,
    );
    // 源码：target 为 build\native\src\{源目录名}\{相对目录}。
    expect(
      mappings.any(
        (m) =>
            m.srcGlob == r'src\v8wrap\win32.cpp' &&
            m.target == r'build\native\src\v8\src\v8wrap',
      ),
      isTrue,
    );
  });

  test('mergeCompileConfigFromSharedProject 去重追加不覆盖', () {
    final base = CompileConfig(
      additionalDependencies: 'ws2_32.lib;user32',
      additionalIncludeDirectories: 'include',
      preprocessorDefines: 'NOMINMAX',
    );
    final info = SharedProjectInfo(
      additionalDependencies: ['ws2_32.lib', 'ntdll.lib'],
      additionalIncludeDirectories: ['extra'],
      preprocessorDefinitions: ['NDEBUG'],
    );
    final merged = mergeCompileConfigFromSharedProject(base, info);

    // ws2_32.lib 去重，ntdll.lib 追加。
    expect(merged.additionalDependencies, 'ws2_32.lib;user32;ntdll.lib');
    expect(merged.additionalIncludeDirectories, 'include;extra');
    expect(merged.preprocessorDefines, 'NOMINMAX;NDEBUG');
    // 既有语言标准等保持不变。
    expect(merged.languageStandard, base.languageStandard);
  });

  test(r'解析含 $(MSBuildThisFileDirectory) 的 ClInclude 剥离宏前缀为相对路径', () {
    final file = writeFile('Shared.vcxitems', r'''
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <ItemGroup>
    <ClInclude Include="$(MSBuildThisFileDirectory)mimalloc\mimalloc-new-delete.h" />
    <ClInclude Include="$(MSBuildThisFileDirectory)mimalloc\mimalloc.h" />
  </ItemGroup>
</Project>
''');
    final info = parseSharedProject(file.path);

    // 不再出现字面 $(MSBuildThisFileDirectory) 前缀（否则会变成 bogus srcGlob）。
    expect(info.headerGlobs, [
      r'mimalloc\mimalloc-new-delete.h',
      r'mimalloc\mimalloc.h',
    ]);
    expect(info.headerGlobs.any((g) => g.contains(r'$(')), isFalse);
    // 派生映射 srcGlob 相对源目录，可被后续打包路径拼接。
    final mappings = buildMappingsFromSharedProject(info, 'mimalloc');
    expect(
      mappings.any(
        (m) =>
            m.srcGlob == r'mimalloc\mimalloc-new-delete.h' &&
            m.target == 'mimalloc',
      ),
      isTrue,
    );
  });

  test('含宏的包含目录/依赖/宏在 macro* 列表与原列表中都保留', () {
    final file = writeFile('Shared.vcxitems', r'''
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <PropertyGroup>
    <AdditionalIncludeDirectories>include;$(MSBuildThisFileDirectory)extra;$(SolutionDir)inc;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    <AdditionalDependencies>ws2_32.lib;$(BuildDir)\foo.lib</AdditionalDependencies>
    <PreprocessorDefinitions>NOMINMAX;$(BaseDefines);USE_$(Platform)</PreprocessorDefinitions>
  </PropertyGroup>
</Project>
''');
    final info = parseSharedProject(file.path);

    // 原列表保留全部（含宏），与既有语义兼容。
    expect(info.additionalIncludeDirectories, [
      'include',
      r'$(MSBuildThisFileDirectory)extra',
      r'$(SolutionDir)inc',
      '%(AdditionalIncludeDirectories)',
    ]);
    expect(info.additionalDependencies, ['ws2_32.lib', r'$(BuildDir)\foo.lib']);
    expect(info.preprocessorDefinitions, [
      'NOMINMAX',
      r'$(BaseDefines)',
      r'USE_$(Platform)',
    ]);

    // macro* 列表只含 MSBuild 引用条目（$(...) 与 %(...)）。
    expect(info.macroIncludeDirectories, [
      r'$(MSBuildThisFileDirectory)extra',
      r'$(SolutionDir)inc',
      '%(AdditionalIncludeDirectories)',
    ]);
    expect(info.macroDependencies, [r'$(BuildDir)\foo.lib']);
    expect(info.macroPreprocessorDefinitions, [
      r'$(BaseDefines)',
      r'USE_$(Platform)',
    ]);
  });

  test('解析 PreBuildEvent/PostBuildEvent 命令并去空去重', () {
    final file = writeFile('Shared.vcxitems', r'''
<?xml version="1.0" encoding="utf-8"?>
<Project>
  <PropertyGroup>
    <PreBuildEvent>
      <Command>echo pre one
echo pre two</Command>
    </PreBuildEvent>
    <PostBuildEvent>
      <Command>copy /y a b</Command>
    </PostBuildEvent>
  </PropertyGroup>
</Project>
''');
    final info = parseSharedProject(file.path);

    expect(info.preBuildCommands, ['echo pre one', 'echo pre two']);
    expect(info.postBuildCommands, ['copy /y a b']);
  });

  test('mergeCompileConfigFromSharedProject 合并编译前/后命令（去重）', () {
    final base = CompileConfig(
      preBuildCommands: ['echo base'],
      postBuildCommands: ['echo base'],
    );
    final info = SharedProjectInfo(
      preBuildCommands: ['echo base', 'echo shared'],
      postBuildCommands: ['echo shared'],
    );
    final merged = mergeCompileConfigFromSharedProject(base, info);

    expect(merged.preBuildCommands, ['echo base', 'echo shared']);
    expect(merged.postBuildCommands, ['echo base', 'echo shared']);
  });

  test('真实 mimalloc.vcxitems 解析：无字面宏前缀（若文件存在）', () {
    const path = r'D:\CODE\Library\mimalloc\mimalloc.vcxitems';
    if (!File(path).existsSync()) {
      markTestSkipped('mimalloc 共享项目不存在，跳过实测');
      return;
    }
    final info = parseSharedProject(path);
    expect(info.headerGlobs, isNotEmpty);
    // 关键：headerGlob 不再含字面 $( 宏前缀（否则打包时拼出错误路径）。
    expect(info.headerGlobs.any((g) => g.contains(r'$(')), isFalse);
    expect(
      info.headerGlobs.first.startsWith(r'mimalloc\'),
      isTrue,
      reason:
          r'首个头文件应剥离 $(MSBuildThisFileDirectory) 前缀，'
          '得到相对源目录的路径',
    );
    // 含宏的包含目录应原样保留，供生成器原样输出。
    expect(
      info.macroIncludeDirectories,
      contains('%(AdditionalIncludeDirectories)'),
    );
  });
}
