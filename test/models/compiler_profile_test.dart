import 'package:cpp_nuget_pack/models/compiler_profile.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认 Profile 为 v1 且 Release/Debug 四字段全 follow', () {
    const CompilerProfile profile = CompilerProfile();
    expect(profile.version, 1);
    expect(profile.release.runtime, CompilerRuntimeChoice.follow);
    expect(profile.debug.instructionSet, CompilerInstructionSetChoice.follow);
    expect(profile.release.optimization, CompilerOptimizationChoice.follow);
    expect(profile.debug.ipo, CompilerIpoChoice.follow);
  });

  test('toMap 规范化 IPO 布尔值并可往返', () {
    const CompilerProfile profile = CompilerProfile(
      release: CompilerConfigProfile(ipo: CompilerIpoChoice.on),
      debug: CompilerConfigProfile(ipo: CompilerIpoChoice.off),
    );

    final Map<String, Object?> map = profile.toMap();
    expect(map['version'], 1);
    expect((map['release']! as Map<String, Object?>)['ipo'], isTrue);
    expect((map['debug']! as Map<String, Object?>)['ipo'], isFalse);

    final CompilerProfile loaded = CompilerProfile.fromMap(map);
    expect(loaded.release.ipo, CompilerIpoChoice.on);
    expect(loaded.debug.ipo, CompilerIpoChoice.off);
  });

  test('非法字段、未知字段和缺失版本产生可见警告并回退 follow', () {
    final List<String> warnings = <String>[];
    final CompilerProfile profile = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 2,
      'release': <Object?, Object?>{'runtime': 'gnu', 'rawFlags': '-O3'},
    }, warnings: warnings);

    expect(profile.version, 1);
    expect(profile.release.runtime, CompilerRuntimeChoice.follow);
    expect(warnings, isNotEmpty);
    expect(warnings.any((String item) => item.contains('version')), isTrue);
    expect(warnings.any((String item) => item.contains('rawFlags')), isTrue);

    final List<String> missingVersionWarnings = <String>[];
    CompilerProfile.fromMap(<Object?, Object?>{}, warnings: missingVersionWarnings);
    expect(missingVersionWarnings.single, contains('version 缺失'));
  });

  test('旧 buildOptions.runtime 参与有效 Profile 但不覆盖显式 Profile', () {
    final PackModel legacy = PackModel.fromMap(<String, Object?>{
      'name': 'demo',
      'version': '1.0.0',
      'author': 'tester',
      'buildOptions': <String, Object?>{legacyRuntimeOptionName: 'MT'},
    });
    expect(legacy.effectiveCompilerProfile.release.runtime, CompilerRuntimeChoice.mt);
    expect(legacy.effectiveCompilerProfile.debug.runtime, CompilerRuntimeChoice.mt);

    final PackModel explicit = PackModel.fromMap(<String, Object?>{
      'name': 'demo',
      'version': '1.0.0',
      'author': 'tester',
      'buildOptions': <String, Object?>{legacyRuntimeOptionName: 'MT'},
      'compilerProfile': <String, Object?>{'version': 1, 'release': <String, Object?>{'runtime': 'md'}},
    });
    expect(explicit.effectiveCompilerProfile.release.runtime, CompilerRuntimeChoice.md);
  });
}
