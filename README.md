# C++ NuGet 打包工具

把 C++ 头文件、源码与库可视化为原生 NuGet 包的 Windows 桌面工具。通过图形界面完成包信息编辑、目录映射、依赖与编译设置，并一键导出可直接被 Visual Studio C++ 工程引用的 `.nupkg`。

- 平台：仅 Windows 桌面
- 界面：全中文、Win11 风格（fluent_ui）、Catppuccin 配色
- 数据：配置保存在程序目录下的 `config/`，便携、无需安装

## 功能特性

| 功能 | 说明 |
| ---- | ---- |
| 包管理 | 添加文件夹（自动扫描后填写包信息）、编辑版本/作者/许可证/描述（包 ID 不可改）、删除包、重新映射源目录 |
| 文件管理 | 目录树展示包内文件（目录大小按后代聚合）；双击用系统默认程序打开；lib/dll/pdb/exe 按路径显示 Release/Debug 构建标签 |
| 依赖管理 | 从现有包选择依赖，自定义 NuGet 版本范围并实时校验；指向不存在包的依赖显示「缺失」 |
| 编译设置 | 宏定义、编译前/后命令（可从包内选择脚本、插入 MSBuild 常用宏）、附加库目录、附加库；条目可按 ALL/Release/Debug 分组 |
| 打包设置 | 选择打包格式（当前支持 NuGet）；预览包内文件树与文本内容；一键导出 `.nupkg` |
| 历史记录 | 时间线记录创建、版本变更、重新映射、打包导出四类事件（上限 100 条，可删除） |
| 设置 | 打包输出目录；主题模式（系统/深色/浅色）、深色配色（Frappe/Macchiato/Mocha）与强调色，即时生效并持久化 |

## 打包产物

导出文件命名为 `<包ID>.<版本>.nupkg`（版本去掉 `+build` 后缀），内部布局：

| 内容 | 包内路径 | 说明 |
| ---- | -------- | ---- |
| 头文件 / 模块 | `build/native/include/<源目录名>/...` | 剥离开头 `include/` 后再套一层源目录名作命名空间，消费者可写 `#include <源目录名/foo.h>` 防冲突；源目录缺失时回退包名 |
| lib / dll / pdb | `build/native/lib/...` | 剥离开头 `lib/`、`bin/` |
| 其余文件 | `build/native/files/...` | 保留原相对路径，全部入包 |
| 包清单 | `<包ID>.nuspec` | 许可证用 SPDX 表达式；依赖组 `native0.0`；恒定声明包图标 |
| MSBuild 集成 | `build/native/<包ID>.targets` | 为消费者工程提供编译集成，见下 |
| 包图标 | `images/icon.png` | 从包图标自动转换，等比缩放至最长边不超过 128；缺失时使用默认纸箱图标 |

`<包ID>.targets` 为消费者工程提供：

- 自动把 `build/native/include` 追加到包含路径
- 写入宏定义、附加库目录与附加库（按 ALL/Release/Debug 条件分组；包内 `.lib` 按路径自动识别配置，同时补充库目录与库名）
- 编译前/后命令写入 `PreBuildEvent`/`PostBuildEvent`（保留消费者工程已有值）
- 包内 dll/pdb 由 `DeployPkgRuntimeBinaries` 目标在构建后硬链接到 `$(OutDir)`（失败回退为拷贝，并登记 `FileWrites` 供清理）
- 包内包含 `.asm` 时条件导入 VS 的 `masm.props`/`masm.targets`，生成 `MASM` 项
- 包内包含 `.rc` 时生成 `ResourceCompile` 项

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

`config.yaml` 保存打包输出目录与主题设置。包 YAML 字段：

| 字段 | 说明 |
| ---- | ---- |
| `name` / `version` / `author` | 必填；`name` 同时决定配置文件名与 NuGet 包 ID |
| `description` / `license` / `iconPath` / `sourcePath` | 可选；`license` 为 SPDX 表达式 |
| `files` | 文件快照（`path`/`size`），由扫描与重新映射写入 |
| `dependencies` | 依赖列表（`name`/`version`，版本范围） |
| `commands` | 编译前/后命令（`command`/`type`/`buildModel`） |
| `macros` | 宏定义（`value`/`buildModel`） |
| `libDirectories` | 附加库目录（`path`/`buildModel`） |
| `libraries` | 附加库（`name`/`buildModel`） |
| `history` | 历史记录（`time`/`type`/`message`，上限 100 条） |

其中 `buildModel` 取值为 ALL / Release / Debug。配置文件损坏或缺必填字段不会导致启动失败，启动后会以悬浮提示列出问题文件。

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
| [archive](https://pub.dev/packages/archive) | `.nupkg`（ZIP/OPC）组装 |
| [file_selector](https://pub.dev/packages/file_selector) | 系统原生目录选择 |

## 第三方声明

目录树图标来自 [Catppuccin Icons for VSCode](https://github.com/catppuccin/vscode-icons)（v1.26.0，MIT 许可）的图标子集；完整第三方组件许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
