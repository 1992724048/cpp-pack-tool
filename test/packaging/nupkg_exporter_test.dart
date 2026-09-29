import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
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

  /// 强杀出口用的独立目录，自行尽力清理，不走上面那个严格的 tearDown。
  ///
  /// 被 `Isolate.kill` 杀掉的 isolate 不会被 VM 跑 finalizer，其写句柄不随退出信号释放
  /// （实测 30/30 轮产物立即删不掉，3 秒后仍有 14/30 被占），共用目录的递归删除会被
  /// 这份残留句率住，故该用例必须自建目录自收尾。
  Directory forceKillRoot() {
    final Directory own = Directory.systemTemp.createTempSync(
      'nupkg_force_kill_test',
    );
    addTearDown(() async {
      for (int attempt = 1; attempt <= 5; attempt++) {
        try {
          if (own.existsSync()) {
            own.deleteSync(recursive: true);
          }
          return;
        } on FileSystemException {
          await Future<void>.delayed(Duration(milliseconds: 100 * attempt));
        }
      }
    });
    return own;
  }

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

  test('含脚本包导出 .ps1（单次 BOM）且 Content_Types 覆盖 ps1', () async {
    final String source = joinPath(root.path, 'source');
    final PackModel pack = _pack(sourcePath: source)
      ..scripts = <ScriptProjectModel>[_validScript()];

    final Archive archive = await _exportAndDecode(root, pack);
    const String scriptPath = 'build/native/files/scripts/script_1.ps1';

    expect(
      archive.files.any((ArchiveFile file) => file.name == scriptPath),
      isTrue,
    );
    final List<int> bytes = _bytesOf(archive, scriptPath);
    expect(bytes.length, greaterThan(3));
    expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
    expect(_countBomOccurrences(bytes), 1);
    expect(
      _textOf(archive, _contentTypesPath),
      contains('<Default Extension="ps1" ContentType="application/octet" />'),
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

  group('进度与取消', () {
    test('进度按字节加权回传且以 1 收尾', () async {
      final String source = joinPath(root.path, 'source');
      _writeFile(joinPath(source, 'include/foo.h'), 'int foo();\n');
      final PackModel pack = _pack(sourcePath: source)
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        ];
      final List<double> fractions = <double>[];

      await exportNuGetPackage(
        pack,
        joinPath(root.path, 'out'),
        iconResolver: _fakeIconResolver,
        onProgress: fractions.add,
      );

      expect(fractions, isNotEmpty);
      expect(fractions.last, 1);
      // 严格单调不减：条目是顺序落盘的。
      for (int index = 1; index < fractions.length; index++) {
        expect(fractions[index], greaterThanOrEqualTo(fractions[index - 1]));
      }
    });

    test('导出期间事件循环仍被调度（主 isolate 未阻塞）', () async {
      final String source = joinPath(root.path, 'source');
      // 3 MB：单条目足够大，若压缩跑在主 isolate 上，Timer 不会被调度。
      final File bigFile = File(joinPath(source, 'lib/big.lib'))
        ..createSync(recursive: true);
      final RandomAccessFile handle = bigFile.openSync(mode: FileMode.write);
      for (int index = 0; index < 3; index++) {
        handle.writeFromSync(
          List<int>.generate(1 << 20, (int step) => (step * (index + 2)) % 251),
        );
      }
      handle.closeSync();
      final PackModel pack = _pack(sourcePath: source)
        ..files = <FileModel>[
          FileModel(name: 'big.lib', path: 'lib/big.lib', size: 3 << 20),
        ];

      int ticks = 0;
      final Timer ticker = Timer.periodic(
        const Duration(milliseconds: 10),
        (Timer _) => ticks++,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final int before = ticks;
      await exportNuGetPackage(
        pack,
        joinPath(root.path, 'out'),
        iconResolver: _fakeIconResolver,
      );
      ticker.cancel();

      // 不断言具体次数（随机器性能波动）。
      expect(ticks - before, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('取消后抛出 ExportCancelledException 且不残留 .tmp', () async {
      final String source = joinPath(root.path, 'source');
      // 结构上必须「大条目在前 + 大量小条目在后」：取消靠消息往返落地，条目数太少时
      // 子 isolate 会在消息送达前跑完全部条目，测出来的成败是掷骰子。
      final File bigFile = File(joinPath(source, 'lib/big.lib'))
        ..createSync(recursive: true);
      final RandomAccessFile handle = bigFile.openSync(mode: FileMode.write);
      for (int index = 0; index < 8; index++) {
        handle.writeFromSync(
          List<int>.generate(1 << 20, (int step) => (step * (index + 3)) % 251),
        );
      }
      handle.closeSync();
      final List<FileModel> files = <FileModel>[
        FileModel(name: 'big.lib', path: 'lib/big.lib', size: 8 << 20),
      ];
      for (int index = 0; index < 400; index++) {
        _writeFile(joinPath(source, 'include/u$index.h'), 'int f$index();\n');
        files.add(
          FileModel(name: 'u$index.h', path: 'include/u$index.h', size: 10),
        );
      }
      final PackModel pack = _pack(sourcePath: source)..files = files;
      final String outputDirectory = joinPath(root.path, 'out');
      final ExportCancelToken token = ExportCancelToken();
      int seen = 0;

      await expectLater(
        exportNuGetPackage(
          pack,
          outputDirectory,
          iconResolver: _fakeIconResolver,
          cancelToken: token,
          onProgress: (double fraction) {
            seen++;
            if (seen == 1) {
              token.cancel();
            }
          },
        ),
        throwsA(isA<ExportCancelledException>()),
      );

      // 取消发生在首条目之后，故至少落过一个条目，产物必然不是完整包。
      expect(seen, greaterThan(0));
      expect(Directory(outputDirectory).listSync(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('进度回调抛异常时导出以该异常失败而非永久挂起', () async {
      final Directory own = forceKillRoot();
      final String source = joinPath(own.path, 'source');
      _writeFile(joinPath(source, 'include/foo.h'), 'int foo();\n');
      final PackModel pack = _pack(sourcePath: source)
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        ];
      final String outputDirectory = joinPath(own.path, 'out');

      // onProgress 是公开注入签名，第三方实现抛异常若逃出端口监听器，completer
      // 永不完成。
      await expectLater(
        exportNuGetPackage(
          pack,
          outputDirectory,
          iconResolver: _fakeIconResolver,
          onProgress: (double _) => throw StateError('第三方进度回调炸了'),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            '第三方进度回调炸了',
          ),
        ),
      );
      // 不能只断言「抛了 StateError」：清理阶段的删除失败曾把导出本身的异常顶替成
      // PathAccessException，那会让用户看到「无法访问文件」而不是真正的原因。
      expect(_nupkgFilesIn(outputDirectory), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('导出前即已置位的取消令牌同样中止作业', () async {
      final String source = joinPath(root.path, 'source');
      _writeFile(joinPath(source, 'include/foo.h'), 'int foo();\n');
      final PackModel pack = _pack(sourcePath: source)
        ..files = <FileModel>[
          FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
        ];
      final String outputDirectory = joinPath(root.path, 'out');
      final ExportCancelToken token = ExportCancelToken()..cancel();

      await expectLater(
        exportNuGetPackage(
          pack,
          outputDirectory,
          iconResolver: _fakeIconResolver,
          cancelToken: token,
        ),
        throwsA(isA<ExportCancelledException>()),
      );

      expect(Directory(outputDirectory).listSync(), isEmpty);
    });
  });

  group('前置校验', () {
    test('图标超过 nuget.org 上限时明确报错且不建产物', () async {
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
          iconResolver: (PackModel pack) async =>
              Uint8List(maxNuGetIconBytes + 1),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('超过 nuget.org 上限'),
          ),
        ),
      );
      expect(Directory(outputDirectory).existsSync(), isFalse);
    });
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

ScriptProjectModel _validScript() {
  final ScriptProjectModel project = ScriptProjectModel(
    id: 'script_1',
    name: '脚本 1',
    trigger: ScriptTrigger.pre,
  );
  project.nodes = <ScriptNodeModel>[
    ScriptNodeModel(id: 'n1', type: 'flow.entry'),
    ScriptNodeModel(id: 'n2', type: 'value.text')..params['value'] = '你好',
    ScriptNodeModel(id: 'n3', type: 'log.message'),
  ];
  project.edges = <ScriptEdgeModel>[
    ScriptEdgeModel(
      from: ScriptEdgeEndpoint(node: 'n1', pin: 'out'),
      to: ScriptEdgeEndpoint(node: 'n3', pin: 'exec'),
    ),
    ScriptEdgeModel(
      from: ScriptEdgeEndpoint(node: 'n2', pin: 'result'),
      to: ScriptEdgeEndpoint(node: 'n3', pin: 'message'),
    ),
  ];
  return project;
}

/// 输出目录里已落地的成品包路径（`.tmp` 临时件不算）。
List<String> _nupkgFilesIn(String outputDirectory) => <String>[
  for (final FileSystemEntity entity in Directory(outputDirectory).listSync())
    if (entity.path.endsWith('.nupkg')) entity.path,
];

int _countBomOccurrences(List<int> bytes) {
  int count = 0;
  for (int index = 0; index + 2 < bytes.length; index++) {
    if (bytes[index] == 0xEF &&
        bytes[index + 1] == 0xBB &&
        bytes[index + 2] == 0xBF) {
      count++;
    }
  }
  return count;
}
