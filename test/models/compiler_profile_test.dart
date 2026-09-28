import 'package:cpp_nuget_pack/models/compiler_profile.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认 Profile 为 v1 且 Release/Debug 三字段全 follow', () {
    const CompilerProfile profile = CompilerProfile();
    expect(profile.version, 1);
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
      'release': <Object?, Object?>{'instructionSet': 'gnu', 'rawFlags': '-O3'},
    }, warnings: warnings);

    expect(profile.version, 1);
    expect(
      profile.release.instructionSet,
      CompilerInstructionSetChoice.follow,
    );
    expect(warnings, isNotEmpty);
    expect(warnings.any((String item) => item.contains('version')), isTrue);
    expect(warnings.any((String item) => item.contains('rawFlags')), isTrue);

    final List<String> missingVersionWarnings = <String>[];
    CompilerProfile.fromMap(<Object?, Object?>{}, warnings: missingVersionWarnings);
    expect(missingVersionWarnings.single, contains('version 缺失'));
  });

  test('版本不受支持时 Release/Debug 回退全 follow 并保留版本警告', () {
    final List<String> warnings = <String>[];
    final CompilerProfile profile = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 2,
      'release': <Object?, Object?>{'instructionSet': 'avx2'},
    }, warnings: warnings);

    expect(profile.version, 1);
    expect(
      profile.release.instructionSet,
      CompilerInstructionSetChoice.follow,
    );
    expect(profile.debug.instructionSet, CompilerInstructionSetChoice.follow);
    expect(
      warnings,
      <String>['compilerProfile.version=2 不受支持，已按 v1 全 follow 处理'],
    );
  });

  test('三字段大小写与空白容错为对应枚举且无警告', () {
    final List<String> warnings = <String>[];
    final CompilerProfile profile = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 1,
      'release': <Object?, Object?>{
        'instructionSet': 'AVX2',
        'optimization': ' MAXIMUM ',
        'ipo': 'On',
      },
    }, warnings: warnings);

    expect(profile.release.instructionSet, CompilerInstructionSetChoice.avx2);
    expect(profile.release.optimization, CompilerOptimizationChoice.maximum);
    expect(profile.release.ipo, CompilerIpoChoice.on);
    expect(warnings, isEmpty);
  });

  test('instructionSet/optimization/ipo 非法值回退 follow 并各自产生警告', () {
    final List<String> warnings = <String>[];
    final CompilerProfile profile = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 1,
      'release': <Object?, Object?>{
        'instructionSet': 'sse5',
        'optimization': 'insane',
        'ipo': 'maybe',
      },
    }, warnings: warnings);

    expect(profile.release.instructionSet, CompilerInstructionSetChoice.follow);
    expect(profile.release.optimization, CompilerOptimizationChoice.follow);
    expect(profile.release.ipo, CompilerIpoChoice.follow);
    expect(warnings, hasLength(3));
    expect(
      warnings.any((String item) => item.contains('instructionSet')),
      isTrue,
    );
    expect(warnings.any((String item) => item.contains('optimization')), isTrue);
    expect(warnings.any((String item) => item.contains('ipo')), isTrue);
  });

  test('数值字段类型非法时回退 follow 并产生警告', () {
    final List<String> warnings = <String>[];
    final CompilerProfile profile = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 1,
      'release': <Object?, Object?>{'ipo': 7},
    }, warnings: warnings);

    expect(profile.release.ipo, CompilerIpoChoice.follow);
    expect(warnings, hasLength(1));
  });

  test('ipo 接受布尔与字符串双形态', () {
    final CompilerProfile bools = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 1,
      'release': <Object?, Object?>{'ipo': true},
      'debug': <Object?, Object?>{'ipo': false},
    });
    expect(bools.release.ipo, CompilerIpoChoice.on);
    expect(bools.debug.ipo, CompilerIpoChoice.off);

    final List<String> warnings = <String>[];
    final CompilerProfile strings = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 1,
      'release': <Object?, Object?>{'ipo': 'on'},
      'debug': <Object?, Object?>{'ipo': 'off'},
    }, warnings: warnings);
    expect(strings.release.ipo, CompilerIpoChoice.on);
    expect(strings.debug.ipo, CompilerIpoChoice.off);
    expect(warnings, isEmpty);
  });

  test('release/debug 非映射时回退全 follow 并产生类型警告', () {
    final List<String> warnings = <String>[];
    final CompilerProfile profile = CompilerProfile.fromMap(<Object?, Object?>{
      'version': 1,
      'release': 5,
      'debug': 'x',
    }, warnings: warnings);

    for (final CompilerConfigProfile config in <CompilerConfigProfile>[
      profile.release,
      profile.debug,
    ]) {
      expect(config.instructionSet, CompilerInstructionSetChoice.follow);
      expect(config.optimization, CompilerOptimizationChoice.follow);
      expect(config.ipo, CompilerIpoChoice.follow);
    }
    expect(warnings, hasLength(2));
    expect(
      warnings.any((String item) => item.contains('compilerProfile.release 类型错误')),
      isTrue,
    );
    expect(
      warnings.any((String item) => item.contains('compilerProfile.debug 类型错误')),
      isTrue,
    );
  });

  test('老包 buildOptions.runtime 不再影响有效 Profile，显式 Profile 仍优先', () {
    final PackModel legacy = PackModel.fromMap(<String, Object?>{
      'name': 'demo',
      'version': '1.0.0',
      'author': 'tester',
      'buildOptions': <String, Object?>{'runtime': 'MT'},
    });
    expect(
      legacy.effectiveCompilerProfile.release.instructionSet,
      CompilerInstructionSetChoice.follow,
    );

    final PackModel explicit = PackModel.fromMap(<String, Object?>{
      'name': 'demo',
      'version': '1.0.0',
      'author': 'tester',
      'buildOptions': <String, Object?>{'runtime': 'MT'},
      'compilerProfile': <String, Object?>{
        'version': 1,
        'release': <String, Object?>{'instructionSet': 'avx2'},
      },
    });
    expect(
      explicit.effectiveCompilerProfile.release.instructionSet,
      CompilerInstructionSetChoice.avx2,
    );
  });
}
