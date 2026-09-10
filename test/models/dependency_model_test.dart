import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap 往返保留字段', () {
    const DependencyModel dependency = DependencyModel(
      name: 'libfoo',
      version: '[1.0,2.0)',
    );

    final Map<String, Object?> map = dependency.toMap();
    final DependencyModel loaded = DependencyModel.fromMap(map);

    expect(map, <String, Object?>{'name': 'libfoo', 'version': '[1.0,2.0)'});
    expect(loaded.name, 'libfoo');
    expect(loaded.version, '[1.0,2.0)');
  });

  test('fromMap 缺少 name 时抛出 FormatException', () {
    expect(
      () => DependencyModel.fromMap(<String, Object?>{'version': '1.0'}),
      throwsFormatException,
    );
  });

  test('fromMap name 为空串时抛出 FormatException', () {
    expect(
      () => DependencyModel.fromMap(<String, Object?>{
        'name': '',
        'version': '1.0',
      }),
      throwsFormatException,
    );
  });

  test('fromMap 缺少 version 时抛出 FormatException', () {
    expect(
      () => DependencyModel.fromMap(<String, Object?>{'name': 'libfoo'}),
      throwsFormatException,
    );
  });

  test('fromMap version 类型错误时抛出 FormatException', () {
    expect(
      () => DependencyModel.fromMap(<String, Object?>{
        'name': 'libfoo',
        'version': 1.0,
      }),
      throwsFormatException,
    );
  });
}
