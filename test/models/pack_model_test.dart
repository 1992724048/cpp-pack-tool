import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    test('toMap/fromMap 往返保留脚本项目（含节点、边与视口）', () {
      final ScriptProjectModel script =
          ScriptProjectModel(
              id: 'script_1',
              name: '生成版本头',
              trigger: ScriptTrigger.pre,
              buildModel: BuildModel.release,
            )
            ..viewX = 12
            ..viewY = -3
            ..viewScale = 0.75;
      script.nodes.add(
        ScriptNodeModel(id: 'n1', type: 'flow.entry', x: 40, y: 60),
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

      final PackModel loaded = PackModel.fromMap(pack.toMap());

      expect(loaded.scripts, hasLength(1));
      final ScriptProjectModel back = loaded.scripts.single;
      expect(back.id, 'script_1');
      expect(back.name, '生成版本头');
      expect(back.trigger, ScriptTrigger.pre);
      expect(back.buildModel, BuildModel.release);
      expect(back.nodes.single.id, 'n1');
      expect(back.nodes.single.x, 40);
      expect(back.edges.single.from.pin, 'out');
      expect(back.viewX, 12);
      expect(back.viewY, -3);
      expect(back.viewScale, 0.75);
    });

    test('toMap 恒写 scripts 键', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      expect(pack.toMap()['scripts'], isEmpty);
    });

    test('fromMap 缺少 scripts 时默认空列表', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });

      expect(pack.scripts, isEmpty);
    });

    test('fromMap scripts 类型错误时抛出 FormatException', () {
      expect(
        () => PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'scripts': 'oops',
        }),
        throwsFormatException,
      );
    });

    test('含 scripts 的往返与坏脚本容错', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'a',
      );
      pack.scripts.add(
        ScriptProjectModel(
          id: 'script_1',
          name: '脚本 1',
          trigger: ScriptTrigger.pre,
          buildModel: BuildModel.all,
        ),
      );
      final PackModel back = PackModel.fromMap(pack.toMap());
      expect(back.scripts.single.id, 'script_1');

      final List<String> warnings = <String>[];
      final PackModel broken = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'a',
        'scripts': <Object?>[
          <String, Object?>{'id': 's', 'name': 'x', 'trigger': 'bad'},
        ],
      }, warnings: warnings);
      expect(broken.scripts, isEmpty);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('脚本'));
    });

    test('fromMap 坏脚本不影响其他脚本且透传节点重复警告', () {
      final List<String> warnings = <String>[];
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'a',
        'scripts': <Object?>[
          <String, Object?>{'id': 'bad', 'name': 'x', 'trigger': 'oops'},
          <String, Object?>{
            'id': 'script_1',
            'name': '好脚本',
            'trigger': 'pre',
            'nodes': <Object?>[
              <String, Object?>{'id': 'n1', 'type': 'flow.entry'},
              <String, Object?>{'id': 'n1', 'type': 'value.text'},
            ],
          },
        ],
      }, warnings: warnings);

      expect(pack.scripts.single.id, 'script_1');
      expect(pack.scripts.single.nodes, hasLength(1));
      expect(warnings, hasLength(2));
      expect(warnings[0], contains('bad'));
      expect(warnings[1], contains('n1'));
    });

    test('fromMap 脚本 id 重复时保留首个并警告', () {
      final List<String> warnings = <String>[];
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'a',
        'scripts': <Object?>[
          <String, Object?>{'id': 'script_1', 'name': '第一个', 'trigger': 'pre'},
          <String, Object?>{'id': 'script_1', 'name': '第二个', 'trigger': 'post'},
        ],
      }, warnings: warnings);

      expect(pack.scripts.single.name, '第一个');
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('script_1'));
    });

    test('buildOptions 默认为空', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      expect(pack.buildOptions, isEmpty);
    });

    test('toMap 空 buildOptions 省略键', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      expect(pack.toMap().containsKey('buildOptions'), isFalse);
    });

    test('toMap/fromMap 往返保留构建选项', () {
      final PackModel pack =
          PackModel(name: 'demo', version: '1.0.0', author: 'tester')
            ..buildOptions = <String, String>{'tbb': 'on', 'mp': 'off'};

      final Map<String, Object?> map = pack.toMap();

      expect(map['buildOptions'], <String, String>{'tbb': 'on', 'mp': 'off'});
      final PackModel loaded = PackModel.fromMap(map);
      expect(loaded.buildOptions, hasLength(2));
      expect(loaded.buildOptions['tbb'], 'on');
      expect(loaded.buildOptions['mp'], 'off');
    });

    test('fromMap 缺少 buildOptions 时默认为空', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });

      expect(pack.buildOptions, isEmpty);
    });

    test('fromMap buildOptions 类型错误时容错为空', () {
      for (final Object? value in <Object?>['oops', <Object?>[], 42]) {
        final PackModel pack = PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'buildOptions': value,
        });

        expect(pack.buildOptions, isEmpty);
      }
    });

    test('fromMap buildOptions 丢弃非法键值项', () {
      final PackModel pack = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
        'buildOptions': <Object?, Object?>{1: 'a', 'k': 7, 'tbb': 'on'},
      });

      expect(pack.buildOptions, <String, String>{'tbb': 'on'});
    });

    test('toMap 空 sourceVersion 省略键', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      expect(pack.toMap().containsKey('sourceVersion'), isFalse);
    });

    test('toMap/fromMap 往返保留仓库版本', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
        sourceVersion: 'v1.2.3',
      );

      final Map<String, Object?> map = pack.toMap();

      expect(map['sourceVersion'], 'v1.2.3');
      expect(PackModel.fromMap(map).sourceVersion, 'v1.2.3');
    });

    test('fromMap sourceVersion 缺失或非法时容错为 null', () {
      final PackModel missing = PackModel.fromMap(<String, Object?>{
        'name': 'demo',
        'version': '1.0.0',
        'author': 'tester',
      });
      expect(missing.sourceVersion, isNull);

      for (final Object? value in <Object?>['', 42, <Object?>[]]) {
        final PackModel pack = PackModel.fromMap(<String, Object?>{
          'name': 'demo',
          'version': '1.0.0',
          'author': 'tester',
          'sourceVersion': value,
        });

        expect(pack.sourceVersion, isNull);
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
