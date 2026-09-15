import 'dart:io';

import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

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

    test('依赖列表写入 YAML 并可往返读回', () async {
      final PackModel pack =
          PackModel(name: 'demo', version: '1.0.0', author: 'tester')
            ..dependencies = <DependencyModel>[
              const DependencyModel(name: 'libfoo', version: '[1.0,2.0)'),
              const DependencyModel(name: 'libbar', version: '1.0'),
            ];

      await store.savePack(pack);
      final String yaml = File('${tempDir.path}/packs/demo.yaml')
          .readAsStringSync();
      final YamlMap document = loadYaml(yaml) as YamlMap;
      final YamlList dependencies = document['dependencies'] as YamlList;

      expect(dependencies, hasLength(2));
      expect((dependencies[0] as YamlMap)['name'], 'libfoo');
      expect((dependencies[0] as YamlMap)['version'], '[1.0,2.0)');
      expect((dependencies[1] as YamlMap)['name'], 'libbar');
      expect((dependencies[1] as YamlMap)['version'], '1.0');

      final PackLoadResult result = await store.loadPacks();

      expect(result.errors, isEmpty);
      final PackModel loaded = result.packs.single;
      expect(loaded.dependencies, hasLength(2));
      expect(loaded.dependencies[0].name, 'libfoo');
      expect(loaded.dependencies[0].version, '[1.0,2.0)');
      expect(loaded.dependencies[1].name, 'libbar');
      expect(loaded.dependencies[1].version, '1.0');
    });

    test('文件缺少 files 与 dependencies 时默认空列表', () async {
      await store.ensureConfigExist();
      File('${tempDir.path}/packs/legacy.yaml')
          .writeAsStringSync('name: legacy\nversion: 1.0.0\nauthor: tester\n');

      final PackLoadResult result = await store.loadPacks();

      expect(result.errors, isEmpty);
      expect(result.packs.single.files, isEmpty);
      expect(result.packs.single.dependencies, isEmpty);
    });

    test('脚本项目写入 YAML 并可往返读回', () async {
      final ScriptProjectModel script = ScriptProjectModel(
        id: 'script_1',
        name: '生成版本头',
        trigger: ScriptTrigger.pre,
        buildModel: BuildModel.release,
      );
      script.nodes.add(
        ScriptNodeModel(id: 'n1', type: 'flow.entry', x: 40, y: 60)
          ..params['value'] = 5.5,
      );
      script.edges.add(
        ScriptEdgeModel(
          from: const ScriptEdgeEndpoint(node: 'n1', pin: 'out'),
          to: const ScriptEdgeEndpoint(node: 'n1', pin: 'exec'),
        ),
      );
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      )..scripts.add(script);

      await store.savePack(pack);
      final PackLoadResult result = await store.loadPacks();

      expect(result.errors, isEmpty);
      final ScriptProjectModel loaded = result.packs.single.scripts.single;
      expect(loaded.id, 'script_1');
      expect(loaded.name, '生成版本头');
      expect(loaded.trigger, ScriptTrigger.pre);
      expect(loaded.buildModel, BuildModel.release);
      expect(loaded.nodes.single.type, 'flow.entry');
      expect(loaded.nodes.single.x, 40);
      final Object? storedNumber = loaded.nodes.single.params['value'];
      expect(storedNumber, isA<double>());
      expect(storedNumber, 5.5);
      expect(loaded.edges.single.to.pin, 'exec');
    });

    test('坏脚本被丢弃但包仍加载并记录脚本警告', () async {
      await store.ensureConfigExist();
      File('${tempDir.path}/packs/warned.yaml').writeAsStringSync(
        'name: warned\nversion: 1.0.0\nauthor: tester\n'
        'scripts:\n'
        '  - id: script_1\n    name: x\n    trigger: bad\n'
        '  - id: script_2\n    name: 好脚本\n    trigger: pre\n',
      );

      final PackLoadResult result = await store.loadPacks();

      expect(result.packs.single.name, 'warned');
      expect(result.packs.single.scripts.single.id, 'script_2');
      expect(result.errors, hasLength(1));
      expect(result.errors.single.fileName, 'warned.yaml');
      expect(result.errors.single.message, contains('脚本'));
    });
  });

  group('deletePack', () {
    test('删除已存在的配置文件且 loadPacks 不再返回', () async {
      await store.savePack(
        PackModel(name: 'demo', version: '1.0.0', author: 'tester'),
      );

      await store.deletePack('demo');

      expect(File('${tempDir.path}/packs/demo.yaml').existsSync(), isFalse);
      final PackLoadResult result = await store.loadPacks();
      expect(result.packs, isEmpty);
    });

    test('文件不存在时不报错', () async {
      await store.ensureConfigExist();

      await expectLater(store.deletePack('missing'), completes);
    });

    test('包名含非法字符时按清洗后的文件名删除', () async {
      await store.savePack(
        PackModel(name: r'a<b>:c', version: '1.0.0', author: 'tester'),
      );
      expect(File('${tempDir.path}/packs/a_b__c.yaml').existsSync(), isTrue);

      await store.deletePack(r'a<b>:c');

      expect(File('${tempDir.path}/packs/a_b__c.yaml').existsSync(), isFalse);
    });
  });

  group('settings', () {
    test('无配置文件时返回默认值', () async {
      final SettingsModel settings = await store.loadSettings();

      expect(settings.outputDirectory, isNull);
      expect(settings.themeMode, ThemeModeSetting.system);
      expect(settings.darkFlavor, 'mocha');
      expect(settings.accent, 'teal');
    });

    test('保存后可往返读回且保留 version 字段', () async {
      const SettingsModel settings = SettingsModel(
        outputDirectory: r'D:\nuget\out',
        themeMode: ThemeModeSetting.dark,
        darkFlavor: 'frappe',
        accent: 'mauve',
      );

      await store.saveSettings(settings);

      final String yaml = File('${tempDir.path}/config.yaml')
          .readAsStringSync();
      expect(yaml, contains('version: 1'));

      final SettingsModel loaded = await store.loadSettings();
      expect(loaded.outputDirectory, r'D:\nuget\out');
      expect(loaded.themeMode, ThemeModeSetting.dark);
      expect(loaded.darkFlavor, 'frappe');
      expect(loaded.accent, 'mauve');
    });

    test('输出目录为空时不写入 YAML', () async {
      await store.saveSettings(const SettingsModel());

      final String yaml = File('${tempDir.path}/config.yaml')
          .readAsStringSync();
      expect(yaml, isNot(contains('outputDirectory')));
      expect(yaml, contains('themeMode: system'));
      expect(yaml, contains('darkFlavor: mocha'));
      expect(yaml, contains('accent: teal'));
    });

    test('已有内容被全量重写', () async {
      await store.ensureConfigExist();
      File('${tempDir.path}/config.yaml')
          .writeAsStringSync('version: 1\nlegacy: true\n');

      await store.saveSettings(const SettingsModel(accent: 'red'));

      final String yaml = File('${tempDir.path}/config.yaml')
          .readAsStringSync();
      expect(yaml, contains('version: 1'));
      expect(yaml, isNot(contains('legacy')));
      expect(yaml, contains('accent: red'));
    });

    test('损坏的配置文件回退默认值', () async {
      File('${tempDir.path}/config.yaml').createSync(recursive: true);
      File('${tempDir.path}/config.yaml')
          .writeAsStringSync('themeMode: [broken');

      final SettingsModel settings = await store.loadSettings();

      expect(settings.themeMode, ThemeModeSetting.system);
      expect(settings.darkFlavor, 'mocha');
      expect(settings.accent, 'teal');
    });

    test('未知字段值回退默认', () async {
      File('${tempDir.path}/config.yaml').createSync(recursive: true);
      File('${tempDir.path}/config.yaml').writeAsStringSync(
        'version: 1\nthemeMode: pink\ndarkFlavor: latte\naccent: rainbow\n',
      );

      final SettingsModel settings = await store.loadSettings();

      expect(settings.themeMode, ThemeModeSetting.system);
      expect(settings.darkFlavor, 'mocha');
      expect(settings.accent, 'teal');
    });

    test('检测缓存随设置往返并写入 YAML', () async {
      const SettingsModel settings = SettingsModel(
        compilerPriority: <String>['icx', 'msvc'],
        detectedCompilers: <DetectedCompiler>[
          DetectedCompiler(
            kind: CompilerKind.icx,
            version: '2026.1.0',
            executablePath: r'D:\oneAPI\compiler\2026.1\bin\icx-cl.exe',
            environmentScript: r'D:\oneAPI\setvars.bat',
          ),
        ],
      );

      await store.saveSettings(settings);

      final String yaml = File('${tempDir.path}/config.yaml')
          .readAsStringSync();
      expect(yaml, contains('detectedCompilers'));
      expect(yaml, contains('kind: icx'));

      final SettingsModel loaded = await store.loadSettings();
      expect(loaded.compilerPriority, <String>[
        'icx',
        'msvc',
        'clang-cl',
        'mingw',
      ]);
      expect(loaded.detectedCompilers, hasLength(1));
      expect(loaded.detectedCompilers.single.kind, CompilerKind.icx);
      expect(loaded.detectedCompilers.single.version, '2026.1.0');
      expect(
        loaded.detectedCompilers.single.environmentScript,
        r'D:\oneAPI\setvars.bat',
      );
    });

    test('损坏的检测缓存条目被跳过而不影响其余设置', () async {
      File('${tempDir.path}/config.yaml').createSync(recursive: true);
      File('${tempDir.path}/config.yaml').writeAsStringSync(
        'version: 1\naccent: mauve\ndetectedCompilers:\n'
        '  - kind: gcc\n    version: 13\n    executablePath: /usr/bin/gcc\n'
        '  - kind: msvc\n    version: 14.44.35207\n    executablePath: C:\\\\VC\\\\cl.exe\n',
      );

      final SettingsModel settings = await store.loadSettings();

      expect(settings.accent, 'mauve');
      expect(settings.detectedCompilers, hasLength(1));
      expect(settings.detectedCompilers.single.kind, CompilerKind.msvc);
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

    test('依赖项损坏的文件被跳过并记录原因', () async {
      await store.savePack(
        PackModel(name: 'good', version: '1.0.0', author: 'tester'),
      );
      File('${tempDir.path}/packs/broken.yaml').writeAsStringSync(
        'name: bad\nversion: 1.0.0\nauthor: tester\ndependencies:\n'
        '  - name: libfoo\n',
      );

      final PackLoadResult result = await store.loadPacks();

      expect(result.packs.single.name, 'good');
      expect(result.errors.single.fileName, 'broken.yaml');
      expect(result.errors.single.message, contains('version'));
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
