import 'dart:io';

import 'package:cpp_nuget_pack/build/build_script.dart';
import 'package:cpp_nuget_pack/pack/model/file_model.dart';
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

    test('findBuildScript 仅按文件名识别 build.py，不解析其内容', () {
      final FileModel? script = findBuildScript(<FileModel>[
        FileModel(name: 'build.py', path: 'build.py', size: 42),
        FileModel(name: 'build.py', path: 'a/build.py', size: 7),
        FileModel(name: 'build.PY', path: 'build.PY', size: 9),
      ]);

      expect(script, isNotNull);
      expect(
        script!.path,
        'build.PY',
        reason: '子目录里的不算；大小写不敏感匹配后按路径字典序取首个',
      );
    });
  });

  group('配方目录契约', () {
    test('.cache/src 与 .cache/tmp 由包源目录派生', () {
      expect(packSourceDirectory(r'C:\libs\demo'), r'C:\libs\demo\.cache\src');
      expect(packTmpDirectory(r'C:\libs\demo'), r'C:\libs\demo\.cache\tmp');
    });

    test('清空 tmp 只删 .cache/tmp 的内容，不动 .cache/src 与产物', () async {
      final Directory root = Directory.systemTemp.createTempSync('cnp-tmp-');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/.cache/tmp/nested').createSync(recursive: true);
      Directory('${root.path}/.cache/src').createSync(recursive: true);
      Directory('${root.path}/release').createSync(recursive: true);
      File('${root.path}/.cache/tmp/stale.obj').writeAsStringSync('x');
      File('${root.path}/.cache/tmp/nested/deep.obj').writeAsStringSync('x');
      File('${root.path}/.cache/src/keep.h').writeAsStringSync('#pragma once');
      File('${root.path}/release/lib.lib').writeAsStringSync('x');

      await clearPackTmpDirectory(root.path);

      expect(File('${root.path}/.cache/tmp/stale.obj').existsSync(), isFalse);
      expect(
        File('${root.path}/.cache/tmp/nested/deep.obj').existsSync(),
        isFalse,
      );
      expect(File('${root.path}/.cache/src/keep.h').existsSync(), isTrue);
      expect(File('${root.path}/release/lib.lib').existsSync(), isTrue);
    });

    test('tmp 不存在时清理不报错（幂等）', () async {
      final Directory root = Directory.systemTemp.createTempSync('cnp-tmp2-');
      addTearDown(() => root.deleteSync(recursive: true));
      await expectLater(clearPackTmpDirectory(root.path), completes);
      expect(Directory('${root.path}/.cache/tmp').existsSync(), isTrue);
    });
  });
}

