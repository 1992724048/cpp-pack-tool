import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inferBuildLabel', () {
    test('release 目录段映射为 Release（大小写不敏感）', () {
      expect(inferBuildLabel('build/release/mylib.lib'), 'Release');
      expect(inferBuildLabel('Release/mylib.lib'), 'Release');
      expect(inferBuildLabel(r'build\RELEASE\mylib.lib'), 'Release');
    });

    test('debug 目录段映射为 Debug（大小写不敏感）', () {
      expect(inferBuildLabel('out/debug/mylib.pdb'), 'Debug');
      expect(inferBuildLabel('Debug/tool.exe'), 'Debug');
      expect(inferBuildLabel(r'out\DEBUG\tool.exe'), 'Debug');
    });

    test('无匹配段返回 null', () {
      expect(inferBuildLabel('lib/mylib.lib'), isNull);
      expect(inferBuildLabel('mylib.lib'), isNull);
      expect(inferBuildLabel('release-build/mylib.lib'), isNull);
      expect(inferBuildLabel('debugging/mylib.lib'), isNull);
      expect(inferBuildLabel(''), isNull);
    });

    test('release 与 debug 同时出现时取更靠后的匹配段', () {
      expect(inferBuildLabel('release/debug/mylib.lib'), 'Debug');
      expect(inferBuildLabel('debug/release/mylib.lib'), 'Release');
      expect(inferBuildLabel(r'release\sub/debug/mylib.lib'), 'Debug');
    });

    test('兼容正反斜杠与重复分隔符', () {
      expect(inferBuildLabel('a//release//mylib.lib'), 'Release');
      expect(inferBuildLabel(r'a\\debug\\mylib.lib'), 'Debug');
    });
  });

  group('buildModelLabel', () {
    test('按构建配置映射标签', () {
      expect(buildModelLabel(BuildModel.all), 'ALL');
      expect(buildModelLabel(BuildModel.release), 'Release');
      expect(buildModelLabel(BuildModel.debug), 'Debug');
    });
  });
}
