import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap 往返保留字段', () {
    const LibraryModel library = LibraryModel(
      name: 'mylib.lib',
      buildModel: BuildModel.debug,
    );

    final Map<String, Object?> map = library.toMap();
    final LibraryModel loaded = LibraryModel.fromMap(map);

    expect(map, <String, Object?>{'name': 'mylib.lib', 'buildModel': 'debug'});
    expect(loaded.name, 'mylib.lib');
    expect(loaded.buildModel, BuildModel.debug);
  });

  test('buildModel 缺省为 all', () {
    const LibraryModel library = LibraryModel(name: 'mylib.lib');

    expect(library.buildModel, BuildModel.all);
  });

  test('fromMap 缺少 name 时抛出 FormatException', () {
    expect(
      () => LibraryModel.fromMap(<String, Object?>{}),
      throwsFormatException,
    );
  });

  test('fromMap name 为空串时抛出 FormatException', () {
    expect(
      () => LibraryModel.fromMap(<String, Object?>{'name': ''}),
      throwsFormatException,
    );
  });

  test('fromMap name 类型错误时抛出 FormatException', () {
    expect(
      () => LibraryModel.fromMap(<String, Object?>{'name': 1}),
      throwsFormatException,
    );
  });

  test('fromMap buildModel 非法值抛出 FormatException', () {
    expect(
      () => LibraryModel.fromMap(<String, Object?>{
        'name': 'mylib.lib',
        'buildModel': 'fast',
      }),
      throwsFormatException,
    );
  });
}
