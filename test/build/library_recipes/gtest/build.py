# https://github.com/google/googletest.git
#
# googletest 配方：源码分发形态（无 lib/dll，消费者随自身工程编译 gtest-all.cc /
# gmock-all.cc）。不执行任何编译，仅取源码并分类布置：
#
#   googletest/include  → BUILD_OUT/include/（镜像出 include/gtest/**）
#   googlemock/include  → BUILD_OUT/include/（镜像出 include/gmock/**）
#   googletest/src      → BUILD_OUT/src/gtest/（整树复制：.cc + 内部 .h）
#   googlemock/src      → BUILD_OUT/src/gmock/（整树复制）
#   LICENSE             → BUILD_OUT 根（经 stage_license）
#
# 契约：SRC_PATH / BUILD_OUT 由工具注入；重复执行幂等（按文件覆盖写）。

import os
import shutil
import sys

from cnp_build_support import stage_headers, stage_license, summary

SRC_PATH = os.environ["SRC_PATH"]
BUILD_OUT = os.environ["BUILD_OUT"]

HEADER_SOURCE_DIRS = (
    os.path.join(SRC_PATH, "googletest", "include"),
    os.path.join(SRC_PATH, "googlemock", "include"),
)

SOURCE_DIRS = (
    (os.path.join(SRC_PATH, "googletest", "src"), "gtest"),
    (os.path.join(SRC_PATH, "googlemock", "src"), "gmock"),
)


def copy_tree(source, destination):
    """整树复制目录内容到 destination，返回复制文件数（顺序确定、覆盖幂等）。"""
    if not os.path.isdir(source):
        raise FileNotFoundError("源码目录不存在：%s" % source)
    copied = 0
    for current, directory_names, file_names in os.walk(source):
        directory_names.sort()
        for file_name in sorted(file_names):
            relative = os.path.relpath(os.path.join(current, file_name), source)
            target = os.path.join(destination, relative)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(os.path.join(current, file_name), target)
            copied += 1
    return copied


def main():
    header_count = 0
    for include_dir in HEADER_SOURCE_DIRS:
        header_count += stage_headers(include_dir, BUILD_OUT)

    source_count = 0
    for source_dir, name in SOURCE_DIRS:
        source_count += copy_tree(
            source_dir,
            os.path.join(BUILD_OUT, "src", name),
        )

    license_path = stage_license(SRC_PATH, BUILD_OUT)
    print(
        "[gtest] headers=%d sources=%d license=%s"
        % (
            header_count,
            source_count,
            os.path.basename(license_path) if license_path else "none",
        )
    )
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
