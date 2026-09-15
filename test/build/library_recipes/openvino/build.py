# https://github.com/openvinotoolkit/openvino.git
# source: none
# option: tbb = off | on
#
# OpenVINO 预构建配方（P3 L6）
#
# 预构建分发：下载官方 Windows 预构建包并分类入库，不编译源码；
# `# source: none` 使工具跳过 git，SRC_PATH 仅作下载/解压工作区。
#
# 事实记录（2026-09-13 经官方包索引核实）：
# - 包索引：https://storage.openvinotoolkit.org/repositories/openvino/packages/
#   （索引 HTML 为 JS 渲染，版本枚举来自官方页面同源数据 filetree.json）；
#   当日最新稳定 2026.3.1 → windows/openvino_toolkit_windows_2026.3.1.22476.56d9685302d_x86_64.zip
#   （207,590,029 字节，sha256 1f94cd7dd2f3b54fe8f0d3f7f77fe0c7d5ac317aaa65ab352d6cbb0459a978b1）。
# - 归档布局（单顶层目录）：
#     runtime/include/openvino/**                 头文件（命名空间 openvino/）
#     runtime/lib/intel64/{Release,Debug}/*.lib   导入库
#     runtime/bin/intel64/{Release,Debug}/*.dll   动态库
#     runtime/3rdparty/tbb/{bin,include,lib}      自带 oneTBB
#     docs/licensing/LICENSE                      Apache-2.0（另含第三方声明）
# - tbb 选项：off（默认）不打包自带 TBB——避免与 ICX / clang-cl 自带 TBB 冲突，
#   消费方自备；on 时完整保留（dll → bin/、头 → include/tbb/、lib → lib/）。
#
# 缓存策略：归档与解压树都落在 SRC_PATH 下并带完成标记，二次构建直接复用，
# 避免 200MB 级重复下载与解压。
#
# 契约：SRC_PATH / BUILD_OUT 由工具注入；产物只落 BUILD_OUT。

import json
import os
import re
import shutil
import sys
import time
import urllib.request
import zipfile

from cnp_build_support import classify_tree, stage_license, summary

SRC_PATH = os.environ["SRC_PATH"]
BUILD_OUT = os.environ["BUILD_OUT"]
TBB_OPTION = os.environ.get("CNP_OPTION_TBB", "off").strip().lower()

FILETREE_URL = "https://storage.openvinotoolkit.org/filetree.json"
PACKAGE_BASE_URL = (
    "https://storage.openvinotoolkit.org/repositories/openvino/packages/"
)
_WINDOWS_ZIP_PATTERN = re.compile(
    r"^openvino_toolkit_windows_(\d{4}\.\d+\.\d+)(?:\.[0-9A-Za-z]+)*_x86_64\.zip$"
)
_VERSION_DIR_PATTERN = re.compile(r"^\d{4}\.\d+(?:\.\d+)?$")
# 解析失败回退（2026-09-13 核实为当日最新稳定版）
FALLBACK_URL = (
    PACKAGE_BASE_URL
    + "2026.3.1/windows/openvino_toolkit_windows_2026.3.1.22476.56d9685302d_x86_64.zip"
)


def _find_child_directory(node, name):
    for child in node.get("children", ()):
        if child.get("type") == "directory" and child.get("name") == name:
            return child
    return None


def _version_key(version):
    return tuple(int(part) for part in version.split("."))


def resolve_latest_archive_url():
    """读官方 filetree.json 取最新稳定版 Windows x64 归档 URL；失败回退内置常量。"""
    try:
        with urllib.request.urlopen(FILETREE_URL, timeout=120) as response:
            tree = json.loads(response.read().decode("utf-8", "replace"))
    except Exception as error:
        print("[openvino] filetree 读取失败，回退内置版本：%s" % error)
        return FALLBACK_URL
    packages = tree
    for segment in ("repositories", "openvino", "packages"):
        packages = _find_child_directory(packages, segment)
        if packages is None:
            print("[openvino] filetree 缺少 packages 节点，回退内置版本")
            return FALLBACK_URL
    candidates = []
    for version_dir in packages.get("children", ()):
        if version_dir.get("type") != "directory":
            continue
        if not _VERSION_DIR_PATTERN.match(version_dir.get("name", "")):
            continue
        windows = _find_child_directory(version_dir, "windows")
        if windows is None:
            continue
        for entry in windows.get("children", ()):
            match = _WINDOWS_ZIP_PATTERN.match(entry.get("name", ""))
            if match is None:
                continue
            candidates.append(
                (_version_key(match.group(1)), version_dir["name"], entry["name"])
            )
    if not candidates:
        print("[openvino] filetree 未找到 Windows 归档，回退内置版本")
        return FALLBACK_URL
    _, version_dir_name, file_name = max(candidates)
    return "%s%s/windows/%s" % (PACKAGE_BASE_URL, version_dir_name, file_name)


def download_archive(url):
    """下载归档到 SRC_PATH/downloads（存在即复用）；先写 .part 再改名。"""
    downloads_dir = os.path.join(SRC_PATH, "downloads")
    os.makedirs(downloads_dir, exist_ok=True)
    archive = os.path.join(downloads_dir, os.path.basename(url))
    if os.path.isfile(archive) and os.path.getsize(archive) > 0:
        print(
            "[openvino] reuse cached archive: %s (%d bytes)"
            % (archive, os.path.getsize(archive))
        )
        return archive
    print("[openvino] downloading: %s" % url)
    started = time.time()
    partial = archive + ".part"
    with urllib.request.urlopen(url, timeout=600) as response:
        total = int(response.headers.get("Content-Length") or 0)
        downloaded = 0
        next_report = 0
        with open(partial, "wb") as handle:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                handle.write(chunk)
                downloaded += len(chunk)
                if total and downloaded >= next_report:
                    print(
                        "[openvino] progress %.1f%% (%d/%d bytes)"
                        % (100.0 * downloaded / total, downloaded, total)
                    )
                    next_report = downloaded + total // 10
    os.replace(partial, archive)
    print(
        "[openvino] downloaded: bytes=%d elapsed=%.1fs"
        % (os.path.getsize(archive), time.time() - started)
    )
    return archive


def ensure_unpacked(archive):
    """解压归档到 SRC_PATH/unpacked；完成标记记录归档名，二次运行按名复用。

    标记与归档身份绑定：官方版本升级后归档文件名变化，旧解压树被丢弃重解压，
    避免复用陈旧产物；同名归档（本地已是最新）直接复用。
    """
    unpacked = os.path.join(SRC_PATH, "unpacked")
    complete = os.path.join(unpacked, ".complete")
    archive_name = os.path.basename(archive)
    if os.path.isfile(complete):
        try:
            with open(complete, "r", encoding="utf-8") as handle:
                completed_archive = handle.read().strip()
        except OSError:
            completed_archive = ""
        if completed_archive == archive_name:
            print("[openvino] reuse unpacked tree: %s" % unpacked)
            return unpacked
        print(
            "[openvino] stale unpacked tree (archive %s -> %s), re-extracting"
            % (completed_archive or "<none>", archive_name)
        )
    if os.path.isdir(unpacked):
        shutil.rmtree(unpacked)
    print("[openvino] extracting: %s" % archive)
    started = time.time()
    os.makedirs(unpacked, exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        package.extractall(unpacked)
    with open(complete, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(archive_name + "\n")
    print("[openvino] extracted: elapsed=%.1fs" % (time.time() - started))
    return unpacked


def find_package_root(unpacked):
    """返回含 runtime/ 的包根：归档为单顶层目录时下钻一层。"""
    if os.path.isdir(os.path.join(unpacked, "runtime")):
        return unpacked
    for name in sorted(os.listdir(unpacked)):
        candidate = os.path.join(unpacked, name)
        if os.path.isdir(candidate) and os.path.isdir(
            os.path.join(candidate, "runtime")
        ):
            return candidate
    raise RuntimeError("归档中未找到含 runtime/ 的包根目录：%s" % unpacked)


def stage_runtime(package_root):
    """runtime/{include,lib,bin} 分别经 classify_tree 分类（docs/samples/python 不参与）。"""
    runtime = os.path.join(package_root, "runtime")
    for name in ("include", "lib", "bin"):
        subtree = os.path.join(runtime, name)
        if not os.path.isdir(subtree):
            raise FileNotFoundError("runtime/%s 目录不存在：%s" % (name, subtree))
        counts = classify_tree(subtree, BUILD_OUT)
        print("[openvino] runtime/%s counts=%s" % (name, counts))


def stage_tbb(package_root):
    """tbb=on：完整保留自带 oneTBB（含 TBB-LICENSE）。

    Debug 变体与 Release 同目录存放（`tbb12_debug.dll/.lib` 等），经
    `debug_name_suffix` 按文件名后缀归入 `debug/` 分层。
    """
    tbb_root = os.path.join(package_root, "runtime", "3rdparty", "tbb")
    if not os.path.isdir(tbb_root):
        raise FileNotFoundError("TBB 目录不存在（归档布局可能已变化）：%s" % tbb_root)
    staged = 0
    for name in ("include", "lib", "bin"):
        subtree = os.path.join(tbb_root, name)
        if not os.path.isdir(subtree):
            continue
        counts = classify_tree(subtree, BUILD_OUT, debug_name_suffix="_debug")
        staged += sum(
            counts[key] for key in ("include", "lib", "bin", "debug_lib", "debug_bin")
        )
        print("[openvino] tbb/%s counts=%s" % (name, counts))
    tbb_license = os.path.join(tbb_root, "TBB-LICENSE")
    if os.path.isfile(tbb_license):
        shutil.copy2(tbb_license, os.path.join(BUILD_OUT, "TBB-LICENSE"))
    print("[openvino] tbb staged files=%d (option=on)" % staged)


def prune_tbb_files():
    """tbb=off 兜底：BUILD_OUT 中任何段名以 tbb 开头的文件零残留。"""
    removed = []
    for current, _directory_names, file_names in os.walk(BUILD_OUT):
        for file_name in sorted(file_names):
            path = os.path.join(current, file_name)
            relative = os.path.relpath(path, BUILD_OUT)
            segments = relative.replace("\\", "/").lower().split("/")
            if not any(segment.startswith("tbb") for segment in segments):
                continue
            os.remove(path)
            removed.append(relative.replace("\\", "/"))
    print(
        "[openvino] tbb remnants removed=%d %s" % (len(removed), sorted(removed))
    )


def stage_openvino_license(package_root):
    """Apache-2.0（docs/licensing/LICENSE）→ BUILD_OUT 根；缺失回退 runtime 根。"""
    licensing_dir = os.path.join(package_root, "docs", "licensing")
    if os.path.isdir(licensing_dir):
        destination = stage_license(licensing_dir, BUILD_OUT)
        if destination is not None:
            return destination
    runtime_dir = os.path.join(package_root, "runtime")
    if os.path.isdir(runtime_dir):
        destination = stage_license(runtime_dir, BUILD_OUT)
        if destination is not None:
            return destination
    print("[openvino] 警告：未找到许可证文件（docs/licensing 与 runtime 根均无）")
    return None


def main():
    print("[openvino] option tbb=%s" % TBB_OPTION)
    url = resolve_latest_archive_url()
    print("[openvino] archive url=%s" % url)
    archive = download_archive(url)
    unpacked = ensure_unpacked(archive)
    package_root = find_package_root(unpacked)
    print("[openvino] package root=%s" % package_root)
    stage_runtime(package_root)
    if TBB_OPTION == "on":
        stage_tbb(package_root)
    else:
        prune_tbb_files()
    print("[openvino] license=%s" % stage_openvino_license(package_root))
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
