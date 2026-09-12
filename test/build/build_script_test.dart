import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
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
}
