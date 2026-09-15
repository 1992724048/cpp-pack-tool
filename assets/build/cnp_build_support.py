"""cnp_build_support — cpp_nuget_pack 构建分类辅助模块（Python 3.8+，仅标准库）。

由 cpp_nuget_pack 构建管线释放到 tools/ 并经 PYTHONPATH 提供给 build.py：

    from cnp_build_support import cmake_configure, cmake_build
    from cnp_build_support import stage_headers, stage_binaries, stage_license, summary

    cmake_configure(SRC_PATH, BUILD_DIR, config='Release')
    cmake_build(BUILD_DIR, config='Release')
    stage_headers([SRC_PATH], BUILD_OUT)
    stage_binaries(BUILD_DIR, BUILD_OUT, config='Release', reset=True)
    stage_license(SRC_PATH, BUILD_OUT)
    summary(BUILD_OUT)

输出布局（release/debug 分层，与打包侧的构建类型识别对齐）：

    <out>/include/                  头文件
    <out>/release/lib, release/bin  Release 静态库 / 动态库、符号、可执行
    <out>/debug/lib, debug/bin      Debug 配置产物
    <out>/<原文件名>                root 根部的许可证文件

CMake 相关函数读取 cpp_nuget_pack 注入的子进程环境变量：CNP_CMAKE、CNP_NINJA、
CNP_C_COMPILER、CNP_CXX_COMPILER、CNP_COMPILER_KIND、CNP_RUNTIME_LIBRARY；
CNP_CMAKE 缺失或为空时给出明确错误。`cmake_configure` 按编译器注入 AVX2（全部
配置）与 Release 最高优化 / IPO（不支持或经 CNP_NO_IPO / enable_ipo=False 时
自动退化），按 CNP_RUNTIME_LIBRARY 注入 MSVC 运行库家族（`md` 默认 / `mt`，
Debug 自动 d 变体），不注入任何语言标准参数；`cmake_build` 缺省以 CPU 逻辑核数
并行构建。
"""

import filecmp
import os
import re
import shutil
import subprocess

VERSION = "6"

__all__ = (
    "VERSION",
    "cmake_build",
    "cmake_configure",
    "classify_tree",
    "stage_binaries",
    "stage_headers",
    "stage_license",
    "summary",
)

HEADER_EXTENSIONS = frozenset((".h", ".hpp", ".hh", ".hxx", ".inl", ".ipp"))
LIBRARY_EXTENSIONS = frozenset((".lib", ".a"))
BINARY_EXTENSIONS = frozenset((".dll", ".pdb", ".exe"))

# 与打包器 lib/packaging/license_file.dart 保持一致：核心名 + `-`/`.` 后缀变体。
LICENSE_NAME_PATTERN = re.compile(
    r"^(license|licence|copying|unlicense|notice)([-.][a-z0-9]+)*$"
)
LICENSE_CORE_PRIORITY = ("license", "licence", "copying", "unlicense", "notice")

_CMAKE_RUNTIME_LIBRARY_ENV = "CNP_RUNTIME_LIBRARY"
_DEFAULT_RUNTIME_LIBRARY = "md"
# 运行库家族 → CMAKE_MSVC_RUNTIME_LIBRARY 取值（Debug 自动 d 变体：
# md → /MD 与 /MDd，mt → /MT 与 /MTd）。
_RUNTIME_LIBRARY_VARIANTS = {
    "md": "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL",
    "mt": "MultiThreaded$<$<CONFIG:Debug>:Debug>",
}
_OUTPUT_TAIL_LINES = 20
_INTERMEDIATE_DIR_SUFFIXES = (".dir", "-c")

# 编译器种类标识与 lib/build/toolchain.dart 的 CNP_COMPILER_KIND 对应。
_COMPILER_KINDS = ("icx", "clang-cl", "msvc")

# AVX2 向量化（全部配置）。
_AVX2_FLAGS = {
    "icx": ("/QxCORE-AVX2", "/QaxCORE-AVX2"),
    "clang-cl": ("/arch:AVX2",),
    "msvc": ("/arch:AVX2",),
}

# Release 最高优化（各编译器上限；/Ob2 /Oi /Ot 内联与内建、/GF 字符串池、
# /Gy 函数级链接，clang-cl / icx 已实证接受）。clang-cl 须用 MSVC 风格 `/O2`：
# GNU 风格 `-O3` 会被驱动忽略并告警；LLVM 23 实证 `/O2`+`/Ot` 映射 cc1 `-O3`
# （最高优化），组合净级别 `-O3`。
_RELEASE_OPTIMIZATION_FLAGS = {
    "icx": ("/O3", "/Ob2", "/Oi", "/Ot", "/GF", "/Gy"),
    "clang-cl": ("/O2", "/Ob2", "/Oi", "/Ot", "/GF", "/Gy"),
    "msvc": ("/O2", "/Ob2", "/Oi", "/Ot", "/GF", "/Gy"),
}

# NDEBUG 定义前缀按编译器习惯书写（cl / icx-cl 兼容 `-D`，此处保留 MSVC 风格）。
_DEFINE_FLAG_PREFIX = {"icx": "/D", "clang-cl": "-D", "msvc": "/D"}

# CMake IPO（Release）：msvc → /GL + /LTCG；icx → -Qipo；clang-cl → -flto=thin。
_IPO_CMAKE_VARIABLE = "CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE"
_IPO_LINKER_PROBE = "lld-link"
_DISABLE_IPO_ENV = "CNP_NO_IPO"


def cmake_configure(
    source, build_dir, config="Release", extra_args=(), enable_ipo=None
):
    """以 Ninja 生成器配置 CMake 工程（单配置，运行库按 CNP_RUNTIME_LIBRARY）。

    固定拼接 `-G Ninja`、`-DCMAKE_BUILD_TYPE`、`-DCMAKE_MSVC_RUNTIME_LIBRARY`；
    `CNP_NINJA`/`CNP_C_COMPILER`/`CNP_CXX_COMPILER` 存在时追加对应 `-D` 参数；
    `extra_args` 原样追加（其中同名 `-DCMAKE_*` 优先于本函数注入的优化参数）。

    运行库家族读取 `CNP_RUNTIME_LIBRARY`（大小写不敏感）：`md`（缺省/非法回退）
    → `/MD` 与 Debug `/MDd`；`mt` → `/MT` 与 Debug `/MTd`。

    优化参数按编译器种类（`CNP_COMPILER_KIND`，回退从编译器路径推断）注入，
    **不注入任何语言标准（std/c++ 标准）参数**：

    - AVX2 全部配置：icx → `/QxCORE-AVX2 /QaxCORE-AVX2`；clang-cl / msvc →
      `/arch:AVX2`（写入两配置共用的 `CMAKE_C_FLAGS` / `CMAKE_CXX_FLAGS`）；
    - Release 最高优化：icx `/O3`、clang-cl `/O2`、msvc `/O2`，并追加
      `/Ob2 /Oi /Ot /GF /Gy`，保留 `NDEBUG`（写入 `CMAKE_C_FLAGS_RELEASE` /
      `CMAKE_CXX_FLAGS_RELEASE`）；
    - Release 启用 CMake IPO（`CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE=ON`）：
      msvc `/GL`+`/LTCG`、icx `-Qipo`；clang-cl 需 PATH 中可解析 `lld-link`，
      缺失时自动退化；`enable_ipo=False` 或环境变量 `CNP_NO_IPO=1` 可显式关闭
      （供单个库按兼容性退化）；
    - Debug 不注入任何优化参数（保留调试信息），AVX2 仍保留。

    编译器种类未知时不注入优化参数；子进程失败抛 RuntimeError（含输出尾部）。
    """
    cmake = _required_environment_path("CNP_CMAKE")
    extra = [str(argument) for argument in extra_args]
    provided = _provided_definition_variables(extra)
    kind = _compiler_kind()
    runtime, runtime_library = _runtime_library()
    avx2_flags = _AVX2_FLAGS.get(kind, ()) if kind else ()
    is_release = str(config).lower() == "release"
    optimization_flags = ()
    if is_release and kind:
        optimization_flags = _RELEASE_OPTIMIZATION_FLAGS.get(kind, ())

    command = [
        cmake,
        "-S",
        os.fspath(source),
        "-B",
        os.fspath(build_dir),
        "-G",
        "Ninja",
        "-DCMAKE_BUILD_TYPE=" + str(config),
        "-DCMAKE_MSVC_RUNTIME_LIBRARY=" + runtime_library,
    ]
    ninja = _optional_environment_path("CNP_NINJA")
    if ninja:
        command.append("-DCMAKE_MAKE_PROGRAM=" + ninja)
    c_compiler = _optional_environment_path("CNP_C_COMPILER")
    if c_compiler:
        command.append("-DCMAKE_C_COMPILER=" + c_compiler)
    cxx_compiler = _optional_environment_path("CNP_CXX_COMPILER")
    if cxx_compiler:
        command.append("-DCMAKE_CXX_COMPILER=" + cxx_compiler)
    command.extend(
        _optimization_arguments(avx2_flags, optimization_flags, kind, provided)
    )

    ipo_state, ipo_reason = _resolve_ipo_state(
        kind, config, enable_ipo, provided
    )
    if ipo_state == "on":
        command.append("-D%s=ON" % _IPO_CMAKE_VARIABLE)
    print(
        "[cnp_build_support] cmake_configure: config=%s compiler=%s avx2=%s "
        "optimization=%s ipo=%s runtime=%s"
        % (
            config,
            kind or "unknown",
            " ".join(avx2_flags) if avx2_flags else "-",
            " ".join(optimization_flags) if optimization_flags else "-",
            ipo_state,
            runtime,
        ),
        flush=True,
    )
    if ipo_reason:
        print(
            "[cnp_build_support] cmake_configure: "
            "ipo=off reason=%s" % ipo_reason,
            flush=True,
        )
    command.extend(extra)
    return _run_process(command, "cmake 配置")


def cmake_build(build_dir, config="Release", jobs=None):
    """以 `cmake --build` 构建已配置的工程（Ninja 单配置）。

    `jobs` 缺省为 `os.cpu_count()`（尽可能多线程）；显式正整数追加
    `--parallel <jobs>`；传 0/负数（或平台无法获取核数）时不追加。失败抛
    RuntimeError（含输出尾部）。
    """
    cmake = _required_environment_path("CNP_CMAKE")
    command = [cmake, "--build", os.fspath(build_dir), "--config", str(config)]
    if jobs is None:
        jobs = os.cpu_count()
    parallel = int(jobs) if jobs is not None and int(jobs) > 0 else None
    if parallel is not None:
        command.extend(("--parallel", str(parallel)))
    print(
        "[cnp_build_support] cmake_build: config=%s parallel=%s"
        % (config, parallel if parallel is not None else "-"),
        flush=True,
    )
    return _run_process(command, "cmake 构建")


def stage_headers(paths, out):
    """头文件 → `<out>/include/`，返回复制数量。

    - 传入文件（单个路径或路径序列）：复制到 `<out>/include/<文件名>`；
    - 传入目录：目录**内容**镜像到 `<out>/include/`（不含目录名层、保留子结构，
      仅复制头文件扩展名 `.h/.hpp/.hh/.hxx/.inl/.ipp`）。
    """
    if isinstance(paths, (str, bytes, os.PathLike)):
        paths = (paths,)
    include_dir = os.path.join(os.fspath(out), "include")
    copied = 0
    for path in paths:
        path = os.fsdecode(os.fspath(path))
        if os.path.isdir(path):
            for current, directory_names, file_names in os.walk(path):
                directory_names.sort()
                for file_name in sorted(file_names):
                    if not _is_header_name(file_name):
                        continue
                    relative = os.path.relpath(
                        os.path.join(current, file_name), path
                    )
                    _copy_file(
                        os.path.join(current, file_name),
                        os.path.join(include_dir, relative),
                    )
                    copied += 1
        elif os.path.isfile(path):
            _copy_file(path, os.path.join(include_dir, os.path.basename(path)))
            copied += 1
        else:
            raise FileNotFoundError("头文件路径不存在：%s" % path)
    return copied


def stage_binaries(build_dir, out, config="Release", reset=False):
    """递归收集构建树中的 `.lib/.dll/.pdb` 并按配置分层，返回计数 dict。

    - Release → `<out>/release/lib/`（.lib）与 `<out>/release/bin/`（.dll/.pdb）；
    - Debug → `<out>/debug/lib/` 与 `<out>/debug/bin/`；
    - 库类产物不落 `<out>` 根（打包侧按 release/debug 路径段识别构建类型）；
    - 跳过 `CMakeFiles`、`*.dir`、`*-c` 中间目录与 `out` 自身；
    - 同名不同内容按父目录名后缀去重（同名同内容只保留一份）；
    - `reset=True` 时先递归删除本配置段（`<out>/release` 或 `<out>/debug`）再
      staging，只清本配置段、不动另一配置与其他目录，杜绝同名去重改名
      （`_build-*`）与陈旧文件跨构建累积；默认 `reset=False` 保持旧语义
      （只增量补入、不改动既有文件）。重置发生在 `build_dir` 校验之后——
      构建目录缺失时直接报错、不触碰输出。

    返回 `{"copied": n, "lib": n, "bin": n, "skipped": n}`；`lib`/`bin` 为实际
    落点计数（Release 时对应 release/lib、release/bin；Debug 时对应 debug/*）。
    """
    build_dir = os.path.abspath(os.fspath(build_dir))
    out = os.path.abspath(os.fspath(out))
    if not os.path.isdir(build_dir):
        raise FileNotFoundError("构建目录不存在：%s" % build_dir)
    is_debug = str(config).lower() == "debug"
    segment = "debug" if is_debug else "release"
    segment_dir = os.path.join(out, segment)
    if reset:
        _reset_stage_segment(segment_dir)
    lib_dir = os.path.join(segment_dir, "lib")
    bin_dir = os.path.join(segment_dir, "bin")

    candidates = []
    for current, directory_names, file_names in os.walk(build_dir):
        directory_names[:] = sorted(
            name
            for name in directory_names
            if not _is_intermediate_dir_name(name)
            and not _is_within(os.path.join(current, name), out)
        )
        for file_name in sorted(file_names):
            extension = os.path.splitext(file_name)[1].lower()
            if extension in (".lib", ".dll", ".pdb"):
                candidates.append((os.path.join(current, file_name), extension))

    counts = {"copied": 0, "lib": 0, "bin": 0, "skipped": 0}
    for source, extension in sorted(candidates):
        is_library = extension == ".lib"
        destination_dir = lib_dir if is_library else bin_dir
        status = _stage_file(source, destination_dir, os.path.basename(source))
        if status == "skipped":
            counts["skipped"] += 1
            continue
        counts["copied"] += 1
        counts["lib" if is_library else "bin"] += 1
    return counts


def stage_license(source_root, out):
    """识别 `source_root` **根目录**的首选许可证并复制到 `<out>/` 根。

    名称规则与打包器 `license_file.dart` 一致：`LICENSE`/`LICENCE`/`COPYING`/
    `UNLICENSE`/`NOTICE` 及 `-`/`.` 变体、大小写不敏感；核心名优先级
    license > licence > copying > unlicense > notice，同核心名按小写字典序。
    仅扫描根目录（子目录不参与）；无命中返回 None，命中返回目标路径（保留原文件名）。
    """
    source_root = os.fspath(source_root)
    if not os.path.isdir(source_root):
        raise FileNotFoundError("目录不存在：%s" % source_root)
    primary_name = _find_primary_license_name(source_root)
    if primary_name is None:
        return None
    destination = os.path.join(os.fspath(out), primary_name)
    _copy_file(os.path.join(source_root, primary_name), destination)
    return destination


def classify_tree(root, out, exclude=(), debug_name_suffix="_debug"):
    """把预构建产物树分类到 release/debug 分层布局，返回各类计数 dict。

    - 头文件 → `<out>/include/`（保留相对结构）；
    - `.lib/.a` → `<out>/release/lib/`，`.dll/.pdb/.exe` → `<out>/release/bin/`；
    - Debug 判定（两者为「或」关系）：
      ① 相对路径中任一段小写为 `debug`；
      ② 文件名 stem 以 `debug_name_suffix` 结尾（大小写不敏感，缺省 `_debug`）——
         适用于同目录存放 Release/Debug 变体的预构建树（如 TBB 的
         `tbb12.dll` 与 `tbb12_debug.dll`）；
      判为 Debug 时分别落 `<out>/debug/lib`、`<out>/debug/bin`；
    - `root` **根部**的许可证名文件 → `<out>/` 根（保留原文件名）；
    - 跳过 `.git`、`exclude` 命中项（相对路径或名称）与 `out` 自身；其余文件跳过。

    计数键：include / lib / bin / debug_lib / debug_bin / license（lib/bin 指
    release 分层）。

    调用开始时打印开始标记 `[cnp_build_support] classify: <root> -> <out>`
    （工具据此把构建阶段从「正在下载」切换为「正在分类」，见 SKILL.md）。
    """
    root = os.path.abspath(os.fspath(root))
    out = os.path.abspath(os.fspath(out))
    if not os.path.isdir(root):
        raise FileNotFoundError("目录不存在：%s" % root)
    excludes = _normalize_excludes(exclude)
    suffix = str(debug_name_suffix).lower()
    print(
        "[cnp_build_support] classify: %s -> %s" % (root, out),
        flush=True,
    )
    counts = {
        "include": 0,
        "lib": 0,
        "bin": 0,
        "debug_lib": 0,
        "debug_bin": 0,
        "license": 0,
    }
    for current, directory_names, file_names in os.walk(root):
        directory_names[:] = sorted(
            name
            for name in directory_names
            if name.lower() != ".git"
            and not _is_within(os.path.join(current, name), out)
            and not _matches_exclude(
                _relative_forward_path(os.path.join(current, name), root), excludes
            )
        )
        for file_name in sorted(file_names):
            source = os.path.join(current, file_name)
            relative = _relative_forward_path(source, root)
            lowered_segments = relative.lower().split("/")
            if ".git" in lowered_segments:
                continue
            if _matches_exclude(relative, excludes):
                continue
            if _is_within(source, out):
                continue
            extension = os.path.splitext(file_name)[1].lower()
            is_debug = "debug" in lowered_segments or _has_debug_suffix(
                relative, suffix
            )
            if extension in HEADER_EXTENSIONS:
                destination_dir = os.path.join(
                    out, "include", os.path.dirname(relative)
                )
                category = "include"
            elif extension in LIBRARY_EXTENSIONS:
                destination_dir = os.path.join(
                    out, "debug" if is_debug else "release", "lib"
                )
                category = "debug_lib" if is_debug else "lib"
            elif extension in BINARY_EXTENSIONS:
                destination_dir = os.path.join(
                    out, "debug" if is_debug else "release", "bin"
                )
                category = "debug_bin" if is_debug else "bin"
            elif "/" not in relative and _is_license_name(file_name):
                destination_dir = out
                category = "license"
            else:
                continue
            if _stage_file(source, destination_dir, file_name) == "skipped":
                continue
            counts[category] += 1
    return counts


def summary(out):
    """遍历输出树打印统计（各类计数与总大小），返回同口径 dict。

    分类口径与产物布局一致：`release/lib` ↔ lib、`release/bin` ↔ bin、
    `debug/lib` ↔ debug_lib、`debug/bin` ↔ debug_bin；兼容旧根布局的 `lib` /
    `bin` 目录。返回键：include / lib / bin / debug_lib / debug_bin / license /
    other / files / bytes；输出树不存在时打印零统计。
    """
    out = os.path.abspath(os.fspath(out))
    result = {
        "include": 0,
        "lib": 0,
        "bin": 0,
        "debug_lib": 0,
        "debug_bin": 0,
        "license": 0,
        "other": 0,
        "files": 0,
        "bytes": 0,
    }
    if os.path.isdir(out):
        for current, directory_names, file_names in os.walk(out):
            directory_names.sort()
            for file_name in sorted(file_names):
                path = os.path.join(current, file_name)
                try:
                    size = os.path.getsize(path)
                except OSError:
                    size = 0
                relative = _relative_forward_path(path, out)
                segments = relative.lower().split("/")
                first_two = segments[:2]
                if first_two == ["debug", "lib"]:
                    category = "debug_lib"
                elif first_two == ["debug", "bin"]:
                    category = "debug_bin"
                elif first_two == ["release", "lib"]:
                    category = "lib"
                elif first_two == ["release", "bin"]:
                    category = "bin"
                elif segments[0] == "include":
                    category = "include"
                elif segments[0] == "lib":
                    category = "lib"
                elif segments[0] == "bin":
                    category = "bin"
                elif len(segments) == 1 and _is_license_name(file_name):
                    category = "license"
                else:
                    category = "other"
                result[category] += 1
                result["files"] += 1
                result["bytes"] += size
    print(
        "[cnp_build_support] summary: include=%d lib=%d bin=%d debug_lib=%d "
        "debug_bin=%d license=%d other=%d files=%d bytes=%d"
        % (
            result["include"],
            result["lib"],
            result["bin"],
            result["debug_lib"],
            result["debug_bin"],
            result["license"],
            result["other"],
            result["files"],
            result["bytes"],
        ),
        flush=True,
    )
    return result


def _required_environment_path(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(
            "环境变量 %s 缺失或为空（应经 cpp_nuget_pack 构建环境运行 build.py）" % name
        )
    return value


def _optional_environment_path(name):
    value = os.environ.get(name, "").strip()
    return value or None


def _compiler_kind():
    """编译器种类：`CNP_COMPILER_KIND`（msvc/clang-cl/icx），回退从编译器路径推断。

    两者都识别不出时返回 None（调用方不注入优化参数）。
    """
    kind = os.environ.get("CNP_COMPILER_KIND", "").strip().lower()
    if kind in _COMPILER_KINDS:
        return kind
    for name in ("CNP_CXX_COMPILER", "CNP_C_COMPILER"):
        executable = os.path.basename(os.environ.get(name, "").strip()).lower()
        if executable.startswith("icx"):
            return "icx"
        if executable.startswith("clang"):
            return "clang-cl"
        if executable in ("cl", "cl.exe"):
            return "msvc"
    return None


def _runtime_library():
    """运行库家族与 `CMAKE_MSVC_RUNTIME_LIBRARY` 取值：`(家族, 取值)`。

    读取 `CNP_RUNTIME_LIBRARY`（大小写不敏感、允许两侧空白）；缺失或非法回退
    `md`（动态运行库，Debug 自动 d 变体）。
    """
    family = os.environ.get(_CMAKE_RUNTIME_LIBRARY_ENV, "").strip().lower()
    if family not in _RUNTIME_LIBRARY_VARIANTS:
        family = _DEFAULT_RUNTIME_LIBRARY
    return family, _RUNTIME_LIBRARY_VARIANTS[family]


def _provided_definition_variables(extra_args):
    """`extra_args` 中 `-D<变量>=...` 的变量名集合（配方自定义优先）。"""
    provided = set()
    for argument in extra_args:
        if not argument.startswith("-D"):
            continue
        name = argument[2:].split("=", 1)[0]
        if name:
            provided.add(name)
    return provided


def _optimization_arguments(avx2_flags, optimization_flags, kind, provided):
    """组装优化 `-D` 参数；配方已提供的同名变量不重复注入。"""
    arguments = []
    joined_avx2 = " ".join(avx2_flags)
    if joined_avx2:
        if "CMAKE_C_FLAGS" not in provided:
            arguments.append("-DCMAKE_C_FLAGS=" + joined_avx2)
        if "CMAKE_CXX_FLAGS" not in provided:
            arguments.append("-DCMAKE_CXX_FLAGS=" + joined_avx2)
    if optimization_flags:
        ndebug = _DEFINE_FLAG_PREFIX.get(kind, "-D") + "NDEBUG"
        joined_release = " ".join(tuple(optimization_flags) + (ndebug,))
        if "CMAKE_C_FLAGS_RELEASE" not in provided:
            arguments.append("-DCMAKE_C_FLAGS_RELEASE=" + joined_release)
        if "CMAKE_CXX_FLAGS_RELEASE" not in provided:
            arguments.append("-DCMAKE_CXX_FLAGS_RELEASE=" + joined_release)
    return arguments


def _resolve_ipo_state(kind, config, enable_ipo, provided):
    """判定 Release IPO 状态：("on"/"off"/"preset", 退化原因或 None)。

    - 非 Release 配置不启用（不算退化）；
    - 配方经 `extra_args` 自带 IPO 变量时保持其取值（"preset"）；
    - `enable_ipo=False` / 环境变量 `CNP_NO_IPO` 显式关闭；`enable_ipo=True` 强制；
    - auto：编译器种类未知 → 退化；clang-cl 无 `lld-link` → 退化（需 lld 链接器）。
    """
    if str(config).lower() != "release":
        return "off", None
    if _IPO_CMAKE_VARIABLE in provided:
        return "preset", None
    if enable_ipo is False:
        return "off", "disabled-by-call"
    if _environment_flag(_DISABLE_IPO_ENV):
        return "off", "disabled-by-env"
    if enable_ipo is True:
        if kind is not None:
            return "on", None
        return "off", "unknown-compiler"
    if kind is None:
        return "off", "unknown-compiler"
    if kind == "clang-cl" and shutil.which(_IPO_LINKER_PROBE) is None:
        return "off", "lld-link-missing"
    return "on", None


def _environment_flag(name):
    """环境变量视为开启：非空且不是 0/false/no/off。"""
    value = os.environ.get(name, "").strip().lower()
    return value not in ("", "0", "false", "no", "off")


def _run_process(command, label):
    """运行子进程并逐行实时打印输出（stderr 合并进 stdout、UTF-8 容错）。

    返回 `subprocess.CompletedProcess` 形状的结果（`stdout` 为完整合并输出）；
    无法启动或非零退出抛 RuntimeError（后者携带输出末尾 [_OUTPUT_TAIL_LINES] 行）。
    """
    command = [str(part) for part in command]
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except OSError as error:
        raise RuntimeError(
            "%s 无法启动（%s）：%s" % (label, error, command[0])
        ) from error
    lines = []
    stream = process.stdout
    if stream is not None:
        for raw_line in stream:
            line = raw_line.rstrip("\r\n")
            lines.append(line)
            print(line, flush=True)
    returncode = process.wait()
    if returncode != 0:
        tail = "\n".join(lines[-_OUTPUT_TAIL_LINES:])
        raise RuntimeError(
            "%s 失败（退出码 %d）：%s\n%s"
            % (label, returncode, " ".join(command), tail)
        )
    return subprocess.CompletedProcess(command, returncode, "\n".join(lines), None)


def _is_header_name(name):
    return os.path.splitext(name)[1].lower() in HEADER_EXTENSIONS


def _has_debug_suffix(relative_path, suffix):
    """路径最后一段的 stem 是否以 `suffix` 结尾（大小写不敏感；空后缀不命中）。

    [relative_path] 传相对路径（含目录段）或仅文件名均可——判定只看最后一段，
    `bin/tbb12_debug.dll` 与 `tbb12_debug.dll` 命中，`tbb12d.dll` 不命中。
    """
    if not suffix:
        return False
    stem = os.path.splitext(os.path.basename(relative_path))[0].lower()
    return stem.endswith(suffix)


def _is_license_name(name):
    return bool(LICENSE_NAME_PATTERN.match(name.lower()))


def _license_core_rank(lowered_name):
    for index, core_name in enumerate(LICENSE_CORE_PRIORITY):
        if (
            lowered_name == core_name
            or lowered_name.startswith(core_name + "-")
            or lowered_name.startswith(core_name + ".")
        ):
            return index
    return len(LICENSE_CORE_PRIORITY)


def _find_primary_license_name(directory):
    best_key = None
    best_name = None
    entries = sorted(os.scandir(directory), key=lambda entry: entry.name.lower())
    for entry in entries:
        if not entry.is_file() or not _is_license_name(entry.name):
            continue
        lowered = entry.name.lower()
        key = (_license_core_rank(lowered), lowered)
        if best_key is None or key < best_key:
            best_key = key
            best_name = entry.name
    return best_name


def _is_intermediate_dir_name(name):
    lowered = name.lower()
    return lowered == "cmakefiles" or lowered.endswith(_INTERMEDIATE_DIR_SUFFIXES)


def _is_within(path, directory):
    path = os.path.normcase(os.path.abspath(path))
    directory = os.path.normcase(os.path.abspath(directory))
    return path == directory or path.startswith(directory + os.sep)


def _relative_forward_path(path, root):
    return os.path.relpath(path, root).replace(os.sep, "/")


def _normalize_excludes(exclude):
    if isinstance(exclude, (str, bytes, os.PathLike)):
        exclude = (exclude,)
    normalized = []
    for item in exclude:
        value = os.fsdecode(os.fspath(item)).replace("\\", "/").strip("/").lower()
        if value:
            normalized.append(value)
    return normalized


def _matches_exclude(relative, excludes):
    lowered = relative.lower()
    segments = lowered.split("/")
    for item in excludes:
        if "/" in item:
            if lowered == item or lowered.startswith(item + "/"):
                return True
        elif item in segments:
            return True
    return False


def _copy_file(source, destination):
    parent = os.path.dirname(destination)
    if parent:
        os.makedirs(parent, exist_ok=True)
    shutil.copy2(source, destination)


def _same_content(path_a, path_b):
    try:
        if os.path.getsize(path_a) != os.path.getsize(path_b):
            return False
        return filecmp.cmp(path_a, path_b, shallow=False)
    except OSError:
        return False


def _sanitize_suffix(name):
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", name).strip("_")
    return cleaned or "dup"


def _deduplicated_name(destination_dir, desired_name, source):
    """目标目录已有同名文件：内容相同返回 None（跳过），不同返回父目录后缀名。"""
    existing = os.path.join(destination_dir, desired_name)
    if not os.path.exists(existing):
        return desired_name
    if _same_content(existing, source):
        return None
    stem, extension = os.path.splitext(desired_name)
    suffix = _sanitize_suffix(
        os.path.basename(os.path.dirname(os.path.abspath(source)))
    )
    candidate = "%s_%s%s" % (stem, suffix, extension)
    counter = 2
    while os.path.exists(os.path.join(destination_dir, candidate)):
        if _same_content(os.path.join(destination_dir, candidate), source):
            return None
        candidate = "%s_%s%d%s" % (stem, suffix, counter, extension)
        counter += 1
    return candidate


def _reset_stage_segment(segment_dir):
    """递归删除单个配置段目录；不存在视为已清空，删除失败抛 RuntimeError。"""
    if not os.path.isdir(segment_dir):
        return
    try:
        shutil.rmtree(segment_dir)
    except OSError as error:
        raise RuntimeError(
            "重置输出段失败（%s）：%s" % (segment_dir, error)
        ) from error


def _stage_file(source, destination_dir, desired_name):
    """复制到目录并返回 'copied'/'skipped'；同名不同内容按父目录名后缀去重。"""
    final_name = _deduplicated_name(destination_dir, desired_name, source)
    if final_name is None:
        return "skipped"
    _copy_file(source, os.path.join(destination_dir, final_name))
    return "copied"
