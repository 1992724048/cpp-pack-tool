import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap 往返保留字段', () {
    const LibDirModel libDir = LibDirModel(
      path: r'third_party\lib',
      buildModel: BuildModel.release,
    );

    final Map<String, Object?> map = libDir.toMap();
    final LibDirModel loaded = LibDirModel.fromMap(map);

    expect(map, <String, Object?>{
      'path': r'third_party\lib',
      'buildModel': 'release',
    });
    expect(loaded.path, r'third_party\lib');
    expect(loaded.buildModel, BuildModel.release);
  });

  test('buildModel 缺省为 all', () {
    const LibDirModel libDir = LibDirModel(path: 'lib');

    expect(libDir.buildModel, BuildModel.all);
  });

  test('fromMap 缺少 path 时抛出 FormatException', () {
    expect(
      () => LibDirModel.fromMap(<String, Object?>{}),
      throwsFormatException,
    );
  });

  test('fromMap path 为空串时抛出 FormatException', () {
    expect(
      () => LibDirModel.fromMap(<String, Object?>{'path': ''}),
      throwsFormatException,
    );
  });

  test('fromMap path 类型错误时抛出 FormatException', () {
    expect(
      () => LibDirModel.fromMap(<String, Object?>{'path': 1}),
      throwsFormatException,
    );
  });

  test('fromMap buildModel 非法值抛出 FormatException', () {
    expect(
      () => LibDirModel.fromMap(<String, Object?>{
        'path': 'lib',
        'buildModel': 'fast',
      }),
      throwsFormatException,
    );
  });
}
