import 'package:cpp_nuget_pack/util/author_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPlaceholderAuthor', () {
    test('命中全部占位值（trim + 大小写不敏感）', () {
      const List<String> placeholders = <String>[
        '',
        '  ',
        '无',
        '未知',
        '未填写',
        'unknown',
        'Unknown',
        'UNKNOWN',
        'anonymous',
        'Anonymous',
        'none',
        'None',
        'n/a',
        'N/A',
        ' 无 ',
        ' 未知 ',
        '佚名',
      ];

      for (final String author in placeholders) {
        expect(isPlaceholderAuthor(author), isTrue, reason: '「$author」应视为占位作者');
      }
    });

    test('真实姓名不命中', () {
      for (final String author in <String>['张三', 'tester', 'Alice', 'N/A-2']) {
        expect(
          isPlaceholderAuthor(author),
          isFalse,
          reason: '「$author」不应视为占位作者',
        );
      }
    });
  });

  group('resolveDefaultAuthor', () {
    test('默认作者非空且作者为占位时替换为默认作者', () {
      expect(resolveDefaultAuthor('无', '张三'), '张三');
      expect(resolveDefaultAuthor('', '张三'), '张三');
      expect(resolveDefaultAuthor('unknown', '张三'), '张三');
    });

    test('默认作者为空或作者已填写时原样返回', () {
      expect(resolveDefaultAuthor('无', ''), '无');
      expect(resolveDefaultAuthor('无', '   '), '无');
      expect(resolveDefaultAuthor('Alice', '张三'), 'Alice');
    });

    test('默认作者去首尾空白后替换', () {
      expect(resolveDefaultAuthor('佚名', '  张三  '), '张三');
    });
  });
}
