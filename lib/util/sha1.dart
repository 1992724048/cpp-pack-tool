import 'dart:convert';
import 'dart:typed_data';

const List<int> _initialState = <int>[
  0x67452301,
  0xEFCDAB89,
  0x98BADCFE,
  0x10325476,
  0xC3D2E1F0,
];

/// 纯 Dart SHA-1（十六进制小写），避免为 8 位散列引入依赖。
String sha1Hex(String input) {
  final Uint8List message = _padMessage(utf8.encode(input));
  final List<int> state = List<int>.of(_initialState);
  final List<int> words = List<int>.filled(80, 0);
  for (int offset = 0; offset < message.length; offset += 64) {
    _fillWords(words, message, offset);
    _compress(state, words);
  }
  final StringBuffer buffer = StringBuffer();
  for (final int value in state) {
    buffer.write(value.toRadixString(16).padLeft(8, '0'));
  }
  return buffer.toString();
}

String hash8(String packId) => sha1Hex(packId).substring(0, 8);

Uint8List _padMessage(List<int> bytes) {
  final int totalLength = ((bytes.length + 9 + 63) ~/ 64) * 64;
  final Uint8List padded = Uint8List(totalLength);
  padded.setAll(0, bytes);
  padded[bytes.length] = 0x80;

  final int bitLength = bytes.length * 8;
  final int highBits = bitLength ~/ 0x100000000;
  final int lowBits = bitLength & 0xFFFFFFFF;
  for (int index = 0; index < 4; index++) {
    padded[totalLength - 8 + index] = (highBits >> (24 - index * 8)) & 0xFF;
    padded[totalLength - 4 + index] = (lowBits >> (24 - index * 8)) & 0xFF;
  }
  return padded;
}

void _fillWords(List<int> words, Uint8List message, int offset) {
  for (int index = 0; index < 16; index++) {
    final int base = offset + index * 4;
    words[index] =
        (message[base] << 24) |
        (message[base + 1] << 16) |
        (message[base + 2] << 8) |
        message[base + 3];
  }
  for (int index = 16; index < 80; index++) {
    words[index] = _rotateLeft(
      words[index - 3] ^
          words[index - 8] ^
          words[index - 14] ^
          words[index - 16],
      1,
    );
  }
}

void _compress(List<int> state, List<int> words) {
  int a = state[0];
  int b = state[1];
  int c = state[2];
  int d = state[3];
  int e = state[4];

  for (int index = 0; index < 80; index++) {
    final (int f, int k) = _round(index, b, c, d);
    final int temp =
        (_rotateLeft(a, 5) + f + e + k + words[index]) & 0xFFFFFFFF;
    e = d;
    d = c;
    c = _rotateLeft(b, 30);
    b = a;
    a = temp;
  }

  state[0] = (state[0] + a) & 0xFFFFFFFF;
  state[1] = (state[1] + b) & 0xFFFFFFFF;
  state[2] = (state[2] + c) & 0xFFFFFFFF;
  state[3] = (state[3] + d) & 0xFFFFFFFF;
  state[4] = (state[4] + e) & 0xFFFFFFFF;
}

(int, int) _round(int index, int b, int c, int d) {
  if (index < 20) {
    return ((b & c) | ((~b & 0xFFFFFFFF) & d), 0x5A827999);
  }
  if (index < 40) {
    return (b ^ c ^ d, 0x6ED9EBA1);
  }
  if (index < 60) {
    return ((b & c) | (b & d) | (c & d), 0x8F1BBCDC);
  }
  return (b ^ c ^ d, 0xCA62C1D6);
}

int _rotateLeft(int value, int shift) =>
    ((value << shift) | (value >> (32 - shift))) & 0xFFFFFFFF;
