# https://github.com/sqlite/sqlite.git
#
# sqlite3 配方（P3 L4）：官方 GitHub 镜像无 CMakeLists.txt（2026-09-13 经 GitHub API
# 核实），其自带构建（configure / Makefile.msc）依赖 TCL 生成 sqlite3.h 与
# amalgamation，工具环境不保证 —— 选定官方 amalgamation 源路线（实施时最稳）：
#   1. 解析 https://sqlite.org/download.html 的 PRODUCT 行取最新
#      sqlite-amalgamation-<版本>.zip；实测 3.53.4 →
#      https://sqlite.org/2026/sqlite-amalgamation-3530400.zip（2.9 MB）；
#   2. 解压出 sqlite3.c / sqlite3.h / sqlite3ext.h，就地生成最小 CMakeLists.txt
#      （SHARED sqlite3 + SQLITE_API=__declspec(dllexport) 导出全部 API）；
#   3. 经 cnp_build_support 的 cmake_configure / cmake_build 双配置（Release MD /
#      Debug MDd）构建，stage_binaries 收集导入库与 DLL。
#
# 许可证：镜像根 LICENSE.md（Public Domain 声明）经 stage_license 落 BUILD_OUT 根。

import os
import re
import shutil
import sys
import urllib.request
import zipfile

from cnp_build_support import (
    cmake_build,
    cmake_configure,
    stage_binaries,
    stage_headers,
    stage_license,
    summary,
)

SRC_PATH = os.environ["SRC_PATH"]
BUILD_OUT = os.environ["BUILD_OUT"]

DOWNLOAD_PAGE = "https://sqlite.org/download.html"
_AMALGAMATION_PRODUCT = re.compile(
    r"PRODUCT,([0-9][0-9.]*),([^,\s]+/sqlite-amalgamation-[0-9]+\.zip),"
)
# 定义值必须带引号：CMake 未引号参数中的括号会被截断
# （`SQLITE_API=__declspec`），导致编译期 __declspec 缺参数报错。
_MINIMAL_CMAKE_LISTS = """cmake_minimum_required(VERSION 3.20)
project(sqlite3 C)

add_library(sqlite3 SHARED sqlite3.c)
target_compile_definitions(sqlite3 PRIVATE "SQLITE_API=__declspec(dllexport)")
"""


def resolve_amalgamation():
    """下载页 PRODUCT 行 → (版本, 官方 zip 绝对 URL)。"""
    with urllib.request.urlopen(DOWNLOAD_PAGE, timeout=60) as response:
        page = response.read().decode("utf-8", "replace")
    match = _AMALGAMATION_PRODUCT.search(page)
    if match is None:
        raise RuntimeError("下载页未找到 sqlite-amalgamation 条目：%s" % DOWNLOAD_PAGE)
    location = match.group(2)
    url = location if location.startswith("http") else "https://sqlite.org/" + location
    return match.group(1), url


def download_file(url, destination):
    with urllib.request.urlopen(url, timeout=120) as response:
        with open(destination, "wb") as handle:
            shutil.copyfileobj(response, handle)


def find_amalgamation_root(directory):
    for current, _directory_names, file_names in os.walk(directory):
        if "sqlite3.c" in file_names and "sqlite3.h" in file_names:
            return current
    raise RuntimeError("解压结果中未找到 sqlite3.c / sqlite3.h：%s" % directory)


def prepare_amalgamation():
    """下载并解压官方 amalgamation，返回含 sqlite3.c 的源码目录。"""
    version, url = resolve_amalgamation()
    archive = os.path.join(SRC_PATH, "downloads", os.path.basename(url))
    os.makedirs(os.path.dirname(archive), exist_ok=True)
    download_file(url, archive)
    extract_root = os.path.join(SRC_PATH, "amalgamation")
    if os.path.isdir(extract_root):
        shutil.rmtree(extract_root)
    with zipfile.ZipFile(archive) as package:
        package.extractall(extract_root)
    source_dir = find_amalgamation_root(extract_root)
    cmake_lists = os.path.join(source_dir, "CMakeLists.txt")
    with open(cmake_lists, "w", encoding="utf-8") as handle:
        handle.write(_MINIMAL_CMAKE_LISTS)
    print(
        "[sqlite3] amalgamation version=%s url=%s archiveBytes=%d sourceDir=%s"
        % (version, url, os.path.getsize(archive), source_dir)
    )
    return source_dir


def build_config(source_dir, config):
    build_dir = os.path.join(SRC_PATH, "build-" + config.lower())
    cmake_configure(source_dir, build_dir, config=config)
    cmake_build(build_dir, config=config)
    counts = stage_binaries(build_dir, BUILD_OUT, config=config)
    print("[sqlite3] staged config=%s counts=%s" % (config, counts))


def main():
    print(
        "[sqlite3] route=amalgamation mirrorHasCMakeLists=%s"
        % os.path.isfile(os.path.join(SRC_PATH, "CMakeLists.txt"))
    )
    source_dir = prepare_amalgamation()
    for config in ("Release", "Debug"):
        build_config(source_dir, config)
    stage_headers(
        (
            os.path.join(source_dir, "sqlite3.h"),
            os.path.join(source_dir, "sqlite3ext.h"),
        ),
        BUILD_OUT,
    )
    stage_license(SRC_PATH, BUILD_OUT)
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
