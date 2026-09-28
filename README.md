<div align="center">
<picture><source media="(prefers-color-scheme: dark)" srcset="./logo/logo.png"><source media="(prefers-color-scheme: light)" srcset="./logo/logo.png"><img alt="CCPPP C/C++ 包管理工具" src="./logo/logo.png" width="128"></picture>

# CCPPP — C/C++ 包管理工具

项目状态：开发中

第三方组件许可与来源声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

</div>

CCPPP（C++ PackTool）是仅支持 Windows 的 Flutter 桌面应用，用于把 C/C++ 头文件、源码和库组织为 NuGet 包或 CMake 配置包。它既支持从本地目录添加包，也支持依据包内预置源码目录的 `build.py` 准备源码、准备编译环境、执行构建并重新映射；节点脚本编辑器可生成 PowerShell 5.1 脚本并随 NuGet 包发布。

## 功能特性

| 功能 | 说明 |
| ---- | ---- |
| 包管理 | 选择目录并扫描文件，添加、编辑、删除包；包 ID 只读，可重新映射源目录。 |
| 文件管理 | 目录树展示文件大小与目录后代统计；双击文件使用系统默认程序打开；库、动态库、调试文件及源码按路径显示 Release/Debug 标签。 |
| 依赖管理 | 从现有包选择依赖，编辑 NuGet 版本范围；缺失依赖有明确标记，并提供可拖拽平移、缩放的依赖关系图。 |
| 编译设置 | 管理宏定义、编译前/后命令、附加库目录和附加库，条目可按 ALL/Release/Debug 分组；可接入根级 `pre.bat`/`post.bat` 系统命令。 |
| 节点脚本 | 在画布上编排节点、连线、检查参数并预览 PowerShell 5.1 脚本；支持校验、诊断、串行防抖保存和失败重试。 |
| 构建 | 源目录根部存在 `build.py` 时显示构建入口；自动准备编译器与工具、准备源码、执行脚本、检查头文件引用并重新映射。 |
| 打包设置 | 为每个包启用 NuGet 或 CMake 格式，预览包内文件树和文本内容后导出；CMake 格式提供 `find_package` 配置包。 |
| 历史记录 | 记录创建、版本变更、重新映射、打包导出和构建事件，时间线最多保留 100 条，可删除单条记录。 |
| 设置与关于 | 配置 NuGet/CMake 输出目录、默认作者、主题与编译器优先级；关于页显示应用信息与项目主页。 |

## 打包产物

### NuGet 包（`.nupkg`）

导出文件名为 `<包ID>.<去 +build 版本>.nupkg`。NuGet 构建器在应用内生成包清单和 MSBuild 集成文件，再由 Dart 代码组装 `.nupkg`；不依赖外部 NuGet CLI、`nuget.exe` 或 `dotnet pack`。

| 内容 | 包内路径 | 说明 |
| ---- | -------- | ---- |
| 头文件 / 模块 | `build/native/include/<源目录名>/...` | 剥离开头 `include/` 后套源目录命名空间；首段已同名时不再叠加。 |
| `lib` / `dll` / `pdb` / `.a` | `build/native/lib/...` | 剥离开头 `lib` 或 `bin`；`.a` 是通用静态归档，一并归入库目录。 |
| 其余源文件 | `build/native/files/...` | 保留相对路径；根级 `build.py` 不入包。 |
| NuGet 清单 | `<包ID>.nuspec` | 由应用生成，记录版本、作者、许可证、依赖和图标引用。 |
| MSBuild 集成 | `build/native/<包ID>.targets` | 由应用生成，供消费者工程导入。 |
| 包图标 | `images/icon.png` | 从包图标转换并等比缩放至最长边不超过 128；缺失时使用默认纸箱图标。 |
| 节点脚本（可选） | `build/native/files/scripts/<id>.ps1` | 节点图生成的 UTF-8 BOM PowerShell 5.1 脚本。 |

`<包ID>.targets` 会追加头文件搜索路径，并按 ALL/Release/Debug 写入宏定义、附加库目录和附加库；包内 `.lib` 可按路径自动推导配置。包内 `dll`/`pdb` 在构建后优先硬链接到 `$(OutDir)`（失败时回退复制），许可证文件也按同样方式部署到 `$(OutDir)licenses`。编译前/后命令以带条件的自定义 `Exec` 目标执行；包内 `.asm` 和 `.rc` 分别生成 MASM 与资源编译项。节点脚本按 pre/post 阶段生成 MSBuild `Exec` 目标并传入 `CNP_*` 环境变量。

### CMake 配置包（`.zip`）

导出文件名为 `<包ID>-<去 +build 版本>-cmake.zip`，内容布局如下：

| 内容 | 包内路径 |
| ---- | -------- |
| 头文件 / 模块 | `include/<源目录名>/...` |
| `lib` / `dll` / `pdb` / `.a` | `lib/...` |
| 其余源文件 | `files/...` |
| CMake 配置 | `lib/cmake/<包名>/<包名>Config.cmake` |
| CMake 目标 | `lib/cmake/<包名>/<包名>Targets.cmake` |
| 版本文件 | `lib/cmake/<包名>/<包名>ConfigVersion.cmake`（版本为数字点分时生成） |

解压后把包根加入 `CMAKE_PREFIX_PATH`，即可使用 `find_package(<包名> CONFIG REQUIRED)`，并链接 `<包名>::<包名>`。两种格式都把 `.a` 视为通用静态归档：与 `.lib` 一样归入库目录并保留 `release`/`debug` 路径段（CMake 格式中按配置分组写入链接列表）。CMake 格式不包含节点脚本，根级 `build.py` 同样排除。

## 构建配方

源目录根部存在 `build.py` 时，应用按以下约定执行构建：

- 第一行必须是 `# source: <包内相对目录>`（严格锚点，不匹配即整头解析失败）；只提供预构建归档的配方写 `# source: none`。其后连续的 `#` 行可声明 `# tool`、`# option`、`# checkbox`、`# multiselect` 和 `# depends` 指令。
- 默认流程是准备构建环境、从预置源码目录备源、执行 `python -u build.py`、检查头文件引用并自动重新映射。
- 脚本在包源目录中运行，接收 `SRC_PATH`（源码/预构建缓存工作区）、`BUILD_OUT`（包源目录）、`CNP_*` 工具链与选项变量以及 `PYTHONIOENCODING=utf-8`。
- 工具链只支持 ICX / clang-cl / MSVC 三种编译器，默认按 `ICX > clang-cl > MSVC` 优先级选择（可在设置页调整），并以 `CNP_COMPILER_KIND`（`icx` / `clang-cl` / `msvc`）告知配方实际驱动；资源编译器不自动探测，仅消费显式 `CNP_RC_COMPILER`。
- 工具只传递编译器与工具链信息，不替配方决定任何编译参数：指令集、优化等级、链接时优化、运行库家族（MD / MT）与语言标准全部由配方自行决定，可经 `cmake_configure` 的 `extra_args` 传任意 `-D` 参数（如 `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`、`-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON`）；不传时沿用 CMake 缺省。
- `assets/build/cnp_build_support.py` 会在构建前释放到 `tools/`，供配方统一处理 CMake/Ninja 调用、产物分层、许可证和预构建归档分类。

### 预置源码目录的硬约束

`# source:` 声明的目录必须是包源目录下的**相对路径**（不得含盘符或 `..`），且**必须以 `.` 开头**（如 `.cnp-src/`）。以 `.` 开头同时满足两条约束，缺一不可：

| 约束 | 不满足的后果 |
| ---- | ---- |
| 以 `.` 开头 | 非隐藏名会被文件扫描扫进 `pack.files` 打进 `.nupkg`（体积暴涨），且会在下次构建被输出清理删除 |
| 已加入清理白名单 | 首次构建后目录即被删，第二次构建报「找不到目录」，根因反直觉 |

头部指令段是从第一行起连续的 `#` 行，**段内不得插入空行**（空行会终止头部解析）：分段请用 `#` 空注释行。另需注意——

- `# source: <dir>`：每次构建把该目录整树拷入 `SRC_PATH`，构建前先清空 `SRC_PATH` 上次构建的残留。
- `# source: none`：跳过备源，只把 `SRC_PATH` 建为空目录并**跨构建保留**，由脚本自行下载和解压产物。

## 构建与运行

环境要求：

- Windows 10/11；项目仅提供 Windows 桌面平台。
- Flutter stable（项目按 `>=3.44.0` 维护）和 Dart SDK `^3.13.2`。
- Visual Studio C++ 工具链与 Windows SDK，用于构建 Windows 桌面应用；项目使用 C++17、`/W4 /WX`。
- Python、CMake、Ninja 等构建工具缺失时，工具会按需准备；本机可用工具优先。

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
| `cmakeOutputDirectory` | CMake 配置包输出目录。 |
| `defaultAuthor` | 新包默认作者，并用于替换占位作者。 |
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
| `buildOptions` / `enabledFormats` | 构建选项和启用的打包格式；空的 `enabledFormats` 表示全部格式启用。 |
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
| [archive](https://pub.dev/packages/archive) | NuGet OPC/ZIP 与 CMake 配置包压缩。 |
| `assets/build/cnp_build_support.py` | 包内 `build.py` 配方使用的构建与产物分类辅助模块。 |

## 第三方声明

第三方组件许可与来源声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。其中包括 Catppuccin Icons for VSCode v1.26.0 的图标子集。

## 交流群

- QQ: 112986834
