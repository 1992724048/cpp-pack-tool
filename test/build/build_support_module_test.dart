// ignore_for_file: avoid_print

// 真实执行 cnp_build_support.py 的冒烟测试（仅 Windows 且本机 Python 可用）。
//
// 模块内容经 rootBundle（回退直接读源文件）载入后写入临时目录，由真实 Python
// 进程驱动各分类函数；断言以进程输出与输出树文件为准，不 import 业务代码。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本机可用的 Python 启动命令（`['python']` 或 `['py', '-3']`）；null 表示不可用。
List<String>? _pythonCommand;

/// skip 原因（非 Windows 或本机无 Python）；null 表示可执行。
Object? _skipReason;

/// 模块源码缓存与载入方式（true = rootBundle，false = 源文件回退）。
String? _cachedModuleSource;
bool _loadedFromBundle = false;

List<String>? _probePython() {
  for (final List<String> candidate in <List<String>>[
    <String>['python'],
    <String>['py', '-3'],
  ]) {
    try {
      final ProcessResult result = Process.runSync(candidate.first, <String>[
        ...candidate.sublist(1),
        '--version',
      ]);
      if (result.exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      // 当前候选不可用，继续探测下一个。
    }
  }
  return null;
}

Future<String> _loadModuleSource() async {
  final String? cached = _cachedModuleSource;
  if (cached != null) {
    return cached;
  }
  try {
    final String source = await rootBundle.loadString(
      'assets/build/cnp_build_support.py',
    );
    _loadedFromBundle = true;
    _cachedModuleSource = source;
    return source;
  } catch (_) {
    final String source = File('assets/build/cnp_build_support.py')
        .readAsStringSync();
    _loadedFromBundle = false;
    _cachedModuleSource = source;
    return source;
  }
}

ProcessResult _runPython(List<String> arguments, {String? workingDirectory}) {
  final List<String> command = _pythonCommand!;
  return Process.runSync(command.first, <String>[
    ...command.sublist(1),
    ...arguments,
  ], workingDirectory: workingDirectory);
}

Directory _createTempDir(String prefix) {
  final Directory directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

String _join(String base, String child) =>
    '$base${Platform.pathSeparator}$child';

String _installModule(Directory directory, String source) {
  final File module = File(_join(directory.path, 'cnp_build_support.py'));
  module.writeAsStringSync(source, flush: true);
  return module.path;
}

File _writeDriver(Directory directory, String source) {
  final File driver = File(_join(directory.path, 'driver.py'));
  driver.writeAsStringSync(source, flush: true);
  return driver;
}

ProcessResult _runDriver(File driver, String label) {
  final ProcessResult result = _runPython(<String>[
    driver.uri.pathSegments.last,
  ], workingDirectory: driver.parent.path);
  print('[evidence] $label exitCode=${result.exitCode}');
  print('[evidence] $label stdout=${result.stdout.toString().trim()}');
  return result;
}

String _readText(String path) => File(path).readAsStringSync();

/// 输出树中的相对文件路径列表（`/` 分隔、排序）；目录不存在时为空。
List<String> _relativeFiles(String root) {
  final Directory directory = Directory(root);
  if (!directory.existsSync()) {
    return <String>[];
  }
  final List<String> files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .map(
        (File file) => file.path
            .substring(root.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
      )
      .toList();
  files.sort();
  return files;
}

/// cmake_configure 命令装配、优化参数注入与缺 CNP_CMAKE 报错：monkeypatch
/// subprocess.run 捕获命令，不真实执行 cmake。
const String _cmakeDriver = r'''
import io
import os

import cnp_build_support

os.environ.pop('CNP_CMAKE', None)
try:
    cnp_build_support.cmake_configure('src', 'build')
except RuntimeError:
    print('missing=RuntimeError')
except Exception as error:
    print('missing=unexpected:' + type(error).__name__)

os.environ['CNP_CMAKE'] = ''
try:
    cnp_build_support.cmake_configure('src', 'build')
except RuntimeError:
    print('empty=RuntimeError')
except Exception as error:
    print('empty=unexpected:' + type(error).__name__)

captured = []
current = {'output': '', 'returncode': 0}


class FakeProcess(object):
    def __init__(self, output, returncode):
        self.stdout = io.StringIO(output)
        self._returncode = returncode

    def wait(self):
        return self._returncode


def fake_popen(command, **kwargs):
    captured.append(list(command))
    return FakeProcess(current['output'], current['returncode'])


def option(command, name):
    prefix = '-D' + name + '='
    for item in command:
        if item.startswith(prefix):
            return item[len(prefix):]
    return 'none'


original_popen = cnp_build_support.subprocess.Popen
original_which = cnp_build_support.shutil.which
cnp_build_support.subprocess.Popen = fake_popen
cnp_build_support.shutil.which = lambda name: (
    'C:/llvm/lld-link.exe' if name == 'lld-link' else None)
try:
    os.environ['CNP_CMAKE'] = 'C:/tools/cmake/bin/cmake.exe'
    os.environ['CNP_NINJA'] = 'C:/tools/ninja/ninja.exe'
    os.environ['CNP_C_COMPILER'] = 'C:/compiler/icx-cl.exe'
    os.environ['CNP_CXX_COMPILER'] = 'C:/compiler/icx-cl.exe'
    os.environ['CNP_COMPILER_KIND'] = 'icx'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release', ['-DEXTRA=1'])
    icx_release = list(captured[-1])

    os.environ['CNP_COMPILER_KIND'] = 'gcc'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    inferred_release = list(captured[-1])
    os.environ['CNP_COMPILER_KIND'] = 'icx'

    os.environ['CNP_COMPILER_KIND'] = 'clang-cl'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    clang_release = list(captured[-1])

    os.environ['CNP_COMPILER_KIND'] = 'msvc'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    msvc_release = list(captured[-1])
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Debug')
    msvc_debug = list(captured[-1])

    # MinGW：GNU 风格旗标、不写 MSVC 运行库变量、mt 链接期静态运行库、
    # RC 编译器注入与保守 IPO（enable_ipo=True 可强制）。
    os.environ['CNP_COMPILER_KIND'] = 'mingw'
    os.environ['CNP_C_COMPILER'] = 'C:/msys64/ucrt64/bin/gcc.exe'
    os.environ['CNP_CXX_COMPILER'] = 'C:/msys64/ucrt64/bin/g++.exe'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    mingw_release = list(captured[-1])
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Debug')
    mingw_debug = list(captured[-1])
    os.environ['CNP_RUNTIME_LIBRARY'] = 'MT'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    mingw_static = list(captured[-1])
    os.environ.pop('CNP_RUNTIME_LIBRARY', None)
    os.environ['CNP_RC_COMPILER'] = 'C:/msys64/ucrt64/bin/windres.exe'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    mingw_rc = list(captured[-1])
    os.environ.pop('CNP_RC_COMPILER', None)
    cnp_build_support.cmake_configure(
        'C:/src', 'C:/build', 'Release', [], enable_ipo=True)
    mingw_forced_ipo = list(captured[-1])

    # 路径推断：CNP_COMPILER_KIND 非法时 gcc/g++ → mingw。
    os.environ['CNP_COMPILER_KIND'] = 'unknown'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    gcc_inferred = list(captured[-1])

    os.environ['CNP_COMPILER_KIND'] = 'msvc'
    os.environ['CNP_C_COMPILER'] = 'C:/compiler/icx-cl.exe'
    os.environ['CNP_CXX_COMPILER'] = 'C:/compiler/icx-cl.exe'
    os.environ['CNP_RUNTIME_LIBRARY'] = 'MT'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    static_runtime = list(captured[-1])
    os.environ['CNP_RUNTIME_LIBRARY'] = 'gnu'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    invalid_runtime = list(captured[-1])
    os.environ.pop('CNP_RUNTIME_LIBRARY', None)

    os.environ.pop('CNP_COMPILER_KIND', None)
    os.environ.pop('CNP_C_COMPILER', None)
    os.environ.pop('CNP_CXX_COMPILER', None)
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    unknown_release = list(captured[-1])

    os.environ.pop('CNP_NINJA', None)
    cnp_build_support.cmake_configure('C:/src', 'C:/build')
    minimal = list(captured[-1])

    os.environ['CNP_COMPILER_KIND'] = 'msvc'
    cnp_build_support.cmake_configure(
        'C:/src', 'C:/build', 'Release', [], enable_ipo=False)
    disabled_call = list(captured[-1])

    os.environ['CNP_NO_IPO'] = '1'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    disabled_env = list(captured[-1])
    os.environ.pop('CNP_NO_IPO', None)

    cnp_build_support.shutil.which = lambda name: None
    os.environ['CNP_COMPILER_KIND'] = 'clang-cl'
    cnp_build_support.cmake_configure('C:/src', 'C:/build', 'Release')
    clang_no_lld = list(captured[-1])

    os.environ['CNP_COMPILER_KIND'] = 'msvc'
    cnp_build_support.cmake_configure(
        'C:/src', 'C:/build', 'Release',
        ['-DCMAKE_CXX_FLAGS_RELEASE=/O1',
         '-DCMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE=OFF'])
    preset_release = list(captured[-1])
finally:
    cnp_build_support.subprocess.Popen = original_popen
    cnp_build_support.shutil.which = original_which

print('icx_avx2_c=%s' % option(icx_release, 'CMAKE_C_FLAGS'))
print('icx_avx2_cxx=%s' % option(icx_release, 'CMAKE_CXX_FLAGS'))
print('icx_opt=%s' % option(icx_release, 'CMAKE_C_FLAGS_RELEASE'))
print('icx_opt_cxx=%s' % option(icx_release, 'CMAKE_CXX_FLAGS_RELEASE'))
print('icx_ipo=%s' % option(icx_release, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('inferred_avx2=%s' % option(inferred_release, 'CMAKE_C_FLAGS'))
print('inferred_opt=%s' % option(inferred_release, 'CMAKE_C_FLAGS_RELEASE'))
print('clang_avx2_c=%s' % option(clang_release, 'CMAKE_C_FLAGS'))
print('clang_opt_cxx=%s' % option(clang_release, 'CMAKE_CXX_FLAGS_RELEASE'))
print('clang_ipo=%s' % option(clang_release, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('clang_cl_ld=%s' % option(clang_release, 'CMAKE_EXE_LINKER_FLAGS'))
print('msvc_opt=%s' % option(msvc_release, 'CMAKE_C_FLAGS_RELEASE'))
print('msvc_opt_cxx=%s' % option(msvc_release, 'CMAKE_CXX_FLAGS_RELEASE'))
print('msvc_ipo=%s' % option(msvc_release, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('debug_avx2=%s' % option(msvc_debug, 'CMAKE_C_FLAGS'))
print('debug_opt=%s' % option(msvc_debug, 'CMAKE_C_FLAGS_RELEASE'))
print('debug_ipo=%s' % option(msvc_debug, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('runtime_mt=%s' % option(static_runtime, 'CMAKE_MSVC_RUNTIME_LIBRARY'))
print('runtime_invalid=%s' % option(invalid_runtime, 'CMAKE_MSVC_RUNTIME_LIBRARY'))
print('unknown_avx2=%s' % option(unknown_release, 'CMAKE_C_FLAGS'))
print('unknown_opt=%s' % option(unknown_release, 'CMAKE_C_FLAGS_RELEASE'))
print('disabled_call_ipo=%s' % option(
    disabled_call, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('disabled_env_ipo=%s' % option(
    disabled_env, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('clang_no_lld_ipo=%s' % option(
    clang_no_lld, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('preset_opt_cxx=%s' % option(preset_release, 'CMAKE_CXX_FLAGS_RELEASE'))
print('preset_opt_c=%s' % option(preset_release, 'CMAKE_C_FLAGS_RELEASE'))
print('preset_ipo=%s' % option(
    preset_release, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('mingw_avx2=%s' % option(mingw_release, 'CMAKE_C_FLAGS'))
print('mingw_opt=%s' % option(mingw_release, 'CMAKE_C_FLAGS_RELEASE'))
print('mingw_opt_cxx=%s' % option(mingw_release, 'CMAKE_CXX_FLAGS_RELEASE'))
print('mingw_msvc_runtime=%s' % option(
    mingw_release, 'CMAKE_MSVC_RUNTIME_LIBRARY'))
print('mingw_ipo=%s' % option(
    mingw_release, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('mingw_cxx=%s' % [item for item in mingw_release
                        if item.startswith('-DCMAKE_CXX_COMPILER=')][0])
print('mingw_debug_opt=%s' % option(mingw_debug, 'CMAKE_C_FLAGS_RELEASE'))
print('mingw_md_shared=%s' % option(mingw_rc, 'CMAKE_SHARED_LINKER_FLAGS'))
print('mingw_static_shared=%s' % option(
    mingw_static, 'CMAKE_SHARED_LINKER_FLAGS'))
print('mingw_static_exe=%s' % option(mingw_static, 'CMAKE_EXE_LINKER_FLAGS'))
print('mingw_static_module=%s' % option(
    mingw_static, 'CMAKE_MODULE_LINKER_FLAGS'))
print('mingw_rc=%s' % option(mingw_rc, 'CMAKE_RC_COMPILER'))
print('mingw_forced_ipo=%s' % option(
    mingw_forced_ipo, 'CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE'))
print('gcc_inferred_avx2=%s' % option(gcc_inferred, 'CMAKE_C_FLAGS'))
print('gcc_inferred_opt=%s' % option(gcc_inferred, 'CMAKE_C_FLAGS_RELEASE'))

command = captured[0]
print('generator=%s' % command[command.index('-G') + 1])
print('build_type=%s' % [item for item in command if item.startswith('-DCMAKE_BUILD_TYPE=')][0])
print('runtime=%s' % [item for item in command if item.startswith('-DCMAKE_MSVC_RUNTIME_LIBRARY=')][0])
print('make_program=%s' % [item for item in command if item.startswith('-DCMAKE_MAKE_PROGRAM=')][0])
print('c_compiler=%s' % [item for item in command if item.startswith('-DCMAKE_C_COMPILER=')][0])
print('extra=%s' % command[-1])
print('minimal_make_program=%s' % any(
    item.startswith('-DCMAKE_MAKE_PROGRAM=') for item in minimal))


current['output'] = 'boom-line-1\nboom-line-2\nboom-tail\n'
current['returncode'] = 3
cnp_build_support.subprocess.Popen = fake_popen
try:
    cnp_build_support.cmake_configure('C:/src', 'C:/build')
except RuntimeError as error:
    print('nonzero=RuntimeError')
    print('nonzero_has_tail=%s' % ('boom-tail' in str(error)))
    print('nonzero_has_code=%s' % ('退出码 3' in str(error)))
    print('nonzero_has_lines=%s' % ('boom-line-1' in str(error)))
except Exception as error:
    print('nonzero=unexpected:' + type(error).__name__)
finally:
    current['output'] = ''
    current['returncode'] = 0
    cnp_build_support.subprocess.Popen = original_popen


def failing_start(command, **kwargs):
    raise OSError('simulated spawn failure')


cnp_build_support.subprocess.Popen = failing_start
try:
    cnp_build_support.cmake_configure('C:/src', 'C:/build')
except RuntimeError as error:
    print('spawn=RuntimeError')
except Exception as error:
    print('spawn=unexpected:' + type(error).__name__)
finally:
    cnp_build_support.subprocess.Popen = original_popen
''';

/// cmake_build：缺省并行到 CPU 逻辑核数、显式 jobs 与 0 禁用；`_run_process`
/// 逐行实时打印子进程输出并返回 CompletedProcess 形状结果。
const String _cmakeBuildDriver = r'''
import builtins
import io
import os

import cnp_build_support

os.environ['CNP_CMAKE'] = 'C:/tools/cmake/bin/cmake.exe'
captured = []


class FakeProcess(object):
    def __init__(self, output, returncode):
        self.stdout = io.StringIO(output)
        self._returncode = returncode

    def wait(self):
        return self._returncode


def fake_popen(command, **kwargs):
    captured.append(list(command))
    return FakeProcess('stream-a\nstream-b\n', 0)


captured_prints = []
original_print = builtins.print


def capturing_print(*args, **kwargs):
    captured_prints.append(' '.join(str(arg) for arg in args))


original_popen = cnp_build_support.subprocess.Popen
cnp_build_support.subprocess.Popen = fake_popen
try:
    default_result = cnp_build_support.cmake_build('C:/build', 'Release')
    default_command = list(captured[-1])
    cnp_build_support.cmake_build('C:/build', 'Release', jobs=2)
    explicit_command = list(captured[-1])
    cnp_build_support.cmake_build('C:/build', 'Release', jobs=0)
    zero_command = list(captured[-1])
finally:
    cnp_build_support.subprocess.Popen = original_popen

cnp_build_support.subprocess.Popen = fake_popen
builtins.print = capturing_print
try:
    cnp_build_support.cmake_build('C:/build', 'Release')
    evidence_line = captured_prints[0]
    streamed_lines = captured_prints[1:3]
finally:
    builtins.print = original_print
    cnp_build_support.subprocess.Popen = original_popen


def parallel_value(command):
    if '--parallel' not in command:
        return 'none'
    return command[command.index('--parallel') + 1]


print('default_parallel=%s' % parallel_value(default_command))
print('explicit_parallel=%s' % parallel_value(explicit_command))
print('zero_parallel=%s' % parallel_value(zero_command))
print('streamed_order=%s' % '|'.join(streamed_lines))
print('captured_evidence=%s' % evidence_line)
print('completed_returncode=%d' % default_result.returncode)
print('completed_stdout=%s' % default_result.stdout.replace('\n', '|'))
''';

/// stage_headers：目录内容镜像（不含目录名层、滤除非头文件）+ 显式文件复制。
const String _headersDriver = r'''
import os

from cnp_build_support import stage_headers

work = os.getcwd()
source = os.path.join(work, 'src')
os.makedirs(os.path.join(source, 'nested'), exist_ok=True)


def write(path, text):
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


write(os.path.join(source, 'alpha.h'), 'alpha')
write(os.path.join(source, 'beta.hpp'), 'beta')
write(os.path.join(source, 'nested', 'gamma.h'), 'gamma')
write(os.path.join(source, 'skip.c'), 'skip')
out_a = os.path.join(work, 'out_a')
count_a = stage_headers([source], out_a)
out_b = os.path.join(work, 'out_b')
count_b = stage_headers([os.path.join(source, 'alpha.h')], out_b)
print('dir_count=%d' % count_a)
print('file_count=%d' % count_b)
''';

/// stage_binaries：Release/Debug 双目录布局、MinGW `.a`/`.dll.a` 落点、
/// 中间目录跳过与同名去重。
const String _binariesDriver = r'''
import os

from cnp_build_support import stage_binaries

work = os.getcwd()
build = os.path.join(work, 'build')
fixtures = {
    'libA/foo.lib': 'foo-a',
    'libA/foo.pdb': 'pdb-a',
    'libA/bar.dll': 'bar-a',
    'libA/libz.a': 'z-a',
    'libA/libz.dll.a': 'z-import-a',
    'libB/foo.lib': 'foo-b',
    'CMakeFiles/generated.lib': 'generated',
    'obj/thing.dir/skipme.lib': 'skipme',
    'obj/odd-c/skipme2.lib': 'skipme2',
}


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


for relative, text in fixtures.items():
    write(os.path.join(build, *relative.split('/')), text)

release = stage_binaries(build, os.path.join(work, 'out_release'), 'Release')
debug = stage_binaries(build, os.path.join(work, 'out_debug'), 'Debug')
print('release_copied=%d release_lib=%d release_bin=%d release_skipped=%d' % (
    release['copied'], release['lib'], release['bin'], release['skipped']))
print('debug_copied=%d debug_lib=%d debug_bin=%d debug_skipped=%d' % (
    debug['copied'], debug['lib'], debug['bin'], debug['skipped']))
''';

/// stage_binaries reset：段重置（残留消失、另一段保留）、默认旧语义与双跑不累积
/// （含 MinGW `.a`/`.dll.a` 产物落点）。
const String _binariesResetDriver = r'''
import os

from cnp_build_support import stage_binaries

work = os.getcwd()
build = os.path.join(work, 'build')
out = os.path.join(work, 'out')


def write(root, relative, text):
    path = os.path.join(root, *relative.split('/'))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


def tree(root):
    files = []
    for current, _, names in os.walk(root):
        for name in names:
            path = os.path.relpath(os.path.join(current, name), root)
            files.append(path.replace('\\', '/'))
    return sorted(files)


write(build, 'fresh/libz.lib', 'fresh-lib')
write(build, 'fresh/libz.dll', 'fresh-dll')
write(build, 'fresh/libz.a', 'fresh-static')
write(build, 'fresh/libz.dll.a', 'fresh-import')

# 预置残留：旧产物、去重改名残留、混入的 debug 产物；另一配置段与 include 应受保护。
write(out, 'release/lib/stale.lib', 'stale-lib')
write(out, 'release/lib/libz_build-release.lib', 'dedup-residue')
write(out, 'release/bin/libzd.dll', 'debug-residue')
write(out, 'debug/bin/libzd.dll', 'debug-keep')
write(out, 'include/zlib.h', 'header-keep')

default_result = stage_binaries(build, out, 'Release')
print('default_counts=%d/%d/%d' % (
    default_result['copied'], default_result['lib'], default_result['bin']))
print('default_release=%s' % '|'.join(tree(os.path.join(out, 'release'))))

reset_result = stage_binaries(build, out, 'Release', reset=True)
print('reset_counts=%d/%d/%d' % (
    reset_result['copied'], reset_result['lib'], reset_result['bin']))
print('reset_release=%s' % '|'.join(tree(os.path.join(out, 'release'))))
print('reset_debug=%s' % '|'.join(tree(os.path.join(out, 'debug'))))
print('reset_include=%s' % '|'.join(tree(os.path.join(out, 'include'))))

# 双跑累积：再次重置 staging 后集合不变。
stage_binaries(build, out, 'Release', reset=True)
print('rerun_release=%s' % '|'.join(tree(os.path.join(out, 'release'))))

# 构建目录缺失：报错且不触碰既有输出（reset 在校验之后）。
try:
    stage_binaries(os.path.join(work, 'missing'), out, 'Release', reset=True)
    print('missing=no-error')
except FileNotFoundError:
    print('missing=FileNotFoundError')
print('missing_release=%s' % '|'.join(tree(os.path.join(out, 'release'))))
''';

/// stage_license：核心名优先级、同级字典序与「仅根目录」。
const String _licenseDriver = r'''
import os

from cnp_build_support import stage_license

work = os.getcwd()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


def make_source(name, files):
    root = os.path.join(work, name)
    for relative, text in files.items():
        write(os.path.join(root, *relative.split('/')), text)
    return root


def staged_basename(source, out):
    staged = stage_license(source, out)
    return 'None' if staged is None else os.path.basename(staged)


source_a = make_source('src_a', {
    'COPYING': 'copying',
    'LICENSE-MIT': 'license-mit',
    'NOTICE.md': 'notice-md',
    'sub/NOTICE': 'sub-notice',
})
source_b = make_source('src_b', {
    'sub/LICENSE': 'sub-only',
})
source_c = make_source('src_c', {
    'LICENSE.txt': 'license-txt',
    'LICENSE': 'license-plain',
})
print('a=%s' % staged_basename(source_a, os.path.join(work, 'out_a')))
print('b=%s' % staged_basename(source_b, os.path.join(work, 'out_b')))
print('c=%s' % staged_basename(source_c, os.path.join(work, 'out_c')))
''';

/// classify_tree：混合假树（含 debug/ 段、exclude、.git 与 out 自身）。
const String _classifyDriver = r'''
import os

from cnp_build_support import classify_tree

work = os.getcwd()
root = os.path.join(work, 'root')


def write(relative, text):
    path = os.path.join(root, *relative.split('/'))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


write('.git/HEAD', 'ref')
write('headers/alpha.h', 'h-alpha')
write('src/beta.hpp', 'h-beta')
write('src/impl/igamma.inl', 'h-gamma')
write('libs/release/foo.lib', 'l-foo')
write('libs/release/bar.a', 'l-bar')
write('libs/release/foo.dll', 'd-foo')
write('libs/release/tool.exe', 'e-tool')
write('libs/debug/foo.lib', 'l-foo-debug')
write('libs/debug/foo.pdb', 'p-foo-debug')
write('bin/helper.exe', 'e-helper')
write('excluded/extra.h', 'h-extra')
write('extra/skip.txt', 'skip')
write('LICENSE', 'license-root')
write('sub/NOTICE', 'notice-sub')

out = os.path.join(root, 'out')
counts = classify_tree(root, out, exclude=['excluded'])
print('include=%d lib=%d bin=%d debug_lib=%d debug_bin=%d license=%d' % (
    counts['include'], counts['lib'], counts['bin'],
    counts['debug_lib'], counts['debug_bin'], counts['license']))
''';

/// classify_tree 的 `_debug` 文件名后缀：同目录 Release/Debug 变体归入 debug 分层。
const String _classifyDebugSuffixDriver = r'''
import os

from cnp_build_support import classify_tree

work = os.getcwd()
root = os.path.join(work, 'root')


def write(relative, text):
    path = os.path.join(root, *relative.split('/'))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


write('bin/tbb12.dll', 'd-release')
write('bin/tbb12_debug.dll', 'd-debug')
write('bin/tbbmalloc.dll', 'd-malloc-release')
write('bin/tbbmalloc_debug.dll', 'd-malloc-debug')
write('lib/tbb12.lib', 'l-release')
write('lib/tbb12_debug.lib', 'l-debug')
write('lib/tbb12d.lib', 'l-d-suffix-unmatched')
write('sub/tbb12_debug.pdb', 'p-debug')
write('sub/helper.dll', 'd-no-marker')

out = os.path.join(root, 'out')
counts = classify_tree(root, out, debug_name_suffix='_debug')
print('suffix lib=%d bin=%d debug_lib=%d debug_bin=%d' % (
    counts['lib'], counts['bin'], counts['debug_lib'], counts['debug_bin']))

# 缺省参数：`_debug` 后缀规则同样默认生效（省略与显式传参计数一致）。
default_out = os.path.join(work, 'out_default')
default_counts = classify_tree(root, default_out)
print('default lib=%d bin=%d debug_lib=%d debug_bin=%d' % (
    default_counts['lib'], default_counts['bin'],
    default_counts['debug_lib'], default_counts['debug_bin']))
''';

/// summary：分类统计输出（证据行）与返回 dict 口径。
const String _summaryDriver = r'''
import os

from cnp_build_support import summary

work = os.getcwd()
out = os.path.join(work, 'out')


def write(relative, text):
    path = os.path.join(out, *relative.split('/'))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


write('include/a.h', 'aa')
write('release/lib/x.lib', 'xxx')
write('release/bin/y.dll', 'yyyy')
write('debug/lib/d.lib', 'dddd')
write('debug/bin/d.pdb', 'ddddd')
write('LICENSE', 'license')
write('misc/unknown.txt', 'u')

result = summary(out)
print('summary_include=%d' % result['include'])
print('summary_lib=%d' % result['lib'])
print('summary_bin=%d' % result['bin'])
print('summary_debug_lib=%d' % result['debug_lib'])
print('summary_debug_bin=%d' % result['debug_bin'])
print('summary_license=%d' % result['license'])
print('summary_other=%d' % result['other'])
print('summary_files=%d' % result['files'])
print('summary_bytes=%d' % result['bytes'])
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    _pythonCommand = _probePython();
    if (_pythonCommand == null) {
      _skipReason = '未检测到可用的 Python（python / py -3 均不可用）';
    }
  } else {
    _skipReason = '仅 Windows 平台执行（依赖真实 Python 进程）';
  }

  group('cnp_build_support.py 真机冒烟（仅 Windows + Python）', () {
    test('模块资产载入与语法：py_compile 退出码 0', () async {
      final String source = await _loadModuleSource();
      print(
        '[evidence] 模块载入方式='
        '${_loadedFromBundle ? 'rootBundle' : '源文件回退'}',
      );
      expect(source, contains('VERSION = "8"'));

      final Directory tempDir = _createTempDir('cnp_support_syntax_');
      final String modulePath = _installModule(tempDir, source);
      final ProcessResult result = _runPython(<String>[
        '-m',
        'py_compile',
        modulePath,
      ]);
      print('[evidence] py_compile exitCode=${result.exitCode}');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
    }, skip: _skipReason);

    test('cmake_configure：命令装配、优化注入与缺 CNP_CMAKE 明确报错', () async {
      final Directory tempDir = _createTempDir('cnp_support_cmake_');
      final File driver = _writeDriver(tempDir, _cmakeDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'cmake');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(stdout, contains('missing=RuntimeError'));
      expect(stdout, contains('empty=RuntimeError'));
      expect(stdout, contains('generator=Ninja'));
      expect(stdout, contains('build_type=-DCMAKE_BUILD_TYPE=Release'));
      expect(
        stdout,
        contains(
          'runtime=-DCMAKE_MSVC_RUNTIME_LIBRARY='
          'MultiThreaded\$<\$<CONFIG:Debug>:Debug>DLL',
        ),
      );
      expect(
        stdout,
        contains('make_program=-DCMAKE_MAKE_PROGRAM=C:/tools/ninja/ninja.exe'),
      );
      expect(
        stdout,
        contains('c_compiler=-DCMAKE_C_COMPILER=C:/compiler/icx-cl.exe'),
      );
      expect(stdout, contains('extra=-DEXTRA=1'));
      expect(stdout, contains('minimal_make_program=False'));
      // icx：AVX2 + /O3 /Ob2 /Oi /Ot /GF /Gy + NDEBUG + IPO。
      expect(stdout, contains('icx_avx2_c=/QxCORE-AVX2 /QaxCORE-AVX2'));
      expect(stdout, contains('icx_avx2_cxx=/QxCORE-AVX2 /QaxCORE-AVX2'));
      expect(stdout, contains('icx_opt=/O3 /Ob2 /Oi /Ot /GF /Gy /DNDEBUG'));
      expect(stdout, contains('icx_opt_cxx=/O3 /Ob2 /Oi /Ot /GF /Gy /DNDEBUG'));
      expect(stdout, contains('icx_ipo=ON'));
      // 非法种类标识时回退按编译器路径推断（icx-cl.exe → icx）。
      expect(stdout, contains('inferred_avx2=/QxCORE-AVX2 /QaxCORE-AVX2'));
      expect(
        stdout,
        contains('inferred_opt=/O3 /Ob2 /Oi /Ot /GF /Gy /DNDEBUG'),
      );
      // clang-cl（cl 兼容驱动）：/arch:AVX2 + /O2 /Ob2 /Oi /Ot /GF /Gy + lld 可解析时 IPO。
      expect(stdout, contains('clang_avx2_c=/arch:AVX2'));
      expect(
        stdout,
        contains('clang_opt_cxx=/O2 /Ob2 /Oi /Ot /GF /Gy -DNDEBUG'),
      );
      expect(stdout, contains('clang_ipo=ON'));
      // clang-cl 不注入 GNU 风链接旗标（GNU clang 驱动已移除）。
      expect(stdout, contains('clang_cl_ld=none'));
      // msvc：/O2 /Ob2 /Oi /Ot /GF /Gy + IPO。
      expect(stdout, contains('msvc_opt=/O2 /Ob2 /Oi /Ot /GF /Gy /DNDEBUG'));
      expect(
        stdout,
        contains('msvc_opt_cxx=/O2 /Ob2 /Oi /Ot /GF /Gy /DNDEBUG'),
      );
      expect(stdout, contains('msvc_ipo=ON'));
      // Debug 不注入优化与 IPO；AVX2 保留。
      expect(stdout, contains('debug_avx2=/arch:AVX2'));
      expect(stdout, contains('debug_opt=none'));
      expect(stdout, contains('debug_ipo=none'));
      // 运行库家族：缺省 md（/MD + Debug /MDd）、显式 mt（/MT + Debug /MTd）、非法回退 md。
      expect(
        stdout,
        contains('runtime_mt=MultiThreaded\$<\$<CONFIG:Debug>:Debug>'),
      );
      expect(
        stdout,
        contains('runtime_invalid=MultiThreaded\$<\$<CONFIG:Debug>:Debug>DLL'),
      );
      // 编译器种类未知时不注入任何优化参数。
      expect(stdout, contains('unknown_avx2=none'));
      expect(stdout, contains('unknown_opt=none'));
      // 退化路径：调用参数 / 环境变量 / clang-cl 缺 lld。
      expect(stdout, contains('disabled_call_ipo=none'));
      expect(stdout, contains('disabled_env_ipo=none'));
      expect(stdout, contains('clang_no_lld_ipo=none'));
      expect(stdout, contains('ipo=off reason=disabled-by-call'));
      expect(stdout, contains('ipo=off reason=disabled-by-env'));
      expect(stdout, contains('ipo=off reason=lld-link-missing'));
      expect(stdout, contains('ipo=off reason=unknown-compiler'));
      // 配方自带同名变量时保持其取值，模块不重复注入。
      expect(stdout, contains('preset_opt_cxx=/O1'));
      expect(
        stdout,
        contains('preset_opt_c=/O2 /Ob2 /Oi /Ot /GF /Gy /DNDEBUG'),
      );
      expect(stdout, contains('preset_ipo=OFF'));
      // MinGW：GNU 旗标、不写 CMAKE_MSVC_RUNTIME_LIBRARY、mt 链接期静态运行库、
      // RC 编译器注入、IPO 保守关闭（enable_ipo=True 可强制）、gcc/g++ 路径推断。
      expect(stdout, contains('mingw_avx2=-mavx2'));
      expect(
        stdout,
        contains('mingw_opt=-O3 -ffunction-sections -fdata-sections -DNDEBUG'),
      );
      expect(
        stdout,
        contains(
          'mingw_opt_cxx=-O3 -ffunction-sections -fdata-sections -DNDEBUG',
        ),
      );
      expect(stdout, contains('mingw_msvc_runtime=none'));
      expect(stdout, contains('mingw_ipo=none'));
      expect(
        stdout,
        contains('mingw_cxx=-DCMAKE_CXX_COMPILER=C:/msys64/ucrt64/bin/g++.exe'),
      );
      expect(stdout, contains('mingw_debug_opt=none'));
      expect(stdout, contains('mingw_md_shared=none'));
      expect(
        stdout,
        contains('mingw_static_shared=-static-libgcc -static-libstdc++'),
      );
      expect(
        stdout,
        contains('mingw_static_exe=-static-libgcc -static-libstdc++'),
      );
      expect(
        stdout,
        contains('mingw_static_module=-static-libgcc -static-libstdc++'),
      );
      expect(stdout, contains('mingw_rc=C:/msys64/ucrt64/bin/windres.exe'));
      expect(stdout, contains('mingw_forced_ipo=ON'));
      expect(stdout, contains('ipo=off reason=mingw-conservative'));
      expect(stdout, contains('gcc_inferred_avx2=-mavx2'));
      expect(
        stdout,
        contains(
          'gcc_inferred_opt=-O3 -ffunction-sections -fdata-sections -DNDEBUG',
        ),
      );
      // 证据行。
      expect(
        stdout,
        contains(
          '[cnp_build_support] cmake_configure: config=Release compiler=icx '
          'avx2=/QxCORE-AVX2 /QaxCORE-AVX2 '
          'optimization=/O3 /Ob2 /Oi /Ot /GF /Gy ipo=on runtime=md',
        ),
      );
      expect(stdout, contains('nonzero=RuntimeError'));
      expect(stdout, contains('nonzero_has_tail=True'));
      expect(stdout, contains('nonzero_has_code=True'));
      expect(stdout, contains('nonzero_has_lines=True'));
      expect(stdout, contains('spawn=RuntimeError'));
    }, skip: _skipReason);

    test('cmake_build：缺省并行到 CPU 核数、显式 jobs 与 0 禁用', () async {
      final Directory tempDir = _createTempDir('cnp_support_cmake_build_');
      final File driver = _writeDriver(tempDir, _cmakeBuildDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'cmake_build');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(stdout, matches(RegExp(r'default_parallel=\d+')));
      expect(stdout, contains('explicit_parallel=2'));
      expect(stdout, contains('zero_parallel=none'));
      expect(
        stdout,
        contains('[cnp_build_support] cmake_build: config=Release parallel='),
      );
      expect(stdout, contains('streamed_order=stream-a|stream-b'));
      expect(
        stdout,
        contains(
          'captured_evidence='
          '[cnp_build_support] cmake_build: config=Release parallel=',
        ),
      );
      expect(stdout, contains('completed_returncode=0'));
      expect(stdout, contains('completed_stdout=stream-a|stream-b'));
    }, skip: _skipReason);

    test('stage_headers：文件与目录内容镜像（不含目录名层）', () async {
      final Directory tempDir = _createTempDir('cnp_support_headers_');
      final File driver = _writeDriver(tempDir, _headersDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'headers');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      expect(result.stdout.toString(), contains('dir_count=3'));
      expect(result.stdout.toString(), contains('file_count=1'));

      final String includeA = _join(_join(tempDir.path, 'out_a'), 'include');
      expect(_readText(_join(includeA, 'alpha.h')), 'alpha');
      expect(_readText(_join(includeA, 'beta.hpp')), 'beta');
      expect(_readText(_join(_join(includeA, 'nested'), 'gamma.h')), 'gamma');
      expect(File(_join(includeA, 'skip.c')).existsSync(), isFalse);
      expect(
        _readText(
          _join(_join(_join(tempDir.path, 'out_b'), 'include'), 'alpha.h'),
        ),
        'alpha',
      );
    }, skip: _skipReason);

    test('stage_binaries：Release/Debug 双目录与同名去重、中间目录跳过', () async {
      final Directory tempDir = _createTempDir('cnp_support_binaries_');
      final File driver = _writeDriver(tempDir, _binariesDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'binaries');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(
        stdout,
        contains(
          'release_copied=6 release_lib=4 release_bin=2 release_skipped=0',
        ),
      );
      expect(
        stdout,
        contains('debug_copied=6 debug_lib=4 debug_bin=2 debug_skipped=0'),
      );

      final String outRelease = _join(tempDir.path, 'out_release');
      expect(_relativeFiles(outRelease), <String>[
        'release/bin/bar.dll',
        'release/bin/foo.pdb',
        'release/lib/foo.lib',
        'release/lib/foo_libB.lib',
        'release/lib/libz.a',
        'release/lib/libz.dll.a',
      ]);
      expect(
        _readText(_join(_join(_join(outRelease, 'release'), 'lib'), 'foo.lib')),
        'foo-a',
      );
      expect(
        _readText(
          _join(_join(_join(outRelease, 'release'), 'lib'), 'foo_libB.lib'),
        ),
        'foo-b',
      );
      expect(
        _readText(_join(_join(_join(outRelease, 'release'), 'bin'), 'foo.pdb')),
        'pdb-a',
      );
      // MinGW：静态库与导入库均以 `.a` 结尾 → lib（而非 bin）。
      expect(
        _readText(_join(_join(_join(outRelease, 'release'), 'lib'), 'libz.a')),
        'z-a',
      );
      expect(
        _readText(
          _join(_join(_join(outRelease, 'release'), 'lib'), 'libz.dll.a'),
        ),
        'z-import-a',
      );

      final String outDebug = _join(tempDir.path, 'out_debug');
      expect(_relativeFiles(outDebug), <String>[
        'debug/bin/bar.dll',
        'debug/bin/foo.pdb',
        'debug/lib/foo.lib',
        'debug/lib/foo_libB.lib',
        'debug/lib/libz.a',
        'debug/lib/libz.dll.a',
      ]);
      expect(
        _readText(_join(_join(_join(outDebug, 'debug'), 'lib'), 'foo.lib')),
        'foo-a',
      );
    }, skip: _skipReason);

    test('stage_binaries reset：残留消失、另一段保留且双跑不累积', () async {
      final Directory tempDir = _createTempDir('cnp_support_binaries_reset_');
      final File driver = _writeDriver(tempDir, _binariesResetDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'binaries_reset');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      // 默认参数：旧语义不变，既有残留与增量产物共存。
      expect(stdout, contains('default_counts=4/3/1'));
      expect(
        stdout,
        contains(
          'default_release=bin/libz.dll|bin/libzd.dll|lib/libz.a|'
          'lib/libz.dll.a|lib/libz.lib|lib/libz_build-release.lib|'
          'lib/stale.lib',
        ),
        reason: '无 reset 时既有文件必须原样保留（向后兼容）',
      );
      // reset：本配置段只剩本次 staging 产物，另一段与 include 不受影响。
      expect(stdout, contains('reset_counts=4/3/1'));
      expect(
        stdout,
        contains(
          'reset_release=bin/libz.dll|lib/libz.a|lib/libz.dll.a|lib/libz.lib',
        ),
        reason: 'reset 后陈旧文件与 _build-* 去重残留应消失',
      );
      expect(stdout, contains('reset_debug=bin/libzd.dll'));
      expect(stdout, contains('reset_include=zlib.h'));
      // 双跑：重置后重复 staging 不产生累积。
      expect(
        stdout,
        contains(
          'rerun_release=bin/libz.dll|lib/libz.a|lib/libz.dll.a|lib/libz.lib',
        ),
      );
      // 构建目录缺失：报错且不触碰既有输出。
      expect(stdout, contains('missing=FileNotFoundError'));
      expect(
        stdout,
        contains(
          'missing_release=bin/libz.dll|lib/libz.a|lib/libz.dll.a|lib/libz.lib',
        ),
      );

      final String out = _join(tempDir.path, 'out');
      expect(
        File(_join(_join(_join(out, 'release'), 'lib'), 'stale.lib'))
            .existsSync(),
        isFalse,
      );
      expect(
        File(
          _join(_join(_join(out, 'release'), 'lib'), 'libz_build-release.lib'),
        ).existsSync(),
        isFalse,
      );
      expect(
        _readText(_join(_join(_join(out, 'release'), 'lib'), 'libz.lib')),
        'fresh-lib',
      );
      // MinGW 静态库与导入库：整段重置后为本次 staging 内容。
      expect(
        _readText(_join(_join(_join(out, 'release'), 'lib'), 'libz.a')),
        'fresh-static',
      );
      expect(
        _readText(_join(_join(_join(out, 'release'), 'lib'), 'libz.dll.a')),
        'fresh-import',
      );
      expect(
        _readText(_join(_join(_join(out, 'debug'), 'bin'), 'libzd.dll')),
        'debug-keep',
      );
    }, skip: _skipReason);

    test('stage_license：核心名优先级与仅根目录', () async {
      final Directory tempDir = _createTempDir('cnp_support_license_');
      final File driver = _writeDriver(tempDir, _licenseDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'license');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(stdout, contains('a=LICENSE-MIT'));
      expect(stdout, contains('b=None'));
      expect(stdout, contains('c=LICENSE'));

      final String outA = _join(tempDir.path, 'out_a');
      expect(_readText(_join(outA, 'LICENSE-MIT')), 'license-mit');
      expect(File(_join(outA, 'COPYING')).existsSync(), isFalse);
      expect(File(_join(outA, 'NOTICE.md')).existsSync(), isFalse);
      expect(
        Directory(_join(outA, 'sub')).existsSync(),
        isFalse,
        reason: '子目录许可证不参与筛选',
      );

      final String outB = _join(tempDir.path, 'out_b');
      expect(Directory(outB).existsSync(), isFalse, reason: '仅子目录命中时不应创建输出目录');

      final String outC = _join(tempDir.path, 'out_c');
      expect(_readText(_join(outC, 'LICENSE')), 'license-plain');
      expect(
        File(_join(outC, 'LICENSE.txt')).existsSync(),
        isFalse,
        reason: '同级命中多个许可证时只复制首选',
      );
    }, skip: _skipReason);

    test('classify_tree：混合假树分类、debug 段与跳过项', () async {
      final Directory tempDir = _createTempDir('cnp_support_classify_');
      final File driver = _writeDriver(tempDir, _classifyDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'classify');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      expect(
        result.stdout.toString(),
        contains('include=3 lib=2 bin=3 debug_lib=1 debug_bin=1 license=1'),
      );
      expect(
        result.stdout.toString(),
        contains('[cnp_build_support] classify: '),
      );
      expect(
        result.stdout.toString(),
        contains(' -> '),
        reason: '开始标记应包含 <root> -> <out> 形态',
      );

      final String out = _join(_join(tempDir.path, 'root'), 'out');
      expect(_relativeFiles(out), <String>[
        'LICENSE',
        'debug/bin/foo.pdb',
        'debug/lib/foo.lib',
        'include/headers/alpha.h',
        'include/src/beta.hpp',
        'include/src/impl/igamma.inl',
        'release/bin/foo.dll',
        'release/bin/helper.exe',
        'release/bin/tool.exe',
        'release/lib/bar.a',
        'release/lib/foo.lib',
      ]);
      expect(_readText(_join(out, 'LICENSE')), 'license-root');
      expect(
        _readText(_join(_join(_join(out, 'include'), 'src'), 'beta.hpp')),
        'h-beta',
      );
      expect(
        _readText(_join(_join(out, 'debug/lib'), 'foo.lib')),
        'l-foo-debug',
      );
      // 跳过项：.git、exclude 命中目录、非根许可证、普通文件与非目标扩展。
      expect(File(_join(out, '.git')).existsSync(), isFalse);
      expect(
        Directory(_join(_join(out, 'include'), 'excluded')).existsSync(),
        isFalse,
      );
      expect(
        File(_join(_join(_join(out, 'include'), 'sub'), 'NOTICE')).existsSync(),
        isFalse,
      );
    }, skip: _skipReason);

    test('classify_tree：_debug 文件名后缀归入 debug 分层（缺省语义不变）', () async {
      final Directory tempDir = _createTempDir('cnp_support_classify_suffix_');
      final File driver = _writeDriver(tempDir, _classifyDebugSuffixDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'classify_suffix');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      // 后缀规则与目录段规则为「或」：tbb12_debug / tbbmalloc_debug 文件名后缀 → debug；
      // tbb12.d / tbbmalloc / helper → release（目录段规则由既有用例锁定）。
      expect(stdout, contains('suffix lib=2 bin=3 debug_lib=1 debug_bin=3'));
      expect(
        stdout,
        contains('default lib=2 bin=3 debug_lib=1 debug_bin=3'),
        reason: '缺省参数（`_debug`）与显式传参口径一致',
      );

      final String out = _join(_join(tempDir.path, 'root'), 'out');
      expect(_relativeFiles(out), <String>[
        'debug/bin/tbb12_debug.dll',
        'debug/bin/tbb12_debug.pdb',
        'debug/bin/tbbmalloc_debug.dll',
        'debug/lib/tbb12_debug.lib',
        'release/bin/helper.dll',
        'release/bin/tbb12.dll',
        'release/bin/tbbmalloc.dll',
        'release/lib/tbb12.lib',
        'release/lib/tbb12d.lib',
      ]);
      expect(
        _readText(_join(_join(out, 'debug/bin'), 'tbb12_debug.dll')),
        'd-debug',
      );
      expect(
        _readText(_join(_join(out, 'release/bin'), 'tbb12.dll')),
        'd-release',
      );
      expect(
        File(_join(_join(out, 'release/bin'), 'tbb12_debug.dll')).existsSync(),
        isFalse,
        reason: 'Debug 变体不得落 release 分层',
      );
      expect(
        File(_join(_join(out, 'debug/lib'), 'tbb12d.lib')).existsSync(),
        isFalse,
        reason: '`d` 后缀不在后缀规则内，仍归 release',
      );
    }, skip: _skipReason);

    test('summary：统计输出（证据行）与返回口径', () async {
      final Directory tempDir = _createTempDir('cnp_support_summary_');
      final File driver = _writeDriver(tempDir, _summaryDriver);
      _installModule(tempDir, await _loadModuleSource());

      final ProcessResult result = _runDriver(driver, 'summary');
      expect(
        result.exitCode,
        0,
        reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
      );
      final String stdout = result.stdout.toString();
      expect(stdout, contains('[cnp_build_support] summary:'));
      expect(stdout, contains('summary_include=1'));
      expect(stdout, contains('summary_lib=1'));
      expect(stdout, contains('summary_bin=1'));
      expect(stdout, contains('summary_debug_lib=1'));
      expect(stdout, contains('summary_debug_bin=1'));
      expect(stdout, contains('summary_license=1'));
      expect(stdout, contains('summary_other=1'));
      expect(stdout, contains('summary_files=7'));
      expect(stdout, contains('summary_bytes=26'));
    }, skip: _skipReason);
  });
}
