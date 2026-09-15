---
name: generating-build-py
description: Use when creating, generating, updating, or maintaining a build.py for cpp_nuget_pack (a Flutter Windows app that builds C++ library sources into NuGet packages), or when a C++ library repository needs a cpp_nuget_pack-compatible build script.
---

# 生成 cpp_nuget_pack 的 build.py

本文档说明如何为 C++ 库源码仓库编写 `build.py`，使其能被 cpp_nuget_pack 的「构建」流水线一键执行：拉取源码 → 准备编译器与工具 → 执行本脚本 → 自动分类产物 → 重新映射入包。

## 何时使用

- 需要把一个 C++ 库（git 仓库）纳入 cpp_nuget_pack 打包管线：在库源码根目录新建 `build.py`；
- 已有 `build.py` 需要升级契约（`# tool` / `# option` / `# checkbox` / `# multiselect` / `# source` / `# runtime` 头部指令）；
- 上游只提供预构建归档、不做源码构建：用 `# source: none` + 下载 / 解压 / 分类（见「预构建配方」）；
- 构建失败，需要排查环境变量、分类结果或退出码问题。

## 运行方式（工具侧）

1. 解析库源码根目录的 `build.py`（文件名大小写不敏感；根级 `build.py` 不随包分发）；
2. 检测编译器（ICX > clang-cl > MSVC > MinGW，可在工具设置页调整优先级）并准备 CMake / Ninja 与 `# tool` 声明的工具；
3. 准备源码：无缓存时 `git clone` 到 `cache/build/<清洗包ID>/`；已有缓存时原位硬重置（`git fetch` → `reset --hard` 上游 → `clean -ffdx`），声明 `# source: none` 时跳过 git 仅创建该目录（缓存目录**不清理**，脚本下载/解压内容跨构建复用）；
4. 以**包源目录为工作目录**运行 `python build.py`（Python 缺失时工具自动下载最小版到 `tools/python`；`python` 优先、`py -3` 兜底），并注入「环境变量」一节的变量；
5. 脚本输出经管道逐行实时显示在构建对话框（`python -u` 无缓冲；git 拉取同样流式）；退出码 0 = 成功，非 0 = 失败（工具保留已显示输出并附输出尾部）；成功后自动扫描并重新映射产物。

## 契约总览（build.py 头部）

第一行必须是仓库地址；其后为**连续**的 `#` 行（遇到第一个非 `#` 行即终止，**空行也算终止**）。

| 位置 | 语法 | 含义 |
| --- | --- | --- |
| 第 1 行 | `# <git仓库地址>` | 源码仓库 URL（如 `# https://github.com/madler/zlib`）。 |
| 其后连续行 | `# tool: <name> <url> [bin=<子目录>]` | 声明自动下载的环境工具：zip 解压到 `tools/<name>/` 并加入子进程 PATH。`name` 限 `[A-Za-z0-9._-]+`；`url` 为 http(s) zip；`bin` 为相对子目录（如 `perl/bin`），不得含盘符或 `..`。 |
| 其后连续行 | `# option: <name> = <默认值> \| <备选值> …` | 声明下拉选项：**首值为默认值**，工具 UI 在【文件管理】页「构建」按钮下方渲染下拉框，选中值经 `CNP_OPTION_<NAME>` 传入。`name` 限 `[A-Za-z_][A-Za-z0-9_]*`（`runtime` 为保留名，禁止使用）；候选值用 `\|` 分隔，不得为空或重复。 |
| 其后连续行 | `# checkbox: <name> = <勾选值> \| <未勾选值>` | 声明布尔选项：工具 UI 渲染复选框，**首值为勾选态（也是默认值）**，建议写作 `ON \| OFF`；落盘值为勾选值 `ON` / 未勾选值 `OFF`，经 `CNP_OPTION_<NAME>` 传入。值恰为 2 个、非空且不重复。 |
| 其后连续行 | `# multiselect: <name> = <值> \| <值> …` | 声明多选选项：工具 UI 渲染勾选组，已选值按声明序以 `;` 连接经 `CNP_OPTION_<NAME>` 传入（全不选为空串）；值不得为空、重复或含 `;`。 |
| 其后连续行 | `# source: none` | 预构建配方：跳过 git 源码拉取；`SRC_PATH` 目录仍会创建并注入，作为脚本自行下载 / 解压的工作区。仅字面值 `none` 合法，其余值按注释忽略。 |
| 其后连续行 | `# runtime: md \| mt` | 声明运行库家族默认值（用户未在 UI 显式覆盖时生效；缺省 `md`）。`md` = 动态运行库（Release `/MD`、Debug `/MDd`），`mt` = 静态运行库（`/MT`、`/MTd`）；非法值按注释忽略。 |
| 其后连续行 | `# depends: <包名> [<版本范围>]` | 声明依赖的包：重映射/构建时自动加入依赖管理（系统条目，禁改删）。`<包名>` 非空白；`<版本范围>` 可选单 token（如 `[1.2.0,)`），缺省时按本地同名包版本推断。 |
| 其余 `#` 行 | 普通注释 | 忽略；非法指令行同样按注释忽略（不报错）。 |

> 同名 tool / option / checkbox / multiselect 以首次声明为准；未声明的选项不会下发环境变量。
>
> `runtime` 为保留名（大小写 / 空白不敏感，供工具的运行库选择器使用），禁止用作选项名：以该名声明 `# option` / `# checkbox` / `# multiselect` 的行按非法行忽略（不报错，也不会下发 `CNP_OPTION_RUNTIME`）。
>
> 根级 `pre.bat` / `post.bat` 会被工具自动注册为系统编译命令（执行时附加 `"$(TargetPath)"` 参数，脚本内以 `%~1` 取目标路径；系统条目禁改删）。

## 环境变量（工具注入，脚本只读）

| 变量 | 说明 |
| --- | --- |
| `SRC_PATH` | 补拉的源码目录（`cache/build/<清洗包ID>/`）；声明 `# source: none` 时为持久工作缓存目录（仍会创建），由脚本自行下载 / 解压填充，**跨构建保留**。 |
| `BUILD_OUT` | 包源目录：分类后的最终产物写入这里（会随包入包）。**源码就绪后、执行 `build.py` 前会被清空**（git 拉取失败时不清理），仅保留根级 `build.py`（大小写不敏感）、`icon.*`、`pre.bat`/`post.bat`、根级 `.git` 与许可证类文件（`LICENSE`/`LICENCE`/`COPYING`/`UNLICENSE`/`NOTICE` 及 `-`/`.` 变体，含 `TBB-LICENSE` 类前缀变体；多段前缀如 `third-party-LICENSE` 不保护）；不要把需要跨构建的中间产物放这里。 |
| `CNP_CMAKE` | cmake 可执行文件路径（`cmake_configure` / `cmake_build` 必需）。 |
| `CNP_NINJA` | ninja 可执行文件路径（自动作为 `CMAKE_MAKE_PROGRAM`）。 |
| `CNP_C_COMPILER` / `CNP_CXX_COMPILER` | 本机选中的 C / C++ 编译器全路径（MinGW 分设 `gcc.exe` / `g++.exe`，或 `clang.exe` / `clang++.exe`）。 |
| `CNP_COMPILER_KIND` | 编译器种类：`msvc` / `clang-cl` / `icx` / `mingw`。 |
| `CNP_RC_COMPILER` | MinGW 的 RC 编译器 `windres.exe` 路径（与 `gcc.exe` 同 bin；仅该文件存在时注入）。 |
| `CNP_TOOLS_DIR` | `tools/` 绝对路径（`# tool` 下载的工具都在这里）。 |
| `CNP_OPTION_<NAME>` | `# option` / `# checkbox` / `# multiselect` 声明的选项当前值（名称大写；多选为声明序 `;` 连接、可空串）。 |
| `CNP_RUNTIME_LIBRARY` | 运行库家族：`md`（缺省/非法回退）或 `mt`；由工具按「用户选择 > `# runtime:` > `md`」解析后下发，辅助模块统一消费。 |
| `PYTHONPATH` | 已前置 `tools/`，脚本可直接 `import cnp_build_support`。 |
| `PYTHONIOENCODING` | 恒为 `utf-8`：脚本 stdout/stderr 统一按 UTF-8 编码（中文 Windows 下管道默认 GBK），中文输出可直接 `print`，无需自行处理编码。 |

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
| `cmake_configure(source, build_dir, config="Release", extra_args=(), enable_ipo=None)` | 以 Ninja 生成器配置 CMake 工程：双配置（`CMAKE_BUILD_TYPE`）+ 运行库按 `CNP_RUNTIME_LIBRARY` 注入（MSVC 系 `md` → Release `/MD`、Debug `/MDd`；`mt` → `/MT`、`/MTd`；MinGW `md` 动态缺省、`mt` 链接期 `-static-libgcc -static-libstdc++`，不写 `CMAKE_MSVC_RUNTIME_LIBRARY`），自动附加 `CMAKE_MAKE_PROGRAM`、`CMAKE_C(XX)_COMPILER` 与 `CNP_RC_COMPILER`（MinGW 的 `CMAKE_RC_COMPILER`）；按编译器注入 AVX2（全配置）与 Release 最高优化 / IPO，**不注入语言标准参数**；`enable_ipo=False` 或环境变量 `CNP_NO_IPO=1` 可对单个库退化 LTO。 |
| `cmake_build(build_dir, config="Release", jobs=None)` | `cmake --build` 构建（Ninja 单配置）；`jobs` 缺省为 CPU 逻辑核数（`--parallel`），显式传 0/负值禁用并行。 |
| `stage_headers(paths, out)` | 头文件 → `<out>/include/`。传目录时镜像其内容（保留子结构）；传文件时复制单个文件。 |
| `stage_binaries(build_dir, out, config="Release", reset=False)` | 递归收集 `.lib/.dll/.pdb`：Release → `release/lib/` + `release/bin/`；Debug → `debug/lib/` + `debug/bin/`（库类产物不落输出根）。跳过 CMake 中间目录；同名不同内容按父目录后缀去重（去重残留形如 `_build-*`）。`reset=True` 先递归删除本配置段再 staging，杜绝陈旧文件与去重改名跨构建累积；默认 `False` 保持「只增量补入」旧语义。 |
| `stage_license(source_root, out)` | 识别源码根目录的许可证（LICENSE/LICENCE/COPYING/UNLICENSE/NOTICE 及变体）→ 复制到 `<out>/` 根。 |
| `classify_tree(root, out, exclude=(), debug_name_suffix="_debug")` | 预构建归档场景：把解压后的产物树分类到 `include/`、`release/lib|bin/`、`debug/lib|bin/` 分层。Debug 判定为「或」关系：相对路径中有 `debug` 目录段，或**文件名 stem 以 `debug_name_suffix` 结尾**（大小写不敏感，缺省 `_debug`；适用于 Release/Debug 变体同目录发布的归档，如 `tbb12.dll` / `tbb12_debug.dll`）。调用开始时打印开始标记 `[cnp_build_support] classify: <root> -> <out>`（见「分类标记与进度」）。 |
| `summary(out)` | 打印并返回产物统计（各分类计数、文件数与字节数），建议作为构建收尾证据。 |

### 分类标记与进度

- **分类开始标记**：`classify_tree` 每次调用开始时打印 `[cnp_build_support] classify: <root> -> <out>`。构建对话框对 `# source: none` 配方据此把阶段显示从「正在下载」切换为「正在分类」；不要删除或改动该行前缀。
- **下载进度（可选）**：脚本自行下载大文件时建议按 `... progress <NN>% ...` 形态输出进度行（如 `[openvino] progress 42.0% (…)`），工具会提取百分比显示在「正在下载」阶段——通用匹配、不依赖库名；不输出也能正常构建。

## 构建约定

- **架构**：只构建 x64（工具侧环境已按 x64 准备）。
- **双配置**：一次构建同时产出 Release 与 Debug（各自独立 build 目录）；运行时库与构建类型由辅助模块固定，不要重复指定。**staging 用 `stage_binaries(..., reset=True)` 重置本配置段**——同名不同内容会按父目录后缀去重改名（`_build-*`），不重置会跨构建永久累积。
- **生成器**：统一 CMake + Ninja（单配置），不要使用 Visual Studio 生成器。
- **运行库（CRT）**：由 `cmake_configure` 按 `CNP_RUNTIME_LIBRARY` 统一注入——MSVC 系为 `md` → Release `/MD`、Debug `/MDd`；`mt` → `/MT`、`/MTd`（写入 `CMAKE_MSVC_RUNTIME_LIBRARY`）；MinGW 为 GNU 语义：`md` 动态缺省（可随附 `libgcc_s`/`libstdc++`（CLANG64 为 libc++）系列 DLL），`mt` 把 `-static-libgcc -static-libstdc++` 注入链接器旗标（winpthread 仍为动态依赖，属有意取舍——全静态 `-static` 会牵动共享库的运行时状态，不在 v1 范围）。配方不要自行注入 `CMAKE_MSVC_RUNTIME_LIBRARY` 或运行库旗标；需要默认静态运行库时在头部声明 `# runtime: mt`（用户仍可在 UI 覆盖）。**支持时优先构建独立 dll + lib（共享依赖省体积）**：动态运行库 + 独立 dll 让多个消费模块共用同一份 CRT 与库代码，产物体积显著更小；静态运行库（`mt`）仅在需要免依赖分发时选用。
- **MinGW 要点**：产物为 GNU 命名（`lib*.dll` / `lib*.dll.a`）；`windres.exe` 由工具从编译器同 bin 注入 `CMAKE_RC_COMPILER`（含 `.rc` 的工程无需自行配置）；不要套用 MSVC 旗标（`/O2`、`/MD` 等在 MinGW 下无效或报错），GNU 旗标由辅助模块统一注入；不要假设存在 vcvars 环境脚本（MinGW 工具链自包含，bin 已前置 PATH）。
- **产物布局（release/debug 分层）**：`include/`、`release/lib/`、`release/bin/`、`debug/lib/`、`debug/bin/`。**库类产物禁止落 `BUILD_OUT` 根**（`lib/`、`bin/`）——打包侧按 `release`/`debug` 路径段识别构建类型，根目录产物会被判为“不限配置”（ALL），消费者无法按配置取库。
- **优化参数（辅助模块自动注入，配方不要重复指定）**：

  | 编译器 | AVX2（全配置） | Release 优化 | LTO/IPO（仅 Release） |
  | --- | --- | --- | --- |
  | ICX | `/QxCORE-AVX2 /QaxCORE-AVX2` | `/O3 /Ob2 /Oi /Ot /GF /Gy` | CMake IPO（`-Qipo`） |
  | clang-cl | `/arch:AVX2` | `/O2 /Ob2 /Oi /Ot /GF /Gy` | CMake IPO（`-flto=thin`；需 `lld-link`，缺失自动退化） |
  | MSVC | `/arch:AVX2` | `/O2 /Ob2 /Oi /Ot /GF /Gy` | CMake IPO（`/GL` + `/LTCG`） |
  | MinGW | `-mavx2` | `-O3 -ffunction-sections -fdata-sections` | 保守关闭（`enable_ipo=True` 可显式开启） |

  - Debug 不注入任何优化参数（保留调试信息，优先保证调试用途），AVX2 仍保留；
  - **语言标准不动原则**：辅助模块与配方都不得注入 `/std:`、`-std=` 等语言标准参数，保持库工程原有设定；
  - **LTO 退化**：某库与 IPO 不兼容时，设 `CNP_NO_IPO=1`，或调用 `cmake_configure(..., enable_ipo=False)`；也可经 `extra_args` 自带同名 `-DCMAKE_*` 变量覆盖（此时模块对该变量不再重复注入）；
  - **多线程**：`cmake_build` 缺省 `--parallel` 到 CPU 逻辑核数，无需手动传 `jobs`。
- **许可证**：经 `stage_license` 落到 `BUILD_OUT` 根，打包器会自动识别并生成部署目标。
- **工作目录**：中间构建目录放在 `SRC_PATH` 下（如 `SRC_PATH/build-release`）；`BUILD_OUT` 下的一切都会入包，不要残留临时文件。
- **构建前清理（BUILD_OUT）**：工具在源码就绪后、执行 `build.py` 前清空 `BUILD_OUT` 中除白名单外的一切（递归删除文件与目录），保证产物不带上次构建残留。白名单：根级 `build.py`（大小写不敏感）、`icon.*`、`pre.bat`/`post.bat`、根级 `.git`、许可证类文件（`LICENSE`/`LICENCE`/`COPYING`/`UNLICENSE`/`NOTICE` 及 `-`/`.` 变体与 `TBB-LICENSE` 类单段前缀变体；多段前缀如 `third-party-LICENSE` 不保护，属打包侧 `license_file.dart` 规则的超集）。需要跨构建保留的中间产物必须放 `SRC_PATH`（源码构建会被 `git clean -ffdx` 清掉、预构建缓存则完整保留），不要放 `BUILD_OUT`。
- **环境**：工具与编译器环境已注入子进程；脚本不得修改系统环境（PATH、注册表），也不要依赖本机预装软件（缺失工具用 `# tool` 声明）。

## 完整骨架示例

```python
# https://github.com/example/mylib
# tool: nasm https://example.com/nasm-2.16.03-win64.zip
# option: tbb = off | on
# checkbox: use_nasm = ON | OFF
# multiselect: accel = SSE2 | AVX2 | NEON
# runtime: mt
#
# 上面的头部从首行仓库地址起必须连续；出现空行或其它非 # 行后，
# 其后的 # 行将不再按指令解析。

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
    stage_binaries(build_dir, BUILD_OUT, config=config, reset=True)


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

## 预构建配方（`# source: none`）

上游只提供预构建归档、没有可用的源码构建流程时使用：头部声明 `# source: none` 跳过 git 源码拉取，脚本把官方归档下载 / 解压到 `SRC_PATH`，再经 `classify_tree` / `stage_*` 分类到 `BUILD_OUT`。

```python
# https://github.com/vendor/library.git
# source: none
# option: tbb = off | on
#
# 预构建：下载官方归档 → 解压到 SRC_PATH（存在即复用）→ 分类入库。

import os
import urllib.request
import zipfile

from cnp_build_support import classify_tree, stage_license, summary

SRC_PATH = os.environ["SRC_PATH"]
BUILD_OUT = os.environ["BUILD_OUT"]

# 1) 解析最新版本并下载归档到 <SRC_PATH>/downloads/，存在即复用（二次构建无大下载）
# 2) 解压到 <SRC_PATH> 下（可写完成标记，二次运行复用解压树）
# 3) 对解压树中头文件 / 库 / 动态库所在子树分别 classify_tree(..., BUILD_OUT)
# 4) stage_license 把许可证落 BUILD_OUT 根；summary(BUILD_OUT) 收尾
```

预构建配方约定：

- **缓存必须放 `SRC_PATH` 下**：归档与解压树都落 `SRC_PATH`（存在即复用），保证二次构建不重复大下载；`SRC_PATH` 对 `# source: none` **跨构建持久保留**（工具不清理），`BUILD_OUT` 则在源码就绪后、执行 `build.py` 前清空且只放最终产物。
- **缓存防陈旧**：复用解压树等缓存时，把缓存身份绑到归档/版本标识（如解压完成标记记录归档文件名），归档升级后丢弃旧缓存重解压，避免复用陈旧产物；本地已有同名最新归档时直接复用，不重复下载。
- **无关目录不进包**：只分类头文件 / 库 / 动态库所在子树，或用 `classify_tree` 的 `exclude` 排除 `docs`/`samples` 等；文档与示例可执行文件不入包。
- **选项门控**：如「是否随包分发第三方运行时」（`# option: tbb = off | on`），经 `os.environ.get("CNP_OPTION_TBB")` 读取；默认值与两条路径都要可复现。
- **许可证**：归档把许可证放在非根目录时（如 `docs/licensing/LICENSE`），用 `stage_license(<许可证目录>, BUILD_OUT)` 显式落 `BUILD_OUT` 根。
- **版本解析**：优先解析官方发布索引取最新版本；解析失败回退脚本内置常量，并在注释中记录核实日期。

## 校验清单

- [ ] 首行是 `# <git仓库地址>`；`# tool` / `# option` / `# source` 指令紧随其后且连续（无空行打断）。
- [ ] `python build.py` 以退出码表达结果：0 = 成功，非 0 = 失败。
- [ ] Release 与 Debug 双配置产物均已分类到 `BUILD_OUT` 的 `include/`、`release/lib/`、`release/bin/`、`debug/lib/`、`debug/bin/`；输出根无 `lib/`、`bin/` 残留。
- [ ] 未在 `build.py` 中重复注入 AVX2 / 最高优化 / IPO / 运行库 / 语言标准参数（由辅助模块负责；确需覆盖时用 `extra_args` 同名变量或 `CNP_NO_IPO`）。
- [ ] 头文件走 `stage_headers`；库与动态库走 `stage_binaries`（`reset=True` 重置本配置段）；许可证（若有）走 `stage_license` 落 `BUILD_OUT` 根。
- [ ] 路径全部由 `SRC_PATH` / `BUILD_OUT` 派生（或 `os.path.join` 拼接），无硬编码本机路径。
- [ ] 未修改系统环境，未依赖本机预装软件；缺失工具在头部用 `# tool` 声明。
- [ ] 中间构建目录位于 `SRC_PATH` 下，`BUILD_OUT` 无临时 / 中间文件残留。
- [ ] 选项经 `os.environ.get("CNP_OPTION_<NAME>")` 读取；多选值按 `;` 拆分求交；未声明选项不下发。
- [ ] 支持时优先产出独立 dll + lib（共享依赖省体积）；`# runtime: mt` 仅在需要免依赖分发时声明。
- [ ] 预构建配方：头部声明 `# source: none`；下载 / 解压缓存位于 `SRC_PATH` 下且可复用；无关目录未进入 `BUILD_OUT`。
- [ ] 依赖其它包时在头部声明 `# depends: <包名> [<版本范围>]`。
- [ ] 需消费方构建前/后处理（如注入）时，在源目录根部提供 `pre.bat` / `post.bat`（以 `%~1` 为目标路径）。`.bat` 以 cmd 原生编码落盘：优先 ANSI/MBCS（`content.encode("mbcs")`），代码页无法表示中文时退纯 ASCII 注释版本；**禁止 UTF-8 无 BOM 中文**——cmd 按系统代码页解析会出乱码命令行、报「不是内部或外部命令」（实测；做法见 mimalloc 配方 `write_post_bat`）。
- [ ] 根级 `build.py` 不随包分发（打包器自动排除，无需手动处理）。
