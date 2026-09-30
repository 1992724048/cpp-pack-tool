import 'package:cpp_nuget_pack/pack/model/build_model.dart';
import 'package:cpp_nuget_pack/pack/build_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildModelLabel', () {
    test('按构建配置映射标签', () {
      expect(buildModelLabel(BuildModel.all), 'ALL');
      expect(buildModelLabel(BuildModel.release), 'Release');
      expect(buildModelLabel(BuildModel.debug), 'Debug');
    });
  });
}
