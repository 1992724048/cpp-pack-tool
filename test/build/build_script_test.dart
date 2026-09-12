import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isBuildScriptPath', () {
    test('根级 build.py 大小写不敏感', () {
      expect(isBuildScriptPath('build.py'), isTrue);
      expect(isBuildScriptPath('Build.py'), isTrue);
      expect(isBuildScriptPath('BUILD.PY'), isTrue);
    });

    test('子目录路径（正反斜杠）不匹配', () {
      expect(isBuildScriptPath('scripts/build.py'), isFalse);
      expect(isBuildScriptPath(r'scripts\build.py'), isFalse);
      expect(isBuildScriptPath('a/b/Build.py'), isFalse);
    });

    test('其他文件名不匹配', () {
      expect(isBuildScriptPath('build.pyc'), isFalse);
      expect(isBuildScriptPath('build.bat'), isFalse);
      expect(isBuildScriptPath('mybuild.py'), isFalse);
      expect(isBuildScriptPath(''), isFalse);
    });
  });

  group('findBuildScript', () {
    test('多个候选时取字典序第一个且忽略子目录', () {
      final FileModel lower = FileModel(name: 'build.py', path: 'build.py');
      final FileModel upper = FileModel(name: 'Build.py', path: 'Build.py');
      final FileModel nested = FileModel(
        name: 'build.py',
        path: 'scripts/build.py',
      );

      expect(findBuildScript(<FileModel>[lower, upper, nested]), same(upper));
    });

    test('无候选返回 null', () {
      expect(findBuildScript(<FileModel>[]), isNull);
      expect(
        findBuildScript(<FileModel>[
          FileModel(name: 'main.cpp', path: 'main.cpp'),
          FileModel(name: 'build.py', path: 'scripts/build.py'),
        ]),
        isNull,
      );
    });
  });

  group('parseBuildScriptRepo', () {
    test('解析 # 开头的仓库地址并 trim', () {
      expect(
        parseBuildScriptRepo('# https://github.com/foo/bar.git'),
        'https://github.com/foo/bar.git',
      );
      expect(
        parseBuildScriptRepo('#https://github.com/foo/bar.git'),
        'https://github.com/foo/bar.git',
      );
      expect(
        parseBuildScriptRepo('  # https://example.com/repo.git  '),
        'https://example.com/repo.git',
      );
    });

    test('多行内容只取首行', () {
      expect(
        parseBuildScriptRepo(
          '# https://a.example.com/b.git\n# comment\nprint(1)\n',
        ),
        'https://a.example.com/b.git',
      );
      expect(
        parseBuildScriptRepo('# https://a.example.com/b.git\r\nprint(1)\r\n'),
        'https://a.example.com/b.git',
      );
    });

    test('非 # 开头返回 null', () {
      expect(parseBuildScriptRepo('print(1)'), isNull);
      expect(parseBuildScriptRepo('import os'), isNull);
    });

    test('# 后无内容返回 null', () {
      expect(parseBuildScriptRepo('#'), isNull);
      expect(parseBuildScriptRepo('#   '), isNull);
      expect(parseBuildScriptRepo('#\nprint(1)'), isNull);
    });

    test('空内容或首行为空返回 null', () {
      expect(parseBuildScriptRepo(''), isNull);
      expect(parseBuildScriptRepo('\n# https://a.example.com/b.git'), isNull);
      expect(parseBuildScriptRepo('   \n# url'), isNull);
    });
  });

  group('parseBuildScriptHeader', () {
    test('仅仓库首行时 tools/options 为空且 sourceNone 为 false', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://github.com/foo/bar.git\nprint(1)\n',
      );

      expect(header, isNotNull);
      expect(header!.repo, 'https://github.com/foo/bar.git');
      expect(header.sourceNone, isFalse);
      expect(header.tools, isEmpty);
      expect(header.options, isEmpty);
      expect(header.dependencies, isEmpty);
    });

    test('# source: none 解析（与 tool/option 混排、兼容 CRLF 与无空格形式）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\r\n'
        '# source: none\r\n'
        '# tool: nasm https://example.com/nasm.zip\r\n'
        '# option: tbb = off | on\r\n'
        'print(1)\r\n',
      );

      expect(header!.sourceNone, isTrue);
      expect(header.repo, 'https://example.com/repo.git');
      expect(header.tools, hasLength(1));
      expect(header.options.single.name, 'tbb');

      final BuildScriptHeader? noSpace = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# source:none\n',
      );
      expect(noSpace!.sourceNone, isTrue);
    });

    test('# source 非法值忽略（仅 none 合法）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# source: yes\n'
        '# source: none extra\n'
        '# source: NONE\n'
        '# source:\n'
        '# source: \n'
        '# source: git\n'
        'print(1)\n',
      );

      expect(header!.sourceNone, isFalse);
    });

    test('# source: none 位于头部连续段之外时不生效', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '\n'
        '# source: none\n',
      );

      expect(header!.sourceNone, isFalse);

      final BuildScriptHeader? afterCode = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        'print(1)\n'
        '# source: none\n',
      );

      expect(afterCode!.sourceNone, isFalse);
    });

    test('首行不合法返回 null', () {
      expect(parseBuildScriptHeader('print(1)'), isNull);
      expect(parseBuildScriptHeader(''), isNull);
      expect(parseBuildScriptHeader('   \n# url'), isNull);
      expect(
        parseBuildScriptHeader('#\n# tool: nasm https://example.com/a.zip'),
        isNull,
      );
    });

    test('# tool 基础解析（name/url，兼容 CRLF）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\r\n'
        '# tool: nasm https://example.com/nasm.zip\r\n'
        'print(1)\r\n',
      );

      expect(header!.tools, hasLength(1));
      expect(header.tools.single.name, 'nasm');
      expect(header.tools.single.url, 'https://example.com/nasm.zip');
      expect(header.tools.single.binSubdir, isNull);
    });

    test('# tool 支持 bin= 子目录', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# tool: perl https://example.com/perl.zip bin=perl/bin\n',
      );

      expect(header!.tools.single.binSubdir, 'perl/bin');
    });

    test('# tool 非法行忽略', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# tool: nasm\n'
        '# tool: bad*name https://example.com/a.zip\n'
        '# tool: bad name https://example.com/a.zip\n'
        '# tool: nasm ftp://example.com/a.zip\n'
        '# tool: nasm example.com/a.zip\n'
        '# tool: nasm https://example.com/a.zip bin=../outside\n'
        '# tool: nasm https://example.com/a.zip bin=C:\\perl\\bin\n'
        '# tool: nasm https://example.com/a.zip bin=\\perl\\bin\n'
        '# tool: nasm https://example.com/a.zip bin=/perl/bin\n'
        '# tool: nasm https://example.com/a.zip bin=\n'
        '# tool: nasm https://example.com/a.zip extra\n'
        'print(1)\n',
      );

      expect(header!.tools, isEmpty);
    });

    test('# option 解析（默认首值、values 顺序）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# option: tbb = off | on\n',
      );

      expect(header!.options, hasLength(1));
      final BuildScriptOption option = header.options.single;
      expect(option.name, 'tbb');
      expect(option.values, <String>['off', 'on']);
      expect(option.defaultValue, 'off');
    });

    test('# option 单值（等号两侧无空格）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# option: mode=fast\n',
      );

      expect(header!.options.single.values, <String>['fast']);
      expect(header.options.single.defaultValue, 'fast');
    });

    test('# option 非法行忽略', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# option: 1abc = on\n'
        '# option: tbb on\n'
        '# option: tbb =\n'
        '# option: tbb = on |\n'
        '# option: tbb = off | off\n'
        '# option: = on\n'
        'print(1)\n',
      );

      expect(header!.options, isEmpty);
    });

    test('未知 # 行忽略，空行终止头部连续段', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# 普通注释\n'
        '#\n'
        '# tool: nasm https://example.com/nasm.zip\n'
        '\n'
        '# option: tbb = off | on\n',
      );

      expect(header!.tools, hasLength(1));
      expect(header.options, isEmpty);
    });

    test('首行后非 # 行立即终止头部连续段', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# tool: nasm https://example.com/nasm.zip\n'
        'print(1)\n'
        '# option: tbb = off | on\n',
      );

      expect(header!.tools, hasLength(1));
      expect(header.options, isEmpty);
    });

    test('重复 tool/option 名首次生效', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# tool: nasm https://one.example.com/a.zip\n'
        '# tool: nasm https://two.example.com/b.zip\n'
        '# option: tbb = off | on\n'
        '# option: tbb = on | off\n',
      );

      expect(header!.tools, hasLength(1));
      expect(header.tools.single.url, 'https://one.example.com/a.zip');
      expect(header.options, hasLength(1));
      expect(header.options.single.values, <String>['off', 'on']);
    });

    test('# depends 解析（包名、缺省版本与显式范围，兼容 CRLF 与无空格）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\r\n'
        '# depends: libfoo\r\n'
        '# depends: libbar [1.0,2.0)\r\n'
        '# depends:libbaz\r\n'
        '# depends: libqux [2.0,)\r\n'
        'print(1)\r\n',
      );

      expect(header!.dependencies, hasLength(4));
      expect(header.dependencies[0].name, 'libfoo');
      expect(header.dependencies[0].version, isNull);
      expect(header.dependencies[1].name, 'libbar');
      expect(header.dependencies[1].version, '[1.0,2.0)');
      expect(header.dependencies[2].name, 'libbaz');
      expect(header.dependencies[2].version, isNull);
      expect(header.dependencies[3].name, 'libqux');
      expect(header.dependencies[3].version, '[2.0,)');
    });

    test('# depends 非法行忽略（空、超 token、非法版本范围）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# depends:\n'
        '# depends: \n'
        '# depends: foo bar baz\n'
        '# depends: foo *\n'
        '# depends: foo (1.0)\n'
        '# depends: foo [2.0,1.0]\n'
        '# depends: foo 1.0.0 extra\n'
        'print(1)\n',
      );

      expect(header!.dependencies, isEmpty);
    });

    test('# depends 同名以首次为准（大小写不敏感）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '# depends: libfoo\n'
        '# depends: LIBFOO [2.0,)\n',
      );

      expect(header!.dependencies, hasLength(1));
      expect(header.dependencies.single.name, 'libfoo');
      expect(header.dependencies.single.version, isNull);
    });

    test('# depends 位于头部连续段之外时不生效', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        '\n'
        '# depends: libfoo\n',
      );

      expect(header!.dependencies, isEmpty);

      final BuildScriptHeader? afterCode = parseBuildScriptHeader(
        '# https://example.com/repo.git\n'
        'print(1)\n'
        '# depends: libfoo\n',
      );

      expect(afterCode!.dependencies, isEmpty);
    });
  });

  group('resolveBuildOptions', () {
    const List<BuildScriptOption> options = <BuildScriptOption>[
      BuildScriptOption(name: 'tbb', values: <String>['off', 'on']),
    ];

    test('合法保存值优先', () {
      expect(
        resolveBuildOptions(options, <String, String>{'tbb': 'on'}),
        <String, String>{'tbb': 'on'},
      );
    });

    test('非法或缺失取默认值', () {
      expect(
        resolveBuildOptions(options, <String, String>{'tbb': 'banana'}),
        <String, String>{'tbb': 'off'},
      );
      expect(resolveBuildOptions(options, <String, String>{}), <String, String>{
        'tbb': 'off',
      });
    });

    test('未声明键剔除', () {
      expect(
        resolveBuildOptions(options, <String, String>{
          'tbb': 'on',
          'other': 'x',
        }),
        <String, String>{'tbb': 'on'},
      );
    });

    test('无声明选项时返回空表', () {
      expect(
        resolveBuildOptions(<BuildScriptOption>[], <String, String>{
          'tbb': 'on',
        }),
        isEmpty,
      );
    });
  });

  group('optionEnvName', () {
    test('名称大写并加 CNP_OPTION_ 前缀', () {
      expect(optionEnvName('tbb'), 'CNP_OPTION_TBB');
      expect(optionEnvName('use_nasm'), 'CNP_OPTION_USE_NASM');
      expect(optionEnvName('my-option'), 'CNP_OPTION_MY_OPTION');
    });
  });

  group('loadBuildScriptHeader', () {
    PackModel buildPack({
      String? sourcePath,
      List<FileModel> files = const <FileModel>[],
    }) {
      final PackModel pack = PackModel(
        name: 'demo',
        version: '1.0.0',
        author: 'tester',
        sourcePath: sourcePath,
      );
      pack.files = List<FileModel>.of(files);
      return pack;
    }

    test('有脚本时读取并解析头部', () async {
      final PackModel pack = buildPack(
        sourcePath: r'C:\packs\demo',
        files: <FileModel>[FileModel(name: 'build.py', path: 'build.py')],
      );
      String? readPath;

      final BuildScriptHeader? header = await loadBuildScriptHeader(
        pack,
        readFile: (String path) async {
          readPath = path;
          return '# https://example.com/repo.git\n'
              '# tool: nasm https://example.com/nasm.zip\n';
        },
      );

      expect(readPath, r'C:\packs\demo/build.py');
      expect(header!.repo, 'https://example.com/repo.git');
      expect(header.tools.single.name, 'nasm');
    });

    test('无根级脚本不读文件并返回 null', () async {
      var readCalls = 0;
      final PackModel pack = buildPack(
        sourcePath: r'C:\packs\demo',
        files: <FileModel>[
          FileModel(name: 'build.py', path: 'scripts/build.py'),
        ],
      );

      final BuildScriptHeader? header = await loadBuildScriptHeader(
        pack,
        readFile: (String path) async {
          readCalls++;
          return '# https://example.com/repo.git';
        },
      );

      expect(header, isNull);
      expect(readCalls, 0);
    });

    test('无 sourcePath 不读文件并返回 null', () async {
      var readCalls = 0;
      final PackModel pack = buildPack(
        files: <FileModel>[FileModel(name: 'build.py', path: 'build.py')],
      );

      final BuildScriptHeader? header = await loadBuildScriptHeader(
        pack,
        readFile: (String path) async {
          readCalls++;
          return '# https://example.com/repo.git';
        },
      );

      expect(header, isNull);
      expect(readCalls, 0);
    });

    test('读取失败抛出原始异常', () async {
      final PackModel pack = buildPack(
        sourcePath: r'C:\packs\demo',
        files: <FileModel>[FileModel(name: 'build.py', path: 'build.py')],
      );
      final Exception failure = Exception('读取失败');

      await expectLater(
        loadBuildScriptHeader(
          pack,
          readFile: (String path) => Future<String>.error(failure),
        ),
        throwsA(same(failure)),
      );
    });
  });
}
