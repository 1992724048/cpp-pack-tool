import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/packaging/license_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLicenseFileName', () {
    test('核心名与后缀/连字符变体匹配（大小写不敏感）', () {
      const List<String> names = <String>[
        'LICENSE',
        'license',
        'License',
        'LICENSE.txt',
        'LICENSE-MIT',
        'LICENCE',
        'licence.md',
        'COPYING',
        'COPYING.LESSER',
        'UNLICENSE',
        'unlicense.txt',
        'NOTICE',
        'NOTICE.md',
      ];

      for (final String name in names) {
        expect(isLicenseFileName(name), isTrue, reason: name);
      }
    });

    test('相似但非法的文件名不匹配', () {
      const List<String> names = <String>[
        'license_checker.dart',
        'licenses',
        'licenses.txt',
        'mylicense.txt',
        'README.md',
        'license.',
        'license-',
        'license..txt',
        'LICENSE!.txt',
        '',
      ];

      for (final String name in names) {
        expect(isLicenseFileName(name), isFalse, reason: name);
      }
    });
  });

  group('findPrimaryLicensePath', () {
    test('仅源目录根部的许可证参与识别', () {
      final List<FileModel> files = <FileModel>[
        FileModel(name: 'LICENSE', path: 'docs/LICENSE', size: 10),
        FileModel(name: 'COPYING', path: r'docs\licenses\COPYING', size: 20),
      ];

      expect(findPrimaryLicensePath(files), isNull);
    });

    test('核心名优先级 license > licence > copying > unlicense > notice', () {
      expect(
        findPrimaryLicensePath(<FileModel>[
          FileModel(name: 'NOTICE', path: 'NOTICE', size: 10),
          FileModel(name: 'COPYING', path: 'COPYING', size: 10),
          FileModel(name: 'LICENCE', path: 'LICENCE', size: 10),
          FileModel(name: 'LICENSE', path: 'LICENSE', size: 10),
        ]),
        'LICENSE',
      );
      expect(
        findPrimaryLicensePath(<FileModel>[
          FileModel(name: 'notice.md', path: 'notice.md', size: 10),
          FileModel(name: 'unlicense.txt', path: 'unlicense.txt', size: 10),
          FileModel(name: 'copying.txt', path: 'copying.txt', size: 10),
          FileModel(name: 'licence.txt', path: 'licence.txt', size: 10),
        ]),
        'licence.txt',
      );
    });

    test('同核心名按小写文件名字典序取先者', () {
      expect(
        findPrimaryLicensePath(<FileModel>[
          FileModel(name: 'LICENSE.txt', path: 'LICENSE.txt', size: 10),
          FileModel(name: 'LICENSE', path: 'LICENSE', size: 10),
        ]),
        'LICENSE',
      );
      expect(
        findPrimaryLicensePath(<FileModel>[
          FileModel(name: 'license.txt', path: 'license.txt', size: 10),
          FileModel(name: 'license.md', path: 'license.md', size: 10),
        ]),
        'license.md',
      );
    });

    test('无匹配或空列表返回 null', () {
      expect(
        findPrimaryLicensePath(<FileModel>[
          FileModel(name: 'README.md', path: 'README.md', size: 10),
        ]),
        isNull,
      );
      expect(findPrimaryLicensePath(const <FileModel>[]), isNull);
    });
  });
}
