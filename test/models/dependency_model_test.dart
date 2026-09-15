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

  test('system 默认 false 且不写入 map', () {
    const DependencyModel dependency = DependencyModel(
      name: 'libfoo',
      version: '1.0',
    );

    expect(dependency.system, isFalse);
    expect(dependency.toMap().containsKey('system'), isFalse);
  });

  test('system: true 往返保留', () {
    const DependencyModel dependency = DependencyModel(
      name: 'libfoo',
      version: '[1.0.0,)',
      system: true,
    );

    expect(dependency.toMap()['system'], isTrue);
    expect(DependencyModel.fromMap(dependency.toMap()).system, isTrue);
  });

  test('fromMap system 非布尔值容错为 false', () {
    for (final Object? value in <Object?>['true', 1, <Object?>[]]) {
      final DependencyModel dependency = DependencyModel.fromMap(
        <String, Object?>{'name': 'libfoo', 'version': '1.0', 'system': value},
      );

      expect(dependency.system, isFalse);
    }
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
