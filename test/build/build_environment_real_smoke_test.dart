// ignore_for_file: avoid_print

// 真实环境冒烟测试：证据行有意用 print 直接输出到测试结果。

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:flutter_test/flutter_test.dart';

const String _skipReason = '设置 CNP_REAL_ENV_SMOKE=1 运行';

/// 真实冒烟覆盖的受支持编译器种类：删除 MinGW 后仅余 icx / clang-cl / msvc。
const List<CompilerKind> expectedKinds = <CompilerKind>[
  CompilerKind.icx,
  CompilerKind.clangCl,
  CompilerKind.msvc,
];

void main() {
  test('期望种类覆盖全部编译器种类（新增种类时强制复核真实冒烟）', () {
    expect(expectedKinds, CompilerKind.values);
  });

  test(
    '环境脚本失败时非零退出码经包装传播（&& 短路）',
    () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'cnp-env-fail-smoke-',
      );
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      final File script = File(joinPath(root.path, 'fail.cmd'));
      await script.writeAsString('@echo off\r\nexit /b 7\r\n');

      String? failureMessage;
      try {
        await captureToolchainEnvironment(
          DetectedCompiler(
            kind: CompilerKind.msvc,
            version: 'test',
            executablePath: r'C:\VC\cl.exe',
            environmentScript: script.path,
          ),
          scratchDirectory: root.path,
        );
      } on BuildPreparationException catch (error) {
        failureMessage = error.message;
      }

      print('[evidence] failureMessage=$failureMessage');
      expect(
        failureMessage,
        isNotNull,
        reason:
            '脚本失败时 captureToolchainEnvironment 应抛 BuildPreparationException',
      );
      expect(failureMessage, contains('退出码 7'));
      expect(failureMessage, contains(script.path));
    },
    skip: Platform.environment['CNP_REAL_ENV_SMOKE'] == '1'
        ? false
        : _skipReason,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
