<div align="center">
<picture><source media="(prefers-color-scheme: dark)" srcset="./logo/logo.png"><source media="(prefers-color-scheme: light)" srcset="./logo/logo.png"><img alt="CCPPP C/C++ 包管理工具" src="./logo/logo.png" width="128"></picture>

# CCPPP — C/C++ 包管理工具

项目状态：开发中

第三方组件许可与来源声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

</div>

CCPPP（C++ PackTool）是仅支持 Windows 的 Flutter 桌面应用，用于把 C/C++ 头文件、源码和库组织为 NuGet 包。它既支持从本地目录添加包，也支持依据包内预置源码目录的 `build.py` 准备源码、准备编译环境、执行构建并重新映射；节点脚本编辑器可生成 PowerShell 5.1 脚本并随 NuGet 包发布。

## 功能特性

| 功能 | 说明 |
| ---- | ---- |
| 包管理 | 选择目录并扫描文件，添加、编辑、删除包；包 ID 只读，可重新映射源目录。 |
| 文件管理 | 目录树展示文件大小与目录后代统计；双击文件使用系统默认程序打开；库、动态库、调试文件及源码按路径显示 Release/Debug 标签。 |
| 依赖管理 | 从现有包选择依赖，编辑 NuGet 版本范围；缺失依赖有明确标记，并提供可拖拽平移、缩放的依赖关系图。 |
| 编译设置 | 管理宏定义、编译前/后命令、附加库目录和附加库，条目可按 ALL/Release/Debug 分组；可接入根级 `pre.bat`/`post.bat` 系统命令。 |
| 节点脚本 | 在画布上编排节点、连线、检查参数并预览 PowerShell 5.1 脚本；支持校验、诊断、串行防抖保存和失败重试。 |
| 构建 | 源目录根部存在 `build.py` 时显示构建入口；自动准备编译器与工具、准备源码、执行脚本、检查头文件引用并重新映射。 |
| 打包设置 | 预览 NuGet 包内的文件树和文本内容后导出；导出前再检查一次头文件引用。 |
| 历史记录 | 记录创建、版本变更、重新映射、打包导出和构建事件，时间线最多保留 100 条，可删除单条记录。 |
| 设置与关于 | 配置 NuGet 输出目录、主题与编译器优先级；关于页显示应用信息与项目主页。 |

## 打包产物

### NuGet 包（`.nupkg`）

导出文件名为 `<包ID>.<去 +build 版本>.nupkg`。NuGet 构建器在应用内生成包清单和 MSBuild 集成文件，再由 Dart 代码组装 `.nupkg`；不依赖外部 NuGet CLI、`nuget.exe` 或 `dotnet pack`。

| 内容 | 包内路径 | 说明 |
| ---- | -------- | ---- |
| 头文件 / 模块 | `build/native/include/<源目录名>/...` | 剥离开头 `include/` 后套源目录命名空间；首段已同名时不再叠加。 |
| `lib` / `dll` / `pdb` / `.a` | `build/native/lib/...` | 剥离开头 `lib` 或 `bin`；`.a` 是通用静态归档，与 `.lib` 一样归入库目录并保留 `release`/`debug` 路径段。 |
| 其余源文件 | `build/native/files/...` | 保留相对路径；根级 `build.py` 不入包。 |
| NuGet 清单 | `<包ID>.nuspec` | 由应用生成，记录版本、作者、许可证、依赖和图标引用。 |
| MSBuild 集成 | `build/native/<包ID>.targets` | 由应用生成，供消费者工程导入。 |
| 包图标 | `images/icon.png` | 从包图标转换并等比缩放至最长边不超过 128；缺失时使用默认纸箱图标。 |
| 节点脚本（可选） | `build/native/files/scripts/<id>.ps1` | 节点图生成的 UTF-8 BOM PowerShell 5.1 脚本。 |

`<包ID>.targets` 会追加头文件搜索路径，并按 ALL/Release/Debug 写入宏定义、附加库目录和附加库；包内 `.lib` 连同其所在目录一并登记进无条件项组，其 Release/Debug 配置由用户在编译设置页为对应条目选择，**不再按路径推断**。包内 `dll`/`pdb` 在构建后优先硬链接到 `$(OutDir)`（失败时回退复制），许可证文件也按同样方式部署到 `$(OutDir)licenses`。编译前/后命令以带条件的自定义 `Exec` 目标执行；包内 `.asm` 和 `.rc` 分别生成 MASM 与资源编译项。节点脚本按 pre/post 阶段生成 MSBuild `Exec` 目标并传入 `CNP_*` 环境变量。

### 头文件引用检查

`#include` 引号引用的失效修复在**构建成功后**与**打包（导出）前**各执行一次：构建后那次提供即时反馈，打包前那次兜住没有 `build.py` 因而不触发构建的目录。

判据唯一：**打包后的布局**。因为 `<包ID>.targets` 恒定只下发 `build/native/include` 一个头文件搜索根，所以源码树里能解析的写法不代表包内能解析。包内可解析的引用原样保留，不做改动。

未解析的引号引用先在包内按文件名找唯一同名候选——同名文件按**包内落点**去重：配方把头文件镜像到 `<包源目录>/include/` 时，原始文件与其镜像落到同一包内位置，是同一份产物而非两个候选；再依次尝试两条改写规则：

1. 候选落在 `build/native/include` 之下（头文件/模块）时，改写为**该候选相对 include 根的包内路径**（如 `flutter/cpp_client_wrapper/binary_messenger_impl.h`）——这一个搜索根对包内任何位置都成立，头文件与 `build/native/files/` 下的源文件通吃。
2. 否则回落到**裸文件名**（取候选的实际文件名），仅当候选落 `build/native/files/`、与引用文件同目录、且两者打包落点目录也一致时成立：此时包内唯一剩下的查找路径就是「引用文件所在目录」，裸文件名由此命中。`.lib`/`.dll`/`.pdb` 落 `build/native/lib/`，`.targets` 不为 `lib/` 下发任何搜索根，裸文件名必然解析不到，故不做这条改写。

引号与尖括号按同一包布局判据检查可解析性，唯一区别是尖括号不查「引用文件所在目录」（MSVC 只对 `"..."` 先查本文件目录，`<...>` 直接走搜索路径）。尖括号缺失只报告、不自动修改，且仅当首段命中包内 include 根下的子目录（`<gtest/...>` 这类引用包内命名空间的形式）时才报，`<vector>` 之类系统头不报。

只报告不修改的情况：按包内落点去重后仍有多个同名候选、包内找不到同名文件、唯一候选两条规则都不适用（既不在 include 根之下，又不落 `files/` 或不同目录）。外部依赖引用（首段目录不落在包内）不报告。

> 风险：修复直接写回用户自有源码树且不可撤销。对**没有 `build.py`** 的目录，构建后那次不触发、只剩导出前这一次兜底，误判造成的改写会长期留在源码里。当前提示只报修复数量、不列 `文件:行 原值 → 新值` 明细，出问题时难以定位。

## 构建配方

源目录根部存在 `build.py` 时，应用按以下约定执行构建：

- `build.py` 是**普通 Python 脚本**，工具不解析其内容——没有头部指令、没有键值声明，所有约定一律经下述环境变量给出。
- 默认流程是准备编译环境（检测编译器、捕获其环境、装配 `PATH` 与 `CNP_*`）、清空中间产物区、执行 `python -u build.py`、检查头文件引用并自动重新映射。
- 脚本的 CWD 就是包源目录，产物直接写在这个目录下（工具扫全树打包）。

### 构建期环境变量

注入的变量**恰为五个**：

| 变量 | 含义 |
| ---- | ---- |
| `CNP_PACKAGE_ROOT` | 包源目录绝对路径（等于 CWD，显式给出以便配方 `chdir` 后仍可用）。产物写这里。 |
| `CNP_SRC_DIR` | `<包源目录>/.cache/src`，源码区，**完全由配方掌控**。 |
| `CNP_TMP_DIR` | `<包源目录>/.cache/tmp`，中间产物区；软件每次构建前清空并重建。 |
| `CNP_TOOLS_DIR` | 跨包共享的工具根目录。 |
| `CNP_COMPILER` | 检测到的首选编译器可执行文件全路径。 |

此外固定注入 `PYTHONIOENCODING=utf-8`，保证管道中的 stdout/stderr 恒为 UTF-8。

**不再注入**：`SRC_PATH`、`BUILD_OUT`、`CNP_CMAKE`、`CNP_NINJA`、`CNP_C_COMPILER`、`CNP_CXX_COMPILER`、`CNP_COMPILER_KIND`、`CNP_OPTION_*`、`PYTHONPATH`。按旧写法读这些变量会直接 `KeyError`。

编译器环境无需配方自己准备：软件只对**选中的首选编译器**执行其环境批处理并捕获结果，配方因此继承一份已可用的 MSVC / ICX 环境。支持的编译器只有 ICX / clang-cl / MSVC 三种，默认按 `ICX > clang-cl > MSVC` 优先级选择（可在设置页调整）；配方只拿得到 `CNP_COMPILER` 路径，**拿不到编译器种类标识**。

### 软件对文件系统做什么、不做什么

- **软件不下载任何工具链**，也不会替你把某个工具准备好。要用的 CMake、Ninja、nasm 与第三方依赖，由配方自己放进共享工具目录或任何别处。
- `CNP_TOOLS_DIR` **自身及其下所有子目录**（递归、不限深度）都会前置到子进程的 `PATH`。因此配方按命令名直接调用即可（`cmake`、`nasm`），无需知道工具目录的内部布局。
- **源码由配方自己放到 `CNP_SRC_DIR`**。软件不拷贝任何源码、不探测预置源码目录——`.cnp-src/` 约定已取消。
- 软件对目录唯一的干预是**每次构建前清空并重建 `CNP_TMP_DIR`**，保证配方从干净的中间产物区开始。`CNP_SRC_DIR` 与配方自行下载的产物**跨构建保留**——是否复用、复用多少由配方自己权衡。
- 软件**不清理包源目录**，构建后的残留由配方自理。

### 配方需要知道的全部

1. 产物直接写在 `CNP_PACKAGE_ROOT` 下（工具扫全树打包）。
2. 源码放 `CNP_SRC_DIR`，中间产物放 `CNP_TMP_DIR`。
3. 编译器路径在 `CNP_COMPILER`；工具链、依赖、环境全自理。
4. 产物不能落在扫描会跳过的位置：隐藏目录，以及名为 `build` / `out` 的目录。

软件不替配方决定任何编译参数：指令集、优化等级、链接时优化、运行库家族（MD / MT）与语言标准全部由配方自行决定，可向 CMake 传任意 `-D` 参数（如 `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`、`-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON`）；不传时沿用 CMake 缺省。

### 最小配方示例

```python
import os
import shutil
import subprocess
from pathlib import Path

PACKAGE_ROOT = Path(os.environ["CNP_PACKAGE_ROOT"])
SRC = Path(os.environ["CNP_SRC_DIR"])
TMP = Path(os.environ["CNP_TMP_DIR"])
OUT = PACKAGE_ROOT / "lib"

TMP.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run(["cmake", "-S", str(SRC), "-B", str(TMP), "-G", "Ninja"], check=True)
subprocess.run(["cmake", "--build", str(TMP), "--config", "Release"], check=True)
shutil.copy(TMP / "zlib.h", OUT / "zlib.h")
shutil.copytree(TMP / "Release", OUT, dirs_exist_ok=True)
```

## 构建与运行

环境要求：

- Windows 10/11；项目仅提供 Windows 桌面平台。
- Flutter stable（项目按 `>=3.44.0` 维护）和 Dart SDK `^3.13.2`。
- Visual Studio C++ 工具链与 Windows SDK，用于构建 Windows 桌面应用；项目使用 C++17、`/W4 /WX`。
- Python（执行配方需要；`python` 不可用时回退 `py -3`）。软件**不下载任何工具链**——配方要用的 CMake、Ninja、nasm 等需自备；放进共享工具目录 `tools/` 即可，该目录及其各级子目录会前置到构建子进程的 `PATH`。

```text
flutter pub get
flutter run -d windows
flutter analyze
flutter test
flutter build windows --release
```

Windows Release 产物位于 `build/windows/x64/runner/Release/`。CI 的门禁顺序为 `flutter pub get → flutter analyze → flutter test → flutter build windows --release`。

## 配置文件

配置保存在工作目录相对的 `config/`，用于便携运行；`config/` 已在 `.gitignore` 中排除。

```text
config/
├── config.yaml
└── packs/
    └── <包ID>.yaml
```

`config.yaml` 保存全局设置：

| 字段 | 说明 |
| ---- | ---- |
| `outputDirectory` | NuGet 打包输出目录。 |
| `themeMode` | `system`、`dark` 或 `light`。 |
| `compilerPriority` / `detectedCompilers` | 编译器优先级（默认 `ICX > clang-cl > MSVC`）与检测缓存（ICX / clang-cl / MSVC）。 |

每个 `packs/<包ID>.yaml` 保存一个包：

| 字段 | 说明 |
| ---- | ---- |
| `name` / `version` / `author` | 必填；`name` 同时决定配置文件名和包 ID。 |
| `description` / `license` / `iconPath` / `sourcePath` | 可选的包元数据与源目录。 |
| `files` | 文件快照（`path`/`size`）。 |
| `dependencies` | 包依赖（`name`/`version`）。 |
| `commands` / `macros` / `libDirectories` / `libraries` | 编译集成配置，条目可带 `buildModel`。 |
| `scripts` | 节点脚本项目、节点、连线和视口数据。 |
| `history` | 创建、版本变更、重新映射、导出和构建历史。 |

`buildModel` 取值为 `all`、`release` 或 `debug`。损坏或缺少必填字段的包配置会被跳过，应用启动后以悬浮提示列出问题文件。

## 版本与发布

- 当前版本：`pubspec.yaml` 中的 `26.3.0+1`；关于页显示 `26.3`。`lib/app_info.dart` 的 `appVersion` 与 pubspec 的一致性由 `test/app_info_test.dart` 校验。
- 版本号唯一来源是 `pubspec.yaml` 的 `version:`。版本方案采用“年份.年内发布数量”，例如 `26.3`；没有发布意图时不要修改版本号。
- 推送到 `dev` 或 `master` 会运行 CI：依赖安装、静态分析、测试和 Windows Release 构建；`dev` 只验证不发布。
- 只有推送到 `master` 且验证通过时才创建 GitHub Release，tag 为 `v<版本>`，资产为 `dist/cpp_nuget_pack-<版本>-win-x86_64.zip`。
- 修改 `pubspec.yaml` 版本号并推送 `master` 即会触发发布流程。

## 技术栈

| 组件 | 用途 |
| ---- | ---- |
| Flutter / Dart | Windows 桌面应用框架与业务逻辑。 |
| [fluent_ui](https://pub.dev/packages/fluent_ui) | Fluent 风格桌面控件。 |
| [file_selector](https://pub.dev/packages/file_selector) | 系统原生目录和保存位置选择。 |
| [flutter_svg](https://pub.dev/packages/flutter_svg) | SVG 图标渲染。 |
| [yaml](https://pub.dev/packages/yaml) / [yaml_edit](https://pub.dev/packages/yaml_edit) | YAML 配置读取与生成。 |
| [archive](https://pub.dev/packages/archive) | NuGet OPC/ZIP 压缩。 |

## 第三方声明

第三方组件许可与来源声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。其中包括 Catppuccin Icons for VSCode v1.26.0 的图标子集。

## 交流群

- QQ: 112986834
