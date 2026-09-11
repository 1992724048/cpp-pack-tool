# cpp_nuget_pack

## Overview

「C++ NuGet 打包工具」：Flutter **Windows 桌面应用**（`.metadata` → `project_type: app`），目标是把 C++ 头文件/源码/库可视化成 NuGet 包。注意：

- **不是** Flutter 插件、**不是** C++ 库。名称里的 NuGet 只是应用的功能主题——构建管线与 CI 至今没有任何 NuGet 工具链集成（无 .nuspec/.targets/nuget.exe/dotnet pack）。
- 当前进度：「添加文件夹」全流程可用（目录选择 → 「添加包」表单 → 保存 YAML → 侧边栏列表更新），且「包信息」页支持编辑并保存回 YAML（版本/作者/许可证/描述可改，包 ID 不可改），工具栏「删除文件夹」可删除选中包（确认对话框仅删配置，被依赖时列出依赖方），「重新映射」可对选中包重新扫描源目录并更新包结构（进度/结果对话框）；「文件管理」目录树支持双击打开文件、lib/dll/pdb/exe 显示 Release/Debug 构建标签；包列表与「文件管理」目录树均为真实数据（配置持久化在 `config/`，见 Architecture）；「依赖管理」支持从现有包选择依赖并自定义 NuGet 版本范围（增删改自动保存、选中包预填 `[版本,)`、失效依赖显示「缺失」）；「编译设置」支持宏定义、编译前/后命令（命令对话框可从包内选择脚本并插入 MSBuild 常用宏）、附加库目录与附加库（条目均带 ALL/Release/Debug 构建标签、增删改自动保存）；「打包设置」支持选择打包格式（当前仅 NuGet）、预览打包后的文件与内容（左侧文件树 + 右侧文本预览；打包包含源目录下全部文件，头文件按源目录名命名词空间）；工具栏「打包文件夹」可对选中包生成真实 .nupkg（进度/完成/失败对话框，输出至设置的全局输出目录，完成后可在资源管理器中定位；包图标自动转换嵌入——检测图标转 PNG 等比缩放至 ≤128，缺失用默认纸箱图标）；「历史记录」按钮弹出选中包的时间线历史（创建/版本变更/重新映射/打包导出四类事件，支持删除条目，上限 100 条），工具栏 5 个按钮至此全部实现；footer「设置」与「关于」均为真实页面（设置页：打包输出目录 + 主题模式 + 主题配色，即时生效并持久化；关于页：应用名/版本号/描述与项目主页链接，版本号来自 `lib/app_info.dart`，与 pubspec 的同步由测试保障）。全部功能至此完成。
- 仅支持 Windows（无 android/ios/linux/macos/web 平台目录）。

## Commands

```text
flutter pub get
flutter analyze                    # 静态检查（CI 门禁，须零问题）；analysis_options.yaml 排除 build/**、windows/**、android/**
flutter test                       # 运行测试（test/：冒烟 + 模型 + 扫描 + 配置存储 + 对话框/接线 + 页面 + 列表/工具（含 file_opener 路径规范化）+ 悬浮提示 + 图标映射 + 构建标签 + 依赖管理/版本范围 + 设置页/主题 + 编译设置 + 打包计划/预览/导出/包图标 + 历史记录 + 关于页/应用信息）
flutter build windows --release    # 产物：build/windows/x64/runner/Release/
flutter run -d windows             # 本地运行
```

- `pub get → analyze → test → build windows --release` 序列来自 `.github/workflows/ci.yml`（命令事实源）。
- Windows 构建走 CMake + MSVC（C++17、`/W4 /WX` 警告即错误，见 `windows/CMakeLists.txt`），需要 Visual Studio C++ 工具链；本机缺工具链时先 `flutter doctor` 确认，构建交给 CI。
- SDK 约束：Dart `^3.13.2`、Flutter `>=3.44.0`（本地环境 Flutter 3.47.2 stable）。

## 发布流程（勿误触发）

- **CI 在 push `master` / `dev` 时触发**：`analyze → test → build windows --release`（Flutter SDK 与 pub 依赖由 `subosito/flutter-action` 缓存）。**仅 `master` 发布**：打包 `dist/cpp_nuget_pack-<版本>-win-x86_64.zip` → 创建 GitHub Release（tag `v<版本>`）；`dev` 渠道只验证（测试+构建）不发布。无 PR 检查。
- 开发在 `dev` 分支进行（日常推送不触发发布）；发布时把 `dev` 合并/推送到 `master` 并升级版本号。
- 版本号唯一来源是 `pubspec.yaml` 的 `version:`（如 `1.0.1+1`；CI 去掉 `+build` 后缀，解析失败回退为时间戳）。同一版本经 CMake `FLUTTER_VERSION*` 宏注入 exe 文件版本（`windows/runner/Runner.rc`）。应用内「关于」页显示的版本来自 `lib/app_info.dart` 的 `appVersion`（去掉 `+build` 后缀）——升级版本号时须同步该常量（`test/app_info_test.dart` 强制校验一致性）。
- 所以「改 `pubspec.yaml` 版本号 + push `master` = 发 Release」——没有发布意图时不要动版本号。

## Architecture

- 入口链：`lib/main.dart` → `MainLayout` → `lib/controls/pack_list.dart` / `pack_manage.dart` → `lib/pages/*`。
- 「添加文件夹」流程：`MainLayout.pickDirectory`（默认 `file_selector` 的 `getDirectoryPath()`，系统原生目录对话框，取消返回 null）→ `lib/controls/add_directory_dialog.dart`「添加包」对话框（分阶段：扫描进行中仅显示进度，完成后才显示表单——路径 + 扫描统计 + 包 ID/版本/作者（必填）/许可证（下拉可空，8 项 SPDX）/描述 + 图标自动识别扫描结果首个图片文件（png/jpg/jpeg/svg/ico/webp）；「确定」返回 `PackModel`（含 `files`/`license`/`iconPath`/`sourcePath`）→ `PackStore.savePack` 写入 YAML 并更新侧边栏列表（同 ID 覆盖、自动选中）。扫描经 `MainLayout.scanFiles`，默认 `FileScan.scan`。`pickDirectory`/`scanFiles`/`store` 均可注入以配合测试。
- 配置持久化在 `lib/config/pack_store.dart`（唯一 YAML 读写点）：根目录为工作目录相对 `config/`（便携）；启动时 `ensureConfigExist()`（`config/`、`config/packs/`、`config.yaml`）+ `loadPacks()` 逐个解析 `packs/*.yaml`，损坏或缺必填字段的文件跳过、启动后以右上角悬浮提示（error、5 秒、多条合并）列出警告（不静默）；`savePack()` 文件名 = 包 ID 清洗（`sanitizeFileName`，非法字符 → `_`，同 ID 覆盖）；`deletePack()` 按同规则删除对应 YAML（幂等，文件不存在视为成功）。YAML 由 `yaml`/`yaml_edit` 生成：null 字段省略、多行描述用 `|-` 块标量；包配置含 `files`/`dependencies`/`commands`/`macros`/`libDirectories`/`libraries`/`history` 七类列表（缺失视为空）。另有 `loadSettings()`/`saveSettings()` 读写 `config.yaml` 中的全局设置（打包输出目录/主题模式/深色配色/强调色；缺文件或损坏回退默认值）。
- 侧边栏列表由 `PackList.buildCards(packs, onSave:)` 从真实包列表动态构建，列表项图标取自包 `iconPath`（与 `sourcePath` 拼接；svg 走 `SvgPicture.file`、位图走 `Image.file`，缺失/加载失败时兜底默认图标）；选中包后右侧为「包信息」与「文件管理」（`pack_files.dart` 目录结构树：fluent_ui `TreeView`，目录/文件均显示大小、目录为后代聚合，默认全部折叠；树图标为 catppuccin/vscode-icons 子集双套——latte/mocha 随主题亮度、具名目录与展开态 `_open`，解析见 `lib/util/catppuccin_icons.dart`；双击文件行用系统默认程序打开（`lib/util/file_opener.dart`），lib/dll/pdb/exe 文件按相对路径推断在名称后显示 Release（绿）/Debug（橙）标签、推断不出不显示（`lib/util/build_config.dart`，另提供 `allBuildLabel`/`buildModelLabel()` 供编译设置标签复用））；无包时显示引导文案。`lib/util/format.dart` 提供共享的 `formatBytes()`/`baseName()`/`joinPath()`/`formatError()`（错误文案，ArgumentError 去前缀）；`lib/util/file_image.dart` 提供共享的 `buildFileImage()` 与图标识别 `findIconFile()`（对话框预览与侧边栏共用）；`lib/util/licenses.dart` 提供共享 SPDX 许可证列表与下拉框等高常量 `comboBoxDensity`（许可证、依赖包名下拉框与相邻输入框等高）；`lib/util/catppuccin_icons.dart` 提供目录树图标资产路径解析 `iconAssetFor()`（文件名 > 前缀 > 扩展名 > 兜底；latte/mocha 随 `Brightness`）；`lib/util/version_range.dart` 提供 NuGet 版本范围校验 `versionRangeError()`/`isValidVersionRange()`（`[ ]` 含端点、`( )` 不含，裸版本 = 最低版本、含预发布排序比较；拒绝浮版本与零宽度区间）。
- 「包信息」编辑流（`lib/pages/pack_info.dart`）：默认只读，点「编辑」后版本/作者/描述/许可证可改（包 ID 永远只读——它同时是 YAML 文件名）；「保存」需必填有效且有改动，「取消」还原原值；保存挂起期间切换包则丢弃回写；成功经 `onSave` 回调链写盘（`PackList → PackManage → PackInfo → MainLayout._savePack`）并弹出右上角悬浮提示「已保存」，失败弹「保存失败」对话框且停留编辑态。`PackManage` 持稳定 `Tab` 实例 + `ValueNotifier<PackModel>` 推送包更新（fluent_ui `TabView` 每次 build 重建 `Tab` 会销毁页面 state）。
- 「删除包」流程：工具栏「删除文件夹」按钮（未选中包或选中 footer「设置/关于」时禁用）→ `lib/controls/delete_pack_dialog.dart` 确认对话框（「删除」红底白字居左、「取消」居右；若被其他包依赖，列出依赖方并提示将显示「缺失」）→ `PackStore.deletePack()` 仅删除配置文件（源目录不动）；成功后从列表移除并调整选择（保持索引位、越界回退末项、空列表置空），悬浮提示「已删除」；失败提示「删除失败」（error、5 秒）。
- 「重新映射」流程：工具栏「重新映射」按钮（未选中包或选中 footer「设置/关于」时禁用）→ 选中包重新扫描 `sourcePath`（缺失时 error 悬浮提示、不弹对话框）→ `lib/controls/remap_pack_dialog.dart`（扫描中 → 更新中 → 完成/失败：显示文件数量、总大小、新增/移除 N，与旧快照按路径大小写不敏感对比）→ 扫描成功后自动 `savePack` 写盘并刷新列表/详情，图标按新结果重识别；扫描完成前关闭对话框即取消（不写盘）。
- 「依赖管理」流程：`PackManage` 第 3 Tab（`lib/pages/pack_dependencies.dart`）列出依赖（包名 + 版本范围 + 编辑/删除）；「添加依赖」经 `lib/controls/dependency_dialog.dart` 从现有包下拉选择（排除自身与已添加、无候选时提示；选中后自动预填 `[该包版本,)`），版本范围实时校验（非法提示并禁用「确定」）；依赖列表行间有分隔线、指向不存在包的依赖显示红色「缺失」标签；增删改均自动保存（构造全字段拷贝的 `PackModel` → `onSave` → 成功悬浮提示「已添加/已保存/已删除」）；依赖持久化为 YAML `dependencies: [{name, version}]`。
- 「编译设置」流程：`PackManage` 第 4 Tab（`lib/pages/pack_compile_settings.dart`）分 5 区：宏定义（单栏「名称=值」文本）、编译前命令、编译后命令、附加库目录（文本 + 「浏览…」调 `getDirectoryPath`）、附加库；条目行 = 内容 + 构建标签（`buildModelLabel()`，ALL 蓝/Release 绿/Debug 橙）+ 编辑/删除，行间分隔线；条目录入经 `lib/controls/compile_entry_dialog.dart`（单文本框 + 构建配置下拉，编辑预填；编译前/后命令对话框另提供「从包中选择」脚本下拉——exe/bat/cmd 插入 `"$(MSBuildThisFileDirectory)files\...\"` 引用路径、ps1/py 自动加解释器前缀——与「插入宏」下拉（16 项常用 `$(...)`/`%(...)` 宏，光标处插入））；增删改自动保存（全字段拷贝 `PackModel` → `onSave` → 悬浮提示「已添加/已保存/已删除」）；持久化为 YAML `macros: [{value, buildModel}]`、`commands: [{command, type, buildModel}]`、`libDirectories: [{path, buildModel}]`、`libraries: [{name, buildModel}]`。
- 「打包设置」流程：`PackManage` 第 5 Tab（`lib/pages/pack_packaging.dart`）选择打包格式（下拉来自 `PackageBuilderRegistry`，当前仅 NuGet）并「预览打包内容」→ `NuGetPackageBuilder.buildPlan()` 生成 `PackagePlan` → `lib/controls/pack_preview_dialog.dart` 预览对话框（左侧包内文件树默认折叠 + 右侧等宽字体文本预览：生成文件直接显示、源文本文件读盘、二进制提示不可预览，读取函数可注入）；缺 `sourcePath` 时悬浮提示无法预览。
- 打包抽象层在 `lib/packaging/`：`package_builder.dart` 定义 `PackageBuilder` 接口（`id`/`displayName`/`buildPlan()`）与 `PackageBuilderRegistry` 注册表（可扩展新格式）；`package_plan.dart` 定义 `PackagePlan`/`PackageEntry`（sealed 来源：源文件/生成文本；包内路径 `/` 分隔、确定性排序）；`nuget_builder.dart` 实现 NuGet 布局——头文件/模块 → `build/native/include/<源目录名>/`（剥离开头 `include/` 后再套一层源目录名命名词空间，消费者可写 `#include <源目录名/foo.h>` 防头文件冲突，源目录缺失时回退包名）、lib/dll/pdb → `build/native/lib/`（剥离开头 `lib|bin`）、其余文件 → `build/native/files/`（保留原相对路径、全部入包）；另生成包根 `<包ID>.nuspec`（license 用 SPDX 表达式、依赖组 `native0.0`、版本去 `+build`、XML 实体转义、恒定声明 `<icon>images\icon.png</icon>`）与 `build/native/<包ID>.targets`（include 行 + 宏/附加库目录/附加库的 ALL/Release/Debug 条件分组；.lib 按路径推断 D/R 自动同时补库目录与库名；包内有 .asm 时条件导入 VS `masm.props/masm.targets` 并生成 `MASM` 项；.rc 生成 `ResourceCompile` 项；dll/pdb 经 `DeployPkgRuntimeBinaries` 目标（`AfterTargets="Build"`）以 `Copy UseHardlinksIfPossible` 硬链接到 `$(OutDir)`（失败回退拷贝，`FileWrites` 供清理）；编译前/后命令追加写入 `PreBuildEvent`/`PostBuildEvent`（ALL/Release/Debug 条件、保留消费者已有值））。
- 「打包文件夹」流程：工具栏「打包文件夹」按钮（未选中包或选中 footer「设置/关于」时禁用）→ 校验全局输出目录（未设置时 error 悬浮提示「请先在设置页配置打包输出目录」）与 `sourcePath` → `lib/controls/pack_export_dialog.dart` 进度对话框（进行中 ProgressRing、关闭禁用 → 完成：输出路径/文件数量/包大小 + 「打开所在目录」/失败：去前缀错误文案）→ `lib/packaging/nupkg_exporter.dart` 的 `exportNuGetPackage()` 把 `PackagePlan` 组装为真实 .nupkg（`archive` 包编码；写 OPC 三件套 `[Content_Types].xml`/`_rels/.rels`/`nuget.psmdcp`；恒定嵌入 `images/icon.png`——经 `lib/packaging/package_icon.dart` 把 `iconPath`（SVG/位图）等比缩放至最长边 ≤128 统一转 PNG，缺失/损坏回退 `assets/icons/cardboard_box.svg`，`iconResolver` 可注入以配合测试；文件名 `<包ID>.<去 +build 版本>.nupkg`；先写 `.tmp` 再改名；输出目录自动创建）。`MainLayout.exportPackage` 可注入以配合测试。
- 「历史记录」流程：工具栏「历史记录」按钮（未选中包或选中 footer「设置/关于」时禁用）→ `lib/controls/pack_history_dialog.dart` 时间线对话框（最新在上，类型着色圆点/标签：创建/版本/映射/打包；删除条目无确认）；四类事件由 `MainLayout` 统一记录（`lib/models/history_model.dart` 的 `appendHistoryEntry()`，上限 100 条淘汰最旧）：创建包、版本变更（`_savePack` 对比旧包版本）、重新映射有变化（`_applyRemap` 对比路径集/总大小）、打包导出（`PackExportDialog.onExported`）；持久化为 YAML `history: [{time, type, message}]`。
- 「设置」页（`lib/pages/setting.dart`，footer「设置」）：打包输出目录（系统原生目录选择 + 清除）、主题模式（系统/深色/浅色）、深色主题配色（Frappe/Macchiato/Mocha）与强调色（14 个 Catppuccin 标准色）；改动即时生效并自动保存至 `config.yaml`（`PackTool` 有状态持有设置并重建 `FluentApp`，浮层提示「已保存」）；浅色模式固定 Latte；`buildTheme(brightness, flavor, accentName)`、`flavorByName()`、`accentColorFor()` 与两个名单常量见 `lib/util/colors.dart`。
- 「关于」页（`lib/pages/about.dart`，footer「关于」）：纸箱 Logo + 应用名 + 版本标签 + 描述 + 「项目主页」按钮（`openExternalUrl()` 经 explorer 打开默认浏览器，失败悬浮提示）+ 第三方声明指引；应用信息常量在 `lib/app_info.dart`（应用名/版本/描述/仓库地址）。
- UI 提示统一走 `lib/widgets/floating_toast.dart` 的 `showFloatingToast()`（右上角悬浮、success/info/error 图标配色、默认 3 秒自动关闭 + 手动关闭、同时最多一条、新提示替换旧提示）；「已保存」（3 秒）与配置加载失败警告（error、5 秒、多条合并）均用它。
- 领域模型在 `lib/models/`：`PackModel`（含可选 `license`/`iconPath`/`sourcePath` 与 `files`/`dependencies`/`commands`/`macros`/`libDirectories`/`libraries`/`history` 七类列表，`toMap`/`fromMap` 序列化）、`DependencyModel`（`name`/`version`）、`CmdModel`（`command`/`type`）+`CmdType`、`MacroModel`（`value`）、`LibDirModel`（`path`）、`LibraryModel`（`name`）——后三类与命令均含 `buildModel` 三态标签、`FileModel`/`FileType`（序列化只存 `path`/`size`，读回时由 basename 推导 name/type；类型识别覆盖 C++ 系与 pdb/asm/fortran/脚本/LLVM/Python/数据库/exe 等扩展）、`BuildModel`（`all`/`release`/`debug`，`fromName()` 容错解析：缺失→all、非法→FormatException）、`HistoryModel`（`time`/`type`/`message`，`HistoryType`：created/versionChanged/filesChanged/exported）、`SettingsModel`（全局设置：`outputDirectory`/`themeMode`/`darkFlavor`/`accent`，容错反序列化）。
- `dart:io` 用法集中在 `lib/scanner/file_scan.dart`（`FileScan.scan()` 异步单次遍历包目录，输出相对路径、稳定排序的 `FileModel` 列表；跳过隐藏目录与 `build`/`out`；`FileModel` 含 `size` 字节数）、`lib/util/file_opener.dart`（`openWithDefaultApp()` 用 `Process.run('explorer', ...)` 以系统默认程序打开文件；`revealInExplorer()` 以 `/select,` 两参数在资源管理器中定位文件；`openExternalUrl()` 以 explorer 打开 http/https 链接（默认浏览器）；前二者预检存在性、打开/定位前经 `explorerPath()` 把路径绝对化并将 `/` 统一为 `\`（explorer 对混合分隔符路径静默失败、只打开默认位置）、均不检查退出码——explorer 成功时也恒为 1）、`lib/controls/pack_preview_dialog.dart`（预览时 `File(path).readAsString()` 读取源文件文本）、`lib/packaging/nupkg_exporter.dart`（读取源文件字节并写出 .nupkg）与 `lib/packaging/package_icon.dart`（读取图标文件、渲染默认图标资产并输出 PNG 字节）。
- **Dart ↔ C++ 无任何桥接**（无 MethodChannel / FFI）；`windows/` 是 Flutter runner 模板，唯一自定义处是窗口标题（`windows/runner/main.cpp`）。要加原生能力需从零自建通道。
- 生成物禁止手改：`windows/flutter/generated_plugin_registrant.*`、`windows/flutter/generated_plugins.cmake`、`windows/flutter/ephemeral/`（均由 Flutter 重新生成）。

## Conventions

- **所有用户可见文案为中文**（硬编码，无 i18n 框架）；新增 UI 文案保持中文。
- UI 使用 `fluent_ui`（Win11 风格）而非 Material；主题色统一走 `lib/util/colors.dart`（`UCColors` / `buildTheme`；深色 flavor 与强调色可配置）。
- 图标：应用自绘 SVG 放 `assets/icons/` 并在 `lib/util/svgs.dart` 注册；目录树图标为第三方子集 `assets/icons/catppuccin/{latte,mocha}/`（catppuccin/vscode-icons v1.26.0，MIT，声明见 `THIRD_PARTY_NOTICES.md`），经 `lib/util/catppuccin_icons.dart` 解析（新增第三方资产须同步声明文件）。
- 测试：`test/` 下为标准 `flutter_test` 测试（冒烟 + 模型 + 扫描 + 配置存储 + 对话框/接线 + 页面 + 列表/工具（含 file_opener 路径规范化）+ 悬浮提示 + 图标映射 + 依赖管理 + 设置页/主题 + 编译设置 + 打包计划/预览/导出/包图标 + 历史记录 + 关于页/应用信息；widget 测试均用有界 `pump`，禁 `pumpAndSettle`）；新增测试放 `test/`。
- `file_selector` 用于「添加文件夹」的系统原生目录选择（`getDirectoryPath()`，取消返回 null）。
- YAML 配置读写用 Dart 官方 `yaml`/`yaml_edit` 包（封装在 `lib/config/pack_store.dart`）；打包 zip 生成用 `archive` 包（封装在 `lib/packaging/nupkg_exporter.dart`）。
- `README.md` 为正式项目文档（简介/功能特性/打包产物/构建运行/配置文件/版本发布/技术栈/第三方声明）；关键事实以本文件、`ci.yml`、CMake 与代码为准。
