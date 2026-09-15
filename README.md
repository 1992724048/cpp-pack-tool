# C++ NuGet 打包工具

把 C++ 头文件、源码与库可视化为原生 NuGet 包的 Windows 桌面工具。通过图形界面完成包信息编辑、目录映射、依赖与编译设置，并一键导出 Visual Studio C++ 工程可直接引用的 `.nupkg`，或供 CMake `find_package` 消费的配置包。

- 平台：仅 Windows 桌面
- 界面：全中文、Win11 风格（fluent_ui）、Catppuccin 配色
- 数据：配置保存在程序目录下的 `config/`，便携、无需安装

## 功能特性

| 功能 | 说明 |
| ---- | ---- |
| 包管理 | 添加文件夹（自动扫描后填写包信息）、编辑版本/作者/许可证/描述（包 ID 不可改）、删除包、重新映射源目录 |
| 文件管理 | 目录树展示包内文件（目录大小按后代聚合）；双击用系统默认程序打开；lib/dll/pdb/exe 按路径显示 Release/Debug 构建标签 |
| 构建 | 源目录根部含 `build.py` 时「文件管理」页显示「构建」按钮：自动拉取 git 源码到 `cache/`（二次构建原位硬重置，预构建包复用本地缓存不重复下载）并执行构建脚本（`SRC_PATH`/`BUILD_OUT` 环境变量；源码就绪后、执行构建脚本前清空包源目录产物（保留 `build.py`/`icon.*`/钩子脚本/根级 `.git` 与许可证）），成功后自动重新映射；构建前自动准备环境——检测本机编译器（默认优先 ICX > clang-cl > MSVC > MinGW，可在设置调整）、捕获编译器环境（vcvars/setvars）、按需下载 CMake/Ninja 到 `tools/`；`build.py` 头部可声明 `# tool`（需自动下载的环境工具，如 NASM/Perl）与 `# option`（构建选项，工具栏内随选随存、构建时经 `CNP_OPTION_*` 下发）；分类辅助模块 `cnp_build_support.py` 随构建释放，脚本可经 `PYTHONPATH` import 完成 CMake 装配与产物分类；`build.py` 不进入打包产物；产物按 `release/`、`debug/` 分层分类（源码构建自动注入 AVX2、Release 最高优化与 LTO（可退化）、多线程构建参数）；构建输出实时显示于进度对话框右侧面板（ERROR/WARNING/INFO 高亮）；源目录根部 `pre.bat`/`post.bat` 与头部 `# depends` 自动注册为系统条目（编译前/后命令与依赖，界面禁改删）；`# source: none` 支持预构建配方；含仓库的包在侧栏显示 git/更新徽标，文件管理页显示当前与最新版本号 |
| 依赖管理 | 从现有包选择依赖，自定义 NuGet 版本范围并实时校验；指向不存在包的依赖显示「缺失」 |
| 编译设置 | 宏定义、编译前/后命令（可从包内选择脚本、插入 MSBuild 常用宏）、附加库目录、附加库；条目可按 ALL/Release/Debug 分组；「节点脚本」分区提供可视化节点编辑器（节点图随包分发并自动执行，见「节点脚本」） |
| 打包设置 | 选择打包格式（NuGet / CMake）；预览包内文件树与文本内容；按所选格式导出（缺失依赖时弹窗提醒，可继续；导出前校验节点脚本与包内可执行二进制，提示后仍可继续/取消） |
| 历史记录 | 时间线记录创建、版本变更、重新映射、打包导出四类事件（上限 100 条，可删除） |
| 依赖关系图 | 全部包的依赖关系可视化：可拖拽平移、滚轮缩放；缺失依赖红色标注，当前包高亮 |
| 设置 | 打包输出目录；编译器优先级（ICX/clang-cl/MSVC/MinGW，检测本机版本、可排序与重新检测；检测结果缓存至 `detectedCompilers`，有缓存时免检测直接显示、「重新检测」刷新并写回）；SKILL.md 生成（内置模板写出，供分发给 AI 插件）；主题模式（系统/深色/浅色）、深色配色（Frappe/Macchiato/Mocha）与强调色，即时生效并持久化 |

## 打包产物

导出文件命名为 `<包ID>.<版本>.nupkg`（版本去掉 `+build` 后缀），内部布局：

| 内容 | 包内路径 | 说明 |
| ---- | -------- | ---- |
| 头文件 / 模块 | `build/native/include/<源目录名>/...` | 剥离开头 `include/` 后再套一层源目录名作命名空间（源目录已自带同名目录时不再叠加，避免重复层），消费者可写 `#include <源目录名/foo.h>` 防冲突；源目录缺失时回退包名 |
| lib / dll / pdb | `build/native/lib/...` | 剥离开头 `lib/`、`bin/` |
| 其余文件 | `build/native/files/...` | 保留原相对路径，全部入包（含 `.exe` 等可执行二进制，导出时提示随包分发） |
| 包清单 | `<包ID>.nuspec` | 许可证用 SPDX 表达式；依赖组 `native0.0`；恒定声明包图标 |
| MSBuild 集成 | `build/native/<包ID>.targets` | 为消费者工程提供编译集成，见下 |
| 节点脚本 | `build/native/files/scripts/<id>.ps1` | 由节点编辑器生成（UTF-8 BOM）；`<id>` 形如 `script_1`；无节点脚本时不产生 |
| 包图标 | `images/icon.png` | 从包图标自动转换，等比缩放至最长边不超过 128；缺失时使用默认纸箱图标 |

`<包ID>.targets` 为消费者工程提供：

- 自动把 `build/native/include` 追加到包含路径
- 写入宏定义、附加库目录与附加库（按 ALL/Release/Debug 条件分组；包内 `.lib` 按路径自动识别配置，同时补充库目录与库名）
- 编译前/后命令以自定义目标自动执行：`CnpPreBuild_<包ID清洗>_<hash8>`（`BeforeTargets="ClCompile"`）/ `CnpPostBuild_<包ID清洗>_<hash8>`（`AfterTargets="Build"`），每命令一条 `Exec`（工作目录 `$(ProjectDir)`，ALL/Release/Debug 条件在目标级，Release/Debug 组以 `_Release`/`_Debug` 后缀区分）
- 包内 dll/pdb 由 `DeployPkgRuntimeBinaries` 目标在构建后硬链接到 `$(OutDir)`（失败回退为拷贝，并登记 `FileWrites` 供清理）
- 包内包含 `.asm` 时条件导入 VS 的 `masm.props`/`masm.targets`，生成 `MASM` 项
- 包内包含 `.rc` 时生成 `ResourceCompile` 项
- 节点脚本以每个触发时机一个目标自动执行：`CnpScripts_<包ID清洗>_<hash8>_Pre` / `..._Post`（`hash8` 为包 ID 的 SHA-1 前 8 位，防跨包目标重名覆盖），见「节点脚本」

> 命令注入修复（自定义 `Exec` 目标）随导出生成于 `.targets`，不回溯既有包：已导出包需重新打包才会带上修复，旧包内仍为旧机制。

### 节点脚本

在「编译设置」→「节点脚本」分区打开可视化节点编辑器（内置 51 种节点）；节点图随包分发，导出 NuGet 包时自动生成执行目标：

- **生成脚本**：`build/native/files/scripts/<id>.ps1`（`<id>` 形如 `script_1`，ASCII 安全文件名），以 UTF-8 BOM 写入，保证 PowerShell 5.1 正确解析脚本中的中文；脚本入口先将 `PSModulePath` 全量归一为 `$PSHOME\Modules`（不保留继承的自定义模块路径），避免中间进程链（如 PowerShell 7）的模块路径遮蔽 5.1 自带模块
- **执行目标**：每个触发时机一个目标——`CnpScripts_<包ID清洗>_<hash8>_Pre` 早于消费者 `PreBuildEvent` 与编译；`..._Post` 晚于运行时二进制部署（包内无 dll/pdb 时为构建之后）。`<包ID清洗>` 将包 ID 中非 `[A-Za-z0-9_]` 字符替换为 `_`；`hash8` 避免不同包的目标重名静默覆盖
- **任务**：每个脚本一条 `Exec`，以 `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File` 调用；顺序与编辑器脚本列表一致，失败即中止且只按退出码判定（不把 stderr 文本当失败）；按脚本的 ALL/Release/Debug 标签生成构建条件
- **节点语义**：`创建硬链接`仅支持同一卷上的文件——跨卷或目录目标会报错；`由十六进制写`的十六进制串忽略空白与连字符后，须为偶数长度且仅含十六进制字符，奇数长度或非法字符时脚本报错中断（十六进制串与字节数组整体驻留内存，不适用于大文件）；`查找工具`用 `Get-Command -CommandType Application` 探测（防别名误中），未命中再按候选路径展开环境变量探测，结果分「是否找到」/「路径」两输出（每次输出各探测一次）；`下载文件`/`上传文件`用 `Net.WebClient`（上传方法默认 PUT）；`包内脚本文件`输出 `Join-Path $env:CNP_PackageRoot` 组合的包内路径；`运行包内脚本`按扩展名分派解释器（ps1 → `powershell.exe -File`、py → `python`、bat/cmd/exe 直调），参数按行拆分、工作目录临时切换、失败默认中止（可关）
- **变量系统**：`写入数值变量`/`读取数值变量`/`写入文本变量`/`读取文本变量` 四个节点读写脚本变量（发射为 `$var_<名称> = 值` / `$var_<名称>`）；名称须以字母或下划线开头且仅含字母、数字、下划线；变量名大小写不敏感，同一名称只能用于一种类型，混用会报校验错误。脚本顶部自动为用到的变量注入初始化——数值 `0`、文本 `''`，按名称字典序；初始化收集口径为**生成路径上的变量**（不可达节点不参与生成），读取永不为 `$null`。变量为动态作用域（循环体内赋值对外可见），且每次脚本执行在独立 `powershell.exe` 进程中进行——变量不跨脚本共享。变量配合 `while`/`branch` 与算术、比较即可表达任意计算（图灵完备可达）
- **环境变量**：恒传 `CNP_PackageRoot`（包根 `build/native/`）；节点中用到的 MSBuild 宏按白名单转成 `CNP_<宏名>`（如 `CNP_OutDir`）；`$(SolutionDir)` 在单项目构建下为 `*Undefined*`
- **CMake 格式不接入节点脚本**：CMake 预览与导出产物均不包含脚本条目

> **安全声明**：节点脚本与手写编译前/后命令一样，会在**消费方构建机**上自动执行（供应链语义）；「运行程序」节点即任意命令执行面，请仅消费可信来源的包。包内若含可执行二进制（`.exe`），导出时会提示其随包分发并被脚本在构建时调用，同样请确认来源可信。AES 加解密与代码签名节点的口令请优先使用「口令环境变量名」方式——直接填写的口令**字面量会随包分发**。
>
> **执行策略提示**：脚本以 `-ExecutionPolicy Bypass` 启动，该参数**无法覆盖企业组策略（GPO）**强制的脚本执行限制；受管控环境请先确认策略允许。

### CMake 配置包

选择 CMake 格式导出时生成 `<包ID>-<版本>-cmake.zip`；解压后将目录加入 `CMAKE_PREFIX_PATH` 即可在 CMake 工程中消费：

```cmake
find_package(<包名> CONFIG REQUIRED)
target_link_libraries(app PRIVATE <包名>::<包名>)
```

| 内容 | 包内路径 | 说明 |
| ---- | -------- | ---- |
| 头文件 / 模块 | `include/<源目录名>/...` | 与 NuGet 产物相同的命名空间策略（源目录已自带同名目录时不再叠加），`#include <源目录名/foo.h>` |
| lib / dll / pdb | `lib/...` | 剥离开头 `lib/`、`bin/`，保留 Release/Debug 子目录结构 |
| 其余文件 | `files/...` | 保留原相对路径 |
| CMake 配置 | `lib/cmake/<包名>/` | `Config.cmake`、`Targets.cmake`（`<包名>::<包名>` INTERFACE IMPORTED 目标、`.lib` 按 Debug/Release 分组条件链接）与 `ConfigVersion.cmake`（版本为数字点分时生成） |

> DLL 不参与链接，需消费方自行拷贝到运行目录（例如 `$<TARGET_RUNTIME_DLLS>` 或手动复制）。
>
> v1 不接入节点脚本：CMake 预览与导出产物均不包含节点脚本条目（仅 NuGet 格式支持）。

## 构建与运行

环境要求：

- Windows 10/11
- Flutter stable（建议 3.44.0 及以上，Dart SDK `^3.13.2`）
- Visual Studio C++ 工具链（含 Windows SDK，用于构建 Windows 桌面产物）

```text
flutter pub get
flutter run -d windows          # 本地运行
flutter analyze                 # 静态检查（要求零问题）
flutter test                    # 运行测试
flutter build windows --release # 产物位于 build/windows/x64/runner/Release/
```

## 配置文件

配置保存在工作目录相对的 `config/`（便携，程序目录即数据目录）：

```text
config/
├── config.yaml          # 全局设置
└── packs/
    └── <包 ID>.yaml     # 每个包一个文件（同 ID 覆盖）
```

`config.yaml` 保存打包输出目录、编译器优先级、编译器检测结果缓存（`detectedCompilers`：设置页有缓存时免检测直接显示、「重新检测」刷新并写回；构建优先复用缓存，缺失/失效时自动重检并写回）与主题设置。包 YAML 字段：

| 字段 | 说明 |
| ---- | ---- |
| `name` / `version` / `author` | 必填；`name` 同时决定配置文件名与 NuGet 包 ID |
| `description` / `license` / `iconPath` / `sourcePath` | 可选；`license` 为 SPDX 表达式 |
| `files` | 文件快照（`path`/`size`），由扫描与重新映射写入 |
| `dependencies` | 依赖列表（`name`/`version`，版本范围；`system: true` 为 `# depends` 自动注册） |
| `commands` | 编译前/后命令（`command`/`type`/`buildModel`；`system: true` 为 `pre.bat`/`post.bat` 自动注册） |
| `macros` | 宏定义（`value`/`buildModel`） |
| `libDirectories` | 附加库目录（`path`/`buildModel`） |
| `libraries` | 附加库（`name`/`buildModel`） |
| `buildOptions` | 构建选项（`{<名称>: <值>}`，由 `build.py` 头部 `# option` 声明；空省略） |
| `sourceVersion` | 上次构建记录的仓库版本（git tag 或短哈希；空省略） |
| `history` | 历史记录（`time`/`type`/`message`，上限 100 条） |
| `scripts` | 节点脚本（`id`/`name`/`trigger`/`buildModel` + 节点图 `nodes`/`edges`/视口；单条损坏仅丢弃该脚本） |

其中 `buildModel` 取值为 ALL / Release / Debug。配置文件损坏或缺必填字段不会导致启动失败，启动后会以悬浮提示列出问题文件。

执行「构建」时下载的源码缓存在工作目录的 `cache/`（可随时删除；再次构建会按需重新下载）；构建环境准备按需下载的工具缓存在 `tools/`（同为本地缓存；本机已有可用的 CMake（≥ 3.25）/Ninja/Python 时优先直接使用，否则自动解析官方最新版本下载最小版；编译器完全缺失时下载 LLVM clang 兜底；构建子进程使用受控 TMP 目录 `tools/.tmp/`）；`build.py` 头部 `# tool` 声明的环境工具同样下载到 `tools/<名称>/`，构建前释放的 `cnp_build_support.py` 也在 `tools/`（均可随时删除）。

## 版本与发布

- 版本号采用「年份.年内发布数量」方案：`26.1` 表示 2026 年第 1 次发布，年内依次递增（`26.2`、`26.3`…），次年从 `27.1` 重新计数；更早的 `1.0.x` 为历史版本号。
- 版本号唯一来源是 `pubspec.yaml` 的 `version:`（格式 `26.1.0+<构建号>`，第三段固定为 0）；发布时同步更新 `lib/app_info.dart` 的 `appVersion`（去掉 `+build` 与末尾 `.0`，即 `26.1.0+1` → `26.1`），两者一致性由 `test/app_info_test.dart` 强制校验。
- `dev` 分支：推送触发 CI（静态检查 → 测试 → Windows Release 构建），只验证不发布。
- `master` 分支：验证通过后打包 `dist/cpp_nuget_pack-<版本>-win-x86_64.zip`，并创建 GitHub Release（tag `v<版本>`，如 `v26.1`）。
- 因此修改版本号并推送到 `master` 即等于发布；没有发布意图时不要改动版本号。

## 技术栈

| 组件 | 用途 |
| ---- | ---- |
| Flutter / Dart | 应用框架（仅 Windows 桌面） |
| [fluent_ui](https://pub.dev/packages/fluent_ui) | Win11 风格控件 |
| [flutter_svg](https://pub.dev/packages/flutter_svg) | SVG 图标渲染 |
| [catppuccin_flutter](https://pub.dev/packages/catppuccin_flutter) | Catppuccin 配色方案 |
| [yaml](https://pub.dev/packages/yaml) / [yaml_edit](https://pub.dev/packages/yaml_edit) | YAML 配置解析与生成 |
| [archive](https://pub.dev/packages/archive) | `.nupkg` / CMake 配置包（ZIP）组装 |
| [file_selector](https://pub.dev/packages/file_selector) | 系统原生目录选择 / 保存位置对话框 |

## 第三方声明

目录树图标来自 [Catppuccin Icons for VSCode](https://github.com/catppuccin/vscode-icons)（v1.26.0，MIT 许可）的图标子集；完整第三方组件许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
