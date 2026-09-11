import 'package:cpp_nuget_pack/script_editor/msbuild_macros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MSBuild 宏白名单', () {
    test('与 spec 附录 A 一致（11 项，顺序稳定）', () {
      expect(msbuildMacroKeys, <String>[
        'Configuration',
        'Platform',
        'OutDir',
        'IntDir',
        'TargetDir',
        'TargetPath',
        'TargetName',
        'TargetExt',
        'ProjectDir',
        'SolutionDir',
        'MSBuildThisFileDirectory',
      ]);
    });

    test('宏键唯一且非空', () {
      expect(msbuildMacroKeys, hasLength(11));
      expect(msbuildMacroKeys.toSet(), hasLength(11));
      expect(msbuildMacroKeys.every((String key) => key.isNotEmpty), isTrue);
    });

    test('macroEnvName 映射为 CNP_ 前缀环境变量', () {
      for (final String key in msbuildMacroKeys) {
        expect(macroEnvName(key), 'CNP_$key');
      }
      expect(macroEnvName('OutDir'), 'CNP_OutDir');
      expect(
        macroEnvName('MSBuildThisFileDirectory'),
        'CNP_MSBuildThisFileDirectory',
      );
    });
  });
}
