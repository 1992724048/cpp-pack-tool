# cpp_nuget_pack

## Overview

「C++ NuGet 打包工具」：Flutter **Windows 桌面应用**（`.metadata` → `project_type: app`），目标是把 C++ 头文件/源码/库可视化成 NuGet 包。注意：

- **不是** Flutter 插件、**不是** C++ 库。名称里的 NuGet 只是应用的功能主题——构建管线与 CI 至今没有任何 NuGet 工具链集成（无 .nuspec/.targets/nuget.exe/dotnet pack）。
- 当前为早期 UI 骨架：`lib/controls/pack_list.dart`、`lib/pages/pack_files.dart` 是硬编码假数据，多个 Tab 与工具栏按钮回调为空；`lib/pages/setting.dart`、`lib/pages/about.dart` 是 0 字节空文件。
- 仅支持 Windows（无 android/ios/linux/macos/web 平台目录）。

## Commands

```text
flutter pub get
flutter analyze                    # 静态检查（CI 门禁，须零问题）；analysis_options.yaml 排除 build/**、windows/**、android/**
flutter test                       # 运行测试（test/：冒烟 + 模型 + 扫描器）
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
- 领域模型在 `lib/models/`：`PackModel`、`CmdModel`/`CmdType`、`MacroModel`、`FileModel`/`FileType`、`BuildModel`——纯数据类，无序列化。
- `lib/scanner/file_scan.dart` 是唯一 `dart:io` 用法：`FileScan.scan()` 异步单次遍历包目录，输出相对路径、稳定排序的 `FileModel` 列表（跳过隐藏目录与 `build`/`out`；`FileModel` 含 `size` 字节数）。
- **Dart ↔ C++ 无任何桥接**（无 MethodChannel / FFI）；`windows/` 是 Flutter runner 模板，唯一自定义处是窗口标题（`windows/runner/main.cpp`）。要加原生能力需从零自建通道。
- 生成物禁止手改：`windows/flutter/generated_plugin_registrant.*`、`windows/flutter/generated_plugins.cmake`、`windows/flutter/ephemeral/`（均由 Flutter 重新生成）。

## Conventions

- **所有用户可见文案为中文**（硬编码，无 i18n 框架）；新增 UI 文案保持中文。
- UI 使用 `fluent_ui`（Win11 风格）而非 Material；主题色统一走 `lib/util/colors.dart`（`UCColors` / `buildTheme`）。
- 图标：SVG 放 `assets/icons/` 并在 `lib/util/svgs.dart` 注册。
- 测试：`test/` 下为标准 `flutter_test` 测试（冒烟 + 模型逻辑 + 目录扫描）；新增测试放 `test/`。
- `file_selector` 已在 pubspec 声明但尚未使用（为文件对话框预留）。
- `README.md` 仅一行占位，不可作为文档来源；以本文件、`ci.yml`、CMake 为准。
