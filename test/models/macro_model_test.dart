import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap 往返保留字段', () {
    const MacroModel macro = MacroModel(
      value: 'MY_MACRO=1',
      buildModel: BuildModel.debug,
    );

    final Map<String, Object?> map = macro.toMap();
    final MacroModel loaded = MacroModel.fromMap(map);

    expect(map, <String, Object?>{
      'value': 'MY_MACRO=1',
      'buildModel': 'debug',
    });
    expect(loaded.value, 'MY_MACRO=1');
    expect(loaded.buildModel, BuildModel.debug);
  });

  test('buildModel 缺省为 all', () {
    const MacroModel macro = MacroModel(value: 'NDEBUG');

    expect(macro.buildModel, BuildModel.all);
    expect(
      MacroModel.fromMap(<String, Object?>{'value': 'NDEBUG'}).buildModel,
      BuildModel.all,
    );
  });

  test('fromMap 缺少 value 时抛出 FormatException', () {
    expect(
      () => MacroModel.fromMap(<String, Object?>{}),
      throwsFormatException,
    );
  });

  test('fromMap value 为空串时抛出 FormatException', () {
    expect(
      () => MacroModel.fromMap(<String, Object?>{'value': ''}),
      throwsFormatException,
    );
  });

  test('fromMap value 类型错误时抛出 FormatException', () {
    expect(
      () => MacroModel.fromMap(<String, Object?>{'value': 1}),
      throwsFormatException,
    );
  });

  test('fromMap buildModel 非法值抛出 FormatException', () {
    expect(
      () => MacroModel.fromMap(<String, Object?>{
        'value': 'NDEBUG',
        'buildModel': 'fast',
      }),
      throwsFormatException,
    );
  });
}
