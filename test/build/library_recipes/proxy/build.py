# https://github.com/microsoft/proxy.git
#
# proxy 配方：纯头文件库（无编译）；镜像 include/proxy/**（含 v4 子目录）与源根许可证
# 到 BUILD_OUT。顶层 proxy.h 转发到 v4/proxy.h，两者都必须入包。
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
