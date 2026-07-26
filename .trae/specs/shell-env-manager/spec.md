# Shell 本地环境管理 - 产品需求文档 (PRD)

## Overview
- **Summary**：在 EnvMatrix 中新增"Shell 本地环境"模块，用于集中管理用户 macOS 登录 shell 的环境变量文件（`~/.zshrc`、`~/.zprofile`、`~/.zshenv`、`~/.bashrc`、`~/.bash_profile`、`~/.profile`）。该模块提供"结构化变量表 + 原文编辑器"双视图：用户既能像编辑表格一样增删改 `export KEY=VALUE` 与 `PATH` 追加项，也能切换到原文视图直接编辑文件内容；每次保存前自动创建带时间戳的备份。
- **Purpose**：EnvMatrix 目前只覆盖了各语言运行时、包管理器缓存与镜像的可视化；用户仍需要打开终端手动编辑 shell rc 文件来配置 `PATH`、`JAVA_HOME`、`GOPATH`、代理、别名相关变量等。此模块把最高频的"编辑 shell rc 文件"操作纳入统一 GUI，避免用户在终端与应用之间来回切换，并降低误改导致 shell 打不开的风险（借助自动备份）。
- **Target Users**：使用 macOS 开发的软件工程师，尤其是需要频繁配置多语言运行时/代理/镜像环境变量的用户。

## Goals
- G1：在侧边栏"系统"分组下新增"Shell 本地环境"入口，一次性列出系统上真实存在的 shell rc 文件。
- G2：为每个受支持的 rc 文件提供**结构化变量表视图**：解析出 `export KEY=VALUE` 行并允许可视化增删改。
- G3：为每个 rc 文件提供**原文编辑器视图**：等宽字体多行文本框，允许直接编辑原始文件内容。
- G4：保存时对目标文件先做时间戳备份（例如 `~/.zshrc.envmatrix.<yyyyMMdd-HHmmss>.bak`），再原子写入新内容。
- G5：所有文本读写在后台线程完成，主线程只负责 UI 更新，避免 UI 卡顿。
- G6：与现有本地化框架（`Localization+Zh.swift` / `Localization+En.swift`）集成，提供中英文双语。

## Non-Goals (Out of Scope)
- 不管理项目级 `.env` / `.env.local` / `.env.production` 文件。
- 不管理 macOS `launchctl setenv` 设置的系统级环境变量。
- 不实现"应用此变更后重启 shell / 使当前应用继承新 PATH"这类需要重启进程/系统才能生效的高级行为，仅负责写入文件。
- 不支持任意 shell 语法解析（例如条件语句、函数、`source` 链式加载等）；结构化视图只识别形如 `export KEY=VALUE`（含可选引号）的行，其他行在结构化视图中标记为"仅原文可见"。
- 不实现从备份恢复的界面（备份仅作为安全网，恢复由用户手工完成或后续迭代补齐）。
- 不新增自动化 UI 快照测试；UI 相关验证走人工判断项。

## Background & Context
- 项目导航采用 `NavigationItem` 枚举（[AppNavigation.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift)），侧边栏分组由 [allSections](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift#L108-L130) 定义；新增页面需要走 `NavigationItem` + `DetailView` 的既有路由模式（[DetailView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/DetailView.swift)）。
- 项目已有"读取用户登录 shell PATH"的能力（[ShellPathResolver.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ShellPathResolver.swift)），可以复用其"从 `SHELL` 环境变量推断当前 shell"的做法，用于优先展示与当前 shell 匹配的 rc 文件。
- 项目的 Service 层普遍采用"Protocol + Default 实现"（如 [CLIConfigService](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/CLIConfigService.swift#L17-L21) 与 [DefaultCLIConfigService](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/CLIConfigService.swift#L35-L67)），并使用 `try data.write(to: url, options: .atomic)` 原子写入，本模块将沿用相同模式。
- 项目的备份约定见 [BackupService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/BackupService.swift)：备份文件命名为 `.<name>.envmatrix[.<stamp>].bak`，本模块延续该约定。
- ViewModel 使用 `@MainActor` + `@Published`（例如 [CLIConfigViewModel](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/ViewModels/CLIConfigViewModel.swift)），本模块沿用同样的写法。
- **强制约束**（源自 `project_memory.md`）：耗时的目录扫描/文件 IO 必须放到后台线程；不能违反"UI 主线程不做重活"的规则。

## Functional Requirements
- **FR-1**：在启动时枚举以下候选 rc 文件（存在的才展示）：
  - `~/.zshrc`、`~/.zprofile`、`~/.zshenv`
  - `~/.bashrc`、`~/.bash_profile`、`~/.profile`
- **FR-2**：识别当前用户的登录 shell（读取 `$SHELL`），把它对应的 rc 文件在列表中标注为"当前 shell"，并默认选中该文件（若存在）；若无匹配文件则默认选中列表第一项。
- **FR-3**：结构化视图：解析文件每一行：
  - 匹配 `export KEY=VALUE` 或 `KEY=VALUE`（可带单/双引号）→ 变量条目。
  - 特殊：形如 `export PATH="$PATH:xxx"` / `export PATH=$PATH:xxx` 的行拆解成"当前 PATH 追加片段"列表（一行可含多个 `:` 分隔片段）。
  - 其他不识别的行（注释、`source`、函数、alias 等）在结构化视图汇总为"未解析行数：N"提示，并保留在原文中；结构化视图**不删除**这些行。
- **FR-4**：结构化视图允许：新增变量、编辑变量（键、值、是否使用引号）、删除变量、追加 / 编辑 / 删除 PATH 片段。
- **FR-5**：原文视图使用等宽字体的 `TextEditor` 展示完整文件内容，允许自由编辑；切换视图时若结构化视图有未保存改动，需要在切换前把结构化改动合并回原文缓冲（保留未解析行位置）。
- **FR-6**：保存流程：
  1. 若目标文件已存在，先复制一份到 `<file>.envmatrix.<yyyyMMdd-HHmmss>.bak`。
  2. 对目标文件执行原子写入（`Data.write(to:options:.atomic)`）。
  3. 保存完成后重新读取文件，刷新 UI。
- **FR-7**：任何一步失败（读取、写入、备份）需通过错误横幅提示（参考现有 CLIConfigView 的错误横幅样式），并保持编辑缓冲不丢失。
- **FR-8**：文件读写、时间戳生成等纯逻辑操作应放在 Service 层；ViewModel 用 `Task.detached(priority: .utility)` 或类似方式在后台线程发起，主线程只回填结果。
- **FR-9**：新增本地化字符串键（`shellEnv.*`）覆盖：模块标题、按钮（保存、刷新、切换视图、新增变量、删除、追加 PATH）、空态提示、错误信息模板。

## Non-Functional Requirements
- **NFR-1**（性能）：从选中文件到 UI 渲染出结构化视图，冷启动 < 200ms（rc 文件通常 < 100KB）。
- **NFR-2**（可靠性）：写入必须先备份再原子替换，确保任何异常都不会留下损坏的目标文件。
- **NFR-3**（一致性）：本模块所有 UI 元素（间距、字体、错误横幅、工具栏按钮位置）与现有 `CLIConfigView` 视觉一致。
- **NFR-4**（可测试性）：Service 层可注入 `FileManager` 与 home URL 以便单元测试；解析器（`export KEY=VALUE` → 结构化模型 / 结构化模型 → 原文）需要有覆盖典型情况的单元测试。
- **NFR-5**（本地化）：中英文完整覆盖，无遗漏硬编码字符串。

## Constraints
- **Technical**：Swift 5.9+/SwiftUI/macOS，遵循已有的 `@MainActor` ViewModel 模式；不能引入新的第三方依赖。
- **Business**：不改变现有导航结构中已有条目的语义或 id，避免破坏已保存的用户偏好。
- **Dependencies**：仅依赖 `Foundation` 与 `SwiftUI`；沿用 [FileSystem.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/FileSystem.swift) 中现有的工具（如有）。

## Assumptions
- 用户对自己的 home 目录下的 rc 文件拥有读写权限（macOS 沙盒关闭或使用非沙盒配置，与现有项目一致）。
- 用户对结构化视图不识别的行不做破坏性操作即认为可接受（结构化视图不擅自删除未解析行）。
- macOS 上目标 shell 是 zsh 或 bash（默认候选文件列表足够覆盖）。

## Acceptance Criteria

### AC-1: 侧边栏新增入口
- **Given**：应用已启动，`~/.zshrc` 存在
- **When**：用户查看侧边栏
- **Then**：在"系统"分组（或紧邻其上的独立分组）中出现"Shell 本地环境"入口；点击后详情区渲染 Shell 本地环境视图
- **Verification**：`programmatic`（`NavigationItem` 新增 case + `DetailView` switch 分支可通过 `swift build` 编译）+ `human-judgment`（视觉上分组归属合理）

### AC-2: rc 文件列表展示
- **Given**：`~/.zshrc` 与 `~/.zprofile` 都存在
- **When**：用户打开 Shell 本地环境视图
- **Then**：左侧列表列出两个文件；当前登录 shell 为 zsh 时，`~/.zshrc` 标注"当前 shell"并被默认选中
- **Verification**：`programmatic`（Service 返回顺序稳定，可通过注入 fake FileManager + 环境的单测覆盖）

### AC-3: 结构化视图能解析并回写
- **Given**：一个含有 `export FOO="bar baz"` 与 `export PATH="$PATH:/opt/x/bin:/opt/y/bin"` 的 rc 文件
- **When**：用户打开结构化视图 → 修改 `FOO` 的值为 `qux` → 删除 `/opt/y/bin` 片段 → 保存
- **Then**：文件被写回后重新解析，能看到 `FOO=qux`，`PATH` 中只保留 `/opt/x/bin`；未解析行（注释、alias 等）保持原样与相对位置
- **Verification**：`programmatic`（对解析器 + 合并器写单元测试）

### AC-4: 备份先于写入
- **Given**：`~/.zshrc` 存在原始内容 X
- **When**：用户在原文视图把内容改为 Y 并保存
- **Then**：磁盘上出现 `~/.zshrc.envmatrix.<yyyyMMdd-HHmmss>.bak` 且内容等于 X；`~/.zshrc` 内容等于 Y
- **Verification**：`programmatic`（Service 层单测直接断言）

### AC-5: 视图切换保留改动
- **Given**：用户在结构化视图里新增了一个 `HELLO=world`，尚未保存
- **When**：用户切换到原文视图
- **Then**：原文视图末尾（或原本 HELLO 该出现的位置）出现 `export HELLO="world"`；再切回结构化视图仍能看到 `HELLO` 条目
- **Verification**：`programmatic`（ViewModel 单测：结构化 ↔ 原文往返）+ `human-judgment`（视觉上没有丢字符）

### AC-6: 后台执行不卡顿
- **Given**：一个 200KB 的 rc 文件
- **When**：用户点击某文件 → 保存
- **Then**：UI 保持响应，不出现明显卡顿（>200ms 的主线程冻结）
- **Verification**：`human-judgment`（人工点击体验；配合代码审查确认 IO 位于 `Task.detached` / 后台队列）

### AC-7: 错误提示可见且不丢改动
- **Given**：目标 rc 文件因权限或磁盘满等原因无法写入
- **When**：用户点击保存
- **Then**：视图顶部出现错误横幅，包含错误描述；用户当前的编辑缓冲仍保留在 UI 上，可再次尝试
- **Verification**：`human-judgment`（人工触发无权限目录进行验证）

### AC-8: 中英文本地化覆盖
- **Given**：应用切换到英文
- **When**：用户查看 Shell 本地环境模块
- **Then**：所有可见文字（标题、按钮、空态、错误横幅模板）均为英文，无中文残留
- **Verification**：`programmatic`（对 `Localization+Zh.swift` 与 `Localization+En.swift` 做键覆盖检查）

## Open Questions
- [ ] 是否需要为"重置到最近一次备份"提供一键按钮？当前 spec 定为 Non-Goal；若用户后续要求可作为下一迭代。
- [ ] 是否需要对写入的 rc 文件运行一次 `zsh -n <file>` / `bash -n <file>` 做语法预检？为避免复杂度目前不做，如出现回归再评估。
