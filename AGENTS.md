# cpp_nuget_pack — C++ NuGet 打包工具

## Overview

Flutter Windows 桌面应用，用于将 C/C++ 库（头文件 + 预编译库 + 数据文件）打包为 NuGet native 包。用户添加库源目录、自动扫描文件、配置包元数据与 MSBuild 集成（props/targets），一键生成 .nuspec/.props/.targets 并调用 nuget.exe 产出 .nupkg；也支持"仅生成文件"模式。输出目录取全局设置；打包成功自动登记到输出目录 `packages.json` 包注册表并在启动时恢复展示，配置同时写回源目录 `.cpp_nuget_pack.json`（加载时源目录配置优先）。

参考格式：D:\CODE\Library\v8（V8 15.2.124.1 的手工打包件，含 V8.Native.nuspec/props/targets/pack.ps1，是生成模板的格式基准）。

## Architecture

分层结构：models（数据模型）→ services（扫描/生成/打包/设置）→ ui（深色专业风界面）→ main.dart（入口）。

- `models/pack_project.dart` — 核心数据模型 `PackProject`/`SourceDir`/`FileMapping`/`CompileConfig`，JSON 可序列化、深拷贝、NuGet id 校验、MSBuild 标识符消毒；头文件映射 `FileMapping.target` 语义为最终 `#include` 路径（不含 `build\native\include\` 前缀，按扩展名经 `isHeaderMapping` 区分），库/数据文件映射为包内目标路径；含构建前/后脚本字段（preBuildCommand/postBuildCommand）
- `services/scanner.dart` — 递归扫描源目录：按扩展名分类（头文件/库文件/数据文件），生成映射建议（头文件按目录簇 → include 路径、库文件按配置目录），忽略生成目录、深度/数量上限、符号链接防循环；`findIconFile` 查找源目录顶层 icon.png/jpg/ico 作为库图标
- `services/nuspec_generator.dart` — 生成 .nuspec（metadata + files 段，files 段头部自动含 props/targets 集成条目，glob 映射，`baseDir` 为相对路径基准；头文件映射 target 自动拼 `build\native\include\` 前缀，旧前缀兼容）
- `services/msbuild_generator.dart` — 生成 `build\native\{id}.props`（C++ 标准含 stdcpplatest、CLanguageStandard、分配置宏/包含目录）与 `{id}.targets`（LibDir 平台×配置映射、平台/配置检查、链接依赖、数据文件**硬链接优先**（mklink /H，失败回退 copy）、消费者侧源码注入）；`%(...)` 元数据收尾的列表不带尾分号，与参考件一致
- `services/packer.dart` — nuget.exe 定位（显式路径 > PATH > winget 常见位置，仿 pack.ps1）与 `nuget pack` 执行（含 `buildPackArgs`/`parseNupkgOutputPath` 可测构件）；`generateConsumerNugetConfig` 生成消费方 nuget.config（globalPackagesFolder 共享缓存 + 本地包源）
- `services/settings.dart` — 应用设置持久化（%APPDATA%\cpp_nuget_pack\settings.json，损坏回退默认；含 defaultOutputDir 与 nugetGlobalCacheDir）
- `services/package_registry.dart` — 输出目录包注册表（`packages.json`：RegisteredPackage 列表，load/save/upsert/remove，原子写、损坏容错）+ 源目录包配置（`.cpp_nuget_pack.json` 写/读）
- `services/path_utils.dart` — 内部路径助手（不引第三方 package:path）
- `ui/tokens.dart` + `ui/theme.dart` — 深色专业风设计令牌与 `buildDarkTheme()`（颜色/字体/间距/圆角全部主题化，正文统一 HarmonyOS_Sans_SC，页面不逐处硬编码）
- `ui/main_shell.dart` — 工作台 Scaffold：左栏库列表（含设置按钮、库图标、主源目录配置写入、删除确认对话框：注册表/源目录配置/nupkg 三选默认全勾但源文件永不删）+ 右栏四 Tab（包信息/文件映射/编译配置/打包）+ 底部日志面板；启动加载输出目录注册表（源目录配置优先覆盖）
- `ui/pages/` — 四个 Tab 页：pack_info（包元数据表单，README/LICENSE 自动填充默认值）/ file_mapping（映射表：源文件模式/目标 #include 路径/条件，行内编辑）/ build_config（C/C++ 标准、宏/附加目录/附加依赖均可增删修改列表、分配置宏折叠块、数据拷贝/源码注入）/ pack（打包模式切换 + 输出目录只读自全局设置 + 流式打包日志（systemEncoding 解码）+ 文件丢失警告 + 构建前/后脚本 + 生成消费方 nuget.config）
- `ui/widgets/` — library_list / log_panel / app_dialogs（添加源目录: 选目录→扫描→映射建议勾选）/ form_fields（含 StringListEditor）/ settings_dialog
- `ui/log_controller.dart` — 日志模型（ChangeNotifier + LogEntry/LogLevel）；`ui/io_picker.dart` — file_selector 唯一入口（目录/可执行文件选择）
- 状态管理：MainShell 内 setState 驱动，不引入状态管理库

## Source Tree

```
lib/
  main.dart         应用入口（MaterialApp + buildDarkTheme + MainShell）
  models/pack_project.dart
  services/{scanner,nuspec_generator,msbuild_generator,packer,settings,package_registry,path_utils}.dart
  ui/
    tokens.dart / theme.dart / log_controller.dart / io_picker.dart / main_shell.dart
    pages/{pack_info,file_mapping,build_config,pack}_page.dart
    widgets/{library_list,log_panel,app_dialogs,form_fields,settings_dialog}.dart
test/
  models_test.dart / scanner_test.dart / generator_test.dart / packer_test.dart / package_registry_test.dart / widget_test.dart
docs/
  ui-spec.md        深色专业风 UI 视觉规格（设计令牌/组件/布局，实现基准）
```

## Build

- Get: `flutter pub get`
- Build: `flutter build windows`（Release 桌面产物）
- Analyze: `flutter analyze`

## Test

- Test: `flutter test`

## Conventions

- Dart 官方风格：类型标注完整；类型 UpperCamelCase、变量/函数 lowerCamelCase、私有成员 `_` 前缀
- 不做 silent ignore：异常捕获必须记录或返回错误信息
- 每个公开 API 有 doc comment（命名不足以表达语义时）
- 圈复杂度 >22 的函数必须拆分
- 中文 UI 文案；日志级别 info/warn/error
- 核心逻辑只用 dart:io/dart:convert 等 SDK 库，不引第三方包（UI 层可用 file_selector 等 UI 包）

## Dependencies

| 依赖 | 用途 |
| --- | --- |
| flutter (SDK ^3.13.2) | 桌面应用框架 |
| file_selector ^1.1.0 | Windows 目录/文件选择（联邦插件，含 file_selector_windows） |
| flutter_lints ^6.0.0 | lint 规则 |
