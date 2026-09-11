import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/cmd_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap 往返保留字段', () {
    const CmdModel cmd = CmdModel(
      command: 'echo hi',
      type: CmdType.postBuild,
      buildModel: BuildModel.release,
    );

    final Map<String, Object?> map = cmd.toMap();
    final CmdModel loaded = CmdModel.fromMap(map);

    expect(map, <String, Object?>{
      'command': 'echo hi',
      'type': 'postBuild',
      'buildModel': 'release',
    });
    expect(loaded.command, 'echo hi');
    expect(loaded.type, CmdType.postBuild);
    expect(loaded.buildModel, BuildModel.release);
  });

  test('buildModel 缺省为 all', () {
    const CmdModel cmd = CmdModel(command: 'echo hi', type: CmdType.preBuild);

    expect(cmd.buildModel, BuildModel.all);
  });

  test('fromMap 缺少 command 时抛出 FormatException', () {
    expect(
      () => CmdModel.fromMap(<String, Object?>{'type': 'preBuild'}),
      throwsFormatException,
    );
  });

  test('fromMap command 为空串时抛出 FormatException', () {
    expect(
      () => CmdModel.fromMap(<String, Object?>{
        'command': '',
        'type': 'preBuild',
      }),
      throwsFormatException,
    );
  });

  test('fromMap 缺少 type 时抛出 FormatException', () {
    expect(
      () => CmdModel.fromMap(<String, Object?>{'command': 'echo hi'}),
      throwsFormatException,
    );
  });

  test('fromMap type 类型错误时抛出 FormatException', () {
    expect(
      () =>
          CmdModel.fromMap(<String, Object?>{'command': 'echo hi', 'type': 1}),
      throwsFormatException,
    );
  });

  test('fromMap type 非法值抛出 FormatException', () {
    expect(
      () => CmdModel.fromMap(<String, Object?>{
        'command': 'echo hi',
        'type': 'duringBuild',
      }),
      throwsFormatException,
    );
  });

  test('fromMap buildModel 非法值抛出 FormatException', () {
    expect(
      () => CmdModel.fromMap(<String, Object?>{
        'command': 'echo hi',
        'type': 'preBuild',
        'buildModel': 'fast',
      }),
      throwsFormatException,
    );
  });
}
