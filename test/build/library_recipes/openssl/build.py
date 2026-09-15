# https://github.com/openssl/openssl.git
# tool: nasm https://www.nasm.us/pub/nasm/releasebuilds/3.02/win64/nasm-3.02-win64.zip
# tool: perl https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54051_64bit/strawberry-perl-5.40.5.1-64bit-portable.zip bin=perl/bin
#
# OpenSSL 配方（P3 L7）：「# tool 环境工具」机制验收——NASM 与 Strawberry Perl
# 由工具在准备阶段自动下载解压到 tools/ 并注入 PATH（本机无 perl/nasm 预装）。
#
# 外部事实（2026-09-13 核验）：
# - NASM 3.02 官方 win64 包（约 0.6 MB）单层根 nasm-3.02/ 被供给器剥离，nasm.exe
#   直接位于 tools/nasm/；OpenSSL Configure 以 `nasm -v` 探测（>= 2.09 生效），
#   命中后 x64 程序集经 nasm 生成并汇编（缺 NASM 时报错，不会静默回退）。
# - Strawberry Perl 5.40.5.1 portable（约 311 MB；官网 releases.json 2026-09-13
#   首个 64bit 条目）：官网 /download/<版本>/<文件名> 直链已 404，改用官网同源的
#   GitHub release 资产直链；zip 含多个顶层目录，perl.exe 位于 perl/bin，
#   故声明 bin=perl/bin。
# - 工具目录路径含空格：Configure 以 PERL=perl 写入 Makefile（而非 $^X 绝对路径），
#   构建期经注入的 PATH 解析，规避 nmake 配方中的路径空格问题。
#
# 构建方案（out-of-tree：空构建目录跑 `perl <源码>/Configure VC-WIN64A` + nmake）：
# - 目标 VC-WIN64A（x64）；Debug 用官方 debug- 前缀目标（/Od /MDd /Zi）。
# - 编译器按工具注入的编译器（CNP_C_COMPILER/CNP_CXX_COMPILER）选择：首选 ICX
#   （icx-cl，cl 兼容驱动）；若 ICX 路线 Configure/nmake 失败，自动回退 clang-cl
#   （PATH 可解析时）并打印失败证据；MSVC 注入时用 cl。注入值为全路径且 oneAPI
#   目录含空格，nmake 无法可靠展开含空格的 $(CC)，故按可执行文件名映射为命令名
#   （编译器目录已由工具注入 PATH：setvars.bat / LLVM bin）。
# - 收窄范围：no-makedepend（免二次依赖扫描）、no-docs；`nmake build_libs` 只出
#   libcrypto/libssl（含导入库与 DLL），不出 apps/tests 可执行文件。
# - 头文件：源码 include/openssl 的静态头 + 构建树 include/openssl 的生成头
#   （ssl.h/configuration.h 等 .in 模板产物），合并镜像到 include/openssl。
#
# 产物：Release → release/lib + release/bin；Debug → debug/lib + debug/bin；许可证
# LICENSE.txt 经 stage_license 落 BUILD_OUT 根；中间构建目录位于 SRC_PATH 下。

import os
import shutil
import subprocess
import sys

from cnp_build_support import (
    stage_binaries,
    stage_headers,
    stage_license,
    summary,
)

SRC_PATH = os.environ["SRC_PATH"]
BUILD_OUT = os.environ["BUILD_OUT"]

CONFIG_TARGETS = {
    "Release": "VC-WIN64A",
    "Debug": "debug-VC-WIN64A",
}
CONFIGURE_FLAGS = ("no-makedepend", "no-docs")
_OUTPUT_TAIL_LINES = 40


def run(command, cwd):
    """执行命令：成功打印输出尾部，失败打印完整输出并抛 RuntimeError。"""
    print("[openssl] run: %s" % " ".join(command))
    result = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        encoding="utf-8",
        errors="replace",
    )
    output = result.stdout or ""
    if result.returncode != 0:
        print(output)
        raise RuntimeError(
            "命令失败（退出码 %d）：%s" % (result.returncode, " ".join(command))
        )
    for line in output.splitlines()[-_OUTPUT_TAIL_LINES:]:
        print("[openssl]   " + line)
    return output


def probe(command):
    """证据命令：打印输出摘要，失败不中断构建。"""
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        print("[openssl] probe %s failed: %s" % (" ".join(command), error))
        return
    lines = [line for line in (result.stdout or "").splitlines() if line.strip()]
    print(
        "[openssl] probe %s -> %s"
        % (" ".join(command), " | ".join(lines[:2]) or "(no output)")
    )


def injected_compiler_name():
    """工具注入编译器的可执行文件名（CNP_C_COMPILER 优先，回退 CNP_CXX_COMPILER）。"""
    value = (
        os.environ.get("CNP_C_COMPILER")
        or os.environ.get("CNP_CXX_COMPILER")
        or ""
    ).strip()
    return os.path.basename(value).lower()


def compiler_route():
    """返回 (路线标签, Configure CC/CXX 变量)：首选工具注入的 ICX。

    注入的编译器全路径无法直接交给 nmake（oneAPI 路径含空格），映射为注入
    PATH 中的命令名；识别不出时按 MSVC cl 处理。
    """
    name = injected_compiler_name()
    if name.startswith("icx"):
        return "icx", ["CC=icx-cl", "CXX=icx-cl"]
    if name.startswith("clang"):
        return "clang-cl", ["CC=clang-cl", "CXX=clang-cl"]
    return "msvc", ["CC=cl", "CXX=cl"]


def fallback_route(failed_label):
    """ICX 路线失败时的回退路线（clang-cl，需 PATH 可解析）；其余路线无回退。"""
    if failed_label != "icx" or shutil.which("clang-cl") is None:
        return None
    return "clang-cl", ["CC=clang-cl", "CXX=clang-cl"]


def configure(config, build_dir, label, variables):
    command = [
        "perl",
        os.path.join(SRC_PATH, "Configure"),
        CONFIG_TARGETS[config],
    ]
    command.extend(CONFIGURE_FLAGS)
    command.extend(variables)
    command.append("PERL=perl")
    run(command, build_dir)
    print(
        "[openssl] configured target=%s dir=%s compilerRoute=%s"
        % (CONFIG_TARGETS[config], build_dir, label)
    )
    return build_dir


def stage_openssl_headers(release_build_dir):
    """合并源码静态头与构建树生成头（openssl/*.h）后镜像到 BUILD_OUT/include。"""
    view = os.path.join(SRC_PATH, "stage-include")
    if os.path.isdir(view):
        shutil.rmtree(view)
    merged = False
    for source in (
        os.path.join(SRC_PATH, "include", "openssl"),
        os.path.join(release_build_dir, "include", "openssl"),
    ):
        if os.path.isdir(source):
            shutil.copytree(source, os.path.join(view, "openssl"), dirs_exist_ok=True)
            merged = True
    if not merged:
        raise FileNotFoundError("未找到 openssl 头文件目录（源码或构建树）")
    copied = stage_headers(view, BUILD_OUT)
    print("[openssl] staged headers=%d" % copied)
    return copied


def clear_staged_binaries():
    """重跑/回退前清空 release/debug 分层，避免同名不同内容被去重改名。"""
    for segment in ("release", "debug"):
        directory = os.path.join(BUILD_OUT, segment)
        if os.path.isdir(directory):
            shutil.rmtree(directory)


def build_all(label, variables):
    """以指定编译器路线构建 Release/Debug 并分类，返回构建目录 dict。"""
    clear_staged_binaries()
    build_dirs = {}
    for config in ("Release", "Debug"):
        build_dir = os.path.join(SRC_PATH, "build-" + config.lower())
        if os.path.isdir(build_dir):
            shutil.rmtree(build_dir)
        os.makedirs(build_dir)
        configure(config, build_dir, label, variables)
        run(["nmake", "/NOLOGO", "build_libs"], build_dir)
        counts = stage_binaries(build_dir, BUILD_OUT, config=config)
        print(
            "[openssl] staged config=%s compilerRoute=%s counts=%s"
            % (config, label, counts)
        )
        build_dirs[config] = build_dir
    return build_dirs


def main():
    label, variables = compiler_route()
    print(
        "[openssl] compilerKind=%s compilerRoute=%s variables=%s"
        % (os.environ.get("CNP_COMPILER_KIND", ""), label, " ".join(variables))
    )
    probe(["nasm", "-v"])
    probe(["perl", "-v"])
    probe(["git", "-C", SRC_PATH, "log", "-1", "--format=%H %cs %s"])
    try:
        build_dirs = build_all(label, variables)
    except RuntimeError as error:
        fallback = fallback_route(label)
        if fallback is None:
            raise
        fallback_label, fallback_variables = fallback
        print("[openssl] compiler route %s failed: %s" % (label, error))
        print(
            "[openssl] falling back to compiler route %s（失败证据见上）"
            % fallback_label
        )
        build_dirs = build_all(fallback_label, fallback_variables)
    stage_openssl_headers(build_dirs["Release"])
    print("[openssl] staged license=%s" % stage_license(SRC_PATH, BUILD_OUT))
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
