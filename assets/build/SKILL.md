---
name: generating-build-py
description: Use when creating, generating, updating, or maintaining a build.py for cpp_nuget_pack (a Flutter Windows app that builds C++ library sources into NuGet packages), or when a C++ library repository needs a cpp_nuget_pack-compatible build script.
---

# 生成 cpp_nuget_pack 的 build.py

本文档说明如何为 C++ 库源码仓库编写 `build.py`，使其能被 cpp_nuget_pack 的「构建」流水线一键执行：拉取源码 → 准备编译器与工具 → 执行本脚本 → 自动分类产物 → 重新映射入包。

## 何时使用

- 需要把一个 C++ 库（git 仓库）纳入 cpp_nuget_pack 打包管线：在库源码根目录新建 `build.py`；
- 已有 `build.py` 需要升级到 v2 契约（`# tool` / `# option` 头部指令）；
- 构建失败，需要排查环境变量、分类结果或退出码问题。

## 运行方式（工具侧）

1. 解析库源码根目录的 `build.py`（文件名大小写不敏感；根级 `build.py` 不随包分发）；
2. 检测编译器（ICX > clang-cl > MSVC，可在工具设置页调整优先级）并准备 CMake / Ninja 与 `# tool` 声明的工具；
3. `git clone` / `git pull --ff-only` 源码到 `cache/build/<清洗包ID>/`；
4. 以**包源目录为工作目录**运行 `python build.py`（无 `python` 时回退 `py -3`），并注入「环境变量」一节的变量；
5. 退出码 0 = 成功，非 0 = 失败（工具会显示输出尾部）；成功后自动扫描并重新映射产物。

## 契约总览（build.py 头部）

第一行必须是仓库地址；其后为**连续**的 `#` 行（遇到第一个非 `#` 行即终止，**空行也算终止**）。

| 位置 | 语法 | 含义 |
| --- | --- | --- |
| 第 1 行 | `# <git仓库地址>` | 源码仓库 URL（如 `# https://github.com/madler/zlib`）。 |
| 其后连续行 | `# tool: <name> <url> [bin=<子目录>]` | 声明自动下载的环境工具：zip 解压到 `tools/<name>/` 并加入子进程 PATH。`name` 限 `[A-Za-z0-9._-]+`；`url` 为 http(s) zip；`bin` 为相对子目录（如 `perl/bin`），不得含盘符或 `..`。 |
| 其后连续行 | `# option: <name> = <默认值> \| <备选值> …` | 声明构建选项：**首值为默认值**，工具 UI 在「构建」按钮旁渲染下拉框，选中值经 `CNP_OPTION_<NAME>` 传入。`name` 限 `[A-Za-z_][A-Za-z0-9_]*`；候选值用 `\|` 分隔，不得为空或重复。 |
| 其余 `#` 行 | 普通注释 | 忽略；非法指令行同样按注释忽略（不报错）。 |

> 同名 tool / option 以首次声明为准；未声明的选项不会下发环境变量。

## 环境变量（工具注入，脚本只读）

| 变量 | 说明 |
| --- | --- |
| `SRC_PATH` | 拉取的源码目录（`cache/build/<清洗包ID>/`）。 |
| `BUILD_OUT` | 包源目录：分类后的最终产物写入这里（会随包入包）。 |
| `CNP_CMAKE` | cmake 可执行文件路径（`cmake_configure` / `cmake_build` 必需）。 |
| `CNP_NINJA` | ninja 可执行文件路径（自动作为 `CMAKE_MAKE_PROGRAM`）。 |
| `CNP_C_COMPILER` / `CNP_CXX_COMPILER` | 本机选中的 C / C++ 编译器全路径。 |
| `CNP_COMPILER_KIND` | 编译器种类：`msvc` / `clang-cl` / `icx`。 |
| `CNP_TOOLS_DIR` | `tools/` 绝对路径（`# tool` 下载的工具都在这里）。 |
| `CNP_OPTION_<NAME>` | `# option` 声明的选项当前值（名称大写）。 |
| `PYTHONPATH` | 已前置 `tools/`，脚本可直接 `import cnp_build_support`。 |

## 分类辅助模块 cnp_build_support

工具在每次构建前把 `cnp_build_support.py` 释放到 `tools/` 并注入 `PYTHONPATH`。**优先直接调用它，不要重复实现分类逻辑。**

```python
from cnp_build_support import (
    cmake_build,
    cmake_configure,
    classify_tree,
    stage_binaries,
    stage_headers,
    stage_license,
    summary,
)
```

| 函数 | 用途 |
| --- | --- |
| `cmake_configure(source, build_dir, config="Release", extra_args=())` | 以 Ninja 生成器配置 CMake 工程：双配置（`CMAKE_BUILD_TYPE`）+ 运行时库（Release `/MD`、Debug `/MDd`），自动附加 `CMAKE_MAKE_PROGRAM` 与 `CMAKE_C(XX)_COMPILER`。 |
| `cmake_build(build_dir, config="Release", jobs=None)` | `cmake --build` 构建（Ninja 单配置）。 |
| `stage_headers(paths, out)` | 头文件 → `<out>/include/`。传目录时镜像其内容（保留子结构）；传文件时复制单个文件。 |
| `stage_binaries(build_dir, out, config="Release")` | 递归收集 `.lib/.dll/.pdb`：Release → `lib/` + `bin/`；Debug → `debug/lib/` + `debug/bin/`。跳过 CMake 中间目录；同名不同内容按父目录后缀去重。 |
| `stage_license(source_root, out)` | 识别源码根目录的许可证（LICENSE/LICENCE/COPYING/UNLICENSE/NOTICE 及变体）→ 复制到 `<out>/` 根。 |
| `classify_tree(root, out, exclude=())` | 预构建归档场景：把解压后的产物树按扩展名分类到 `include/lib/bin/debug-*`。 |
| `summary(out)` | 打印并返回产物统计（各分类计数、文件数与字节数），建议作为构建收尾证据。 |

## 构建约定

- **架构**：只构建 x64（工具侧环境已按 x64 准备）。
- **双配置**：一次构建同时产出 Release 与 Debug（各自独立 build 目录）；运行时库与构建类型由辅助模块固定，不要重复指定。
- **生成器**：统一 CMake + Ninja（单配置），不要使用 Visual Studio 生成器。
- **产物布局**（类 vcpkg 参考）：`include/`、`lib/`、`bin/`、`debug/lib/`、`debug/bin/`。
- **许可证**：经 `stage_license` 落到 `BUILD_OUT` 根，打包器会自动识别并生成部署目标。
- **工作目录**：中间构建目录放在 `SRC_PATH` 下（如 `SRC_PATH/build-release`）；`BUILD_OUT` 下的一切都会入包，不要残留临时文件。
- **环境**：工具与编译器环境已注入子进程；脚本不得修改系统环境（PATH、注册表），也不要依赖本机预装软件（缺失工具用 `# tool` 声明）。

## 完整骨架示例

```python
# https://github.com/example/mylib
# tool: nasm https://example.com/nasm-2.16.03-win64.zip
# option: tbb = off | on
#
# 上面 3 行为完整头部：首行仓库地址，其后指令必须连续；
# 出现空行或其它非 # 行后，其后的 # 行将不再按指令解析。

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


def build_config(config):
    build_dir = os.path.join(SRC_PATH, "build-" + config.lower())
    cmake_configure(
        SRC_PATH,
        build_dir,
        config=config,
        extra_args=["-DCMAKE_POLICY_VERSION_MINIMUM=3.5"],  # 老工程按需
    )
    cmake_build(build_dir, config=config)
    stage_binaries(build_dir, BUILD_OUT, config=config)


def main():
    for config in ("Release", "Debug"):
        build_config(config)
    stage_headers(os.path.join(SRC_PATH, "include"), BUILD_OUT)
    stage_license(SRC_PATH, BUILD_OUT)
    summary(BUILD_OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

预构建归档（自带 include/lib/dll 的发布包）可改用分类模式：

```python
from cnp_build_support import classify_tree

classify_tree(unpacked_dir, BUILD_OUT, exclude=("docs", "tests"))
```

## 校验清单

- [ ] 首行是 `# <git仓库地址>`；`# tool` / `# option` 指令紧随其后且连续（无空行打断）。
- [ ] `python build.py` 以退出码表达结果：0 = 成功，非 0 = 失败。
- [ ] Release 与 Debug 双配置产物均已分类到 `BUILD_OUT` 的 `include/`、`lib/`、`bin/`、`debug/lib/`、`debug/bin/`。
- [ ] 头文件走 `stage_headers`；库与动态库走 `stage_binaries`；许可证（若有）走 `stage_license` 落 `BUILD_OUT` 根。
- [ ] 路径全部由 `SRC_PATH` / `BUILD_OUT` 派生（或 `os.path.join` 拼接），无硬编码本机路径。
- [ ] 未修改系统环境，未依赖本机预装软件；缺失工具在头部用 `# tool` 声明。
- [ ] 中间构建目录位于 `SRC_PATH` 下，`BUILD_OUT` 无临时 / 中间文件残留。
- [ ] 选项经 `os.environ.get("CNP_OPTION_<NAME>")` 读取；未声明选项不下发。
- [ ] 根级 `build.py` 不随包分发（打包器自动排除，无需手动处理）。
