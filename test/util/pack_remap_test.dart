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
import 'package:cpp_nuget_pack/util/pack_remap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('totalFileSize 汇总全部文件字节数', () {
    final List<FileModel> files = <FileModel>[
      FileModel(name: 'a.h', path: 'include/a.h', size: 100),
      FileModel(name: 'b.cpp', path: 'src/b.cpp', size: 200),
    ];

    expect(totalFileSize(files), 300);
    expect(totalFileSize(const <FileModel>[]), 0);
  });

  group('comparePackFiles', () {
    test('按小写路径对比新增/移除并汇总两侧大小', () {
      final PackFilesDiff diff = comparePackFiles(
        <FileModel>[
          FileModel(name: 'OLD.H', path: 'include/OLD.H', size: 100),
          FileModel(name: 'gone.cpp', path: 'src/gone.cpp', size: 200),
        ],
        <FileModel>[
          FileModel(name: 'old.h', path: 'include/old.h', size: 150),
          FileModel(name: 'new.h', path: 'include/new.h', size: 50),
        ],
      );

      expect(diff.added, 1);
      expect(diff.removed, 1);
      expect(diff.oldSize, 300);
      expect(diff.newSize, 200);
      expect(diff.hasChanges, isTrue);
    });

    test('路径与大小均未变化时 hasChanges 为假', () {
      final PackFilesDiff diff = comparePackFiles(
        <FileModel>[FileModel(name: 'a.h', path: 'include/a.h', size: 10)],
        <FileModel>[FileModel(name: 'a.h', path: 'include/a.h', size: 10)],
      );

      expect(diff.hasChanges, isFalse);
    });

    test('大小变化（路径集相同）时 hasChanges 为真', () {
      final PackFilesDiff diff = comparePackFiles(
        <FileModel>[FileModel(name: 'a.h', path: 'include/a.h', size: 10)],
        <FileModel>[FileModel(name: 'a.h', path: 'include/a.h', size: 20)],
      );

      expect(diff.added, 0);
      expect(diff.removed, 0);
      expect(diff.hasChanges, isTrue);
    });
  });

  group('copyPackWithFiles', () {
    test('替换文件列表、按新快照重识别图标并保留全部其余字段', () {
      final PackModel pack =
          PackModel(
              name: 'demo',
              version: '2.1.0',
              author: 'tester',
              description: '描述',
              license: 'MIT',
              iconPath: 'assets/old.png',
              sourcePath: r'D:\src',
              sourceVersion: 'v2.3.4',
            )
            ..files = <FileModel>[
              FileModel(name: 'old.h', path: 'include/old.h', size: 64),
            ]
            ..commands = <CmdModel>[
              const CmdModel(command: 'echo hi', type: CmdType.preBuild),
            ]
            ..dependencies = <DependencyModel>[
              const DependencyModel(name: 'dep', version: '[1.0,)'),
            ]
            ..macros = <MacroModel>[
              const MacroModel(value: 'FOO=1', buildModel: BuildModel.all),
            ]
            ..libDirectories = <LibDirModel>[
              const LibDirModel(path: r'third_party\lib'),
            ]
            ..libraries = <LibraryModel>[
              const LibraryModel(name: 'a.lib', buildModel: BuildModel.debug),
            ]
            ..history = <HistoryModel>[
              HistoryModel(
                time: DateTime(2026, 9, 12),
                type: HistoryType.created,
                message: '创建',
              ),
            ]
            ..scripts = <ScriptProjectModel>[
              ScriptProjectModel(
                id: 'script_1',
                name: '脚本 1',
                trigger: ScriptTrigger.pre,
              ),
            ]
            ..buildOptions = <String, String>{'tbb': 'on', 'mp': 'off'}
            ..enabledFormats = <String>['nuget'];
      final List<FileModel> files = <FileModel>[
        FileModel(name: 'logo.svg', path: 'assets/logo.svg', size: 128),
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 256),
      ];

      final PackModel updated = copyPackWithFiles(pack, files);

      expect(updated, isNot(same(pack)));
      expect(updated.name, 'demo');
      expect(updated.version, '2.1.0');
      expect(updated.author, 'tester');
      expect(updated.description, '描述');
      expect(updated.license, 'MIT');
      expect(updated.sourcePath, r'D:\src');
      expect(updated.sourceVersion, 'v2.3.4');
      expect(updated.iconPath, 'assets/logo.svg');
      expect(updated.files, same(files));
      expect(updated.commands, same(pack.commands));
      expect(updated.dependencies, same(pack.dependencies));
      expect(updated.macros, same(pack.macros));
      expect(updated.libDirectories, same(pack.libDirectories));
      expect(updated.libraries, same(pack.libraries));
      expect(updated.history, same(pack.history));
      expect(updated.scripts, same(pack.scripts));
      expect(updated.buildOptions, <String, String>{'tbb': 'on', 'mp': 'off'});
      expect(updated.enabledFormats, <String>['nuget']);
    });

    test('新快照无图片文件时 iconPath 为空', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
        iconPath: 'assets/old.png',
      );

      final PackModel updated = copyPackWithFiles(pack, <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 10),
      ]);

      expect(updated.iconPath, isNull);
    });

    test('buildOptions 为空时拷贝结果同样为空', () {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
      );

      final PackModel updated = copyPackWithFiles(pack, const <FileModel>[]);

      expect(updated.buildOptions, isEmpty);
    });
  });
}
