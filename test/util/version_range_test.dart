import 'package:cpp_nuget_pack/util/version_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('versionRangeError 合法输入', () {
    const List<String> inputs = <String>[
      '1',
      '1.0',
      '1.0.0',
      '1.0.0.0',
      '0.0.1',
      '01.0',
      '2147483647',
      '1.0.0-beta',
      '1.0.0-Beta',
      '1.0.0-alpha.1',
      '1.0.0-0',
      '1.0.0-beta.11',
      '1.0.0+build',
      '1.0.0-beta+exp.sha.5114f85',
      '[1.0]',
      '[1]',
      '[1.0.0.0]',
      '[1.0,)',
      '(1.0,)',
      '[1.0,]',
      '(1.0,]',
      '(,2.0]',
      '[,2.0]',
      '(,2.0)',
      '[,2.0)',
      '[1.0,2.0]',
      '(1.0,2.0]',
      '[1.0,2.0)',
      '(1.0,2.0)',
      '[1.0,1.0]',
      '[1.0,1.0.0]',
      '[1.0-alpha,1.0]',
      '[ 1.0 , 2.0 ]',
      '  [1.0, ] ',
    ];

    for (final String input in inputs) {
      test('接受「$input」', () {
        expect(versionRangeError(input), isNull);
        expect(isValidVersionRange(input), isTrue);
      });
    }
  });

  group('versionRangeError 拒绝输入', () {
    test('空输入提示必填', () {
      expect(versionRangeError(''), '请输入版本范围');
      expect(versionRangeError('   '), '请输入版本范围');
    });

    test('浮版本一律拒绝', () {
      for (final String input in <String>[
        '*',
        '1.*',
        '1.0.*',
        '*-*',
        '1.0-*',
      ]) {
        expect(versionRangeError(input), contains('浮版本'), reason: input);
      }
    });

    test('单值必须双方括号', () {
      for (final String input in <String>['(1.0)', '[1.0)', '(1.0]']) {
        expect(versionRangeError(input), '单值范围必须写成 [版本] 形式', reason: input);
      }
    });

    test('空区间与畸形结构无效', () {
      for (final String input in <String>[
        '[]',
        '(,)',
        '[,]',
        '[,)',
        '(,]',
        '[1.0,2.0,3.0]',
        '[1.0',
        '1.0]',
        '[1.0, 2.0',
        '[1.0]extra',
      ]) {
        expect(versionRangeError(input), '版本范围格式无效', reason: input);
      }
    });

    test('零宽度区间无效', () {
      for (final String input in <String>[
        '[1.0,1.0)',
        '(1.0,1.0]',
        '(1.0,1.0)',
        '[1.0-beta,1.0-beta)',
      ]) {
        expect(versionRangeError(input), '区间宽度为零，请使用 [版本] 表示', reason: input);
      }
    });

    test('下限高于上限无效', () {
      expect(versionRangeError('[2.0,1.0]'), '下限高于上限');
      expect(versionRangeError('[1.0,1.0-alpha]'), '下限高于上限');
      expect(versionRangeError('(1.0-beta,1.0-alpha)'), '下限高于上限');
    });

    test('非法版本号无效', () {
      for (final String input in <String>[
        '[1.0.0.0.0]',
        '[-1.0]',
        '1.',
        '.1',
        '2147483648',
        '1.0-01',
        '1.0-',
        '1.0+',
        '1.0.0-alpha..1',
        '1.0.0-al pha',
        '[1.0;2.0]',
        '<1.0',
        '~1.0',
        '^1.0',
        '>=1.0',
      ]) {
        expect(versionRangeError(input), '版本号格式无效', reason: input);
      }
    });

    test('逗号位置错误无效', () {
      for (final String input in <String>['1,', ',1', ',', '1.0,2.0']) {
        expect(versionRangeError(input), '版本范围格式无效', reason: input);
      }
    });

    test('非法输入时 isValidVersionRange 返回 false', () {
      expect(isValidVersionRange('(1.0)'), isFalse);
      expect(isValidVersionRange(''), isFalse);
    });
  });
}
