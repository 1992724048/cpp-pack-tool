import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/models/pack_project.dart';
import 'package:cpp_nuget_pack/services/msbuild_generator.dart';
import 'package:cpp_nuget_pack/services/nuspec_generator.dart';

PackProject buildProject() {
  return PackProject(
    packageId: 'V8.Native',
    version: '1.0.0',
    authors: 'ACME',
    owners: 'ACME',
    description: '预编译静态库',
    tags: 'v8, native',
    license: 'MIT',
    repository: 'https://example.com/repo',
    sourceDirs: [
      SourceDir(
        path: r'C:\src\v8',
        mappings: [
          FileMapping(srcGlob: r'..\v8\*.h', target: r'v8'),
          FileMapping(srcGlob: r'*.lib', target: r'build\native\lib\x64\Debug'),
          FileMapping(
            srcGlob: r'src\v8wrap\win32.cpp',
            target: r'build\native\src\v8wrap',
          ),
          FileMapping(
            srcGlob: r'lib\x64\Debug\icudtl.dat',
            target: r'build\native\lib\x64\Debug',
          ),
        ],
      ),
    ],
    compileConfig: CompileConfig(
      preprocessorDefines: 'NOMINMAX;V8_ENABLE_WEBASSEMBLY',
      configDefines: {'Debug': 'V8_ENABLE_CHECKS'},
      additionalLibraryDirectories: r'extra\lib',
      additionalDependencies: 'ws2_32.lib;ntdll.lib',
      clanguageStandard: 'c17',
    ),
  );
}

void main() {
  group('nuspec 生成', () {
    final nuspec = generate(buildProject(), baseDir: r'C:\pkg\build');

    test('含 XML 声明与命名空间', () {
      expect(nuspec, startsWith(r'<?xml version="1.0" encoding="utf-8"?>'));
      expect(
        nuspec,
        contains(
          'xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd"',
        ),
      );
      expect(nuspec.trim(), endsWith('</package>'));
    });

    test('metadata 含 id/version/authors/owners/description/tags', () {
      expect(nuspec, contains('<id>V8.Native</id>'));
      expect(nuspec, contains('<version>1.0.0</version>'));
      expect(nuspec, contains('<authors>ACME</authors>'));
      expect(nuspec, contains('<owners>ACME</owners>'));
      expect(nuspec, contains('<description>预编译静态库</description>'));
      expect(nuspec, contains('<tags>v8 native</tags>'));
      expect(
        nuspec,
        contains('<requireLicenseAcceptance>false</requireLicenseAcceptance>'),
      );
    });

    test('license/repository 非空时输出', () {
      expect(nuspec, contains('<license>MIT</license>'));
      expect(
        nuspec,
        contains('<repository>https://example.com/repo</repository>'),
      );
    });

    test('files 段按 sourceDirs->mappings 展开', () {
      expect(
        nuspec,
        contains(r'<file src="..\v8\*.h" target="build\native\include\v8" />'),
      );
      expect(
        nuspec,
        contains(
          r'<file src="..\..\src\v8\*.lib" target="build\native\lib\x64\Debug" />',
        ),
      );
      // 源码映射 target 自动拼 `build\native\src` 前缀（相对 src 段）。
      expect(
        nuspec,
        contains(
          r'<file src="..\..\src\v8\src\v8wrap\win32.cpp" target="build\native\src\v8wrap" />',
        ),
      );
      // 数据映射 target 原样输出为包内目录。
      expect(
        nuspec,
        contains(
          r'<file src="..\..\src\v8\lib\x64\Debug\icudtl.dat" target="build\native\lib\x64\Debug" />',
        ),
      );
      expect(nuspec, contains('<files>'));
      expect(nuspec, contains('</files>'));
    });

    test('files 段开头包含 props/targets 集成文件条目（src 相对 nuspec 目录）', () {
      // 新布局：nuspec 位于 build\ 下，src 相对 nuspec = native\...；target 为包内路径。
      expect(
        nuspec,
        contains(
          r'    <file src="native\V8.Native.props" target="build\native\V8.Native.props" />',
        ),
      );
      expect(
        nuspec,
        contains(
          r'    <file src="native\V8.Native.targets" target="build\native\V8.Native.targets" />',
        ),
      );

      final filesOpenIdx = nuspec.indexOf('<files>');
      final propsIdx = nuspec.indexOf(
        r'<file src="native\V8.Native.props" target="build\native\V8.Native.props" />',
      );
      final targetsIdx = nuspec.indexOf(
        r'<file src="native\V8.Native.targets" target="build\native\V8.Native.targets" />',
      );
      final firstMappingIdx = nuspec.indexOf(
        r'<file src="..\v8\*.h" target="build\native\include\v8" />',
      );

      // 两条集成文件条目必须位于 files 段开头、且均在首个 sourceDirs 映射之前。
      expect(filesOpenIdx, isNonNegative);
      expect(propsIdx, greaterThan(filesOpenIdx));
      expect(targetsIdx, greaterThan(propsIdx));
      expect(firstMappingIdx, greaterThan(targetsIdx));
    });
  });

  group('xmlEscape', () {
    test('转义 XML 特殊字符', () {
      expect(xmlEscape('a<b&c>"d\''), 'a&lt;b&amp;c&gt;&quot;d&apos;');
    });
  });

  group('props 生成', () {
    final props = generateProps(buildProject());

    test('设置语言标准', () {
      expect(
        props,
        contains(
          "    <LanguageStandard Condition=\"'\$(LanguageStandard)' == ''\">stdcpp23</LanguageStandard>",
        ),
      );
    });

    test('C 语言标准非空时输出 CLanguageStandard', () {
      expect(
        props,
        contains(
          "    <CLanguageStandard Condition=\"'\$(CLanguageStandard)' == ''\">c17</CLanguageStandard>",
        ),
      );
    });

    test('C++ 标准最新（stdcpplatest）映射正确', () {
      final latest = buildProject().copyWith(
        compileConfig: buildProject().compileConfig.copyWith(
          languageStandard: 'stdcpplatest',
        ),
      );
      expect(
        generateProps(latest),
        contains(
          "    <LanguageStandard Condition=\"'\$(LanguageStandard)' == ''\">stdcpplatest</LanguageStandard>",
        ),
      );
    });

    test('生成 packageId 前缀的跳过宏标志', () {
      expect(
        props,
        contains(
          "<V8_Native_SkipDefines Condition=\"'\$(PreprocessorDefinitions)' != '' and "
          "\$(PreprocessorDefinitions.Contains('NOMINMAX'))\">true</V8_Native_SkipDefines>",
        ),
      );
    });

    test('预处理宏分配置展开并追加 %(PreprocessorDefinitions)', () {
      expect(
        props,
        contains(
          "<PreprocessorDefinitions Condition=\"'\$(V8_Native_SkipDefines)' != 'true' and "
          "'\$(Configuration)' == 'Debug'\">"
          'NOMINMAX;V8_ENABLE_WEBASSEMBLY;V8_ENABLE_CHECKS;%(PreprocessorDefinitions)'
          '</PreprocessorDefinitions>',
        ),
      );
      expect(
        props,
        contains(
          "<PreprocessorDefinitions Condition=\"'\$(V8_Native_SkipDefines)' != 'true' and "
          "'\$(Configuration)' == 'Release'\">"
          'NOMINMAX;V8_ENABLE_WEBASSEMBLY;%(PreprocessorDefinitions)'
          '</PreprocessorDefinitions>',
        ),
      );
    });

    test('包含路径含 MSBuildThisFileDirectory 与派生子目录', () {
      expect(props, contains(r'$(MSBuildThisFileDirectory)include'));
      expect(props, contains(r'$(MSBuildThisFileDirectory)include\v8'));
    });
  });

  group('targets 生成', () {
    final targets = generateTargets(buildProject());

    test('按平台×配置生成 {id}_LibDir 组合属性', () {
      expect(
        targets,
        contains(
          "<V8_Native_LibDir Condition=\"'\$(Platform)' == 'x64' and "
          "'\$(Configuration.ToLower())' == 'debug'\">"
          r'$(MSBuildThisFileDirectory)lib\x64\Debug</V8_Native_LibDir>',
        ),
      );
      expect(
        targets,
        contains(
          "<V8_Native_LibDir Condition=\"'\$(Platform)' == 'x64' and "
          "'\$(Configuration.ToLower())' == 'release'\">"
          r'$(MSBuildThisFileDirectory)lib\x64\Release</V8_Native_LibDir>',
        ),
      );
    });

    test('平台/配置检查 Target 带错误提示', () {
      expect(targets, contains('<Target Name="V8_NativeCheckPlatform"'));
      expect(targets, contains('V8.Native 包仅支持 x64 平台'));
      expect(targets, contains('<Target Name="V8_NativeCheckConfiguration"'));
    });

    test('注入源码 Target 仿照 V8NativeAddWin32Compile', () {
      expect(targets, contains('<Target Name="V8_NativeAddInjectedCompile"'));
      expect(targets, contains('BeforeTargets="SelectClCompile"'));
      expect(
        targets,
        contains(
          r'<ClCompile Include="$(MSBuildThisFileDirectory)src\v8wrap\win32.cpp" />',
        ),
      );
      expect(targets, contains('<V8_Native_win32_cpp_Injected'));
    });

    test('链接依赖与库路径', () {
      expect(
        targets,
        contains(
          r'$(V8_Native_LibDir);extra\lib;%(AdditionalLibraryDirectories)',
        ),
      );
      expect(
        targets,
        contains('ws2_32.lib;ntdll.lib;%(AdditionalDependencies)'),
      );
    });

    test('数据文件硬链接 Target 用映射目标并带防重复标志', () {
      expect(targets, contains('<Target Name="V8_NativeCopyicudtl_dat"'));
      // 源 = $(MSBuildThisFileDirectory) + 数据映射目标相对 build\native 的段。
      expect(
        targets,
        contains(
          r'''<Exec Command="cmd /c mklink /H &quot;$(OutDir)\icudtl.dat&quot; &quot;$(MSBuildThisFileDirectory)lib\x64\Debug\icudtl.dat&quot; 2&gt;nul || copy /y &quot;$(MSBuildThisFileDirectory)lib\x64\Debug\icudtl.dat&quot; &quot;$(OutDir)\icudtl.dat&quot; &gt;nul" Condition="!Exists('$(OutDir)\icudtl.dat')" />''',
        ),
      );
      expect(
        targets,
        contains(
          '<V8_Native_icudtl_dat_Copied>true</V8_Native_icudtl_dat_Copied>',
        ),
      );
    });
  });
}
