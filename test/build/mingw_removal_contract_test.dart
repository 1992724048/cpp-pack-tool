import 'package:cpp_nuget_pack/models/compiler_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('删除 MinGW 后只保留 icx、clang-cl、msvc 三种编译器种类', () {
    expect(
      CompilerKind.values,
      <CompilerKind>[
        CompilerKind.icx,
        CompilerKind.clangCl,
        CompilerKind.msvc,
      ],
    );
  });

  test('mingw 稳定标识读回为未知值，R23 clang 也不映射为 clang-cl', () {
    expect(compilerKindFromId('mingw'), isNull);
    expect(compilerKindFromId('MINGW'), isNull);
    expect(compilerKindFromId('clang'), isNull);
    expect(isLegacyCompilerKindId('clang'), isTrue);
  });

  test('三种有效标识与显示名保持契约', () {
    expect(compilerKindId(CompilerKind.icx), 'icx');
    expect(compilerKindId(CompilerKind.clangCl), 'clang-cl');
    expect(compilerKindId(CompilerKind.msvc), 'msvc');
    expect(compilerKindLabel(CompilerKind.icx), 'ICX');
    expect(compilerKindLabel(CompilerKind.clangCl), 'clang-cl');
    expect(compilerKindLabel(CompilerKind.msvc), 'MSVC');
  });
}
