import 'package:cpp_nuget_pack/util/sha1.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sha1Hex', () {
    test('标准已知向量', () {
      expect(sha1Hex(''), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(sha1Hex('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(
        sha1Hex('The quick brown fox jumps over the lazy dog'),
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
    });

    test('跨数据块填充边界已知向量', () {
      expect(
        sha1Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
        '84983e441c3bd26ebaae4aa1f95129e5e54670f1',
      );
    });

    test('UTF-8 编码输入', () {
      expect(sha1Hex('中文'), '7be2d2d20c106eee0836c9bc2b939890a78e8fb3');
    });

    test('输出为 40 位小写十六进制且确定性', () {
      final String first = sha1Hex('deterministic-input');

      expect(first, hasLength(40));
      expect(first, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(sha1Hex('deterministic-input'), first);
    });
  });

  group('hash8', () {
    test('取 SHA-1 前 8 位小写十六进制', () {
      expect(hash8('demo'), '89e495e7');
      expect(hash8('my.lib'), '5b7003fb');
      expect(hash8('demo'), sha1Hex('demo').substring(0, 8));
      expect(hash8('demo'), hasLength(8));
    });
  });
}
