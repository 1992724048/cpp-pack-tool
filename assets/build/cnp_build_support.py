"""cnp_build_support — cpp_nuget_pack 构建分类辅助模块（Python 3.8+，仅标准库）。

由 cpp_nuget_pack 构建管线释放到 tools/ 并经 PYTHONPATH 提供给 build.py：

    from cnp_build_support import cmake_configure, cmake_build
    from cnp_build_support import stage_headers, stage_binaries, stage_license, summary

    cmake_configure(SRC_PATH, BUILD_DIR, config='Release')
    cmake_build(BUILD_DIR, config='Release')
    stage_headers([SRC_PATH], BUILD_OUT)
    stage_binaries(BUILD_DIR, BUILD_OUT, config='Release')
    stage_license(SRC_PATH, BUILD_OUT)
    summary(BUILD_OUT)

输出布局（类 vcpkg 参考，非逐条复刻）：

    <out>/include/                头文件
    <out>/lib/                    静态库（非 Debug 路径段）
    <out>/bin/                    动态库 / 符号 / 可执行（非 Debug 路径段）
    <out>/debug/lib, debug/bin    Debug 配置产物
    <out>/<原文件名>              root 根部的许可证文件

CMake 相关函数读取 cpp_nuget_pack 注入的子进程环境变量：CNP_CMAKE、CNP_NINJA、
CNP_C_COMPILER、CNP_CXX_COMPILER；CNP_CMAKE 缺失或为空时给出明确错误。
"""

import filecmp
import os
import re
import shutil
import subprocess

VERSION = "2"

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

_CMAKE_RUNTIME_LIBRARY = "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
_OUTPUT_TAIL_LINES = 20
_INTERMEDIATE_DIR_SUFFIXES = (".dir", "-c")


def cmake_configure(source, build_dir, config="Release", extra_args=()):
    """以 Ninja 生成器配置 CMake 工程（单配置，运行时库 MD/MDd）。

    固定拼接 `-G Ninja`、`-DCMAKE_BUILD_TYPE`、`-DCMAKE_MSVC_RUNTIME_LIBRARY`；
    `CNP_NINJA`/`CNP_C_COMPILER`/`CNP_CXX_COMPILER` 存在时追加对应 `-D` 参数；
    `extra_args` 原样追加。子进程失败抛 RuntimeError（含输出尾部）。
    """
    cmake = _required_environment_path("CNP_CMAKE")
    command = [
        cmake,
        "-S",
        os.fspath(source),
        "-B",
        os.fspath(build_dir),
        "-G",
        "Ninja",
        "-DCMAKE_BUILD_TYPE=" + str(config),
        "-DCMAKE_MSVC_RUNTIME_LIBRARY=" + _CMAKE_RUNTIME_LIBRARY,
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
    command.extend(str(argument) for argument in extra_args)
    return _run_process(command, "cmake 配置")


def cmake_build(build_dir, config="Release", jobs=None):
    """以 `cmake --build` 构建已配置的工程（Ninja 单配置）。

    `jobs` 为正整数时追加 `--parallel <jobs>`；失败抛 RuntimeError（含输出尾部）。
    """
    cmake = _required_environment_path("CNP_CMAKE")
    command = [cmake, "--build", os.fspath(build_dir), "--config", str(config)]
    if jobs is not None and int(jobs) > 0:
        command.extend(("--parallel", str(int(jobs))))
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


def stage_binaries(build_dir, out, config="Release"):
    """递归收集构建树中的 `.lib/.dll/.pdb` 并按配置分类，返回计数 dict。

    - Release → `<out>/lib/`（.lib）与 `<out>/bin/`（.dll/.pdb）；
    - Debug → `<out>/debug/lib/` 与 `<out>/debug/bin/`；
    - 跳过 `CMakeFiles`、`*.dir`、`*-c` 中间目录与 `out` 自身；
    - 同名不同内容按父目录名后缀去重（同名同内容只保留一份）。

    返回 `{"copied": n, "lib": n, "bin": n, "skipped": n}`；`lib`/`bin` 为实际
    落点计数（Debug 时对应 debug/lib、debug/bin）。
    """
    build_dir = os.path.abspath(os.fspath(build_dir))
    out = os.path.abspath(os.fspath(out))
    if not os.path.isdir(build_dir):
        raise FileNotFoundError("构建目录不存在：%s" % build_dir)
    is_debug = str(config).lower() == "debug"
    lib_dir = os.path.join(out, "debug", "lib") if is_debug else os.path.join(out, "lib")
    bin_dir = os.path.join(out, "debug", "bin") if is_debug else os.path.join(out, "bin")

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


def classify_tree(root, out, exclude=()):
    """把预构建产物树分类到类 vcpkg 布局，返回各类计数 dict。

    - 头文件 → `<out>/include/`（保留相对结构）；
    - `.lib/.a` → `<out>/lib/`，`.dll/.pdb/.exe` → `<out>/bin/`；
    - 相对路径中任一段小写为 `debug` 时分别落 `<out>/debug/lib`、`<out>/debug/bin`；
    - `root` **根部**的许可证名文件 → `<out>/` 根（保留原文件名）；
    - 跳过 `.git`、`exclude` 命中项（相对路径或名称）与 `out` 自身；其余文件跳过。

    计数键：include / lib / bin / debug_lib / debug_bin / license。
    """
    root = os.path.abspath(os.fspath(root))
    out = os.path.abspath(os.fspath(out))
    if not os.path.isdir(root):
        raise FileNotFoundError("目录不存在：%s" % root)
    excludes = _normalize_excludes(exclude)
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
            is_debug = "debug" in lowered_segments
            if extension in HEADER_EXTENSIONS:
                destination_dir = os.path.join(
                    out, "include", os.path.dirname(relative)
                )
                category = "include"
            elif extension in LIBRARY_EXTENSIONS:
                destination_dir = os.path.join(
                    out, "debug", "lib"
                ) if is_debug else os.path.join(out, "lib")
                category = "debug_lib" if is_debug else "lib"
            elif extension in BINARY_EXTENSIONS:
                destination_dir = os.path.join(
                    out, "debug", "bin"
                ) if is_debug else os.path.join(out, "bin")
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

    返回键：include / lib / bin / debug_lib / debug_bin / license / other /
    files / bytes；输出树不存在时打印零统计。
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
                if segments[0] == "debug" and len(segments) >= 2 and segments[1] == "lib":
                    category = "debug_lib"
                elif segments[0] == "debug" and len(segments) >= 2 and segments[1] == "bin":
                    category = "debug_bin"
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
        )
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


def _run_process(command, label):
    try:
        result = subprocess.run(
            [str(part) for part in command],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        raise RuntimeError(
            "%s 无法启动（%s）：%s" % (label, error, command[0])
        ) from error
    if result.returncode != 0:
        output = result.stdout or ""
        tail = "\n".join(output.splitlines()[-_OUTPUT_TAIL_LINES:])
        raise RuntimeError(
            "%s 失败（退出码 %d）：%s\n%s"
            % (label, result.returncode, " ".join(str(part) for part in command), tail)
        )
    return result


def _is_header_name(name):
    return os.path.splitext(name)[1].lower() in HEADER_EXTENSIONS


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


def _stage_file(source, destination_dir, desired_name):
    """复制到目录并返回 'copied'/'skipped'；同名不同内容按父目录名后缀去重。"""
    final_name = _deduplicated_name(destination_dir, desired_name, source)
    if final_name is None:
        return "skipped"
    _copy_file(source, os.path.join(destination_dir, final_name))
    return "copied"
