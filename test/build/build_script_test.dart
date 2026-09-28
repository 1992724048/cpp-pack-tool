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

  group('parseBuildScriptHeader', () {
    test('无任何指令行时返回空头部', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\nprint(1)\n',
      );

      expect(header.tools, isEmpty);
      expect(header.options, isEmpty);
      expect(header.dependencies, isEmpty);
    });

    test('首行非 # 行时头部为空（其后 # 行不再解析）', () {
      expect(parseBuildScriptHeader('print(1)').tools, isEmpty);
      expect(parseBuildScriptHeader('').tools, isEmpty);
      expect(
        parseBuildScriptHeader(
          '   \n# tool: nasm https://example.com/a.zip\n',
        ).tools,
        isEmpty,
      );
    });

    // 各形态走同一条「未知注释」分支，故本例对「首行内容」这一维度是恒真的；
    // 它的作用是防回归——一旦有人重新为 `# source:` 行加特判（如再当作源码声明
    // 或直接报错），本例会因首行被区别对待而失败。
    test('旧式首行（裸 URL / # source: none / # source: <dir>）按普通注释忽略，其余指令照常解析', () {
      for (final String legacy in <String>[
        '# https://github.com/foo/bar.git',
        '# https://example.com/repo.git',
        '# source: none',
        '# source: NONE',
        '# source: .cnp-src',
        '# source: .cnp-src/vendor/zlib',
        r'# source: .cnp-src\vendor\zlib',
        '# 普通注释',
      ]) {
        final BuildScriptHeader header = parseBuildScriptHeader(
          '$legacy\n'
          '# tool: nasm https://example.com/nasm.zip\n'
          '# option: tbb = off | on\n'
          '# depends: libfoo\n'
          'print(1)\n',
        );

        expect(header.tools.single.name, 'nasm', reason: '首行 "$legacy"');
        expect(header.options.single.name, 'tbb', reason: '首行 "$legacy"');
        expect(
          header.dependencies.single.name,
          'libfoo',
          reason: '首行 "$legacy"',
        );
      }
    });

    test('头部连续段以第 1 行起算（首行即指令）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# tool: nasm https://example.com/nasm.zip\n'
        '# option: tbb = off | on\n'
        'print(1)\n',
      );

      expect(header.tools.single.name, 'nasm');
      expect(header.options.single.name, 'tbb');
    });

    test('段内任意位置的 # source: 行按注释忽略', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# 配方说明\n'
        '# source: yes\n'
        '# source:\n'
        '# tool: nasm https://example.com/nasm.zip\n',
      );

      expect(header.tools, hasLength(1));
      expect(header.options, isEmpty);
    });

    test('# tool 基础解析（name/url，兼容 CRLF）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\r\n'
        '# tool: nasm https://example.com/nasm.zip\r\n'
        'print(1)\r\n',
      );

      expect(header.tools, hasLength(1));
      expect(header.tools.single.name, 'nasm');
      expect(header.tools.single.url, 'https://example.com/nasm.zip');
      expect(header.tools.single.binSubdir, isNull);
    });

    test('# tool 支持 bin= 子目录', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# tool: perl https://example.com/perl.zip bin=perl/bin\n',
      );

      expect(header.tools.single.binSubdir, 'perl/bin');
    });

    test('# tool 非法行忽略', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
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

      expect(header.tools, isEmpty);
    });

    test('# option 解析（默认首值、values 顺序）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# option: tbb = off | on\n',
      );

      expect(header.options, hasLength(1));
      final BuildScriptOption option = header.options.single;
      expect(option.name, 'tbb');
      expect(option.values, <String>['off', 'on']);
      expect(option.defaultValue, 'off');
    });

    test('# option 单值（等号两侧无空格）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# option: mode=fast\n',
      );

      expect(header.options.single.values, <String>['fast']);
      expect(header.options.single.defaultValue, 'fast');
    });

    test('# option 非法行忽略', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# option: 1abc = on\n'
        '# option: tbb on\n'
        '# option: tbb =\n'
        '# option: tbb = on |\n'
        '# option: tbb = off | off\n'
        '# option: = on\n'
        'print(1)\n',
      );

      expect(header.options, isEmpty);
    });

    test('# checkbox 解析（勾选态 / 未勾选态，首值为默认）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# checkbox: use_nasm = ON | OFF\n'
        '# checkbox:strict=OFF|ON\n',
      );

      expect(header.options, hasLength(2));
      expect(header.options[0].name, 'use_nasm');
      expect(header.options[0].control, BuildOptionControl.checkbox);
      expect(header.options[0].values, <String>['ON', 'OFF']);
      expect(header.options[0].defaultValue, 'ON');
      expect(header.options[1].name, 'strict');
      expect(header.options[1].values, <String>['OFF', 'ON']);
    });

    test('# checkbox 非法行忽略（值非恰 2 个 / 空 / 重复）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# checkbox: one = ON\n'
        '# checkbox: three = ON | OFF | AUTO\n'
        '# checkbox: empty = ON |\n'
        '# checkbox: dup = ON | ON\n'
        '# checkbox: no-equals ON OFF\n'
        'print(1)\n',
      );

      expect(header.options, isEmpty);
    });

    test('# multiselect 解析（声明序值列表）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# multiselect: accel = SSE2 | AVX2 | NEON\n',
      );

      expect(header.options, hasLength(1));
      expect(header.options.single.control, BuildOptionControl.multiselect);
      expect(header.options.single.values, <String>['SSE2', 'AVX2', 'NEON']);
    });

    test('# multiselect 非法行忽略（空值 / 重复 / 含分号）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# multiselect: a = x | | y\n'
        '# multiselect: b = x | x\n'
        '# multiselect: c = a;b | c\n'
        '# multiselect: d =\n'
        'print(1)\n',
      );

      expect(header.options, isEmpty);
    });

    test('三型同名以首次声明为准（跨指令）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# option: mode = fast | slow\n'
        '# checkbox: mode = ON | OFF\n',
      );

      expect(header.options, hasLength(1));
      expect(header.options.single.control, BuildOptionControl.dropdown);
    });

    test('未知 # 行忽略，空行终止头部连续段', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# 普通注释\n'
        '#\n'
        '# tool: nasm https://example.com/nasm.zip\n'
        '\n'
        '# option: tbb = off | on\n',
      );

      expect(header.tools, hasLength(1));
      expect(header.options, isEmpty);
    });

    test('首行后非 # 行立即终止头部连续段', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# tool: nasm https://example.com/nasm.zip\n'
        'print(1)\n'
        '# option: tbb = off | on\n',
      );

      expect(header.tools, hasLength(1));
      expect(header.options, isEmpty);
    });

    test('重复 tool/option 名首次生效', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# tool: nasm https://one.example.com/a.zip\n'
        '# tool: nasm https://two.example.com/b.zip\n'
        '# option: tbb = off | on\n'
        '# option: tbb = on | off\n',
      );

      expect(header.tools, hasLength(1));
      expect(header.tools.single.url, 'https://one.example.com/a.zip');
      expect(header.options, hasLength(1));
      expect(header.options.single.values, <String>['off', 'on']);
    });

    test('# depends 解析（包名、缺省版本与显式范围，兼容 CRLF 与无空格）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\r\n'
        '# depends: libfoo\r\n'
        '# depends: libbar [1.0,2.0)\r\n'
        '# depends:libbaz\r\n'
        '# depends: libqux [2.0,)\r\n'
        'print(1)\r\n',
      );

      expect(header.dependencies, hasLength(4));
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
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# depends:\n'
        '# depends: \n'
        '# depends: foo bar baz\n'
        '# depends: foo *\n'
        '# depends: foo (1.0)\n'
        '# depends: foo [2.0,1.0]\n'
        '# depends: foo 1.0.0 extra\n'
        'print(1)\n',
      );

      expect(header.dependencies, isEmpty);
    });

    test('# depends 同名以首次为准（大小写不敏感）', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# depends: libfoo\n'
        '# depends: LIBFOO [2.0,)\n',
      );

      expect(header.dependencies, hasLength(1));
      expect(header.dependencies.single.name, 'libfoo');
      expect(header.dependencies.single.version, isNull);
    });

    test('# depends 位于头部连续段之外时不生效', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '\n'
        '# depends: libfoo\n',
      );

      expect(header.dependencies, isEmpty);

      final BuildScriptHeader afterCode = parseBuildScriptHeader(
        '# 配方说明\n'
        'print(1)\n'
        '# depends: libfoo\n',
      );

      expect(afterCode.dependencies, isEmpty);
    });
  });

  group('# profile 指令已退役', () {
    test('头部内的 # profile: 行按未知注释忽略，不影响其余指令解析', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n'
        '# profile: v1\n'
        '# tool: nasm https://example.com/nasm.zip\n',
      );

      expect(header.tools, hasLength(1));
    });

    test('不带 # profile: 声明的配方照常解析出头部', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# 配方说明\n',
      );

      expect(header.tools, isEmpty);
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

    test('复选框：合法值优先，非法或缺失取首值（ON）', () {
      const List<BuildScriptOption> checkboxOptions = <BuildScriptOption>[
        BuildScriptOption(
          name: 'use_nasm',
          values: <String>['ON', 'OFF'],
          control: BuildOptionControl.checkbox,
        ),
      ];

      expect(
        resolveBuildOptions(checkboxOptions, <String, String>{
          'use_nasm': 'OFF',
        }),
        <String, String>{'use_nasm': 'OFF'},
      );
      expect(
        resolveBuildOptions(checkboxOptions, <String, String>{
          'use_nasm': 'ON',
        }),
        <String, String>{'use_nasm': 'ON'},
      );
      expect(
        resolveBuildOptions(checkboxOptions, <String, String>{
          'use_nasm': 'maybe',
        }),
        <String, String>{'use_nasm': 'ON'},
      );
      expect(
        resolveBuildOptions(checkboxOptions, <String, String>{'use_nasm': ''}),
        <String, String>{'use_nasm': 'ON'},
      );
    });

    test('多选：求交并按声明序连接，可全不选（空串）', () {
      const List<BuildScriptOption> multiOptions = <BuildScriptOption>[
        BuildScriptOption(
          name: 'accel',
          values: <String>['SSE2', 'AVX2', 'NEON'],
          control: BuildOptionControl.multiselect,
        ),
      ];

      expect(
        resolveBuildOptions(multiOptions, <String, String>{
          'accel': 'NEON;SSE2',
        }),
        <String, String>{'accel': 'SSE2;NEON'},
      );
      expect(
        resolveBuildOptions(multiOptions, <String, String>{
          'accel': ' AVX2 ; bogus ',
        }),
        <String, String>{'accel': 'AVX2'},
      );
      expect(
        resolveBuildOptions(multiOptions, <String, String>{'accel': ''}),
        <String, String>{'accel': ''},
      );
      expect(
        resolveBuildOptions(multiOptions, <String, String>{}),
        <String, String>{'accel': ''},
      );
    });
  });

  group('effectiveBuildOptionValue', () {
    const BuildScriptOption dropdown = BuildScriptOption(
      name: 'mode',
      values: <String>['fast', 'slow'],
    );
    const BuildScriptOption checkbox = BuildScriptOption(
      name: 'toggle',
      values: <String>['ON', 'OFF'],
      control: BuildOptionControl.checkbox,
    );
    const BuildScriptOption multi = BuildScriptOption(
      name: 'accel',
      values: <String>['SSE2', 'AVX2', 'NEON'],
      control: BuildOptionControl.multiselect,
    );

    test('下拉与复选框：合法保存值优先，非法或缺失取默认值', () {
      expect(
        effectiveBuildOptionValue(dropdown, <String, String>{'mode': 'slow'}),
        'slow',
      );
      expect(
        effectiveBuildOptionValue(dropdown, <String, String>{'mode': 'turbo'}),
        'fast',
      );
      expect(effectiveBuildOptionValue(dropdown, <String, String>{}), 'fast');
      expect(
        effectiveBuildOptionValue(checkbox, <String, String>{'toggle': 'OFF'}),
        'OFF',
      );
      expect(
        effectiveBuildOptionValue(checkbox, <String, String>{'toggle': 'x'}),
        'ON',
      );
    });

    test('多选：归一化为声明序连接（可空串）', () {
      expect(
        effectiveBuildOptionValue(multi, <String, String>{
          'accel': 'NEON;SSE2',
        }),
        'SSE2;NEON',
      );
      expect(
        effectiveBuildOptionValue(multi, <String, String>{'accel': 'bogus'}),
        '',
      );
      expect(
        effectiveBuildOptionValue(multi, <String, String>{'accel': ''}),
        '',
      );
      expect(effectiveBuildOptionValue(multi, <String, String>{}), '');
    });

    test('multiSelectSelection 求交并保留声明顺序', () {
      expect(
        multiSelectSelection(<String>['SSE2', 'AVX2', 'NEON'], 'NEON;SSE2'),
        <String>{'SSE2', 'NEON'},
      );
      expect(multiSelectSelection(<String>['SSE2', 'AVX2'], null), isEmpty);
      expect(
        multiSelectSelection(<String>['SSE2', 'AVX2'], 'AVX2;ghost;'),
        <String>{'AVX2'},
      );
    });

    test('normalizedMultiSelectValue 归一化保存值', () {
      expect(normalizedMultiSelectValue(<String>['a', 'b', 'c'], 'c;a'), 'a;c');
      expect(normalizedMultiSelectValue(<String>['a', 'b'], ''), '');
      expect(normalizedMultiSelectValue(<String>['a', 'b'], null), '');
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
          return '# 配方说明\n'
              '# tool: nasm https://example.com/nasm.zip\n';
        },
      );

      expect(readPath, r'C:\packs\demo/build.py');
      expect(header!.tools.single.name, 'nasm');
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
          return '# 配方说明\n';
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
          return '# 配方说明\n';
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
