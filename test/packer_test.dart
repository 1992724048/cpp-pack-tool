import 'package:flutter_test/flutter_test.dart';

import 'package:cpp_nuget_pack/services/packer.dart';

void main() {
  group('buildPackArgs', () {
    test('构造 nuget pack 命令行参数', () {
      expect(buildPackArgs(nuspecPath: r'a\b.nuspec', outputDir: r'out'), [
        'pack',
        r'a\b.nuspec',
        '-OutputDirectory',
        r'out',
        '-NonInteractive',
      ]);
    });
  });

  group('resolveNuGetExe', () {
    NuGetProbe buildProbe({
      required bool Function(String path) fileExists,
      String? Function()? whichOnPath,
      String? Function(List<String> roots)? searchNugetIn,
      List<String>? roots,
    }) {
      return NuGetProbe(
        fileExists: fileExists,
        whichOnPath: whichOnPath ?? () => null,
        searchNugetIn: searchNugetIn ?? (_) => null,
        typicalRoots: roots ?? [],
      );
    }

    test('显式路径（存在者）优先', () {
      final probe = buildProbe(
        fileExists: (path) => path == r'C:\tools\nuget.exe',
      );
      final result = resolveNuGetExe(
        explicitCandidates: [r'C:\tools\nuget.exe', r'C:\other.exe'],
        probe: probe,
      );
      expect(result, endsWith(r'\nuget.exe'));
    });

    test('PATH 次之', () {
      final probe = buildProbe(
        fileExists: (_) => false,
        whichOnPath: () => r'C:\path\nuget.exe',
      );
      expect(
        resolveNuGetExe(explicitCandidates: [r'C:\missing.exe'], probe: probe),
        r'C:\path\nuget.exe',
      );
    });

    test('常见安装位置最后', () {
      final probe = buildProbe(
        fileExists: (_) => false,
        searchNugetIn: (roots) => r'C:\winget\NuGet\nuget.exe',
        roots: [r'C:\winget'],
      );
      expect(
        resolveNuGetExe(explicitCandidates: const [], probe: probe),
        r'C:\winget\NuGet\nuget.exe',
      );
    });

    test('均未找到时返回 null', () {
      final probe = buildProbe(fileExists: (_) => false, roots: const []);
      expect(
        resolveNuGetExe(explicitCandidates: const [], probe: probe),
        isNull,
      );
    });

    test('空候选被跳过，继续尝试后续候选', () {
      final probe = buildProbe(
        fileExists: (path) => path == r'C:\ok\nuget.exe',
      );
      final result = resolveNuGetExe(
        explicitCandidates: ['  ', r'C:\ok\nuget.exe'],
        probe: probe,
      );
      expect(result, endsWith(r'\nuget.exe'));
    });
  });

  group('parseNupkgOutputPath', () {
    test('从成功输出解析 .nupkg 完整路径', () {
      const stdout =
          "Attempting to build package from 'V8.Native.nuspec'.\r\n"
          "Successfully created package 'C:\\out\\V8.Native.1.0.0.nupkg'.";
      expect(parseNupkgOutputPath(stdout), r'C:\out\V8.Native.1.0.0.nupkg');
    });

    test('无法解析时返回 null', () {
      expect(parseNupkgOutputPath('nothing here'), isNull);
    });
  });
}
