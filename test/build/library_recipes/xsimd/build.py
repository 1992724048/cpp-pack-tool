# https://github.com/xtensor-stack/xsimd.git
#
# xsimd 配方：纯头文件库（无编译）；镜像 include/xsimd/** 与源根许可证到 BUILD_OUT。
#
# 契约：SRC_PATH / BUILD_OUT 由工具注入；产物分类走 cnp_build_support。

import os
import sys

from cnp_build_support import stage_headers, stage_license, summary

SRC_PATH = os.environ["SRC_PATH"]
BUILD_OUT = os.environ["BUILD_OUT"]


def main():
    stage_headers(os.path.join(SRC_PATH, "include"), BUILD_OUT)
    stage_license(SRC_PATH, BUILD_OUT)
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
