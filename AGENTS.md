# cpp_nuget_pack

## Overview

「C++ NuGet 打包工具」：Flutter **Windows 桌面应用**（`.metadata` → `project_type: app`），目标是把 C++ 头文件/源码/库可视化成 NuGet 包。注意：

- **不是** Flutter 插件、**不是** C++ 库。名称里的 NuGet 是应用生成的目标格式：NuGet 构建器会在打包时自行生成 `<包ID>.nuspec` 与 `build/native/<包ID>.targets`，导出器用 Dart 组装 `.nupkg`。应用不依赖外部 NuGet CLI、`nuget.exe` 或 `dotnet pack`，CI 也不执行 NuGet 工具链。
- 仅支持 Windows（无 android/ios/linux/macos/web 平台目录）。

## Commands

```text
flutter pub get
flutter analyze                    # 静态检查（CI 门禁，须零问题）；analysis_options.yaml 排除 build/**、windows/**、android/**
flutter test                       # 运行测试
flutter build windows --release    # 产物：build/windows/x64/runner/Release/
flutter run -d windows             # 本地运行
```

- `pub get → analyze → test → build windows --release` 序列来自 `.github/workflows/ci.yml`（命令事实源）。
- Windows 构建走 CMake + MSVC（C++17、`/W4 /WX` 警告即错误，见 `windows/CMakeLists.txt`），需要 Visual Studio C++ 工具链；本机缺工具链时先 `flutter doctor` 确认，构建交给 CI。
- SDK 约束：Dart `^3.13.2`、Flutter `>=3.44.0`（本地环境 Flutter 3.47.2 stable）。

## 发布流程（勿误触发）

- **CI 在 push `master` / `dev` 时触发**：`analyze → test → build windows --release`（Flutter SDK 与 pub 依赖由 `subosito/flutter-action` 缓存）。**仅 `master` 发布**：打包 `dist/cpp_nuget_pack-<版本>-win-x86_64.zip` → 创建 GitHub Release（tag `v<版本>`，如 `v26.1`）；`dev` 渠道只验证（测试+构建）不发布。无 PR 检查。
- 开发在 `dev` 分支进行（日常推送不触发发布）；发布时把 `dev` 合并/推送到 `master` 并升级版本号。
- 版本号采用「年份.年内发布数量」方案（如 `26.1` = 2026 年第 1 次发布；年内递增 `26.2`、`26.3`…；次年从 `27.1` 重计；更早的 `1.0.x` 为历史版本）。唯一来源是 `pubspec.yaml` 的 `version:`（存三段格式 `26.1.0+1`，第三段固定 0；CI 去掉 `+build` 并去掉尾部 `.0` → tag `v26.1`，解析失败回退为时间戳）。同一版本经 CMake `FLUTTER_VERSION*` 宏注入 exe 文件版本（`windows/runner/Runner.rc`）。应用内「关于」页显示的版本来自 `lib/app_info.dart` 的 `appVersion`（去掉 `+build` 与末尾 `.0`，即 `26.1`）——升级版本号时须同步该常量（`test/app_info_test.dart` 强制校验一致性）。
- 所以「改 `pubspec.yaml` 版本号 + push `master` = 发 Release」——没有发布意图时不要动版本号。