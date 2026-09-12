# https://github.com/microsoft/mimalloc.git
#
# mimalloc 配方：x64 + MD/MDd 双配置，Ninja 与编译器由工具环境注入。
# 事实记录（2026-09-13 核实）：远端默认分支为 main3；CMake 选项 MI_BUILD_SHARED/
# MI_BUILD_STATIC 默认 ON（Release 产出 mimalloc.dll + 导入库 mimalloc.dll.lib +
# 静态库 mimalloc.lib；Debug 因 mi_libname 追加 -debug 后缀为 mimalloc-debug.*）。
#
# minject.exe：CMake 无该构建目标——仓库 bin/ 内为预构建 x64 工具（CMake 仅在其
# 测试目标后处理时引用 bin/minject.exe，见 CMakeLists.txt MINJECT_SUFFIX / 测试节）。
# 本配方从 SRC_PATH/bin/minject.exe 直接复制，与构建配置无关，release/bin（Release
# 默认注入工具）与 debug/bin 各放一份入包（minject32/minject-arm64 不属 x64 包）。
# mimalloc-redirect.dll：仓库 bin/ 内预构建（minject 使用前提）；共享库构建时
# MI_WIN_REDIRECT=ON（默认）将其复制到构建输出目录，由 stage_binaries 随配置分类。
#
# post.bat：在 BUILD_OUT 根生成，消费方构建后以 `post.bat <目标可执行文件>` 调用，
# minject 以 --force --inplace 就地注入 Release 的 mimalloc.dll；注入失败不阻断
# 消费者构建（脚本恒 exit /b 0），兼容 minject --help 用法（-f / -i / --postfix）。
#
# 契约：SRC_PATH / BUILD_OUT 由工具注入；产物分类走 cnp_build_support。

import os
import shutil
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

# MI_BUILD_TESTS=OFF：测试可执行文件不属包布局；MI_BUILD_OBJECT=OFF：单对象静态
# 文件 mimalloc.obj 不属包布局，且会触发第三次全量编译。
CMAKE_ARGS = (
    "-DMI_BUILD_TESTS=OFF",
    "-DMI_BUILD_OBJECT=OFF",
)

# MI_NO_USE_CXX=ON（仅 ICX）：mimalloc 的 CMake 对 MSVC/Intel 类编译器强制
# MI_USE_CXX=ON，而 icx-cl 默认未启用 C++ 异常——alloc.c 的裸 try/catch 直接
# 编译失败（实测：alloc.c(770) "cannot use 'try' with exceptions disabled"）。
# 官方 MI_NO_USE_CXX 切换纯 C 编译（Windows 经典路线）后 ICX 双配置构建通过；
# clang-cl（默认启用异常）与 MSVC（CMake 自动注入 /EHsc）保持 C++ 路线。
_ICX_EXTRA_ARGS = ("-DMI_NO_USE_CXX=ON",)

POST_BAT_CONTENT = (
    "@echo off\r\n"
    "rem 由 cpp_nuget_pack 构建管线生成；系统脚本，请勿修改。\r\n"
    "rem 将 mimalloc 注入消费者可执行文件（%~1 = 目标 exe 路径）；注入失败不阻断构建。\r\n"
    'if "%~1"=="" exit /b 0\r\n'
    '"%~dp0release\\bin\\minject.exe" --force --inplace "%~1"\r\n'
    "exit /b 0\r\n"
)


def compiler_uses_icx():
    """工具注入的编译器是否为 ICX（CNP_C_COMPILER 优先，回退 CNP_CXX_COMPILER）。"""
    name = os.path.basename(
        (
            os.environ.get("CNP_C_COMPILER")
            or os.environ.get("CNP_CXX_COMPILER")
            or ""
        ).strip()
    ).lower()
    return name.startswith("icx")


def cmake_arguments():
    arguments = [str(argument) for argument in CMAKE_ARGS]
    if compiler_uses_icx():
        arguments.extend(_ICX_EXTRA_ARGS)
    return arguments


def build_config(config):
    build_dir = os.path.join(SRC_PATH, "build-" + config.lower())
    cmake_configure(
        SRC_PATH, build_dir, config=config, extra_args=cmake_arguments()
    )
    cmake_build(build_dir, config=config)
    stage_binaries(build_dir, BUILD_OUT, config=config)


def stage_minject():
    source = os.path.join(SRC_PATH, "bin", "minject.exe")
    if not os.path.isfile(source):
        raise FileNotFoundError(
            "minject.exe 不存在（仓库 bin/ 布局可能已变化）：%s" % source
        )
    for directory in (
        os.path.join(BUILD_OUT, "release", "bin"),
        os.path.join(BUILD_OUT, "debug", "bin"),
    ):
        os.makedirs(directory, exist_ok=True)
        shutil.copy2(source, os.path.join(directory, "minject.exe"))
    write_post_bat()
    print(
        "[mimalloc] staged minject=release/bin+debug/bin post.bat=%s"
        % os.path.join(BUILD_OUT, "post.bat")
    )


def write_post_bat():
    """生成 post.bat：消费方以 `post.bat <exe>` 就地注入 mimalloc（失败不阻断）。"""
    path = os.path.join(BUILD_OUT, "post.bat")
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(POST_BAT_CONTENT)


def main():
    for config in ("Release", "Debug"):
        build_config(config)
    # include/ 布局：mimalloc.h / mimalloc-override.h / mimalloc-new-delete.h /
    # mimalloc-stats.h + mimalloc/ 子目录（types.h 等），整体镜像。
    stage_headers(os.path.join(SRC_PATH, "include"), BUILD_OUT)
    stage_minject()
    stage_license(SRC_PATH, BUILD_OUT)
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
