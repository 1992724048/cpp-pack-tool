<div align="center">
<picture><source media="(prefers-color-scheme: dark)" srcset="./logo/logo.png"><source media="(prefers-color-scheme: light)" srcset="./logo/logo.png"><img alt="CCPPP C/C++ 包管理工具" src="./logo/logo.png" width="128"></picture>

# CCPPP — C/C++ 包管理工具

项目状态：开发中

第三方组件许可与来源声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

</div>

CCPPP（C++ PackTool）是仅支持 Windows 的 Flutter 桌面应用，用于把 C/C++ 头文件、源码和库组织为 NuGet 包。它既支持从本地目录添加包，也支持由 `build.py` 配方自行把源码放到 `CNP_SRC_DIR`、在只读检测到编译环境后执行构建并重新映射。

## 功能特性

| 功能 | 说明 |
| ---- | ---- |
| 包管理 | 选择目录并扫描文件，添加、编辑、删除包；包 ID 只读，可重新映射源目录。 |
| 文件管理 | 目录树展示文件大小与目录后代统计；双击文件使用系统默认程序打开；库、动态库、调试文件及源码按路径显示 Release/Debug 标签。 |
| 依赖管理 | 从现有包选择依赖，编辑 NuGet 版本范围；缺失依赖有明确标记，并提供可拖拽平移、缩放的依赖关系图。 |
| 编译设置 | 管理宏定义、编译前/后命令、附加库目录和附加库，条目可按 ALL/Release/Debug 分组；可接入根级 `pre.bat`/`post.bat` 系统命令。 |
| 构建 | 源目录根部存在 `build.py` 时显示构建入口；只读检测编译器环境（不下载任何工具链），把共享工具目录及其各级子目录前置到子进程 `PATH`，执行脚本、检查头文件引用并重新映射。 |
| 打包设置 | 预览 NuGet 包内的文件树和文本内容后导出；导出前再检查一次头文件引用。 |
| 历史记录 | 记录创建、版本变更、重新映射、打包导出和构建事件，时间线最多保留 100 条，可删除单条记录。 |
| 设置与关于 | 配置 NuGet 输出目录、主题与编译器优先级；关于页显示应用信息与项目主页。 |

## 构建配方

源目录根部存在 `build.py` 时，应用按以下约定执行构建：

- `build.py` 是**普通 Python 脚本**。
- 默认流程是准备编译环境（检测编译器、捕获其环境、装配 `PATH` 与 `CNP_*`）、清空中间产物区、执行 `python -u build.py`、检查头文件引用并自动重新映射。
- 脚本的 CWD 就是包源目录，产物直接写在这个目录下（工具扫全树打包）。

### 构建期环境变量

| 变量 | 含义 |
| ---- | ---- |
| `CNP_PACKAGE_ROOT` | 包源目录绝对路径（等于 CWD，显式给出以便配方 `chdir` 后仍可用）。产物写这里。 |
| `CNP_SRC_DIR` | `<包源目录>/.cache/src`，源码区，**完全由配方掌控**。 |
| `CNP_TMP_DIR` | `<包源目录>/.cache/tmp`，中间产物区；软件每次构建前清空并重建。 |
| `CNP_TOOLS_DIR` | 跨包共享的工具根目录。 |
| `CNP_COMPILER` | 检测到的首选编译器可执行文件全路径。 |

此外固定注入 `PYTHONIOENCODING=utf-8`，保证管道中的 stdout/stderr 恒为 UTF-8；并把 `TMP`/`TEMP` 指向 `CNP_TMP_DIR`，故配方用 `tempfile` 拿到的目录同样落在每次构建前清空的中间产物区。

### 配方需要知道的全部

1. 产物直接写在 `CNP_PACKAGE_ROOT` 下（工具扫全树打包）。
2. 源码放 `CNP_SRC_DIR`，中间产物放 `CNP_TMP_DIR`。
3. 编译器路径在 `CNP_COMPILER`；工具链、依赖、环境全自理。
4. 产物不能落在扫描会跳过的位置：隐藏目录，以及名为 `build` / `out` 的目录。

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

### .lib / .a 的配置隔离约定

自动派生的 `.lib` 与 `.a` 适用同一约定：按**包内路径中的 `release` / `debug` 目录名**判定配置。

| 路径 | 生效范围 |
| --- | --- |
| `files/library/x64/Release/foo.lib` | 仅 `Configuration=Release` |
| `files/library/x64/Debug/foo.lib` | 仅 `Configuration=Debug` |
| `files/library/foo.lib` | 所有配置 |

判定细则：

- **大小写不敏感** —— `Release` / `RELEASE` / `release` 等价。
- **多段命中取最后一个** —— `files/library/release/Debug/foo.lib` 归 `Debug`，越靠近文件名的目录段语义最强。

写进 `.targets` 的附加库条目用的是包内文件名（如 MinGW 的 `libz.dll.a` 原样写入），链接器是否接受取决于工具链。

**目录名即契约**：把 `Release` 目录改名会让该文件退回「所有配置」，链接器可能挑到错误版本且不报错。

## 包消费契约

包靠 `build/native/<包ID>.targets` 与 `build/<包ID>.props` 接入消费方工程。下面五条都是**隐式约定**，违反后 NuGet 与 MSBuild 一律不报错、只静默失效：

| # | 约定 | 违反后果 |
| ---- | ---- | ---- |
| 1 | `.targets` 所在路径的 `native` 段名必须**字面一致** | 改成 `build/native/x64/` 之类四段路径，整个 `.targets` 静默不导入，零报错 |
| 2 | 文件名必须**恰好**是 `<包ID>.targets` / `<包ID>.props` | 改名后静默不导入 |
| 3 | 消费方项目必须是 `.vcxproj`（C++/CLI 亦可） | 其它项目类型不导入 |
| 4 | 产物不得落 `.` 开头或名为 `build` / `out` 的目录（任意层级） | 扫描器静默跳过，不进包、不报错 |
| 5 | `.lib` / `.a` 的配置隔离靠路径里的 `release` / `debug` 段（大小写不敏感、多段命中取最后一个） | 目录改名后隔离静默失效，链接器挑到错误版本 |

第一条最反直觉，值得单独说明：`build/native/` 之所以能生效，**纯粹因为 `native` 恰好是 NuGet 为 `.vcxproj` 硬编码的字面目标框架标识 `native@0.0`**。这不是能自然理解的规则，调整包内布局时务必让 `native` 原样保留。`build/<包ID>.props` 则是两段路径（等价于 `any`），任何目标框架的项目都会导入。

## 交流群

- QQ: 112986834
