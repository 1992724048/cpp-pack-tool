import 'dart:io';

import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late PackStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pack_store_test');
    store = PackStore(rootPath: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ensureConfigExist', () {
    test('创建 config/packs 目录与 config.yaml', () async {
      await store.ensureConfigExist();

      expect(Directory('${tempDir.path}/packs').existsSync(), isTrue);
      final File configFile = File('${tempDir.path}/config.yaml');
      expect(configFile.existsSync(), isTrue);
      expect(configFile.readAsStringSync(), 'version: 1\n');
    });

    test('config.yaml 已存在时不覆盖', () async {
      final File configFile = File('${tempDir.path}/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('version: 2\n');

      await store.ensureConfigExist();

      expect(configFile.readAsStringSync(), 'version: 2\n');
    });
  });

  group('savePack / loadPacks', () {
    test('往返保留中文、多行描述、特殊字符与文件列表', () async {
      final PackModel pack =
          PackModel(
              name: '演示包',
              version: '1.2.3',
              author: '张三',
              description: '第一行\n第二行：包含 # 与 "引号"',
              license: 'MIT',
              iconPath: 'assets/logo.svg',
              sourcePath: r'D:\libs\演示',
            )
            ..files = <FileModel>[
              FileModel(name: 'foo.h', path: 'include/foo.h', size: 1234),
              FileModel(name: 'main.cpp', path: 'src/main.cpp', size: 2048),
            ];

      await store.savePack(pack);
      final PackLoadResult result = await store.loadPacks();

      expect(result.errors, isEmpty);
      expect(result.packs, hasLength(1));
      final PackModel loaded = result.packs.single;
      expect(loaded.name, '演示包');
      expect(loaded.version, '1.2.3');
      expect(loaded.author, '张三');
      expect(loaded.description, '第一行\n第二行：包含 # 与 "引号"');
      expect(loaded.license, 'MIT');
      expect(loaded.iconPath, 'assets/logo.svg');
      expect(loaded.sourcePath, r'D:\libs\演示');
      expect(loaded.files, hasLength(2));
      expect(loaded.files[0].name, 'foo.h');
      expect(loaded.files[0].path, 'include/foo.h');
      expect(loaded.files[0].size, 1234);
      expect(loaded.files[0].type, FileType.header);
      expect(loaded.files[1].name, 'main.cpp');
      expect(loaded.files[1].type, FileType.source);

      final String yaml = File('${tempDir.path}/packs/演示包.yaml')
          .readAsStringSync();
      expect(yaml, contains('|-\n'));
      expect(yaml, endsWith('\n'));
    });

    test('单行描述中的特殊字符往返正确', () async {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
        description: '冒号: #井号 "引号" \'单引号\'',
      );

      await store.savePack(pack);
      final PackLoadResult result = await store.loadPacks();

      expect(result.errors, isEmpty);
      expect(result.packs.single.description, '冒号: #井号 "引号" \'单引号\'');
    });

    test('null 字段不写入 YAML 文本', () async {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      await store.savePack(pack);
      final String yaml = File('${tempDir.path}/packs/demo.yaml')
          .readAsStringSync();

      expect(yaml, isNot(contains('description')));
      expect(yaml, isNot(contains('license')));
      expect(yaml, isNot(contains('iconPath')));
      expect(yaml, isNot(contains('sourcePath')));
      expect(yaml, isNot(contains('null')));
      expect(yaml, endsWith('\n'));
    });

    test('同 ID 再次保存覆盖原文件', () async {
      await store.savePack(
        PackModel(name: 'demo', version: '1.0.0', author: '甲'),
      );
      await store.savePack(
        PackModel(name: 'demo', version: '2.0.0', author: '乙'),
      );

      final PackLoadResult result = await store.loadPacks();

      expect(result.packs, hasLength(1));
      expect(result.packs.single.version, '2.0.0');
      expect(result.packs.single.author, '乙');
    });

    test('包名含非法文件名字符时替换为下划线', () async {
      await store.savePack(
        PackModel(
          name: r'a<b>c:d"e/f\g|h?i*j',
          version: '1.0.0',
          author: 'tester',
        ),
      );

      final List<String> names = Directory('${tempDir.path}/packs')
          .listSync()
          .map((FileSystemEntity entity) => entity.uri.pathSegments.last)
          .toList();

      expect(names, ['a_b_c_d_e_f_g_h_i_j.yaml']);
    });

    test('返回列表按包名大小写不敏感排序', () async {
      await store.savePack(
        PackModel(name: 'beta', version: '1.0.0', author: 'tester'),
      );
      await store.savePack(
        PackModel(name: 'Alpha', version: '1.0.0', author: 'tester'),
      );

      final PackLoadResult result = await store.loadPacks();

      expect(result.packs.map((PackModel pack) => pack.name).toList(), <String>[
        'Alpha',
        'beta',
      ]);
    });
  });

  group('loadPacks 容错', () {
    test('目录不存在时返回空结果', () async {
      final PackLoadResult result = await store.loadPacks();

      expect(result.packs, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('损坏的 YAML 被跳过并记录错误，不影响其他文件', () async {
      await store.savePack(
        PackModel(name: 'good', version: '1.0.0', author: 'tester'),
      );
      File('${tempDir.path}/packs/broken.yaml')
          .writeAsStringSync('name: [unclosed');

      final PackLoadResult result = await store.loadPacks();

      expect(result.packs.map((PackModel pack) => pack.name).toList(), <String>[
        'good',
      ]);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.fileName, 'broken.yaml');
      expect(result.errors.single.message, isNotEmpty);
    });

    test('缺少必填字段的文件被跳过并记录原因', () async {
      await store.ensureConfigExist();
      File('${tempDir.path}/packs/incomplete.yaml')
          .writeAsStringSync('name: demo\nversion: 1.0.0\n');

      final PackLoadResult result = await store.loadPacks();

      expect(result.packs, isEmpty);
      expect(result.errors.single.fileName, 'incomplete.yaml');
      expect(result.errors.single.message, contains('author'));
    });

    test('空文件被跳过并记录错误', () async {
      await store.ensureConfigExist();
      File('${tempDir.path}/packs/empty.yaml').writeAsStringSync('');

      final PackLoadResult result = await store.loadPacks();

      expect(result.packs, isEmpty);
      expect(result.errors.single.fileName, 'empty.yaml');
    });
  });

  group('sanitizeFileName', () {
    test('非法字符替换为下划线并去除首尾空白', () {
      expect(
        PackStore.sanitizeFileName(r' a<b>:c"/d\e|f?g*h '),
        'a_b__c__d_e_f_g_h',
      );
    });

    test('清洗后为空时使用 pack', () {
      expect(PackStore.sanitizeFileName('   '), 'pack');
      expect(PackStore.sanitizeFileName('***'), '___');
    });

    test('超长名称截断到 100 个字符', () {
      final String name = 'a' * 150;

      expect(PackStore.sanitizeFileName(name), 'a' * 100);
    });
  });
}
