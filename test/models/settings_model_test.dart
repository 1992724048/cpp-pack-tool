import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认值为 system / mocha / teal 且输出目录为空', () {
    const SettingsModel settings = SettingsModel();

    expect(settings.outputDirectory, isNull);
    expect(settings.themeMode, ThemeModeSetting.system);
    expect(settings.darkFlavor, 'mocha');
    expect(settings.accent, 'teal');
    expect(settings.compilerPriority, <String>['icx', 'clang', 'msvc']);
    expect(settings.detectedCompilers, isEmpty);
  });

  test('toMap 省略 null 输出目录且保留其余字段', () {
    final Map<String, Object?> map = const SettingsModel().toMap();

    expect(map.containsKey('outputDirectory'), isFalse);
    expect(map['themeMode'], 'system');
    expect(map['darkFlavor'], 'mocha');
    expect(map['accent'], 'teal');
    expect(map['compilerPriority'], <String>['icx', 'clang', 'msvc']);
  });

  test('往返保留全部字段', () {
    const SettingsModel settings = SettingsModel(
      outputDirectory: r'D:\nuget\out',
      themeMode: ThemeModeSetting.dark,
      darkFlavor: 'frappe',
      accent: 'mauve',
      compilerPriority: <String>['msvc', 'icx'],
    );

    final SettingsModel loaded = SettingsModel.fromMap(settings.toMap());

    expect(loaded.outputDirectory, r'D:\nuget\out');
    expect(loaded.themeMode, ThemeModeSetting.dark);
    expect(loaded.darkFlavor, 'frappe');
    expect(loaded.accent, 'mauve');
    expect(loaded.compilerPriority, <String>['msvc', 'icx']);
  });

  test('未知枚举与非法值回退默认', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{
      'themeMode': 'pink',
      'darkFlavor': 'latte',
      'accent': 'rainbow',
      'outputDirectory': 42,
    });

    expect(loaded.themeMode, ThemeModeSetting.system);
    expect(loaded.darkFlavor, 'mocha');
    expect(loaded.accent, 'teal');
    expect(loaded.outputDirectory, isNull);
  });

  test('空映射返回默认值', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{});

    expect(loaded.themeMode, ThemeModeSetting.system);
    expect(loaded.darkFlavor, 'mocha');
    expect(loaded.accent, 'teal');
    expect(loaded.outputDirectory, isNull);
    expect(loaded.compilerPriority, <String>['icx', 'clang', 'msvc']);
  });

  test('编译器优先级容错：非列表、空列表回退默认，非法项过滤', () {
    final SettingsModel nonList = SettingsModel.fromMap(<String, Object?>{
      'compilerPriority': 42,
    });
    final SettingsModel empty = SettingsModel.fromMap(<String, Object?>{
      'compilerPriority': <Object?>[],
    });
    final SettingsModel filtered = SettingsModel.fromMap(<String, Object?>{
      'compilerPriority': <Object?>['msvc', 42, '', '  ', 'icx'],
    });

    expect(nonList.compilerPriority, <String>['icx', 'clang', 'msvc']);
    expect(empty.compilerPriority, <String>['icx', 'clang', 'msvc']);
    expect(filtered.compilerPriority, <String>['msvc', 'icx']);
  });

  test('优先级 R23 迁移：旧 clang-cl 改写为 clang 并按首见去重', () {
    final SettingsModel legacy = SettingsModel.fromMap(<String, Object?>{
      'compilerPriority': <Object?>['icx', 'clang-cl', 'msvc'],
    });
    final SettingsModel mixed = SettingsModel.fromMap(<String, Object?>{
      'compilerPriority': <Object?>['clang-cl', 'clang', 'icx'],
    });

    expect(legacy.compilerPriority, <String>['icx', 'clang', 'msvc']);
    expect(
      mixed.compilerPriority,
      <String>['clang', 'icx'],
      reason: '旧标识迁移后与既有 clang 视为同项，只保留首个',
    );
  });

  test('空字符串输出目录视为未设置', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{
      'outputDirectory': '',
    });

    expect(loaded.outputDirectory, isNull);
  });

  test('检测缓存序列化往返：保留类型/版本/路径/环境脚本/附加 PATH', () {
    const SettingsModel settings = SettingsModel(
      detectedCompilers: <DetectedCompiler>[
        DetectedCompiler(
          kind: CompilerKind.icx,
          version: '2026.1.0',
          executablePath: r'C:\oneAPI\compiler\2026.1\bin\icx-cl.exe',
          environmentScript: r'C:\oneAPI\setvars.bat',
          extraPathEntries: <String>[r'C:\oneAPI\bin'],
        ),
        DetectedCompiler(
          kind: CompilerKind.msvc,
          version: '14.44.35207',
          executablePath: r'C:\VS\cl.exe',
          environmentScript: null,
        ),
      ],
    );

    final Map<String, Object?> map = settings.toMap();
    final SettingsModel loaded = SettingsModel.fromMap(map);

    expect(map['detectedCompilers'], isA<List<Object?>>());
    expect(loaded.detectedCompilers, hasLength(2));
    expect(loaded.detectedCompilers[0].kind, CompilerKind.icx);
    expect(loaded.detectedCompilers[0].version, '2026.1.0');
    expect(
      loaded.detectedCompilers[0].executablePath,
      r'C:\oneAPI\compiler\2026.1\bin\icx-cl.exe',
    );
    expect(
      loaded.detectedCompilers[0].environmentScript,
      r'C:\oneAPI\setvars.bat',
    );
    expect(loaded.detectedCompilers[0].extraPathEntries, <String>[
      r'C:\oneAPI\bin',
    ]);
    expect(loaded.detectedCompilers[1].kind, CompilerKind.msvc);
    expect(loaded.detectedCompilers[1].environmentScript, isNull);
    expect(loaded.detectedCompilers[1].extraPathEntries, isEmpty);
  });

  test('空缓存不写入映射，缺失/非列表视为无缓存', () {
    expect(
      const SettingsModel().toMap().containsKey('detectedCompilers'),
      isFalse,
    );
    final SettingsModel fromScalar = SettingsModel.fromMap(<String, Object?>{
      'detectedCompilers': 42,
    });
    final SettingsModel fromString = SettingsModel.fromMap(<String, Object?>{
      'detectedCompilers': 'broken',
    });
    final SettingsModel missing = SettingsModel.fromMap(<String, Object?>{});

    expect(fromScalar.detectedCompilers, isEmpty);
    expect(fromString.detectedCompilers, isEmpty);
    expect(missing.detectedCompilers, isEmpty);
  });

  test('检测缓存条目容错：坏条目跳过、好条目保留', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{
      'detectedCompilers': <Object?>[
        42,
        <String, Object?>{
          'kind': 'unknown',
          'version': '1',
          'executablePath': 'x',
        },
        <String, Object?>{'kind': 7, 'version': '1', 'executablePath': 'x'},
        <String, Object?>{'kind': 'icx', 'version': '', 'executablePath': 'x'},
        <String, Object?>{'kind': 'icx', 'version': '2026.1.0'},
        <String, Object?>{
          'kind': 'clang',
          'version': '23.1.1',
          'executablePath': r'C:\LLVM\bin\clang.exe',
          'environmentScript': 42,
          'extraPathEntries': <Object?>[r'C:\LLVM\bin', 7, '', '  '],
        },
      ],
    });

    expect(loaded.detectedCompilers, hasLength(1));
    expect(loaded.detectedCompilers.single.kind, CompilerKind.clang);
    expect(loaded.detectedCompilers.single.version, '23.1.1');
    expect(loaded.detectedCompilers.single.environmentScript, isNull);
    expect(loaded.detectedCompilers.single.extraPathEntries, <String>[
      r'C:\LLVM\bin',
    ]);
  });

  test('检测缓存 R23 迁移：含旧 clang-cl 条目时整表作废（强制重检）', () {
    final SettingsModel legacyOnly = SettingsModel.fromMap(<String, Object?>{
      'detectedCompilers': <Object?>[
        <String, Object?>{
          'kind': 'clang-cl',
          'version': '23.1.1',
          'executablePath': r'C:\LLVM\bin\clang-cl.exe',
        },
      ],
    });
    final SettingsModel mixed = SettingsModel.fromMap(<String, Object?>{
      'detectedCompilers': <Object?>[
        <String, Object?>{
          'kind': 'msvc',
          'version': '14.44.35207',
          'executablePath': r'C:\VS\cl.exe',
        },
        <String, Object?>{
          'kind': 'clang-cl',
          'version': '23.1.1',
          'executablePath': r'C:\LLVM\bin\clang-cl.exe',
        },
      ],
    });

    expect(
      legacyOnly.detectedCompilers,
      isEmpty,
      reason: '旧驱动条目不可复用，整表作废交设置页/构建重检',
    );
    expect(
      mixed.detectedCompilers,
      isEmpty,
      reason: '仅丢弃旧条目会让 clang 无缓存可匹配而回落 msvc，必须整表作废',
    );
  });

  test('检测缓存与编译器优先级互不影响', () {
    final SettingsModel loaded = SettingsModel.fromMap(<String, Object?>{
      'compilerPriority': <Object?>['msvc'],
      'detectedCompilers': <Object?>[
        <String, Object?>{
          'kind': 'icx',
          'version': '2026.1.0',
          'executablePath': 'x',
        },
      ],
    });

    expect(loaded.compilerPriority, <String>['msvc']);
    expect(loaded.detectedCompilers.single.kind, CompilerKind.icx);
  });
}
