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
    test('仅源码声明首行时 tools/options 为空且 sourceNone 为 false', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\nprint(1)\n',
      );

      expect(header, isNotNull);
      expect(header!.sourceDir, '.cnp-src');
      expect(header.sourceNone, isFalse);
      expect(header.tools, isEmpty);
      expect(header.options, isEmpty);
      expect(header.dependencies, isEmpty);
    });

    test('# source: none 作为首行解析（兼容 CRLF 与无空格形式）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: none\r\n'
        '# tool: nasm https://example.com/nasm.zip\r\n'
        '# option: tbb = off | on\r\n'
        'print(1)\r\n',
      );

      expect(header!.sourceDir, isNull);
      expect(header.sourceNone, isTrue);
      expect(header.tools, hasLength(1));
      expect(header.options.single.name, 'tbb');

      final BuildScriptHeader? noSpace = parseBuildScriptHeader(
        '# source:none\n',
      );
      expect(noSpace!.sourceNone, isTrue);

      final BuildScriptHeader? upper = parseBuildScriptHeader(
        '# source: NONE\n',
      );
      expect(upper!.sourceNone, isTrue);
    });

    test('预置源码目录保留原样（含子目录、两侧空白、多种分隔符）', () {
      expect(
        parseBuildScriptHeader('# source: vendor/zlib\n')!.sourceDir,
        'vendor/zlib',
      );
      expect(
        parseBuildScriptHeader('# source:   .cnp-src   \n')!.sourceDir,
        '.cnp-src',
      );
      expect(
        parseBuildScriptHeader('# source: .cnp-src\\win\n')!.sourceDir,
        r'.cnp-src\win',
      );
    });

    test('第 2 行起的 # source: 一律按注释忽略（不覆盖首行声明）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# source: yes\n'
        '# source: none\n'
        '# source: \n'
        'print(1)\n',
      );

      expect(header!.sourceDir, '.cnp-src');
      expect(header.sourceNone, isFalse);
    });

    test('首行缺值解析为非 null 空串（交由 requireValidSourceDirective 报错）', () {
      expect(parseBuildScriptHeader('# source:\n')!.sourceDir, '');
      expect(parseBuildScriptHeader('# source:   \n')!.sourceDir, '');
      expect(parseBuildScriptHeader('# source:\n')!.sourceNone, isFalse);
    });

    test('首行缺声明时整头解析失败（fail-closed，不做旧写法兼容）', () {
      expect(
        parseBuildScriptHeader('# https://github.com/foo/bar.git\nprint(1)\n'),
        isNull,
      );
      expect(
        parseBuildScriptHeader('# https://example.com/repo.git\n'),
        isNull,
      );
      expect(parseBuildScriptHeader('# 普通注释\n# source: none\n'), isNull);
      expect(parseBuildScriptHeader('   #   \n# source: none\n'), isNull);
      // 锚点前缀含空格，`#source:` 不命中
      expect(parseBuildScriptHeader('#source: .cnp-src\n'), isNull);
      expect(parseBuildScriptHeader('# source: .cnp-src\n'), isNotNull);
    });

    test('首行不合法返回 null', () {
      expect(parseBuildScriptHeader('print(1)'), isNull);
      expect(parseBuildScriptHeader(''), isNull);
      expect(parseBuildScriptHeader('   \n# source: none'), isNull);
      expect(
        parseBuildScriptHeader('#\n# tool: nasm https://example.com/a.zip'),
        isNull,
      );
    });

    test('# tool 基础解析（name/url，兼容 CRLF）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\r\n'
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
        '# source: .cnp-src\n'
        '# tool: perl https://example.com/perl.zip bin=perl/bin\n',
      );

      expect(header!.tools.single.binSubdir, 'perl/bin');
    });

    test('# tool 非法行忽略', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
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
        '# source: .cnp-src\n'
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
        '# source: .cnp-src\n'
        '# option: mode=fast\n',
      );

      expect(header!.options.single.values, <String>['fast']);
      expect(header.options.single.defaultValue, 'fast');
    });

    test('# option 非法行忽略', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
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

    test('# checkbox 解析（勾选态 / 未勾选态，首值为默认）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# checkbox: use_nasm = ON | OFF\n'
        '# checkbox:strict=OFF|ON\n',
      );

      expect(header!.options, hasLength(2));
      expect(header.options[0].name, 'use_nasm');
      expect(header.options[0].control, BuildOptionControl.checkbox);
      expect(header.options[0].values, <String>['ON', 'OFF']);
      expect(header.options[0].defaultValue, 'ON');
      expect(header.options[1].name, 'strict');
      expect(header.options[1].values, <String>['OFF', 'ON']);
    });

    test('# checkbox 非法行忽略（值非恰 2 个 / 空 / 重复）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# checkbox: one = ON\n'
        '# checkbox: three = ON | OFF | AUTO\n'
        '# checkbox: empty = ON |\n'
        '# checkbox: dup = ON | ON\n'
        '# checkbox: no-equals ON OFF\n'
        'print(1)\n',
      );

      expect(header!.options, isEmpty);
    });

    test('# multiselect 解析（声明序值列表）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# multiselect: accel = SSE2 | AVX2 | NEON\n',
      );

      expect(header!.options, hasLength(1));
      expect(header.options.single.control, BuildOptionControl.multiselect);
      expect(header.options.single.values, <String>['SSE2', 'AVX2', 'NEON']);
    });

    test('# multiselect 非法行忽略（空值 / 重复 / 含分号）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# multiselect: a = x | | y\n'
        '# multiselect: b = x | x\n'
        '# multiselect: c = a;b | c\n'
        '# multiselect: d =\n'
        'print(1)\n',
      );

      expect(header!.options, isEmpty);
    });

    test('保留名 runtime 的选项声明忽略（大小写 / 空白不敏感，其余正常解析）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# option: runtime = md | mt\n'
        '# checkbox: Runtime = ON | OFF\n'
        '# multiselect: RUNTIME = x | y\n'
        '# option:   rUnTiMe   = fast | slow\n'
        '# option: tbb = off | on\n',
      );

      expect(header!.options, hasLength(1));
      expect(header.options.single.name, 'tbb');
      expect(header.options.single.values, <String>['off', 'on']);
      expect(header.runtime, isNull);
    });

    test('三型同名以首次声明为准（跨指令）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# option: mode = fast | slow\n'
        '# checkbox: mode = ON | OFF\n',
      );

      expect(header!.options, hasLength(1));
      expect(header.options.single.control, BuildOptionControl.dropdown);
    });

    test('# runtime 解析（大小写不敏感，首次有效声明生效）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# runtime: MT\n'
        '# runtime: md\n',
      );

      expect(header!.runtime, 'mt');

      final BuildScriptHeader? invalidFirst = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# runtime: gnu\n'
        '# runtime: md\n',
      );
      expect(invalidFirst!.runtime, 'md');

      final BuildScriptHeader? noSpace = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# runtime:mt\n',
      );
      expect(noSpace!.runtime, 'mt');
    });

    test('# runtime 非法行忽略（空值 / 未知家族 / 多余 token）', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# runtime:\n'
        '# runtime: \n'
        '# runtime: dynamic\n'
        '# runtime: mt extra\n',
      );

      expect(header!.runtime, isNull);
    });

    test('# runtime 位于头部连续段之外时不生效', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '\n'
        '# runtime: mt\n',
      );

      expect(header!.runtime, isNull);

      final BuildScriptHeader? afterCode = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        'print(1)\n'
        '# runtime: mt\n',
      );

      expect(afterCode!.runtime, isNull);
    });

    test('未知 # 行忽略，空行终止头部连续段', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
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
        '# source: .cnp-src\n'
        '# tool: nasm https://example.com/nasm.zip\n'
        'print(1)\n'
        '# option: tbb = off | on\n',
      );

      expect(header!.tools, hasLength(1));
      expect(header.options, isEmpty);
    });

    test('重复 tool/option 名首次生效', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
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
        '# source: .cnp-src\r\n'
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
        '# source: .cnp-src\n'
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
        '# source: .cnp-src\n'
        '# depends: libfoo\n'
        '# depends: LIBFOO [2.0,)\n',
      );

      expect(header!.dependencies, hasLength(1));
      expect(header.dependencies.single.name, 'libfoo');
      expect(header.dependencies.single.version, isNull);
    });

    test('# depends 位于头部连续段之外时不生效', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '\n'
        '# depends: libfoo\n',
      );

      expect(header!.dependencies, isEmpty);

      final BuildScriptHeader? afterCode = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        'print(1)\n'
        '# depends: libfoo\n',
      );

      expect(afterCode!.dependencies, isEmpty);
    });
  });

  group('# profile 指令', () {
    test('解析头部记录 # profile: v1', () {
      final BuildScriptHeader? header = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# profile: v1\n'
        '# tool: nasm https://example.com/nasm.zip\n',
      );

      expect(header!.profileVersion, 'v1');
      expect(header.tools, hasLength(1));
    });

    test('v1 允许值大小写与空白，头部连续段之外不生效', () {
      final BuildScriptHeader? tolerated = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# profile:  V1  \n',
      );
      expect(tolerated!.profileVersion, 'V1');
      expect(
        () => requireSupportedBuildProfile(tolerated, r'C:\libs\demo\build.py'),
        returnsNormally,
      );

      final BuildScriptHeader? outside = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '\n'
        '# profile: v1\n',
      );
      expect(outside!.profileVersion, isNull);

      final BuildScriptHeader? afterCode = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        'print(1)\n'
        '# profile: v1\n',
      );
      expect(afterCode!.profileVersion, isNull);
    });

    test('缺少/空/不支持 Profile 声明均给出包含路径的中文错误', () {
      final BuildScriptHeader header = parseBuildScriptHeader(
        '# source: .cnp-src\n',
      )!;
      expect(
        () => requireSupportedBuildProfile(header, r'C:\libs\demo\build.py'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            allOf(
              contains(r'C:\libs\demo\build.py'),
              contains('# profile: v1'),
            ),
          ),
        ),
      );

      final BuildScriptHeader empty = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# profile:\n',
      )!;
      expect(
        () => requireSupportedBuildProfile(empty, r'C:\libs\demo\build.py'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            allOf(contains('缺少 Profile 声明'), contains('# profile: v1')),
          ),
        ),
      );

      final BuildScriptHeader unsupported = parseBuildScriptHeader(
        '# source: .cnp-src\n'
        '# profile: v2\n',
      )!;
      expect(
        () =>
            requireSupportedBuildProfile(unsupported, r'C:\libs\demo\build.py'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            allOf(contains('v2'), contains('仅支持 v1')),
          ),
        ),
      );
    });
  });

  group('requireValidSourceDirective', () {
    const String scriptPath = r'C:\libs\demo\build.py';

    void expectRejected(String firstLine, String value, String reason) {
      final BuildScriptHeader header = parseBuildScriptHeader('$firstLine\n')!;
      expect(
        () => requireValidSourceDirective(header, scriptPath),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            allOf(
              contains('build.py 源码目录声明非法'),
              contains(scriptPath),
              contains('# source: $value'),
              contains(reason),
            ),
          ),
        ),
      );
    }

    test('# source: none 与隐藏目录声明通过', () {
      requireValidSourceDirective(
        parseBuildScriptHeader('# source: none\n')!,
        scriptPath,
      );
      requireValidSourceDirective(
        parseBuildScriptHeader('# source: .cnp-src\n')!,
        scriptPath,
      );
    });

    test('首段为隐藏名的多段相对路径通过', () {
      requireValidSourceDirective(
        parseBuildScriptHeader('# source: .cnp-src/vendor/zlib\n')!,
        scriptPath,
      );
      requireValidSourceDirective(
        parseBuildScriptHeader(r'# source: .cnp-src\vendor\zlib\n')!,
        scriptPath,
      );
    });

    test('空值按「值非法」处理', () {
      expectRejected('# source:', '', '不得含盘符 或 ..');
      expectRejected('# source:    ', '', '不得含盘符 或 ..');
    });

    test('绝对路径、盘符与 .. 越界被拒绝', () {
      expectRejected('# source: ../escape', '../escape', '不得含盘符 或 ..');
      expectRejected(
        '# source: vendor/../../escape',
        'vendor/../../escape',
        '不得含盘符 或 ..',
      );
      expectRejected(r'# source: C:\abs\path', r'C:\abs\path', '不得含盘符 或 ..');
      expectRejected('# source: /abs/path', '/abs/path', '不得含盘符 或 ..');
      expectRejected(r'# source: \abs\path', r'\abs\path', '不得含盘符 或 ..');
    });

    test('非隐藏目录名被拒绝（否则源码进包且构建后被删）', () {
      expectRejected('# source: vendor/zlib', 'vendor/zlib', '隐藏目录');
      expectRejected('# source: src', 'src', '隐藏目录');
      expectRejected(r'# source: vendor\zlib', r'vendor\zlib', '隐藏目录');
      expectRejected('# source: cnp-src', 'cnp-src', '隐藏目录');
    });

    test('缺声明文案同时点出两种合法写法', () {
      final String message = buildScriptSourceDeclarationMissingMessage(
        scriptPath,
      );
      expect(
        message,
        allOf(
          contains('build.py 首行缺少源码声明'),
          contains(scriptPath),
          contains('# source: <包内相对目录>'),
          contains('# source: none'),
        ),
      );
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

  group('runtime 保留键与归一化', () {
    test('normalizeRuntimeLibrary 大小写与空白不敏感', () {
      expect(normalizeRuntimeLibrary(' MD '), 'md');
      expect(normalizeRuntimeLibrary('Mt'), 'mt');
      expect(normalizeRuntimeLibrary('dynamic'), isNull);
      expect(normalizeRuntimeLibrary(null), isNull);
      expect(normalizeRuntimeLibrary(''), isNull);
    });

    test('保留键与下发环境变量名常量', () {
      expect(runtimeOptionName, 'runtime');
      expect(runtimeLibraryEnvName, 'CNP_RUNTIME_LIBRARY');
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
          return '# source: .cnp-src\n'
              '# tool: nasm https://example.com/nasm.zip\n';
        },
      );

      expect(readPath, r'C:\packs\demo/build.py');
      expect(header!.sourceDir, '.cnp-src');
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
          return '# source: .cnp-src';
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
          return '# source: .cnp-src';
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
