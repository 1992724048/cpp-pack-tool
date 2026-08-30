import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/models/pack_project.dart';
import 'package:cpp_nuget_pack/services/package_registry.dart';
import 'package:cpp_nuget_pack/services/path_utils.dart';

PackProject buildProject(String id) {
  return PackProject(
    packageId: id,
    version: '1.2.3',
    description: '测试包',
    sourceDirs: [
      SourceDir(
        path: r'C:\src\v8',
        mappings: [FileMapping(srcGlob: r'*.h', target: r'include\v8')],
      ),
    ],
    platforms: ['x64'],
    configurations: ['Debug', 'Release'],
    compileConfig: CompileConfig(preprocessorDefines: 'NOMINMAX'),
  );
}

void main() {
  late Directory tempRoot;
  late String outputDir;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('pkg_registry_');
    outputDir = joinPath([tempRoot.path, 'out']);
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // 清理失败不阻塞测试。
    }
  });

  group('loadRegistry', () {
    test('文件不存在返回空列表且无错误', () {
      final result = loadRegistry(outputDir);
      expect(result.hasError, isFalse);
      expect(result.packages, isEmpty);
    });

    test('损坏的 JSON 返回空列表且带错误信息', () {
      Directory(outputDir).createSync(recursive: true);
      File(joinPath([outputDir, kRegistryFileName]))
          .writeAsStringSync('{ not valid json !!!');
      expect(() => loadRegistry(outputDir), returnsNormally);
      final result = loadRegistry(outputDir);
      expect(result.packages, isEmpty);
      expect(result.hasError, isTrue);
      expect(result.error, isNotNull);
    });

    test('正常解析抛出包列表', () {
      saveRegistry(outputDir, [
        RegisteredPackage(
          project: buildProject('V8.Native'),
          lastPackedAt: DateTime.parse('2026-08-27T12:00:00'),
        ),
      ]);
      final result = loadRegistry(outputDir);
      expect(result.hasError, isFalse);
      expect(result.packages, hasLength(1));
      final pkg = result.packages.single;
      expect(pkg.project.packageId, 'V8.Native');
      expect(pkg.project.version, '1.2.3');
      expect(pkg.project.sourceDirs.single.mappings.single.srcGlob, r'*.h');
      expect(pkg.project.compileConfig.preprocessorDefines, 'NOMINMAX');
      expect(pkg.lastPackedAt?.toIso8601String(), '2026-08-27T12:00:00.000');
    });
  });

  group('saveRegistry', () {
    test('目录不存在时自动创建并落盘，原子写不留临时文件', () {
      expect(Directory(outputDir).existsSync(), isFalse);
      saveRegistry(outputDir, [
        RegisteredPackage(project: buildProject('A.B'), lastPackedAt: null),
      ]);
      expect(Directory(outputDir).existsSync(), isTrue);
      final file = File(joinPath([outputDir, kRegistryFileName]));
      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['packages'], hasLength(1));
      final entry =
          (decoded['packages'] as List).single as Map<String, dynamic>;
      expect(entry['project'], isA<Map<String, dynamic>>());
    });

    test('重复保存覆盖旧内容', () {
      saveRegistry(outputDir, [
        RegisteredPackage(project: buildProject('X.Y')),
      ]);
      saveRegistry(outputDir, [
        RegisteredPackage(project: buildProject('X.Y')),
      ]);
      final result = loadRegistry(outputDir);
      expect(result.packages, hasLength(1));
      expect(result.packages.single.project.packageId, 'X.Y');
    });
  });

  group('upsertPackage', () {
    test('新 packageId 追加一条', () {
      expect(
        upsertPackage(
          outputDir,
          RegisteredPackage(project: buildProject('B.C')),
        ),
        isTrue,
      );
      expect(loadRegistry(outputDir).packages, hasLength(1));
    });

    test('相同 packageId 更新并覆盖 lastPackedAt', () {
      final first = RegisteredPackage(
        project: buildProject('Foo.Bar'),
        lastPackedAt: DateTime.parse('2026-08-27T12:00:00'),
      );
      final second = RegisteredPackage(
        project: buildProject('Foo.Bar'),
        lastPackedAt: DateTime.parse('2026-09-01T08:00:00'),
      );
      expect(upsertPackage(outputDir, first), isTrue);
      expect(upsertPackage(outputDir, second), isTrue);
      final result = loadRegistry(outputDir);
      expect(result.packages, hasLength(1));
      expect(
        result.packages.single.lastPackedAt?.toIso8601String(),
        '2026-09-01T08:00:00.000',
      );
    });

    test('空输出目录返回 false 且不写入', () {
      expect(
        upsertPackage('', RegisteredPackage(project: buildProject('Z'))),
        isFalse,
      );
    });
  });

  group('removePackage', () {
    test('移除存在的 packageId 并落盘', () {
      saveRegistry(outputDir, [
        RegisteredPackage(project: buildProject('Keep.A')),
        RegisteredPackage(project: buildProject('Drop.B')),
      ]);
      expect(removePackage(outputDir, 'Drop.B'), isTrue);
      final result = loadRegistry(outputDir);
      expect(result.packages, hasLength(1));
      expect(result.packages.single.project.packageId, 'Keep.A');
    });

    test('文件不存在时静默返回 true', () {
      expect(removePackage(outputDir, 'Nobody'), isTrue);
    });

    test('移除不存在的 packageId 保持其它记录不变', () {
      saveRegistry(outputDir, [
        RegisteredPackage(project: buildProject('Stay')),
      ]);
      expect(removePackage(outputDir, 'Missing'), isTrue);
      expect(loadRegistry(outputDir).packages, hasLength(1));
    });
  });

  group('writeSourceDirConfig / readSourceDirConfig', () {
    test('写入后读取往返一致', () {
      final srcDir = Directory(joinPath([tempRoot.path, 'src', 'v8']))
        ..createSync(recursive: true);
      expect(
        writeSourceDirConfig(srcDir.path, buildProject('V8.Native')),
        isTrue,
      );
      final result = readSourceDirConfig(srcDir.path);
      expect(result.hasError, isFalse);
      expect(result.project, isNotNull);
      expect(result.project!.packageId, 'V8.Native');
      expect(result.project!.version, '1.2.3');
      expect(result.project!.compileConfig.preprocessorDefines, 'NOMINMAX');
    });

    test('源目录不存在时写入返回 false', () {
      final missing = joinPath([tempRoot.path, 'missing']);
      expect(writeSourceDirConfig(missing, buildProject('X.Y')), isFalse);
    });

    test('损坏的配置文件返回空项目并带错误', () {
      final srcDir = Directory(joinPath([tempRoot.path, 'src', 'bad']))
        ..createSync(recursive: true);
      File(joinPath([srcDir.path, kSourceDirConfigFileName]))
          .writeAsStringSync('{ not valid json !!!');
      final result = readSourceDirConfig(srcDir.path);
      expect(result.project, isNull);
      expect(result.hasError, isTrue);
      expect(result.error, isNotNull);
    });

    test('文件不存在返回空结果且无错误', () {
      final srcDir = Directory(joinPath([tempRoot.path, 'nothere']))
        ..createSync(recursive: true);
      final result = readSourceDirConfig(srcDir.path);
      expect(result.hasError, isFalse);
      expect(result.project, isNull);
    });
  });
}
