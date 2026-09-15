// ignore_for_file: avoid_print

// 真实环境冒烟（Q7 复现）：重放设置页/构建共用的受控 TMP 检测链路，输出本机实际
// 检测清单与关键环境（TMP、oneAPI 根、探测到的可执行文件），供根因定位与回归核对。
//
// Q7 回归防护：受控 TMP 指向「本次新建、owner 为当前用户」的目录，检测清单不得
// 比默认环境少——历史缺陷中受控 TMP 指向他人所有的既有目录，ICX 在自建临时目录内
// 被 ACCESS DENIED（`error #10026`）、整体漏检。

import 'dart:io';

import 'package:cpp_nuget_pack/build/build_environment.dart';
import 'package:cpp_nuget_pack/build/toolchain.dart';
import 'package:flutter_test/flutter_test.dart';

const String _skipReason =
    '设置 CNP_REAL_ENV_SMOKE=1 运行（真实探测本机编译器，重放设置页/构建共用的检测链路）';

void main() {
  test(
    '真实环境冒烟：受控 TMP 检测清单与条目有效性',
    () async {
      final Map<String, String> baseEnvironment = Map<String, String>.of(
        Platform.environment,
      );
      final Map<String, String> controlled = await withControlledTempEnvironment(
        baseEnvironment,
      );
      print('[evidence] controlled.TMP=${controlled['TMP']}');
      print('[evidence] controlled.TEMP=${controlled['TEMP']}');
      print(
        '[evidence] ProgramFiles(x86)=${Platform.environment['ProgramFiles(x86)']}',
      );
      print('[evidence] ONEAPI_ROOT=${Platform.environment['ONEAPI_ROOT']}');
      print('[evidence] Directory.current=${Directory.current.path}');

      final List<DetectedCompiler> baseline = await detectCompilers(
        environment: baseEnvironment,
      );
      final List<DetectedCompiler> compilers =
          await detectCompilersWithControlledTemp();

      for (final DetectedCompiler compiler in compilers) {
        print(
          '[evidence] detected kind=${compilerKindId(compiler.kind)} '
          'version=${compiler.version} executable=${compiler.executablePath} '
          'script=${compiler.environmentScript} '
          'extraPath=${compiler.extraPathEntries.join(';')}',
        );
      }
      print(
        '[evidence] detectedKinds='
        '${compilers.map((DetectedCompiler c) => compilerKindId(c.kind)).join(',')}',
      );
      print(
        '[evidence] baselineKinds='
        '${baseline.map((DetectedCompiler c) => compilerKindId(c.kind)).join(',')}',
      );

      expect(
        compilers,
        isNotEmpty,
        reason: '受控 TMP 检测链路应至少检出本机 MSVC；空列表说明检测链路整体失效',
      );
      for (final DetectedCompiler compiler in compilers) {
        expect(
          File(compiler.executablePath).existsSync(),
          isTrue,
          reason: '检测到的编译器可执行文件应真实存在：${compiler.executablePath}',
        );
      }

      final bool baselineHasIcx = baseline.any(
        (DetectedCompiler compiler) => compiler.kind == CompilerKind.icx,
      );
      if (baselineHasIcx) {
        expect(
          compilers.map((DetectedCompiler c) => c.kind),
          contains(CompilerKind.icx),
          reason:
              'Q7 回归：默认环境可检出 ICX 时受控 TMP 不得漏检（受控目录须为本次新建）',
        );
      }
    },
    skip: Platform.environment['CNP_REAL_ENV_SMOKE'] == '1'
        ? false
        : _skipReason,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
