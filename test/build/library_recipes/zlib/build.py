# https://github.com/madler/zlib.git
#
# zlib 配方：x64 + MD/MDd 双配置，Ninja 与编译器由工具环境注入。
# 同次构建产出共享库（zlib.dll + 导入库）与静态库（zlibs.lib），关闭测试可执行文件。
# 上游 CMake 目标名不稳定（v1.3.2 为 z/zs，develop 的 MSVC 分支为 libz），
# 构建前做受控文本补丁统一为用户期望的 zlib/zlibs 命名（Debug 经
# CMAKE_DEBUG_POSTFIX 得 d 后缀 → zlibd/zlibsd）。
# 逐配置独立 build 目录，并在 staging 前重置本配置段（reset=True），
# 杜绝跨配置扫描与同名去重改名（_build-*）残留。
#
# 契约：SRC_PATH / BUILD_OUT 由工具注入；产物分类走 cnp_build_support。

import os
import sys

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

CMAKE_ARGS = (
    "-DZLIB_BUILD_SHARED=ON",
    "-DZLIB_BUILD_STATIC=ON",
    "-DZLIB_BUILD_TESTING=OFF",
)

# 输出名补丁：上游 CMake 沿用 Unix 口径——v1.3.2 共享库为 `z`、静态库为
# `z${zlib_static_suffix}`，develop 分支的 MSVC 分支又写作 `libz...`；用户期望
# Windows 常规的 `zlib` 命名。构建前对 CMakeLists.txt 做受控文本替换：
# 已应用则跳过、目标文本未命中则报错（上游布局变化时不得静默沿用错误命名）。
_OUTPUT_NAME_PATCHES = (
    # develop 形态（MSVC 分支）：先替换 libz，避免后续 z 形态替换误伤。
    ("OUTPUT_NAME libz)", "OUTPUT_NAME zlib)"),
    (
        "ARCHIVE_OUTPUT_NAME libz${zlib_static_suffix})",
        "ARCHIVE_OUTPUT_NAME zlib${zlib_static_suffix})",
    ),
    # v1.3.2 共享库形态与 develop 非 MSVC 分支。
    ("OUTPUT_NAME z)", "OUTPUT_NAME zlib)"),
    # 静态库：v1.3.2 的跨行 `OUTPUT_NAME` 与 develop 的 ARCHIVE_OUTPUT_NAME
    # 均含 `z${zlib_static_suffix}`，统一并入 zlib 前缀。
    ("z${zlib_static_suffix})", "zlib${zlib_static_suffix})"),
)

_RC_OLD_TOKEN = '"zlib1.dll'
_RC_NEW_TOKEN = '"zlib.dll'


def _read_text(path):
    with open(path, "r", encoding="utf-8", newline="") as handle:
        return handle.read()


def _write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def patch_output_names(source_root):
    """把 CMake 输出目标名统一为 zlib / zlibs（幂等；未命中预期文本报错）。"""
    cmake_lists = os.path.join(source_root, "CMakeLists.txt")
    original = _read_text(cmake_lists)
    if (
        "OUTPUT_NAME zlib)" in original
        and "zlib${zlib_static_suffix})" in original
    ):
        print("[zlib-recipe] CMakeLists.txt 输出名补丁已应用，跳过", flush=True)
        return
    patched = original
    for old, new in _OUTPUT_NAME_PATCHES:
        patched = patched.replace(old, new)
    if "OUTPUT_NAME zlib)" not in patched:
        raise RuntimeError(
            "zlib 输出名补丁未命中共享库目标文本（预期 `OUTPUT_NAME z)` 或 "
            "`OUTPUT_NAME libz)`）：%s；上游 CMake 布局可能已变化，"
            "请检查配方 patch_output_names()" % cmake_lists
        )
    if "zlib${zlib_static_suffix})" not in patched:
        raise RuntimeError(
            "zlib 输出名补丁未命中静态库目标文本（预期 `z${zlib_static_suffix}` 或 "
            "`ARCHIVE_OUTPUT_NAME libz${zlib_static_suffix}`）：%s；上游 CMake 布局"
            "可能已变化，请检查配方 patch_output_names()" % cmake_lists
        )
    _write_text(cmake_lists, patched)
    print(
        "[zlib-recipe] CMakeLists.txt 输出名补丁已应用（zlib / zlibs）",
        flush=True,
    )


def patch_rc_metadata(source_root):
    """修正 win32/zlib1.rc 内嵌文件名 zlib1.dll → zlib.dll（可选元数据）。

    仅影响版本资源的一致性（实际文件名为 zlib.dll）；文件缺失或未命中时打印
    说明后跳过——产物命名由 CMake 补丁保证，不因可选元数据阻断上游布局演进。
    """
    rc_path = os.path.join(source_root, "win32", "zlib1.rc")
    if not os.path.isfile(rc_path):
        print("[zlib-recipe] 缺少 win32/zlib1.rc，跳过内嵌文件名补丁", flush=True)
        return
    original = _read_text(rc_path)
    patched = original.replace(_RC_OLD_TOKEN, _RC_NEW_TOKEN)
    if patched == original:
        if _RC_NEW_TOKEN in original:
            print("[zlib-recipe] zlib1.rc 内嵌文件名补丁已应用，跳过", flush=True)
        else:
            print(
                "[zlib-recipe] zlib1.rc 未命中 zlib1.dll 元数据，跳过（可选元数据）",
                flush=True,
            )
        return
    _write_text(rc_path, patched)
    print("[zlib-recipe] zlib1.rc 内嵌文件名已改为 zlib.dll", flush=True)


def build_config(config):
    build_dir = os.path.join(SRC_PATH, "build-" + config.lower())
    cmake_configure(SRC_PATH, build_dir, config=config, extra_args=CMAKE_ARGS)
    cmake_build(build_dir, config=config)
    stage_binaries(build_dir, BUILD_OUT, config=config, reset=True)
    return build_dir


def main():
    patch_output_names(SRC_PATH)
    patch_rc_metadata(SRC_PATH)
    release_build_dir = build_config("Release")
    build_config("Debug")
    # zlib.h 在源码根；zconf.h 由 CMake 按配置生成到构建目录。
    stage_headers(
        (
            os.path.join(SRC_PATH, "zlib.h"),
            os.path.join(release_build_dir, "zconf.h"),
        ),
        BUILD_OUT,
    )
    stage_license(SRC_PATH, BUILD_OUT)
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
