import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/system_entries.dart';
import 'package:flutter_test/flutter_test.dart';

const String _preCommand =
    r'"$(MSBuildThisFileDirectory)files\pre.bat" "$(TargetPath)"';
const String _postCommand =
    r'"$(MSBuildThisFileDirectory)files\post.bat" "$(TargetPath)"';

void main() {
  group('applySystemEntries 脚本命令', () {
    test('根级 pre.bat/post.bat 注册为 ALL 系统命令（大小写不敏感）', () {
      final PackModel pack = _pack(
        files: <FileModel>[_file('PRE.BAT'), _file('post.bat')],
      );

      final SystemEntriesUpdate update = applySystemEntries(pack);

      expect(update.changed, isTrue);
      expect(update.notes, isEmpty);
      expect(update.pack, isNot(same(pack)));
      expect(update.pack.commands, hasLength(2));

      final CmdModel pre = update.pack.commands[0];
      expect(pre.command, _preCommand);
      expect(pre.type, CmdType.preBuild);
      expect(pre.buildModel, BuildModel.all);
      expect(pre.system, isTrue);

      final CmdModel post = update.pack.commands[1];
      expect(post.command, _postCommand);
      expect(post.type, CmdType.postBuild);
      expect(post.buildModel, BuildModel.all);
      expect(post.system, isTrue);
    });

    test('命令恒用规范小写文件名（源文件大小写不敏感）', () {
      final PackModel pack = _pack(
        files: <FileModel>[
          FileModel(name: 'PRE.BAT', path: 'PRE.BAT'),
          FileModel(name: 'Post.Bat', path: 'Post.Bat'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(pack);

      expect(update.pack.commands[0].command, _preCommand);
      expect(update.pack.commands[1].command, _postCommand);
    });

    test('无根级脚本或仅子目录脚本时不注册', () {
      final PackModel pack = _pack(
        files: <FileModel>[
          _file('scripts/pre.bat'),
          _file(r'scripts\post.bat'),
          _file('pre.bat.bak'),
          _file('main.cpp'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(pack);

      expect(update.changed, isFalse);
      expect(update.pack, same(pack));
      expect(update.pack.commands, isEmpty);
    });

    test('已存在同命令条目（非系统）时不重复添加且不改动', () {
      final PackModel pack = _pack(
        files: <FileModel>[_file('pre.bat')],
        commands: <CmdModel>[
          const CmdModel(
            command: _preCommand,
            type: CmdType.preBuild,
            buildModel: BuildModel.debug,
          ),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(pack);

      expect(update.changed, isFalse);
      expect(update.pack, same(pack));
      expect(update.pack.commands.single.buildModel, BuildModel.debug);
      expect(update.pack.commands.single.system, isFalse);
    });

    test('已存在同命令但大小写不同的条目时不重复添加', () {
      final PackModel pack = _pack(
        files: <FileModel>[_file('pre.bat')],
        commands: <CmdModel>[
          const CmdModel(
            command:
                r'"$(MSBuildThisFileDirectory)files\PRE.BAT" "$(targetpath)"',
            type: CmdType.preBuild,
          ),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(pack);

      expect(update.changed, isFalse);
      expect(update.pack.commands, hasLength(1));
    });

    test('重复同步幂等', () {
      final PackModel first = applySystemEntries(
        _pack(files: <FileModel>[_file('pre.bat'), _file('post.bat')]),
      ).pack;

      final SystemEntriesUpdate second = applySystemEntries(first);

      expect(second.changed, isFalse);
      expect(second.pack, same(first));
      expect(second.pack.commands, hasLength(2));
    });
  });

  group('applySystemEntries 依赖', () {
    test('显式版本范围优先', () {
      final PackModel pack = _pack();
      const BuildScriptHeader header = BuildScriptHeader(
        repo: 'https://example.com/demo.git',
        dependencies: <BuildScriptDependency>[
          BuildScriptDependency(name: 'libbar', version: '[1.0,2.0)'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(
        pack,
        header: header,
      );

      expect(update.changed, isTrue);
      expect(update.notes, isEmpty);
      expect(update.pack.dependencies.single.name, 'libbar');
      expect(update.pack.dependencies.single.version, '[1.0,2.0)');
      expect(update.pack.dependencies.single.system, isTrue);
    });

    test('缺省版本用本地包版本生成下限', () {
      const BuildScriptHeader header = BuildScriptHeader(
        repo: 'https://example.com/demo.git',
        dependencies: <BuildScriptDependency>[
          BuildScriptDependency(name: 'libfoo'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(
        _pack(),
        header: header,
        resolvePackVersion: (String name) =>
            name.toLowerCase() == 'libfoo' ? '2.5.0' : null,
      );

      expect(update.pack.dependencies.single.version, '[2.5.0,)');
      expect(update.notes, isEmpty);
    });

    test('本地包缺失回退 [0.0.0,) 并注明；本地版本非法同样回退', () {
      const BuildScriptHeader header = BuildScriptHeader(
        repo: 'https://example.com/demo.git',
        dependencies: <BuildScriptDependency>[
          BuildScriptDependency(name: 'ghost'),
          BuildScriptDependency(name: 'weird'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(
        _pack(),
        header: header,
        resolvePackVersion: (String name) =>
            name == 'weird' ? 'not a version' : null,
      );

      expect(update.pack.dependencies, hasLength(2));
      expect(update.pack.dependencies[0].version, '[0.0.0,)');
      expect(update.pack.dependencies[1].version, '[0.0.0,)');
      expect(update.notes, hasLength(2));
      expect(update.notes[0], contains('ghost'));
      expect(update.notes[0], contains('[0.0.0,)'));
      expect(update.notes[1], contains('weird'));
    });

    test('已存在同名依赖时不重复添加且不改动', () {
      final PackModel pack = _pack(
        dependencies: <DependencyModel>[
          const DependencyModel(name: 'LIBFOO', version: '1.0'),
        ],
      );
      const BuildScriptHeader header = BuildScriptHeader(
        repo: 'https://example.com/demo.git',
        dependencies: <BuildScriptDependency>[
          BuildScriptDependency(name: 'libfoo', version: '[2.0,)'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(
        pack,
        header: header,
      );

      expect(update.changed, isFalse);
      expect(update.pack, same(pack));
      expect(update.pack.dependencies.single.name, 'LIBFOO');
      expect(update.pack.dependencies.single.version, '1.0');
      expect(update.pack.dependencies.single.system, isFalse);
    });

    test('自依赖跳过', () {
      const BuildScriptHeader header = BuildScriptHeader(
        repo: 'https://example.com/demo.git',
        dependencies: <BuildScriptDependency>[
          BuildScriptDependency(name: 'DEMO'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(
        _pack(name: 'demo'),
        header: header,
      );

      expect(update.changed, isFalse);
      expect(update.pack.dependencies, isEmpty);
    });

    test('header 为 null 或声明为空时零变化', () {
      final PackModel pack = _pack();

      expect(applySystemEntries(pack).changed, isFalse);
      expect(
        applySystemEntries(
          pack,
          header: const BuildScriptHeader(
            repo: 'https://example.com/demo.git',
          ),
        ).changed,
        isFalse,
      );
    });
  });

  group('applySystemEntries 整体', () {
    test('脚本与依赖同时注册，并保留其余字段与构建选项', () {
      final PackModel pack = _pack(
        files: <FileModel>[_file('pre.bat'), _file('post.bat')],
        dependencies: <DependencyModel>[
          const DependencyModel(name: 'keep', version: '3.0'),
        ],
        buildOptions: <String, String>{'tbb': 'on'},
        license: 'MIT',
        sourcePath: r'D:\libs\demo',
      )
        ..macros = <MacroModel>[const MacroModel(value: 'A=1')]
        ..history = <HistoryModel>[
          HistoryModel(
            time: DateTime(2026, 9, 13),
            type: HistoryType.created,
            message: '创建包',
          ),
        ]
        ..sourceVersion = 'v5.6.7'
        ..enabledFormats = <String>['nuget'];
      const BuildScriptHeader header = BuildScriptHeader(
        repo: 'https://example.com/demo.git',
        dependencies: <BuildScriptDependency>[
          BuildScriptDependency(name: 'libfoo'),
        ],
      );

      final SystemEntriesUpdate update = applySystemEntries(
        pack,
        header: header,
        resolvePackVersion: (String name) => '1.2.3',
      );

      expect(update.changed, isTrue);
      final PackModel updated = update.pack;
      expect(updated.name, 'demo');
      expect(updated.version, '1.0.0');
      expect(updated.author, 'tester');
      expect(updated.license, 'MIT');
      expect(updated.sourcePath, r'D:\libs\demo');
      expect(updated.files, hasLength(2));
      expect(updated.commands, hasLength(2));
      expect(updated.dependencies, hasLength(2));
      expect(updated.dependencies[0].version, '3.0');
      expect(updated.dependencies[1].name, 'libfoo');
      expect(updated.dependencies[1].version, '[1.2.3,)');
      expect(updated.macros.single.value, 'A=1');
      expect(updated.history.single.message, '创建包');
      expect(updated.sourceVersion, 'v5.6.7');
      expect(updated.buildOptions, <String, String>{'tbb': 'on'});
      expect(updated.enabledFormats, <String>['nuget']);
      // 不修改入参：原包列表保持原样
      expect(pack.commands, isEmpty);
      expect(pack.dependencies, hasLength(1));
    });
  });
}

PackModel _pack({
  String name = 'demo',
  List<FileModel> files = const <FileModel>[],
  List<CmdModel> commands = const <CmdModel>[],
  List<DependencyModel> dependencies = const <DependencyModel>[],
  Map<String, String>? buildOptions,
  String? license,
  String? sourcePath,
}) {
  final PackModel pack = PackModel(
    name: name,
    version: '1.0.0',
    author: 'tester',
    license: license,
    sourcePath: sourcePath,
  );
  pack.files = List<FileModel>.of(files);
  pack.commands = List<CmdModel>.of(commands);
  pack.dependencies = List<DependencyModel>.of(dependencies);
  if (buildOptions != null) {
    pack.buildOptions = buildOptions;
  }
  return pack;
}

FileModel _file(String path) => FileModel(name: path, path: path, size: 10);
