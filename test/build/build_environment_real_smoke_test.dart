// ignore_for_file: avoid_print

// 真实环境冒烟测试：证据行有意用 print 直接输出到测试结果。

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

const String _skipReason =
    '设置 CNP_REAL_ENV_SMOKE=1 运行（真实检测编译器、捕获编译器环境、联网下载 CMake/Ninja 到 tools/）';

void main() {
  test(
    '真实环境冒烟：检测编译器、捕获编译器环境、供给 CMake/Ninja',
    () async {
      final BuildEnvironment env = await prepareBuildEnvironment();
      final DetectedCompiler compiler = env.compiler;

      print('[evidence] Directory.current=${Directory.current.path}');
      print('[evidence] compiler.kind=${compilerKindId(compiler.kind)}');
      print('[evidence] compiler.version=${compiler.version}');
      print('[evidence] compiler.executablePath=${compiler.executablePath}');
      print(
        '[evidence] compiler.environmentScript=${compiler.environmentScript}',
      );
      print('[evidence] CNP_C_COMPILER=${env.environment['CNP_C_COMPILER']}');
      print(
        '[evidence] CNP_COMPILER_KIND=${env.environment['CNP_COMPILER_KIND']}',
      );
      print('[evidence] cmakePath=${env.cmakePath}');
      print('[evidence] ninjaPath=${env.ninjaPath}');
      print('[evidence] CNP_TOOLS_DIR=${env.environment['CNP_TOOLS_DIR']}');
      print('[evidence] toolsDir=${env.toolsDir}');
      print('[evidence] hasINCLUDE=${env.environment.containsKey('INCLUDE')}');
      print('[evidence] INCLUDE=${env.environment['INCLUDE'] ?? ''}');
      print('[evidence] cmakeMarker=${_markerState(env.toolsDir, 'cmake')}');
      print('[evidence] ninjaMarker=${_markerState(env.toolsDir, 'ninja')}');

      expect(env.environment['CNP_C_COMPILER'], isNotEmpty);
      expect(env.environment['CNP_COMPILER_KIND'], isNotEmpty);
      expect(env.cmakePath, isNotEmpty);
      expect(env.ninjaPath, isNotEmpty);
      expect(
        File(compiler.executablePath).existsSync(),
        isTrue,
        reason: '检测到的编译器可执行文件应真实存在',
      );

      final String? environmentScript = compiler.environmentScript;
      if (environmentScript != null && environmentScript.isNotEmpty) {
        expect(
          env.environment['INCLUDE'] ?? '',
          isNotEmpty,
          reason: '编译器环境脚本非空时应捕获到非空 INCLUDE（证明捕获生效）',
        );
      }
    },
    skip: Platform.environment['CNP_REAL_ENV_SMOKE'] == '1'
        ? false
        : _skipReason,
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    '真实环境冒烟：环境脚本失败时非零退出码经包装传播（&& 短路）',
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

String _markerState(String toolsDir, String toolName) {
  final File marker = File(joinPath(toolsDir, '$toolName/.source'));
  if (!marker.existsSync()) {
    return 'missing';
  }
  try {
    return 'present (${marker.readAsStringSync().trim()})';
  } on FileSystemException {
    return 'present (unreadable)';
  }
}
