# C++ NuGet 打包工具 — 深色专业工具风 UI/UX 视觉规格

> 适用：Flutter 桌面应用（Material 3 + 自定义主题）。本文档为视觉规格，不含实现代码。
> 风格基准：VS Code 深色（背景 #1e1e1e/#252526/#2d2d30，强调 #007acc/#0e639c，紧凑密度，数据密集）。
> 术语：`主色`=强调色；`表面`=面板/卡片背景；`正文字体`=HarmonyOS_Sans_SC；`等宽`=mono。

## 一、设计原则（可执行规则）

| # | 原则 | 规则 |
| - | ---- | ---- |
| P1 | 对比度分层 | 背景用三档分层（最深 1e1e1e → 表面 252526 → 抬升 2d2d30），层级用背景差与 1px 边框表达，不用阴影 |
| P2 | 高信息密度 | 控件高 28-36px、行高 32-36px、字体 11-14px；Tab 内容 padding 12-16px；避免大留白与 hero 元素 |
| P3 | 层级 = 背景+边框+字号 | 页面结构靠分栏区（背景差 + 分隔边框）而非卡片投影建立；卡片仅用于强聚集（表单项/列表项） |
| P4 | 色彩语义克制 | 每屏有效用色 ≤ 3 个主语义色（强调/成功/错误）；警示黄仅用于 warn 状态，杜绝装饰性彩色 |
| P5 | 等宽专用于数据 | 路径/glob/日志/命令输出/代码片段一律等宽，与正文语义分离（开发工具惯例） |
| P6 | 动效只服务功能 | 仅用短于 200ms 的反馈动效（悬停/选中/展开）；禁装饰性动画与转场花活 |
| P7 | 无阴影、以边框分区 | 分栏分隔用 1px 边框，不用浮雕/渐变/重阴影；阴影只留给 Dialog/Menu/Popup |

## 二、设计令牌（Design Tokens）

### 2.1 颜色 Color

| 令牌 | 值 | 用途 |
| ---- | --- | ---- |
| `bg.app` | `#1e1e1e` | 窗口根背景 / 内容区 / 日志区 |
| `bg.panel` | `#252526` | 工具栏 / 左栏 / 右栏 Tab 区背景 |
| `bg.surface` | `#2d2d30` | 输入框内 / 表头 / 表格奇行 / 弹窗 |
| `bg.hover` | `#2a2d2e` | 行/项悬停背景 |
| `bg.sel` | `#094771` | 列表选中背景 |
| `bg.sel.inactive` | `#37373d` | 失焦选中背景 |
| `bg.disabled` | `#2d2d30` | 禁用项背景（叠加 .4 透明度） |
| `border` | `#3c3c3c` | 常规分隔/输入边框 |
| `border.strong` | `#454545` | 强调分隔线（左右栏边界、表头下边线） |
| `text.primary` | `#d4d4d4` | 主文本 |
| `text.semantic` | `#9d9d9d` | 次文本 / 表头 / 说明 / disabled 说明 |
| `text.disabled` | `#6a6a6a` | 禁用文本（WCAG 禁用豁免） |
| `text.onDark` | `#ffffff` | 强调/成功背景上的文字 |
| `accent` | `#007acc` | 强调填充（选中项/主按钮底部色/指示条），仅用于填充与边框 |
| `accent.hover` | `#0e639c` | 强调填充悬停 |
| `accent.strong` | `#0e639c` | 主按钮底色（VS Code primary 按钮） |
| `text.accent` | `#4fc1ff` | 强调色**文字**（链接/高亮 id），比 #007acc 更亮以满足 AA |
| `focus` | `#007fd4` | 键盘焦点描边 |
| `success` | `#3fb950` | 成功 / 通过 |
| `warn` | `#e0af68` | 警告信息 |
| `error` | `#f47067` | 错误信息 / 危险边框 |
| `error.bg` | `rgba(244,112,103,.12)` | 危险按钮悬停浅底 / 错误提示浅底 |

### 2.2 字体 Font

| 令牌 | 值 | 应用场景 |
| ---- | --- | --------- |
| `font.body` | `HarmonyOS_Sans_SC` | UI 全部文本（按钮/标签/标题） |
| `font.mono` | `fontFamilyFallback: ['Consolas','monospace']` 或新增资产（见下） | 文件路径、glob、表内技术列、日志、命令输出、宏/代码片段 |

- 等宽建议：Windows 目标环境系统自带 `Consolas`（专业、零成本），实现时用 `fontFamilyFallback` 兜底即可；若要跨平台一致，建议后续在 pubspec 增配 JetBrains Mono / Cascadia Code 资产。
- 现有资产仅 `HarmonyOS_Sans_SC_Regular`（单字重）：加粗为 Flutter 合成（faux-bold），可接受；后续如需更佳观感可补 Bold 资产，但不阻塞本期。
- 表内技术列（源 glob / 目标路径 / 平台·配置）一律 `font.mono`、字号比正文小 1-2px。

**字号阶梯**：

| 阶梯 | 值 | 用途 |
| ---- | -- | ---- |
| `t.caption` | 11px | 日志行内时间戳、表内次要注解 |
| `t.small` | 12px | 表头、按钮文字、表单体 |
| `t.body` | 13px | 正文、输入框 |
| `t.input` | 14px | 输入框焦点文案 / 关键值 |
| `t.h3` | 16px | Tab 页内分区标题、弹窗标题 |
| `t.h1` | 20px | 应用标题、主页面标题 |

**字号使用规则**：正文、表单、列表默认 `13px`；按钮 13px；中文字体行高 `1.4-1.55`；等宽行高 `1.5-1.6`。

### 2.3 间距 Spacing（4/8/12/16/24）

| 令牌 | 值 | 用途 |
| ---- | -- | ---- |
| `s.sm` | 4px | 图标与文字间距、紧凑内边距 |
| `s.1` | 8px | 组件间水平 micro 间距、图标按钮间距 |
| `s.2` | 12px | 表单行内子元素间距、Tab 内容区 padding |
| `s.3` | 16px | 分区之间、分栏与内容间距、Table 行内 |
| `s.4` | 24px | 页面级大区块之间 |

控件内边距推荐：输入框 `padding 8-10px (h)`；行高 `28-36px`；按钮 `12-16px (h)`。

### 2.4 圆角 Radius

| 令牌 | 值 | 用途 |
| ---- | -- | ---- |
| `r.sm` | 2px | 密集单元格、小 chip、状态标签 |
| `r.md` | 3px | 输入框、按钮、下拉、TabBar 选中段 |
| `r.lg` | 4px | 弹窗、卡片、面板容器 |

理由：桌面工具风为数据密集、紧凑布局，大于 4px 的圆角会引入视觉噪音并压缩内容；小圆角 + 1px 边框已足够建立层级，符合扁平化设计（AGENTS.md「UI/UX 设计规范」：纯色分层建立层级）。

### 2.5 阴影 Shadow

| 令牌 | 值 | 用途 |
| ---- | -- | ---- |
| `shadow.none` | 无 | 常规面板/卡片/表格（用背景+边框分层） |
| `shadow.popup` | `elevation 8, color rgba(0,0,0,.4)` | 仅 Dialog / Menu / Popup / Dropdown 浮层 |

原则：阴影**只给浮层**；面板、卡片、表格、按钮一律不用阴影（扁平化）。按钮层级差异靠背景明度与边框，不靠高度。

## 三、组件规格

> 通用约束：所有可交互元素提供 hover / focus / disabled 三态；图标按钮必须带 `Tooltip` + `SemanticLabel`（见"可访问性"）。

### 3.1 顶部工具栏

| 维度 | 规格 |
| ---- | ---- |
| 尺寸 | 高 40px；左 16px 标题，右 8px 图标按钮 |
| 外观 | 背景 `bg.panel`，下边框 `border.strong`；标题左侧可放 16px 小图标（可选） |
| 状态 | 标题：`text.primary`，20px 加粗；图标按钮 32x32，icon 18px `text.semantic`，hover bg `bg.hover`，focus 描边 `focus` |
| 行为 | 标题为应用名；设置按钮点击展开设置/偏好（Theme 切换、默认输出目录、nuget 路径缓存等） |
| Flutter | 不用 `AppBar`（密度与定制度不足），用自定义 `Material`(color: bg.panel) + Row；或 `AppBar` + `ThemeData.appBarTheme`（背景/前景/高度，`toolbarHeight: 40`）。右侧 `IconButton` 需 `<IconButton(iconSize:18, tooltip: '设置')>` |

### 3.2 左侧库列表

| 维度 | 规格 |
| ---- | ---- |
| 尺寸 | 宽 260-320px；背景 `bg.panel`；右边框 `border.strong`；固定，不随窗口缩放 |
| 结构 | 头部：`"库项目"` 16px `text.primary` + 右侧 `+` 添加按钮；下方 `ListView.builder` 列表 |
| 行默认 | 高 40px，左侧 16px 图标（`Icons.library_books`/`Icons.account_tree`），主行=包 id（`text.primary` 13px），副行=版本号（`text.semantic` 11px） |
| 悬停 | `bg.hover` |
| 选中 | `bg.sel`，主行 `text.onDark`，左侧 2px `accent` 指示条；失焦选中 `bg.sel.inactive` |
| 禁用/空态 | 无选中项时内容区显示占位；空列表显示空态文案 + 添加引导 |
| 行为 | 单击选中并驱动右栏 Tab 数据；`+` 触发「添加源目录」对话框；每行 trailing 提供 `...` 菜单（重命名/删除库项目） |
| Flutter | `ListView.builder` + 每行自定义 `InkWell`/`MouseRegion` 行组件（比 `ListTile` 更可控密度）；或 `ListTile` 经 `ListTileTheme` 统一；`NavigationRail` 不适合（需要显示版本号等富信息） |

### 3.3 TabBar / TabBarView（4 Tab）

| 维度 | 规格 |
| ---- | ---- |
| 尺寸 | 高 40px；背景 `bg.panel`；下边框 `border` |
| Tab | 包信息 / 文件映射 / 编译配置 / 打包；文字 13px，选中 `text.primary`，未选 `text.semantic` |
| 指示条 | 高 2px `accent`，仅选中 Tab 下 |
| 悬停 | 未选中 Tab hover 显示 `bg.hover` 背景 |
| 行为 | 点击切换 TabView；`包信息`/`文件映射`/`编译配置`/`打包` 均绑定当前选中库项目；未选中库项目时各 Tab 显示占位 |
| Flutter | `DefaultTabController(length:4)` + `TabBar`（`labelColor: text.primary, unselectedLabelColor: text.semantic, indicatorColor: accent, dividerColor: border, labelStyle: 13px`）+ `TabBarView` |

### 3.4 表单组件

| 组件 | 默认态 | 聚焦态 | 错误态 | 禁用态 |
| ---- | ------ | ------ | ------ | ------ |
| 文本输入 `TextFormField` | 背景 `bg.surface`，边框 `border`，圆角 3px，`text.primary` 13px，高 32-36px | 边框 2px `focus`，背景 `#1e1e1e` | 边框 2px `error`，下方 helper 文本 `error` 11px | 背景 `bg.disabled`+0.4 透明度，`text.disabled` |
| 下拉 `DropdownButtonFormField` / `DropdownMenu` | 同输入框 | 同输入框 focus | 同表单错误态 | 同禁用 |
| 开关 `Switch` | track 关 `bg.surface`+边框，开 `accent`；thumb 白 | — | — | overall 0.4 透明 |
| 主按钮 `FilledButton` | 底 `accent.strong`，文字 `text.onDark` 13px，圆角 3px，高 30-32px，左右 padding 12-16px | focus 描边 `focus` | — | 全透明 .4，文字 `text.disabled` |
| 次按钮 `OutlinedButton`/`TextButton` | 底 `bg.surface`，边框 `border`，文字 `text.semantic`；或纯文本 `text.accent` | hover 底 `bg.hover` | — | .4 透明 |
| 危险按钮（删除映射/确认删除） | 描边式：边框+文字 `error`，透明底；确认删除用填充式：底 `error`，文字 `text.onDark` | hover 底 `error.bg`（描边式）/ `error` 加深（填充式） | — | .4 透明 |

行为说明：
- 危险操作统一用 `error` 色区分；**描边式**用于表内行级次要删除，**填充式**用于"确认删除"这类需强确认的动作。
- 表单校验：设置 `errorText` 内联提示（对应字段下方），不用弹窗打断。

Flutter：统一经 `ThemeData` 的 `filledButtonTheme/outlinedButtonTheme/textTheme/inputDecorationTheme` 集中配置（勿在 `base_style.dart` 硬编码，见 §七）。输入框可用统一 `InputDecoration`（`filled: true, fillColor: bg.surface, border/activeBorder/errorBorder` 用 `OutlineInputBorder` 圆角 3px）。

### 3.5 文件映射表

| 维度 | 规格 |
| ---- | ---- |
| 列 | 源 glob / 目标路径 / 平台·配置条件 / 操作 |
| 行高 | 34-36px，紧凑；行分隔线 `border` 1px |
| 表头 | 高 32px，背景 `bg.surface`，文字 `text.semantic` 12px 加粗，表头下边线 `border.strong`（sticky） |
| 内容 | 源 glob / 目标路径 / 条件列用 `font.mono` 12px；平台·配置列用 chip 或纯文本 `text.semantic` |
| 行悬停 | `bg.hover` |
| 行操作 | 操作列两个图标按钮：编辑（铅笔）`text.semantic`、删除（垃圾桶）`error`；仅行悬停/选中时显示，避免始终占用空间 |
| 空态 | 居中图标 + 文案 `尚无文件映射` + `添加映射` 按钮 |
| 禁用 | 未选中库项目时整表灰化/占位；行删除为危险操作，删除前置确认弹窗 |

行为说明：支持新增/编辑/删除单条映射；每个映射可携带"平台·配置条件"（可选，留空=适用于所有）。

Flutter：**推荐自定义 `ListView.builder` + 行 widget**（行内三列用 `Row`/`IntrinsicHeight` 或 `Table`），便于精细控制等宽字体、行操作按钮与 hover；`DataTable` 也可用但有局限（列宽/字体/懒加载/行内按钮样式不易定制，数据量小场景可用）。若数据量大（>200 行）必须用懒加载列表并只渲染可见行。

### 3.6 打包页

| 维度 | 规格 |
| ---- | ---- |
| 模式切换 | `SegmentedButton`（推荐，单行紧凑）两段：`一键打包` / `仅生成文件`；选中段背景 `accent`，文字 `text.onDark`；未选段文字 `text.semantic` |
| 输出目录 | 只读 `TextFormField` + 右侧文件夹选择 `IconButton`；显示已选路径（`font.mono` 12px） |
| nuget 路径 | `TextFormField` + `浏览` 按钮；支持自动探测并缓存到设置 |
| 打包按钮 | 主按钮 `FilledButton`：`一键打包` → `打包`，`仅生成文件` → `生成文件` |
| 打包按钮禁用逻辑 | 满足全部条件才可点击：① 已选中库项目 ② 包 id 与版本已填 ③ 输出目录已选 ④ `一键打包` 模式下 nuget.exe 路径已配置。禁用时下方显示说明文字（`text.semantic` 12px）说明缺失项 |

行为说明：点"打包"进入加载态（按钮变为 spinner + `正在打包…` 并禁用，防重复点击）；日志面板实时追加输出流（见 §5.2）。

Flutter：用 `SegmentedButton`（M3）而非 `Radio`（紧凑省行）；输出目录选择用 `showDirectoryPicker`（`file_picker` / `file_selector` 包）；禁用态用 `onPressed: enabled ? fn : null` + 说明文案。

### 3.7 底部日志面板

| 维度 | 规格 |
| ---- | ---- |
| 尺寸 | 高 160-220px（可折叠）；背景 `bg.app`；顶边框 `border.strong` |
| 头部 | 高 32px：左侧 `日志` `text.primary` 13px，右侧 `清空`（次按钮小图标）+ 折叠箭头（上/下） |
| 内容 | 等宽 `font.mono` 11-12px；每行 = `时间戳(text.semantic) + 级别(着色) + 消息(text.primary)`；行内左 2px 级别色条 |
| 行着色 | INFO=`text.semantic`（或 `text.accent`）、WARN=`warn`、ERROR=`error` |
| 清空 | 危险风格次按钮，点击清空并日志提示 |
| 折叠 | 点击头部折叠，折叠后仅留头部 32px，可视区恢复主内容；展开箭头 / 折叠未读条数提示 |
| 自动滚动 | 追加新行自动滚动到底部；用 `reverse: true` 的 `ListView`（新行 index 0）天然贴底，无需手动锚点 |
| 空态 | 无日志时头部下方显示 `暂无日志`（`text.semantic`） |

Flutter：用 `ScrollController` 或 `reverse ListView` 实现追加贴底；级别着色用 `TextStyle(color)` 或左侧 `Container(width:2,color:levelColor)` 装饰；日志从 `Stream`/`ChangeNotifier` 订阅增量追加；折叠用 `AnimatedContainer`/`AnimatedSize`（200ms）。

### 3.8 对话框（添加源目录 / 确认删除）

| 维度 | 规格 |
| ---- | ---- |
| 外观 | 背景 `bg.surface`，边框 `border.strong`，圆角 4px，最小宽 480px、最大 600px，浮层阴影 `shadow.popup`；标题 `text.primary` 16px |
| 添加源目录 | ① 目录路径 `TextFormField`（只读）+ 浏览按钮 ② 可选"扫描范围/平台·配置"筛选 `FilterChip` ③ 扫描进度条（`LinearProgressIndicator`）＋状态文案 ④ 映射建议预览列表（只读，含勾选，按匹配文件高亮）⑤ 动作：`开始扫描`（次）/ `确认添加`（主，扫描完成才可点）/ `取消`（次） |
| 确认删除 | 标题 `删除确认`，正文说明被删对象（如映射 glob），动作：`删除`（填充式危险）+ `取消`（次按钮）；不可点关闭外的其他默认按钮，防误触 |
| 状态 | 扫描进行中：spinner + `正在扫描… 已发现 N 项`；完成（成功）：`扫描完成，发现 N 项可映射`（success 色）；失败：`扫描失败：<原因>`（error 色），`确认添加` 禁用 |

行为说明：对话框内进度与状态内联呈现，不用 SnackBar 贯穿长流程。

Flutter：用 `showDialog` + `AlertDialog`（`backgroundColor: bg.surface, shape: RoundedRectangleBorder(radius 4)`，`titleTextStyle`/`contentTextStyle` 主题化）；长表单（添加源目录）用 `Dialog` 自定义内容布局，避免 `AlertDialog` 内容溢出。

## 四、页面布局规格

### 4.1 完整窗口布局（ASCII）

```
+------------------------------------------------------------------------------+
|  [图标] C++ NuGet 打包工具                                   [设置 ⚙] (40px)  |  工具栏 40px
+-----------------------------+------------------------------------------------+
|  库项目              [ + ]  |   [包信息] [文件映射] [编译配置] [打包]    (40px)  |  TabBar 40px
|-----------------------------+------------------------------------------------+
|  (左栏 260-320px)          |  Tab 内容区  padding 12-16px                       |
|                            |                                                  |
|  ▎MyLib  (包 id)           |   [包信息 / 文件映射 / 编译配置 / 打包]             |
|    v1.2.0                  |   当前选中库项目的表单或表格                        |
|  MyLib2                    |   内容占满右栏宽度                                  |
|    v1.0.0                  |                                                  |
|                            |                                                  |
|  (空列表=空态提示)         |  (未选中库项目=占位提示)                            |
+-----------------------------+------------------------------------------------+
|  [日志]                              [清空]      [▾ 折叠]            (32px)  |  头部 32px
|  12:01:02  INFO  Build started ...                                        |
|  12:01:03  WARN  Skipping header without license: <path>                  |  日志区 160-220px
|  12:01:04  ERROR NuGet pack failed: <reason>                              |
+------------------------------------------------------------------------------+
       左栏 260-320px          主区（自适应，≥1280×800）                     日志区（可折叠）
```

### 4.2 尺寸建议

| 区域 | 尺寸 |
| ---- | ---- |
| 左栏 | 260-320px（固定区，随窗口缩放保持在范围，可拖拽边界可选） |
| 工具栏 | 高 40px |
| TabBar | 高 40px |
| Tab 内容区 padding | 12-16px |
| 日志面板 | 高 160-220px（默认 200px；可折叠至仅头部 32px） |
| 窗口最小尺寸 | 1280×800（保持左栏+主区可用、日志不挤压） |

### 4.3 空态 / 未选中占位

| 场景 | 占位内容 |
| ---- | -------- |
| 左栏空列表 | 居中图标 + `尚未添加库项目` + `点击 + 添加` 引导按钮 |
| 未选中库项目（右栏） | 居中占位：`从左侧选择一个库项目开始编辑` |
| `文件映射` Tab 空 | `尚无文件映射` + `添加映射` 按钮 |
| `打包` 页未满足条件 | 打包按钮禁用 + 下方 `text.semantic` 说明缺失项 |

## 五、交互与反馈

### 5.1 扫描进度状态机

| 状态 | 呈现 | 提示文案示例 |
| ---- | ---- | ------------ |
| 进行中 | 对话框内 `LinearProgressIndicator` + spinner 图标 | `正在扫描目录… 已发现 N 项` |
| 完成 | 状态文案转 success 色，`确认添加` 启用 | `扫描完成，发现 N 项可映射文件` |
| 失败 | 状态文案转 error 色，`确认添加` 禁用 | `扫描失败：<具体原因>` |

### 5.2 打包过程实时日志流

- 打包子进程 stdout/stderr 按行增量写入日志面板；用 `Stream`/`ChangeNotifier` 订阅，逐行 append。
- 日志面板 `reverse: true` 列表天然贴底；行级别着色（INFO/WARN/ERROR），ERROR 行左 2px `error` 色条。
- 打包期间主按钮转 `loading`（spinner + 文案），禁重复点击；打包结束后按钮恢复，日志追加结果行（成功/失败）。

### 5.3 错误呈现选择规则

| 类型 | 方案 |
| ---- | ---- |
| 表单/持久数据错误 | **内联错误**（字段下方 `errorText`），常驻可修，不弹窗打断 |
| 一次性操作错误 | **SnackBar**（打包失败、复制失败、命令异常），自动消失，同时写入日志面板 |
| 需用户决策的错误 | 点击后弹出确认（如删除映射），不静默 |

规则：**能就地修的先就地，结果型的用 SnackBar+日志**；所有错误同时落到日志面板以便回溯。

### 5.4 加载中状态

- 扫描 / 打包：对应按钮或面板区域显示 `LinearProgressIndicator`（2-4px 顶部细条）＋状态文案。
- 长列表/表格：首屏 loading 时显示居中 spinner，不用骨架屏（紧凑工具风，数据量小）。

## 六、可访问性

### 6.1 对比度（WCAG AA ≥ 4.5:1，正文/背景）

| 文本/背景 | 对比度 | 达标 |
| --------- | ------ | ---- |
| `text.primary #d4d4d4` / `bg.app #1e1e1e` | ≈11.4:1 | √ AA |
| `text.primary #d4d4d4` / `bg.surface #2d2d30` | ≈9.9:1 | √ AA |
| `text.semantic #9d9d9d` / `bg.app #1e1e1e` | ≈6.2:1 | √ AA（次文本） |
| `text.accent #4fc1ff` / `bg.app #1e1e1e` | ≈6.9:1 | √ AA（强调字） |
| `text.onDark #fff` / `accent.strong #0e639c` | ≈6.4:1 | √ AA（主按钮字） |
| `success #3fb950` / `bg.app` | ≈7.0:1 | √ AA |
| `warn #e0af68` / `bg.app` | ≈8.2:1 | √ AA |
| `error #f47067` / `bg.app` | ≈6.3:1 | √ AA |
| `text.disabled #6a6a6a` / `bg.app` | ≈3.0:1 | — WCAG 禁用文本豁免 |

- `#007acc` 仅作填充/边框/指示条，**不作深底文字色**（作为文字对比度 ≈3.7:1 不达 AA）；作文字时用 `text.accent #4fc1ff` 或用白色 `text.onDark` 承载于强调填充上。
- 所有正文/次文本/状态色均在 AA 以上；仅 disabled 豁免。

### 6.2 键盘导航

- Tab 顺序：左上（工具栏标题/设置）→ 左栏 `+`与列表项 → 右栏 TabBar → Tab 内容各控件（从上到下、从左到右）→ 底部日志面板。用 Flutter 默认遍历，保证分栏内顺序合理。
- Enter 触发主操作（对话框"确认添加/确认删除"、表单提交）；Space 切换 Switch/触发按钮；Esc 关闭对话框。
- 所有图标按钮提供 `Tooltip` + `SemanticLabel`；键盘 focus 时有 2px `focus`(#007fd4) 描边，清晰可见。

## 七、实现索引

### 7.1 lib/ui/ 文件建议

| 文件 | 职责 |
| ---- | ---- |
| `lib/ui/tokens.dart` | 颜色/间距/圆角/字号常量（`AppColors`/`AppSpacing`/`AppRadius`/`AppFonts`），供主题与组件共用 |
| `lib/ui/theme.dart` | 构建 `ThemeData`（colorScheme + textTheme + 各 componentTheme），导出 `buildAppTheme()`；含 `darkTheme` 配置 |
| `lib/ui/pages/main_workspace.dart` | 三栏工作台 scaffold（左栏+右栏+底部日志），TabBar/TabBarView 容器 |
| `lib/ui/pages/pack_info_page.dart` | `包信息` Tab（id/version/description/authors/tags/license 表单） |
| `lib/ui/pages/file_mapping_page.dart` | `文件映射` Tab（映射表 + 增删改 + 空态） |
| `lib/ui/pages/build_config_page.dart` | `编译配置` Tab（宏/C++ 标准/链接依赖/数据文件拷贝/消费者源码注入 + 平台·配置矩阵） |
| `lib/ui/pages/pack_page.dart` | `打包` Tab（模式切换/输出目录/nuget 路径/打包按钮状态机） |
| `lib/ui/widgets/top_toolbar.dart` | 顶部工具栏 |
| `lib/ui/widgets/library_list.dart` | 左栏库列表（含选中/悬停/空态/`+`添加） |
| `lib/ui/widgets/mapping_table.dart` | 映射表行/表头/空态 |
| `lib/ui/widgets/log_panel.dart` | 底部日志面板（级别着色/清空/折叠/自动滚动） |
| `lib/ui/widgets/app_dialogs.dart` | 添加源目录对话框、确认删除对话框、通用选择器 |

### 7.2 主题代码位置

- 主题集中在 `lib/ui/theme.dart`（+ 常量在 `lib/ui/tokens.dart`），入口 `main.dart` 用 `theme: buildAppTheme()` 注入。
- 本应用为**深色专用**：`MaterialApp` 设 `themeMode: ThemeMode.dark`，只提供一套深色 `ThemeData`（可保留 `darkTheme` 即可，不强制做 light）。

### 7.3 与 `lib/base_style.dart` 的处置建议

- **建议删除 `base_style.dart`**。原因：硬编码 `Colors.blue`、`fontSize:16`、加粗、`radius 5`，与本文档令牌体系（`#007acc/+14px/radius 3`）冲突，且单文件全局 `ButtonStyle` 违背组件级主题化。
- 处置：删除后，按钮统一经由 `theme.dart` 的 `filledButtonTheme`/`outlinedButtonTheme`/`textButtonTheme` 配置，如需样式差异（危险/次按钮），在组件内用上层 `FilledButton.styleFrom` 局部覆盖，而非全局硬编码。
- 若暂不能删：将其中常量迁移到 `tokens.dart`，并删除硬编码色值，改引用令牌。

完
