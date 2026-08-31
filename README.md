# cpp_nuget_pack — C++ NuGet 打包工具

> 基于 Flutter 的 Windows 桌面应用：把 C/C++ 库（头文件 + 预编译库 + 数据文件）一键打包为 NuGet native 包，并支持导出 CMake 包配置。

## 功能特性

- **多库项目管理** — 左栏库列表管理多个库项目，每个项目独立配置包元数据、文件映射、编译配置与依赖
- **智能目录扫描** — 添加源目录后自动扫描并生成映射建议：头文件 / 源码 / C++ Module / 静态库 / 动态库 / 数据文件 / 可执行文件八类文件按规则自动归类
- **共享项目导入** — 源目录检测到 `.vcxitems` / `.vcxproj` / `.props` / `.targets` 时提示基于共享项目生成映射与编译配置（含 PreBuild/PostBuild 命令导入，可选替换扫描结果）
- **NuGet native 格式** — 生成标准 `build\native\{id}.props` / `{id}.targets`：C/C++ 语言标准、分配置预处理宏、包含/库目录、链接依赖、平台/配置检查、防重复标志，格式对齐 V8 手工打包件
- **自动文件处理** — 源码/模块文件自动注入消费者编译；数据/动态库/可执行文件以硬链接（mklink，失败回退复制）输出到消费方目录
- **映射级构建命令** — 每个映射可配置构建前/后命令行（如 EXE 注入），生成进消费方 MSBuild 目标
- **依赖管理** — 从已有包注册表选择依赖（自动排除自身）或手动指定，导出 nuspec `<dependencies>` 段；打包前检查依赖缺失并警告
- **打包历史时间线** — 每次打包记录进包注册表（版本号、时间、摘要），git 风格时间线查看
- **版本策略** — 手动 / 时间戳 / 自动递进三种版本生成策略
- **生成文件预览** — 打包前预览 nuspec / props / targets 内容并复制
- **两种打包模式** — 一键打包（自动定位 nuget.exe，流式日志）或仅生成文件；打包前/后脚本（工具侧）可选
- **CMake 包导出** — 生成 `{Package}Config.cmake`（imported target + 配置级宏/链接依赖/语言标准）
- **共享包缓存** — 生成消费方 `nuget.config`（globalPackagesFolder 指向共享缓存 + 本地包源），多项目共用一份解压
- **深色专业工具风** — 工作台分栏布局（库列表 + 五个 Tab + 可折叠日志面板，日志可选中复制）

## 快速开始

```powershell
# 获取依赖
flutter pub get

# 运行
flutter run -d windows

# 构建 Release
flutter build windows --release
# 产物: build\windows\x64\runner\Release\cpp_nuget_pack.exe
```

**使用流程**：设置全局输出目录（含 NuGet 全局缓存目录）→ 左栏「＋」添加库项目（选择源目录 → 扫描/共享项目导入 → 确认映射）→ 配置包信息与编译配置 → 打包页选择模式（一键打包 / 仅生成文件）→ 打包完成自动登记包注册表。

## 输出目录结构

```
<全局输出目录>\
  packages.json                包注册表（含打包历史，启动时恢复展示）
  nuget.config                 消费方共享缓存配置（可生成）
  build\                       生成中间文件
    {id}.nuspec
    native\{id}.props / {id}.targets
  {id}.{version}.nupkg         打包产物
  cmake\{id}\{id}Config.cmake  CMake 包配置（可生成）
```

## 目录结构

```
lib/
  main.dart              应用入口
  models/pack_project.dart  核心数据模型（PackProject/SourceDir/FileMapping/CompileConfig/PackDependency）
  services/              扫描器、nuspec/props/targets 生成器、CMake 生成器、nuget.exe 定位与打包、
                        设置持久化、包注册表、共享项目解析器、路径助手
  ui/                    深色主题令牌、工作台主壳、五个 Tab 页、公共组件
test/                    单元与组件测试（136 项）
docs/ui-spec.md          深色专业风 UI 视觉规格
AGENTS.md                AI 协作项目文档（架构/源码树/约定）
```

## 开发

```powershell
flutter analyze   # 静态分析（0 issues）
flutter test      # 单元与组件测试（136 项）
```

## 技术栈

- Flutter 3.47（Windows 桌面）/ Dart 3.13
- `file_selector` — Windows 目录/文件选择
- 仅依赖官方与第一方包，核心逻辑零第三方依赖
