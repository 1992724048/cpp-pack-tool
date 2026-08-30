# cpp_nuget_pack — C++ NuGet 打包工具

## Overview

Flutter Windows 桌面应用，用于将 C/C++ 库（头文件 + 预编译库 + 数据文件）打包为 NuGet native 包。用户添加库源目录、自动扫描文件、配置包元数据与 MSBuild 集成（props/targets），一键生成 .nuspec/.props/.targets 并调用 nuget.exe 产出 .nupkg；也支持"仅生成文件"模式。

参考格式：D:\CODE\Library\v8（V8 15.2.124.1 的手工打包件，含 V8.Native.nuspec/props/targets/pack.ps1，是生成模板的格式基准）。

## Architecture

分层结构：models（数据模型）→ services（扫描/生成/打包/设置）→ ui（待实现）→ main.dart（入口）。

- `models/pack_project.dart` — 核心数据模型 `PackProject`/`SourceDir`/`FileMapping`/`CompileConfig`，JSON 可序列化、深拷贝、NuGet id 校验、MSBuild 标识符消毒
- `services/scanner.dart` — 递归扫描源目录：按扩展名分类（头文件/库文件/数据文件），生成映射建议（头文件按目录簇、库文件按配置目录），忽略生成目录、深度/数量上限、符号链接防循环
- `services/nuspec_generator.dart` — 生成 .nuspec（metadata + files 段，glob 映射，`outputDirectory` 为相对路径基准）
- `services/msbuild_generator.dart` — 生成 `build\native\{id}.props`（语言标准/分配置宏/包含目录）与 `{id}.targets`（LibDir 平台×配置映射、平台/配置检查、链接依赖、数据文件拷贝、消费者侧源码注入）
- `services/packer.dart` — nuget.exe 定位（显式路径 > PATH > winget 常见位置，仿 pack.ps1）与 `nuget pack` 执行
- `services/settings.dart` — 应用设置持久化（%APPDATA%\cpp_nuget_pack\settings.json，损坏回退默认）
- `services/path_utils.dart` — 内部路径助手（不引第三方 package:path）

## Source Tree

```
lib/
  main.dart         应用入口（骨架 UI，待 UI 实现替换）
  base_style.dart   旧 ButtonStyle（计划删除，统一到 ui/theme.dart）
  pack_info.dart    占位文件（计划废弃）
  models/pack_project.dart
  services/{scanner,nuspec_generator,msbuild_generator,packer,settings,path_utils}.dart
test/
  models_test.dart / scanner_test.dart / generator_test.dart / packer_test.dart
docs/
  ui-spec.md        深色专业风 UI 视觉规格（设计令牌/组件/布局）
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
| cupertino_icons ^1.0.8 | 图标 |
| flutter_lints ^6.0.0 | lint 规则 |
