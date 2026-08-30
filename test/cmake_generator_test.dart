import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/models/pack_project.dart';
import 'package:cpp_nuget_pack/services/cmake_generator.dart';

PackProject buildCmakeProject() {
  return PackProject(
    packageId: 'Mimalloc',
    version: '1.0.0',
    sourceDirs: [
      SourceDir(
        path: r'C:\src\mimalloc',
        mappings: [
          FileMapping(srcGlob: r'..\mimalloc\*.h', target: r'mimalloc'),
          FileMapping(
            srcGlob: r'lib\x64\Debug\mimalloc.lib',
            target: r'build\native\lib\x64\Debug',
          ),
          FileMapping(
            srcGlob: r'lib\x64\Release\mimalloc.lib',
            target: r'build\native\lib\x64\Release',
          ),
        ],
      ),
    ],
    platforms: ['x64'],
    configurations: ['Debug', 'Release'],
    compileConfig: CompileConfig(
      languageStandard: 'stdcpplatest',
      preprocessorDefines: 'MIMALLOC;NOMINMAX',
      additionalDependencies: 'ws2_32.lib;ntdll.lib',
    ),
  );
}

void main() {
  final config = generateCmakeConfig(buildCmakeProject());

  test('生成 add_library STATIC IMPORTED 与分配置 IMPORTED_LOCATION', () {
    expect(config, contains('add_library(Mimalloc::Mimalloc STATIC IMPORTED)'));
    expect(
      config,
      contains(
        'IMPORTED_LOCATION_DEBUG '
        r'"${CMAKE_CURRENT_LIST_DIR}/lib/x64/Debug/mimalloc.lib"',
      ),
    );
    expect(
      config,
      contains(
        'IMPORTED_LOCATION_RELEASE '
        r'"${CMAKE_CURRENT_LIST_DIR}/lib/x64/Release/mimalloc.lib"',
      ),
    );
  });

  test('INTERFACE_INCLUDE_DIRECTORIES 指向包内 include', () {
    expect(
      config,
      contains(
        'INTERFACE_INCLUDE_DIRECTORIES '
        r'"${CMAKE_CURRENT_LIST_DIR}/include"',
      ),
    );
  });

  test('INTERFACE_COMPILE_DEFINITIONS 输出预处理宏', () {
    expect(
      config,
      contains('INTERFACE_COMPILE_DEFINITIONS "MIMALLOC;NOMINMAX"'),
    );
  });

  test('INTERFACE_LINK_LIBRARIES 将 .lib 转 CMake 名', () {
    expect(config, contains('INTERFACE_LINK_LIBRARIES "ws2_32;ntdll"'));
  });

  test('INTERFACE_COMPILE_FEATURES 将 stdcpplatest 映射为 cxx_std_23', () {
    expect(config, contains('INTERFACE_COMPILE_FEATURES cxx_std_23'));
  });

  test('仅有头文件（无库映射）时生成 INTERFACE IMPORTED', () {
    final headerOnly = PackProject(
      packageId: 'HeaderOnly',
      version: '1.0.0',
      sourceDirs: [
        SourceDir(
          path: r'C:\src\ho',
          mappings: [FileMapping(srcGlob: r'*.h', target: r'ho')],
        ),
      ],
      compileConfig: CompileConfig(),
    );
    final content = generateCmakeConfig(headerOnly);
    expect(
      content,
      contains('add_library(HeaderOnly::HeaderOnly INTERFACE IMPORTED)'),
    );
    expect(
      content,
      contains(
        'INTERFACE_INCLUDE_DIRECTORIES '
        r'"${CMAKE_CURRENT_LIST_DIR}/include"',
      ),
    );
    // 无 IMPORTED_LOCATION。
    expect(content, isNot(contains('IMPORTED_LOCATION')));
  });

  test('generateCmakeEntries 返回 {id}Config.cmake 单条目', () {
    final entries = generateCmakeEntries(buildCmakeProject());
    expect(entries, hasLength(1));
    expect(entries.single.path, 'MimallocConfig.cmake');
    expect(entries.single.content, contains('add_library(Mimalloc::Mimalloc'));
  });
}
