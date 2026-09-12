# https://github.com/madler/zlib.git
#
# zlib 配方：x64 + MD/MDd 双配置，Ninja 与编译器由工具环境注入。
# 同次构建产出共享库（libz.dll + 导入库）与静态库（libzs.lib），关闭测试可执行文件。
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


def build_config(config):
    build_dir = os.path.join(SRC_PATH, "build-" + config.lower())
    cmake_configure(SRC_PATH, build_dir, config=config, extra_args=CMAKE_ARGS)
    cmake_build(build_dir, config=config)
    stage_binaries(build_dir, BUILD_OUT, config=config)
    return build_dir


def main():
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
