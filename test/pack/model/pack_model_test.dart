import 'package:cpp_nuget_pack/pack/model/build_model.dart';
import 'package:cpp_nuget_pack/pack/model/cmd_model.dart';
import 'package:cpp_nuget_pack/pack/model/dependency_model.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:cpp_nuget_pack/pack/model/history_model.dart';
import 'package:cpp_nuget_pack/pack/model/lib_dir_model.dart';
import 'package:cpp_nuget_pack/pack/model/library_model.dart';
import 'package:cpp_nuget_pack/pack/model/macro_model.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackModel.copyWith', () {
    test('copyWith 覆盖单字段时保留所有列表', () {
      final PackModel source = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      final PackModel changed = source.copyWith(version: '1.0.1');

      expect(changed.version, '1.0.1');
      expect(changed.files, same(source.files));
      expect(changed.dependencies, same(source.dependencies));
      expect(changed.commands, same(source.commands));
      expect(changed.macros, same(source.macros));
      expect(changed.libDirectories, same(source.libDirectories));
      expect(changed.libraries, same(source.libraries));
      expect(changed.history, same(source.history));
      expect(changed.name, 'demo');
      expect(changed.author, 'tester');
    });

    test('copyWith 显式传 null 才清空可空字段', () {
      final PackModel source = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
        description: '说明',
        license: 'MIT',
        iconPath: 'icon.png',
        sourcePath: r'D:\src',
      );

      final PackModel cleared = source.copyWith(description: null);

      expect(cleared.description, isNull);
      expect(cleared.license, 'MIT');
      expect(cleared.iconPath, 'icon.png');
      expect(cleared.sourcePath, r'D:\src');

      final PackModel replaced = source.copyWith(description: '新说明');
      expect(replaced.description, '新说明');
    });
  });

  group('PackModel 序列化', () {
    test('toMap/fromMap 往返保留全部字段与文件列表', () {
      final PackModel pack =
          PackModel(
              name: 'MyLib',
              version: '1.0.0',
              author: '张三',
              description: '描述\n第二行',
              license: 'MIT',
              iconPath: 'assets/logo.svg',
              sourcePath: r'D:\libs\mylib',
            )
            ..files = <FileModel>[
              FileModel(name: 'foo.h', path: 'include/foo.h', size: 123),
            ];

      final PackModel loaded = PackModel.fromMap(pack.toMap());

      expect(loaded.name, pack.name);
      expect(loaded.version, pack.version);
      expect(loaded.author, pack.author);
      expect(loaded.description, pack.description);
      expect(loaded.license, pack.license);
      expect(loaded.iconPath, pack.iconPath);
      expect(loaded.sourcePath, pack.sourcePath);
      expect(loaded.files.single.path, 'include/foo.h');
      expect(loaded.files.single.name, 'foo.h');
      expect(loaded.files.single.size, 123);
      expect(loaded.files.single.type, FileType.header);
    });

    test('toMap 省略 null 字段', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      final Map<String, Object?> map = pack.toMap();

      expect(map.containsKey('description'), isFalse);
      expect(map.containsKey('license'), isFalse);
      expect(map.containsKey('iconPath'), isFalse);
      expect(map.containsKey('sourcePath'), isFalse);
      expect(map['files'], isEmpty);
      expect(map['dependencies'], isEmpty);
      expect(map['commands'], isEmpty);
      expect(map['macros'], isEmpty);
      expect(map['libDirectories'], isEmpty);
      expect(map['libraries'], isEmpty);
    });

    test('fromMap 缺少 files 时默认空列表', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });

      expect(pack.files, isEmpty);
    });

    test('fromMap 从 path 推导文件名并兼容反斜杠分隔符', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
        'files': <Object?>[
          <String, Object?>{'path': 'include/foo.h', 'size': 1},
          <String, Object?>{'path': r'src\main.cpp', 'size': 2},
        ],
      });

      expect(pack.files[0].name, 'foo.h');
      expect(pack.files[0].type, FileType.header);
      expect(pack.files[1].name, 'main.cpp');
      expect(pack.files[1].type, FileType.source);
      expect(pack.files[1].path, r'src\main.cpp');
    });

    test('fromMap 缺少必填字段时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'version': '1.0.0',
          'author': 'tester',
        }),
        throwsFormatException,
      );
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'author': 'tester',
        }),
        throwsFormatException,
      );
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
        }),
        throwsFormatException,
      );
    });

    test('fromMap files 类型错误时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'files': 'oops',
        }),
        throwsFormatException,
      );
    });

    test('toMap/fromMap 往返保留依赖列表', () {
      final PackModel pack =
          PackModel(name: 'demo', version: '1.0.0', author: 'tester')
            ..dependencies = <DependencyModel>[
              const DependencyModel(name: 'libfoo', version: '[1.0,2.0)'),
              const DependencyModel(name: 'libbar', version: '1.0'),
            ];

      final PackModel loaded = PackModel.fromMap(pack.toMap());

      expect(loaded.dependencies, hasLength(2));
      expect(loaded.dependencies[0].name, 'libfoo');
      expect(loaded.dependencies[0].version, '[1.0,2.0)');
      expect(loaded.dependencies[1].name, 'libbar');
      expect(loaded.dependencies[1].version, '1.0');
    });

    test('fromMap 缺少 dependencies 时默认空列表', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });

      expect(pack.dependencies, isEmpty);
    });

    test('fromMap dependencies 类型错误时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'dependencies': 'oops',
        }),
        throwsFormatException,
      );
    });

    test('fromMap dependencies 项类型错误时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'dependencies': <Object?>['oops'],
        }),
        throwsFormatException,
      );
    });

    test('fromMap 依赖项缺少 version 时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'dependencies': <Object?>[
            <String, Object?>{'name': 'libfoo'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('toMap/fromMap 往返保留命令与编译设置列表', () {
      final PackModel
      pack = PackModel(name: 'demo', version: '1.0.0', author: 'tester')
        ..commands = <CmdModel>[
          const CmdModel(
            command: 'echo hi',
            type: CmdType.preBuild,
            buildModel: BuildModel.debug,
          ),
        ]
        ..macros = <MacroModel>[
          const MacroModel(value: 'MY_MACRO=1', buildModel: BuildModel.release),
        ]
        ..libDirectories = <LibDirModel>[
          const LibDirModel(
            path: r'third_party\lib',
            buildModel: BuildModel.debug,
          ),
        ]
        ..libraries = <LibraryModel>[
          const LibraryModel(name: 'mylib.lib', buildModel: BuildModel.release),
        ];

      final PackModel loaded = PackModel.fromMap(pack.toMap());

      expect(loaded.commands, hasLength(1));
      expect(loaded.commands.single.command, 'echo hi');
      expect(loaded.commands.single.type, CmdType.preBuild);
      expect(loaded.commands.single.buildModel, BuildModel.debug);
      expect(loaded.macros.single.value, 'MY_MACRO=1');
      expect(loaded.macros.single.buildModel, BuildModel.release);
      expect(loaded.libDirectories.single.path, r'third_party\lib');
      expect(loaded.libDirectories.single.buildModel, BuildModel.debug);
      expect(loaded.libraries.single.name, 'mylib.lib');
      expect(loaded.libraries.single.buildModel, BuildModel.release);
    });

    test('toMap 按顺序恒写编译设置列表键', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      final List<String> keys = pack.toMap().keys.toList();

      expect(
        keys,
        containsAllInOrder(<String>[
          'commands',
          'macros',
          'libDirectories',
          'libraries',
        ]),
      );
    });

    test('fromMap 缺少编译设置列表时默认空列表', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });

      expect(pack.commands, isEmpty);
      expect(pack.macros, isEmpty);
      expect(pack.libDirectories, isEmpty);
      expect(pack.libraries, isEmpty);
    });

    test('fromMap 编译设置列表类型错误时抛出 FormatException', () {
      for (final String key in <String>[
        'commands',
        'macros',
        'libDirectories',
        'libraries',
      ]) {
        expect(
          () => PackModel.fromMap(<String, Object?>{
            'name': 'demo',
            'version': '1.0.0',
            'author': 'tester',
            key: 'oops',
          }),
          throwsFormatException,
        );
      }
    });

    test('fromMap 编译设置列表项类型错误时抛出 FormatException', () {
      for (final String key in <String>[
        'commands',
        'macros',
        'libDirectories',
        'libraries',
      ]) {
        expect(
          () => PackModel.fromMap(<String, Object?>{
            'name': 'demo',
            'version': '1.0.0',
            'author': 'tester',
            key: <Object?>['oops'],
          }),
          throwsFormatException,
        );
      }
    });

    test('fromMap 命令项缺少 type 时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'commands': <Object?>[
            <String, Object?>{'command': 'echo hi'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('toMap/fromMap 往返保留历史记录', () {
      final PackModel pack =
          PackModel(name: 'demo', version: '1.0.0', author: 'tester')
            ..history = <HistoryModel>[
              HistoryModel(
                time: DateTime(2026, 9, 11, 14, 30, 5),
                type: HistoryType.created,
                message: '创建包：1 个文件，总大小 128 B',
              ),
              HistoryModel(
                time: DateTime(2026, 9, 12, 9, 0, 0),
                type: HistoryType.exported,
                message: r'打包导出：D:\out\demo.1.0.0.nupkg',
              ),
            ];

      final PackModel loaded = PackModel.fromMap(pack.toMap());

      expect(loaded.history, hasLength(2));
      expect(loaded.history[0].time, DateTime(2026, 9, 11, 14, 30, 5));
      expect(loaded.history[0].type, HistoryType.created);
      expect(loaded.history[0].message, '创建包：1 个文件，总大小 128 B');
      expect(loaded.history[1].time, DateTime(2026, 9, 12, 9, 0, 0));
      expect(loaded.history[1].type, HistoryType.exported);
      expect(loaded.history[1].message, r'打包导出：D:\out\demo.1.0.0.nupkg');
    });

    test('toMap 恒写 history 键', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      expect(pack.toMap()['history'], isEmpty);
    });

    test('fromMap 缺少 history 时默认空列表', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });

      expect(pack.history, isEmpty);
    });

    test('fromMap history 类型错误时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'history': 'oops',
        }),
        throwsFormatException,
      );
    });

    test('fromMap history 项类型错误时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'history': <Object?>['oops'],
        }),
        throwsFormatException,
      );
    });

    test('老包已删除的 enabledFormats 键按未知键忽略，写回时不再出现', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
        'enabledFormats': <Object?>['nuget', 'cmake'],
      });

      expect(pack.name, 'demo');
      expect(pack.toMap().containsKey('enabledFormats'), isFalse);
    });

    test('已删除的 buildOptions 键按未知键忽略，且写回时不再出现', () {
      final PackModel loaded = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
        'buildOptions': <String, String>{'runtime': 'mt'},
      });

      expect(loaded.name, 'demo');
      expect(loaded.toMap().containsKey('buildOptions'), isFalse);
    });
  });

  group('commands 脚本路径读时兼容', () {
    test('存量 files\\pre.bat 命令读回后插入 script\\', () {
      final PackModel pack = PackModel.fromMap(
        _packWithCommands(
          r'"$(MSBuildThisFileDirectory)files\pre.bat" "$(TargetPath)"',
        ),
      );

      expect(
        pack.commands.single.command,
        r'"$(MSBuildThisFileDirectory)files\script\pre.bat" "$(TargetPath)"',
      );
    });

    test('存量 files\\scripts\\build.cmd 命令读回后插入 script\\', () {
      final PackModel pack = PackModel.fromMap(
        _packWithCommands(
          r'"$(MSBuildThisFileDirectory)files\scripts\build.cmd" '
          r'"$(TargetPath)"',
        ),
      );

      expect(
        pack.commands.single.command,
        r'"$(MSBuildThisFileDirectory)files\script\scripts\build.cmd" '
        r'"$(TargetPath)"',
      );
    });

    test('非脚本扩展名的 files\\ 命令原样保留', () {
      final String python = r'"$(MSBuildThisFileDirectory)files\helper.py" '
          r'"$(TargetPath)"';
      final String source = r'"$(MSBuildThisFileDirectory)files\helper.cpp" '
          r'"$(TargetPath)"';

      for (final String command in <String>[python, source]) {
        expect(
          PackModel.fromMap(_packWithCommands(command)).commands.single.command,
          command,
        );
      }
    });

    test('前缀不匹配的命令原样保留', () {
      const String original = r'"$(MSBuildThisFileDirectory)lib\foo.lib" '
          r'"$(TargetPath)"';
      final PackModel pack = PackModel.fromMap(_packWithCommands(original));

      expect(pack.commands.single.command, original);
    });

    test('伪扩展名 pre.batx 不被改写', () {
      const String original = r'"$(MSBuildThisFileDirectory)files\pre.batx"';
      final PackModel pack = PackModel.fromMap(_packWithCommands(original));

      expect(pack.commands.single.command, original);
    });

    test('扩展名大写仍判定为脚本', () {
      final PackModel pack = PackModel.fromMap(
        _packWithCommands(r'"$(MSBuildThisFileDirectory)files\BUILD.CMD"'),
      );

      expect(
        pack.commands.single.command,
        r'"$(MSBuildThisFileDirectory)files\script\BUILD.CMD"',
      );
    });

    test('前缀目录名大写 FILES\\ 也判定为脚本路径', () {
      final PackModel pack = PackModel.fromMap(
        _packWithCommands(r'"$(MSBuildThisFileDirectory)FILES\PRE.BAT"'),
      );

      expect(
        pack.commands.single.command,
        r'"$(MSBuildThisFileDirectory)FILES\script\PRE.BAT"',
      );
    });

    test('已迁移的 files\\script\\pre.bat 原样保留', () {
      const String original = r'"$(MSBuildThisFileDirectory)files\script\pre.bat" '
          r'"$(TargetPath)"';
      final PackModel pack = PackModel.fromMap(_packWithCommands(original));

      expect(pack.commands.single.command, original);
    });

    test('已迁移路径的目录段大写 files\\SCRIPT\\pre.bat 也原样保留', () {
      const String original = r'"$(MSBuildThisFileDirectory)files\SCRIPT\pre.bat" '
          r'"$(TargetPath)"';
      final PackModel pack = PackModel.fromMap(_packWithCommands(original));

      expect(pack.commands.single.command, original);
    });

    test('重复读回同一份 YAML 结果稳定（不再累加 script\\ 层）', () {
      const List<String> inputs = <String>[
        r'"$(MSBuildThisFileDirectory)files\pre.bat" "$(TargetPath)"',
        r'"$(MSBuildThisFileDirectory)files\scripts\build.cmd" "$(TargetPath)"',
        r'"$(MSBuildThisFileDirectory)files\script\pre.bat" "$(TargetPath)"',
        r'"$(MSBuildThisFileDirectory)files\script\scripts\build.cmd" "$(TargetPath)"',
      ];

      for (final String input in inputs) {
        final PackModel once = PackModel.fromMap(_packWithCommands(input));
        final PackModel twice = PackModel.fromMap(once.toMap());

        expect(twice.commands.single.command, once.commands.single.command);
      }
    });
  });

  group('FileModel 序列化', () {
    test('toMap 只包含 path 与 size', () {
      final FileModel file = FileModel(
        name: 'foo.h',
        path: 'include/foo.h',
        size: 42,
      );

      expect(file.toMap(), <String, Object?>{
        'path': 'include/foo.h',
        'size': 42,
      });
    });

    test('fromMap 缺失 size 时默认为 0', () {
      final FileModel file = FileModel.fromMap(<String, Object?>{
        'path': 'foo.h',
      });

      expect(file.size, 0);
      expect(file.name, 'foo.h');
    });

    test('fromMap 缺少 path 时抛出 FormatException', () {
      expect(
        () => FileModel.fromMap(<String, Object?>{}),
        throwsFormatException,
      );
    });
  });
}

Map<String, Object?> _packWithCommands(String command) => <String, Object?>{
  'name': 'demo',
  'version': '1.0.0',
  'author': 'tester',
  'description': '说明',
  'commands': <Map<String, Object?>>[
    <String, Object?>{
      'command': command,
      'type': 'preBuild',
      'buildModel': 'all',
    },
  ],
};
