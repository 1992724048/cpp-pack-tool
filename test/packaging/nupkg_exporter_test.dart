import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

const String _contentTypesPath = '[Content_Types].xml';
const String _relationshipsPath = '_rels/.rels';
const String _iconPath = 'images/icon.png';
const String _corePropertiesPath =
    'package/services/metadata/core-properties/nuget.psmdcp';

/// 1×1 透明 PNG，供导出测试替代真实图标渲染。
final Uint8List _fakeIconPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<Uint8List> _fakeIconResolver(PackModel pack) async => _fakeIconPng;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nupkg_exporter_test');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('导出包包含 nuspec、targets、载荷与 OPC 三件套', () async {
    final String source = joinPath(root.path, 'source');
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

    final PackageExportResult result = await exportNuGetPackage(
      pack,
      outputDirectory,
      iconResolver: _fakeIconResolver,
    );

    expect(result.outputPath, joinPath(outputDirectory, 'demo.1.2.3.nupkg'));
    expect(result.fileCount, 10);
    expect(result.packageSize, greaterThan(0));
    final File nupkg = File(result.outputPath);
    expect(nupkg.existsSync(), isTrue);
    expect(nupkg.lengthSync(), result.packageSize);

    final Archive archive = ZipDecoder().decodeBytes(nupkg.readAsBytesSync());
    expect(archive.files.map((ArchiveFile file) => file.name), <String>[
      _relationshipsPath,
      'demo.nuspec',
      'build/native/demo.targets',
      'build/native/files/src/main.cpp',
      'build/native/include/source/empty.h',
      'build/native/include/source/foo.h',
      'build/native/lib/x64/Release/foo.lib',
      _iconPath,
      _contentTypesPath,
      _corePropertiesPath,
    ]);

    expect(_bytesOf(archive, _iconPath), _fakeIconPng);

    expect(
      _textOf(archive, 'build/native/include/source/foo.h'),
      'int foo();\n',
    );
    expect(_bytesOf(archive, 'build/native/include/source/empty.h'), isEmpty);
    expect(
      _bytesOf(archive, 'build/native/files/src/main.cpp'),
      utf8.encode('int main() {}\n'),
    );
    expect(_bytesOf(archive, 'build/native/lib/x64/Release/foo.lib'), <int>[
      1,
      2,
      3,
      4,
    ]);
    expect(
      _textOf(archive, 'build/native/include/source/foo.h'),
      isNot(contains('main')),
    );
    expect(
      _textOf(archive, 'build/native/files/src/main.cpp'),
      contains('int main() {}'),
    );

    final String nuspec = _textOf(archive, 'demo.nuspec');
    expect(nuspec, contains('<id>demo</id>'));
    expect(nuspec, contains('<version>1.2.3</version>'));
    expect(nuspec, contains('<license type="expression">MIT</license>'));
    expect(
      _textOf(archive, 'build/native/demo.targets'),
      contains('MSBuildThisFileDirectory'),
    );
  });

  test('Content_Types 覆盖包内全部文件扩展名', () async {
    final String source = joinPath(root.path, 'source');
    _writeFile(joinPath(source, 'include/foo.h'), 'int foo();\n');
    _writeFile(joinPath(source, 'src/main.cpp'), 'int main() {}\n');

    final PackModel pack = _pack(sourcePath: source)
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 14),
      ];

    final Archive archive = await _exportAndDecode(root, pack);
    final String contentTypes = _textOf(archive, _contentTypesPath);

    expect(
      contentTypes,
      contains(
        '<Default Extension="rels" '
        'ContentType="application/vnd.openxmlformats-package.relationships+xml" />',
      ),
    );
    expect(
      contentTypes,
      contains(
        '<Default Extension="psmdcp" '
        'ContentType="application/vnd.openxmlformats-package.core-properties+xml" />',
      ),
    );
    expect(
      contentTypes,
      contains(
        '<Default Extension="nuspec" ContentType="application/octet" />',
      ),
    );
    expect(
      contentTypes,
      contains(
        '<Default Extension="targets" ContentType="application/octet" />',
      ),
    );
    expect(
      contentTypes,
      contains('<Default Extension="png" ContentType="application/octet" />'),
    );
    expect(
      contentTypes,
      contains('<Default Extension="h" ContentType="application/octet" />'),
    );
    expect(
      contentTypes,
      contains('<Default Extension="cpp" ContentType="application/octet" />'),
    );
  });

  test('relationships 与 core-properties 指向 nuspec 与包内条目', () async {
    final String source = joinPath(root.path, 'source');

    final PackModel pack = _pack(sourcePath: source);

    final Archive archive = await _exportAndDecode(root, pack);
    final String relationships = _textOf(archive, _relationshipsPath);

    expect(
      relationships,
      contains(
        '<Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" '
        'Target="/demo.nuspec" Id="R1" />',
      ),
    );
    expect(
      relationships,
      contains(
        '<Relationship Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
        'Target="/$_corePropertiesPath" Id="R2" />',
      ),
    );

    final String coreProperties = _textOf(archive, _corePropertiesPath);
    expect(coreProperties, contains('<dc:creator>tester</dc:creator>'));
    expect(coreProperties, contains('<dc:description>演示包</dc:description>'));
    expect(coreProperties, contains('<dc:identifier>demo</dc:identifier>'));
    expect(coreProperties, contains('<version>1.2.3</version>'));
    expect(coreProperties, contains('<keywords>native cpp</keywords>'));
    expect(
      coreProperties,
      contains('<lastModifiedBy>cpp_nuget_pack</lastModifiedBy>'),
    );
  });

  test('元数据 XML 特殊字符被转义且空描述输出空元素', () async {
    final String source = joinPath(root.path, 'source');

    final Archive escaped = await _exportAndDecode(
      root,
      _pack(sourcePath: source, author: 'A & B', description: 'x < y'),
      outputName: 'escaped',
    );
    final String coreProperties = _textOf(escaped, _corePropertiesPath);
    expect(coreProperties, contains('<dc:creator>A &amp; B</dc:creator>'));
    expect(
      coreProperties,
      contains('<dc:description>x &lt; y</dc:description>'),
    );

    final Archive empty = await _exportAndDecode(
      root,
      _pack(sourcePath: source, description: null),
      outputName: 'empty',
    );
    expect(
      _textOf(empty, _corePropertiesPath),
      contains('<dc:description></dc:description>'),
    );
  });

  test('重复导出覆盖旧文件且不残留临时文件', () async {
    final String source = joinPath(root.path, 'source');
    _writeFile(joinPath(source, 'include/foo.h'), 'old');
    final PackModel pack = _pack(sourcePath: source)
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 3),
      ];
    final String outputDirectory = joinPath(root.path, 'out');

    final PackageExportResult first = await exportNuGetPackage(
      pack,
      outputDirectory,
      iconResolver: _fakeIconResolver,
    );
    _writeFile(joinPath(source, 'include/foo.h'), 'new-content');
    final PackageExportResult second = await exportNuGetPackage(
      pack,
      outputDirectory,
      iconResolver: _fakeIconResolver,
    );

    expect(second.outputPath, first.outputPath);
    final Archive archive = ZipDecoder().decodeBytes(
      File(second.outputPath).readAsBytesSync(),
    );
    expect(
      _textOf(archive, 'build/native/include/source/foo.h'),
      'new-content',
    );

    final List<FileSystemEntity> files = Directory(outputDirectory).listSync();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('.nupkg'));
  });

  test('源文件缺失时抛出异常', () async {
    final PackModel pack = _pack(sourcePath: joinPath(root.path, 'source'))
      ..files = <FileModel>[
        FileModel(name: 'missing.h', path: 'include/missing.h', size: 1),
      ];

    await expectLater(
      exportNuGetPackage(
        pack,
        joinPath(root.path, 'out'),
        iconResolver: _fakeIconResolver,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('缺少源目录时抛出 ArgumentError 且不创建输出目录', () async {
    final String outputDirectory = joinPath(root.path, 'out');

    await expectLater(
      exportNuGetPackage(
        _pack(),
        outputDirectory,
        iconResolver: _fakeIconResolver,
      ),
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

  test('图标解析失败时抛出异常且不创建输出目录', () async {
    final String source = joinPath(root.path, 'source');
    _writeFile(joinPath(source, 'include/foo.h'), 'int foo();\n');
    final PackModel pack = _pack(sourcePath: source)
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
      ];
    final String outputDirectory = joinPath(root.path, 'out');

    await expectLater(
      exportNuGetPackage(
        pack,
        outputDirectory,
        iconResolver: (PackModel pack) async => throw StateError('默认包图标渲染失败'),
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          '默认包图标渲染失败',
        ),
      ),
    );
    expect(Directory(outputDirectory).existsSync(), isFalse);
  });
}

PackModel _pack({
  String? sourcePath,
  String version = '1.2.3+7',
  String author = 'tester',
  String? description = '演示包',
}) {
  return PackModel(
    name: 'demo',
    version: version,
    author: author,
    description: description,
    license: 'MIT',
    sourcePath: sourcePath,
  );
}

Future<Archive> _exportAndDecode(
  Directory root,
  PackModel pack, {
  String outputName = 'out',
}) async {
  final PackageExportResult result = await exportNuGetPackage(
    pack,
    joinPath(root.path, outputName),
    iconResolver: _fakeIconResolver,
  );
  return ZipDecoder().decodeBytes(File(result.outputPath).readAsBytesSync());
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
