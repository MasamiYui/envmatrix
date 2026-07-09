# EnvMatrix - macOS 原生环境管理器 - 实施计划

> 约定：所有 Swift 源码存放于 `EnvMatrix/Sources/EnvMatrix/`；测试位于 `EnvMatrix/Tests/EnvMatrixTests/`。构建工具采用 Swift Package Manager (executableTarget，macOS 13.0)。

## [x] Task 1: 初始化 Swift Package 项目骨架
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 在项目根目录创建 `Package.swift`，声明 macOS 13 平台、executable target `EnvMatrix`、test target `EnvMatrixTests`。
  - 创建目录 `Sources/EnvMatrix/`、`Tests/EnvMatrixTests/`、`Resources/`。
  - 添加 `.gitignore`（Swift/Xcode 通用）。
  - 生成入口 `EnvMatrixApp.swift`（`@main` App）和最小 `ContentView.swift`。
- **Acceptance Criteria Addressed**: AC-12
- **Test Requirements**:
  - `programmatic` TR-1.1: 在项目根执行 `swift build` 返回 exit code 0 且无 error。
  - `programmatic` TR-1.2: `Package.swift` 声明 `.macOS(.v13)` 且 target 结构正确。
- **Notes**: 保持最小依赖；仅使用 Foundation + SwiftUI。

## [x] Task 2: 核心领域模型与工具层
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 创建 `Models/RuntimeVersion.swift`、`Models/RuntimeKind.swift`（enum: node/python/java/go/rust）、`Models/Skill.swift`、`Models/MCPServer.swift`、`Models/CLIConfig.swift`。
  - 创建 `Utils/FileSystem.swift`（封装 FileManager 常用能力，含 `~/.envmatrix` 目录初始化）。
  - 创建 `Utils/Shell.swift`（Process 执行命令，异步 async/await 接口）。
  - 创建 `Utils/Logger.swift`（OSLog 简单封装）。
- **Acceptance Criteria Addressed**: AC-3, AC-4, AC-5, AC-6, AC-11
- **Test Requirements**:
  - `programmatic` TR-2.1: 运行 `swift test` 覆盖 `FileSystem.envmatrixRoot` 返回 `~/.envmatrix` 绝对路径。
  - `programmatic` TR-2.2: `Shell.run("/bin/echo", ["hello"])` 单测返回 stdout="hello\n" 且 exitCode=0。
  - `programmatic` TR-2.3: 所有新增 Swift 文件行数 ≤ 500。

## [x] Task 3: Runtime 管理服务（下载 / 安装 / 切换 / 卸载）
- **Priority**: P0
- **Depends On**: Task 2
- **Description**:
  - 创建 `Services/RuntimeService.swift`（协议 + 默认实现），提供 `listAvailable(kind:)`、`listInstalled(kind:)`、`install(version:kind:progress:)`、`activate(version:kind:)`、`uninstall(version:kind:)`。
  - 创建 `Services/Providers/NodeProvider.swift`：解析 `https://nodejs.org/dist/index.json`，选择 darwin-arm64 / darwin-x64 tarball。
  - 创建 `Services/Providers/PythonProvider.swift`：解析 python-build-standalone GitHub releases。
  - 创建 `Services/Providers/JavaProvider.swift`：调用 Adoptium API。
  - 创建 `Services/Providers/GoProvider.swift`：解析 `https://go.dev/dl/?mode=json`。
  - 创建 `Services/Providers/RustProvider.swift`：读取本机 rustup toolchain 列表（`rustup toolchain list`），激活通过 `rustup default`。
  - 版本安装到 `~/.envmatrix/versions/<kind>/<version>/`；shim 位于 `~/.envmatrix/shims/`。
- **Acceptance Criteria Addressed**: AC-2, AC-3, AC-4, AC-5
- **Test Requirements**:
  - `programmatic` TR-3.1: Mock URLSession 后 `NodeProvider.listAvailable()` 返回非空数组，能解析出版本号。
  - `programmatic` TR-3.2: `activate(version:kind:)` 后 `~/.envmatrix/shims/node` 是指向对应目录的 symlink（unit test 用临时目录）。
  - `programmatic` TR-3.3: `uninstall` 后目标目录不存在，若为激活版本则 shim 被移除。
  - `programmatic` TR-3.4: 每个 Provider 文件行数 ≤ 500。

## [x] Task 4: AI 环境服务（Skills / CLI / MCP）
- **Priority**: P0
- **Depends On**: Task 2
- **Description**:
  - 创建 `Services/SkillsService.swift`：扫描 `~/.claude/skills`、`~/.trae-cn/skills`、`~/.trae/skills`；提供 enable/disable（`.disabled` 后缀重命名）、delete、reveal 功能。
  - 创建 `Services/CLIConfigService.swift`：读写常见 JSON 配置；敏感字段（apiKey/token）以掩码返回。
  - 创建 `Services/MCPService.swift`：读写 MCP JSON 配置文件，支持 CRUD。
- **Acceptance Criteria Addressed**: AC-6, AC-7, AC-8
- **Test Requirements**:
  - `programmatic` TR-4.1: 在临时目录构造 3 个假 skill，`SkillsService.list()` 返回 3 条；disable 后再 list，其状态为 `.disabled`。
  - `programmatic` TR-4.2: `CLIConfigService.load()` 对 `apiKey` 字段返回掩码字符串（如 `sk-****abcd`）。
  - `programmatic` TR-4.3: `MCPService.add(server:)` 后再次 `load()` 能查到该条目，且 JSON 文件格式合法。

## [x] Task 5: SwiftUI 界面 - App 骨架与 Dashboard
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 使用 `NavigationSplitView` 构造主布局；侧边栏包含 Dashboard、Dev Environments (5 项)、AI Environments (3 项)、Settings。
  - 创建 `Views/Dashboard/DashboardView.swift`：卡片式展示每种语言当前版本、Skills 数、MCP 数、磁盘占用。
  - 采用 SF Symbols 与 `.background(.regularMaterial)` 等 native 视觉效果。
- **Acceptance Criteria Addressed**: AC-1, AC-9, AC-10
- **Test Requirements**:
  - `human-judgement` TR-5.1: 主界面视觉简约现代，与 macOS Sonoma/Sequoia 一致，评审通过。
  - `programmatic` TR-5.2: 每个 View 文件行数 ≤ 500。

## [x] Task 6: SwiftUI 界面 - Dev Environments 页面
- **Priority**: P0
- **Depends On**: Task 3, Task 5
- **Description**:
  - 创建通用组件 `Views/DevEnv/RuntimeDetailView.swift`：Tabs 分 Installed / Available；表格展示版本 + 操作按钮。
  - 每种语言对应一个薄壳视图（NodeView/PythonView/JavaView/GoView/RustView），复用 RuntimeDetailView。
  - 创建 `ViewModels/RuntimeViewModel.swift`（@MainActor ObservableObject）驱动异步下载/安装并驱动进度条。
- **Acceptance Criteria Addressed**: AC-2, AC-3, AC-4, AC-5
- **Test Requirements**:
  - `programmatic` TR-6.1: ViewModel `installProgress` 属性能在下载过程中被更新（用 mock 触发 progress callback）。
  - `human-judgement` TR-6.2: 界面下载中显示进度条、当前版本被高亮为"Active"。

## [x] Task 7: SwiftUI 界面 - AI Environments 页面
- **Priority**: P1
- **Depends On**: Task 4, Task 5
- **Description**:
  - 创建 `Views/AI/SkillsView.swift`：列出 skills，Toggle 切换启用，右键菜单支持 Reveal in Finder / Delete。
  - 创建 `Views/AI/CLIConfigView.swift`：以 Form 形式编辑关键字段，API Key 采用 `SecureField`。
  - 创建 `Views/AI/MCPServersView.swift`：List + Add/Edit Sheet，字段：name、command、args (逗号分隔)、env (key=value 列表)。
- **Acceptance Criteria Addressed**: AC-6, AC-7, AC-8
- **Test Requirements**:
  - `programmatic` TR-7.1: 触发 SkillsViewModel.toggle 后底层文件被重命名 `.disabled`。
  - `human-judgement` TR-7.2: MCP 编辑弹窗使用 Sheet 展示，字段布局清晰。

## [x] Task 8: Settings 页面 & 主题适配
- **Priority**: P1
- **Depends On**: Task 5
- **Description**:
  - 创建 `Views/Settings/SettingsView.swift`：使用 `TabView` 呈现 General（主题、镜像源）、Logs（表格滚动）、About。
  - 通过 `@AppStorage("colorSchemePreference")` 支持系统/浅色/深色。
- **Acceptance Criteria Addressed**: AC-10, AC-11
- **Test Requirements**:
  - `programmatic` TR-8.1: 切换 colorSchemePreference 后 `preferredColorScheme` 环境值随之更改（单测视图状态）。
  - `human-judgement` TR-8.2: 深浅色模式切换后无控件断层、可读性良好。

## [x] Task 9: 集成测试与构建校验
- **Priority**: P0
- **Depends On**: Task 3, Task 4, Task 6, Task 7, Task 8
- **Description**:
  - 在 `Tests/EnvMatrixTests/` 增加最终集成测试：模拟 install→activate→uninstall 端到端；模拟 Skills toggle；模拟 MCP CRUD。
  - 在 CI 脚本 `scripts/verify.sh` 中依次执行 `swift build`、`swift test`、`find . -name "*.swift" -exec wc -l {} + | awk '$1>500'` 检查。
- **Acceptance Criteria Addressed**: AC-11, AC-12
- **Test Requirements**:
  - `programmatic` TR-9.1: `swift build` 成功。
  - `programmatic` TR-9.2: `swift test` 通过，覆盖 ≥ 10 个 test cases。
  - `programmatic` TR-9.3: 无任何 `.swift` 文件行数 > 500。
