import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/cmake_exporter.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cmake_exporter_test');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('导出 zip 包含全部计划条目与 CMake 配置三件套', () async {
    final String source = joinPath(root.path, 'mylib');
    _writeFile(joinPath(source, 'include/foo.h'), 'int foo();\n');
    _writeFile(joinPath(source, 'include/empty.h'), '');
    _writeBytes(joinPath(source, 'lib/x64/Release/foo.lib'), <int>[1, 2, 3, 4]);
    _writeFile(joinPath(source, 'src/main.cpp'), 'int main() {}\n');

    final PackModel pack = _pack(sourcePath: source)
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        FileModel(name: 'empty.h', path: 'include/empty.h', size: 0),
        FileModel(name: 'foo.lib', path: 'lib/x64/Release/foo.lib', size: 4),
        FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 14),
      ];
    final String outputDirectory = joinPath(root.path, 'out/nested');

    final PackageExportResult result = await exportCmakePackage(
      pack,
      outputDirectory,
    );

    expect(
      result.outputPath,
      joinPath(outputDirectory, 'demo-1.2.3-cmake.zip'),
    );
    expect(result.fileCount, 7);
    expect(result.packageSize, greaterThan(0));
    final File zip = File(result.outputPath);
    expect(zip.existsSync(), isTrue);
    expect(zip.lengthSync(), result.packageSize);

    final Archive archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    expect(archive.files.map((ArchiveFile file) => file.name), <String>[
      'files/src/main.cpp',
      'include/mylib/empty.h',
      'include/mylib/foo.h',
      'lib/cmake/demo/demoConfig.cmake',
      'lib/cmake/demo/demoConfigVersion.cmake',
      'lib/cmake/demo/demoTargets.cmake',
      'lib/x64/Release/foo.lib',
    ]);

    expect(_textOf(archive, 'include/mylib/foo.h'), 'int foo();\n');
    expect(_bytesOf(archive, 'include/mylib/empty.h'), isEmpty);
    expect(_bytesOf(archive, 'lib/x64/Release/foo.lib'), <int>[1, 2, 3, 4]);
    expect(_textOf(archive, 'files/src/main.cpp'), 'int main() {}\n');

    final String config = _textOf(archive, 'lib/cmake/demo/demoConfig.cmake');
    expect(config, contains('macro(check_required_components _NAME)'));
    expect(
      config,
      contains(r'include("${CMAKE_CURRENT_LIST_DIR}/demoTargets.cmake")'),
    );
    expect(config, contains('check_required_components(demo)'));

    final String targets = _textOf(archive, 'lib/cmake/demo/demoTargets.cmake');
    expect(targets, contains('add_library(demo::demo INTERFACE IMPORTED)'));
    expect(
      targets,
      contains(
        r'  INTERFACE_LINK_LIBRARIES "${_IMPORT_PREFIX}/lib/x64/Release/foo.lib"',
      ),
    );
    expect(
      targets,
      contains(r'INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"'),
    );

    expect(
      _textOf(archive, 'lib/cmake/demo/demoConfigVersion.cmake'),
      contains('set(PACKAGE_VERSION "1.2.3")'),
    );
  });

  test('版本号非数字时省略 ConfigVersion 且文件名保留版本', () async {
    final String source = joinPath(root.path, 'mylib');
    _writeFile(joinPath(source, 'include/foo.h'), 'int foo();\n');

    final PackModel pack = _pack(version: '1.2-beta', sourcePath: source)
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
      ];
    final String outputDirectory = joinPath(root.path, 'out');

    final PackageExportResult result = await exportCmakePackage(
      pack,
      outputDirectory,
    );

    expect(
      result.outputPath,
      joinPath(outputDirectory, 'demo-1.2-beta-cmake.zip'),
    );
    expect(result.fileCount, 3);
    final Archive archive = ZipDecoder().decodeBytes(
      File(result.outputPath).readAsBytesSync(),
    );
    expect(archive.files.map((ArchiveFile file) => file.name), <String>[
      'include/mylib/foo.h',
      'lib/cmake/demo/demoConfig.cmake',
      'lib/cmake/demo/demoTargets.cmake',
    ]);
  });

  test('重复导出覆盖旧文件且不残留临时文件', () async {
    final String source = joinPath(root.path, 'mylib');
    _writeFile(joinPath(source, 'include/foo.h'), 'old');
    final PackModel pack = _pack(sourcePath: source)
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 3),
      ];
    final String outputDirectory = joinPath(root.path, 'out');

    final PackageExportResult first = await exportCmakePackage(
      pack,
      outputDirectory,
    );
    _writeFile(joinPath(source, 'include/foo.h'), 'new-content');
    final PackageExportResult second = await exportCmakePackage(
      pack,
      outputDirectory,
    );

    expect(second.outputPath, first.outputPath);
    final Archive archive = ZipDecoder().decodeBytes(
      File(second.outputPath).readAsBytesSync(),
    );
    expect(_textOf(archive, 'include/mylib/foo.h'), 'new-content');

    final List<FileSystemEntity> files = Directory(outputDirectory).listSync();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('-cmake.zip'));
  });

  test('缺少源目录时抛出 ArgumentError 且不创建输出目录', () async {
    final String outputDirectory = joinPath(root.path, 'out');

    await expectLater(
      exportCmakePackage(_pack(), outputDirectory),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError error) => error.message,
          'message',
          '该包缺少源目录信息，无法打包',
        ),
      ),
    );
    expect(Directory(outputDirectory).existsSync(), isFalse);
  });

  test('源文件缺失时抛出异常', () async {
    final PackModel pack = _pack(sourcePath: joinPath(root.path, 'mylib'))
      ..files = <FileModel>[
        FileModel(name: 'missing.h', path: 'include/missing.h', size: 1),
      ];

    await expectLater(
      exportCmakePackage(pack, joinPath(root.path, 'out')),
      throwsA(isA<FileSystemException>()),
    );
  });
}

PackModel _pack({String? sourcePath, String version = '1.2.3+7'}) {
  return PackModel(
    name: 'demo',
    version: version,
    author: 'tester',
    description: '演示包',
    license: 'MIT',
    sourcePath: sourcePath,
  );
}

void _writeFile(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

void _writeBytes(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

String _textOf(Archive archive, String name) =>
    utf8.decode(_bytesOf(archive, name));

List<int> _bytesOf(Archive archive, String name) =>
    archive.files.firstWhere((ArchiveFile file) => file.name == name).content;
