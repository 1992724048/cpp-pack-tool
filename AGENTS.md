# cpp_nuget_pack

## Overview

「C++ NuGet 打包工具」：Flutter **Windows 桌面应用**（`.metadata` → `project_type: app`），目标是把 C++ 头文件/源码/库可视化成 NuGet 包。注意：

- **不是** Flutter 插件、**不是** C++ 库。名称里的 NuGet 只是应用的功能主题——构建管线与 CI 至今没有任何 NuGet 工具链集成（无 .nuspec/.targets/nuget.exe/dotnet pack）。
- 当前进度：「添加文件夹」全流程可用（目录选择 → 「添加包」表单 → 保存 YAML → 侧边栏列表更新），包列表/包信息/文件表均为真实数据（配置持久化在 `config/`，见 Architecture）；「依赖管理/编译设置/打包设置」3 个 Tab 与「删除/映射/打包/历史」4 个工具栏按钮回调仍为空；`lib/pages/setting.dart`、`lib/pages/about.dart` 仍是 0 字节空文件。
- 仅支持 Windows（无 android/ios/linux/macos/web 平台目录）。

## Commands

```text
flutter pub get
flutter analyze                    # 静态检查（CI 门禁，须零问题）；analysis_options.yaml 排除 build/**、windows/**、android/**
flutter test                       # 运行测试（test/：冒烟 + 模型 + 扫描 + 配置存储 + 对话框/接线 + 页面 + 列表/工具）
flutter build windows --release    # 产物：build/windows/x64/runner/Release/
flutter run -d windows             # 本地运行
```

- `pub get → analyze → test → build windows --release` 序列来自 `.github/workflows/ci.yml`（命令事实源）。
- Windows 构建走 CMake + MSVC（C++17、`/W4 /WX` 警告即错误，见 `windows/CMakeLists.txt`），需要 Visual Studio C++ 工具链；本机缺工具链时先 `flutter doctor` 确认，构建交给 CI。
- SDK 约束：Dart `^3.13.2`、Flutter `>=3.44.0`（本地环境 Flutter 3.47.2 stable）。

## 发布流程（勿误触发）

- **推送/合并到 `master` 即触发 CI 发布**：构建 → 打包 `dist/cpp_nuget_pack-<版本>-win-x86_64.zip` → 创建 GitHub Release（tag `v<版本>`）。CI 仅 push master 触发，无 PR 检查。
- 版本号唯一来源是 `pubspec.yaml` 的 `version:`（如 `1.0.1+1`；CI 去掉 `+build` 后缀，解析失败回退为时间戳）。同一版本经 CMake `FLUTTER_VERSION*` 宏注入 exe 文件版本（`windows/runner/Runner.rc`）。
- 所以「改 `pubspec.yaml` 版本号 + push master = 发 Release」——没有发布意图时不要动版本号。

## Architecture

- 入口链：`lib/main.dart` → `MainLayout` → `lib/controls/pack_list.dart` / `pack_manage.dart` → `lib/pages/*`。
- 「添加文件夹」流程：`MainLayout.pickDirectory`（默认 `file_selector` 的 `getDirectoryPath()`，系统原生目录对话框，取消返回 null）→ `lib/controls/add_directory_dialog.dart`「添加包」表单对话框（路径 + 扫描统计 + 包 ID/版本/作者（必填）/许可证（下拉可空，8 项 SPDX）/描述 + 图标自动识别扫描结果首个图片文件（png/jpg/jpeg/svg/ico/webp）；「确定」返回 `PackModel`（含 `files`/`license`/`iconPath`/`sourcePath`）→ `PackStore.savePack` 写入 YAML 并更新侧边栏列表（同 ID 覆盖、自动选中）。扫描经 `MainLayout.scanFiles`，默认 `FileScan.scan`。`pickDirectory`/`scanFiles`/`store` 均可注入以配合测试。
- 配置持久化在 `lib/config/pack_store.dart`（唯一 YAML 读写点）：根目录为工作目录相对 `config/`（便携）；启动时 `ensureConfigExist()`（`config/`、`config/packs/`、`config.yaml`）+ `loadPacks()` 逐个解析 `packs/*.yaml`，损坏或缺必填字段的文件跳过、界面以 `InfoBar` 列出警告（不静默）；`savePack()` 文件名 = 包 ID 清洗（`sanitizeFileName`，非法字符 → `_`，同 ID 覆盖）。YAML 由 `yaml`/`yaml_edit` 生成：null 字段省略、多行描述用 `|-` 块标量。
- 侧边栏列表由 `PackList.buildCards(packs)` 从真实包列表动态构建，列表项图标取自包 `iconPath`（与 `sourcePath` 拼接；svg 走 `SvgPicture.file`、位图走 `Image.file`，缺失/加载失败时兜底默认图标）；选中包后右侧为只读详情（`pack_info.dart` 展示字段、`pack_files.dart` 展示文件表）；无包时显示引导文案。`lib/util/format.dart` 提供共享的 `formatBytes()`/`baseName()`/`joinPath()`；`lib/util/file_image.dart` 提供共享的 `buildFileImage()`（对话框预览与侧边栏共用）。
- 领域模型在 `lib/models/`：`PackModel`（含可选 `license`/`iconPath`/`sourcePath`，`toMap`/`fromMap` 序列化）、`CmdModel`/`CmdType`、`MacroModel`、`FileModel`/`FileType`（序列化只存 `path`/`size`，读回时由 basename 推导 name/type）、`BuildModel`。
- `lib/scanner/file_scan.dart` 是唯一 `dart:io` 用法：`FileScan.scan()` 异步单次遍历包目录，输出相对路径、稳定排序的 `FileModel` 列表（跳过隐藏目录与 `build`/`out`；`FileModel` 含 `size` 字节数）。
- **Dart ↔ C++ 无任何桥接**（无 MethodChannel / FFI）；`windows/` 是 Flutter runner 模板，唯一自定义处是窗口标题（`windows/runner/main.cpp`）。要加原生能力需从零自建通道。
- 生成物禁止手改：`windows/flutter/generated_plugin_registrant.*`、`windows/flutter/generated_plugins.cmake`、`windows/flutter/ephemeral/`（均由 Flutter 重新生成）。

## Conventions

- **所有用户可见文案为中文**（硬编码，无 i18n 框架）；新增 UI 文案保持中文。
- UI 使用 `fluent_ui`（Win11 风格）而非 Material；主题色统一走 `lib/util/colors.dart`（`UCColors` / `buildTheme`）。
- 图标：SVG 放 `assets/icons/` 并在 `lib/util/svgs.dart` 注册。
- 测试：`test/` 下为标准 `flutter_test` 测试（冒烟 + 模型 + 扫描 + 配置存储 + 对话框/接线 + 页面 + 列表/工具；widget 测试均用有界 `pump`，禁 `pumpAndSettle`）；新增测试放 `test/`。
- `file_selector` 用于「添加文件夹」的系统原生目录选择（`getDirectoryPath()`，取消返回 null）。
- YAML 配置读写用 Dart 官方 `yaml`/`yaml_edit` 包（封装在 `lib/config/pack_store.dart`）。
- `README.md` 仅一行占位，不可作为文档来源；以本文件、`ci.yml`、CMake 为准。
