# 新增 Provider：Kotlin / uv / pnpm - Product Requirement Document

## Overview
- **Summary**：在 EnvMatrix 现有的 Runtime + Packages 双轴框架下，扩充三个高呼声生态的一等公民支持：**Kotlin**（作为独立 Runtime，与 Java/Scala 同类）、**uv**（Python 生态的 pip 替代，位于 Packages 分区）、**pnpm**（Node 生态的 npm 替代，位于 Packages 分区）。三者遵循既有的 Provider / Service / ViewModel / View 分层与备份、二次确认、i18n 双语约束。
- **Purpose**：填补当前 11 种运行时对 JVM 系语言（Kotlin 独立于 Java toolchain）的缺失；同时把 Python / Node 现代包管理器纳入统一入口，减少用户在 EnvMatrix 之外再打开终端切换镜像/清理缓存的场景。
- **Target Users**：使用 Kotlin/Android/KMP 的 JVM 开发者；采用 uv 加速 Python 依赖管理的科学计算/AI 开发者；使用 pnpm 管理 monorepo 的前端/全栈开发者。

## Goals
- 在 [RuntimeKind.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/RuntimeKind.swift) 新增 `case kotlin`，并接入 Runtime 三分栏（Installed/Available/Usage）、Dashboard 卡片、侧边栏导航与全局搜索。
- 提供 [KotlinProvider.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/Providers) 实现 `VersionProvider`，从 JetBrains/kotlin GitHub Releases API 解析可用版本与 darwin 归档下载 URL。
- 提供 [UvService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services) 与对应 ViewModel / View：镜像切换（清华 / 阿里 / 官方 PyPI）、全局工具列表（`uv tool list`）+ 二次确认卸载（`uv tool uninstall`）、缓存统计与清理（`uv cache dir` + `uv cache clean`）。
- 提供 [PnpmService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services) 与对应 ViewModel / View：registry 切换（官方 / 淘宝 / 腾讯 / 华为，写入 `pnpm config set registry`，同时保留 `.envmatrix.bak`）、全局包列表（`pnpm ls -g --depth 0 --json`）+ 二次确认卸载（`pnpm remove -g <pkg>`）、`pnpm store path` + `pnpm store prune` 的存储占用统计与清理。
- 三个新增模块的 i18n key 完整对称登记到 [Localization+En.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 与 [Localization+Zh.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift)。
- 补齐单元测试（Provider 解码、Service 命令解析），覆盖率不低于现有 Node/Npm 模块的水平；全量 `swift test` 通过。

## Non-Goals (Out of Scope)
- **不**为 Kotlin 实现 `install(version:)` 的真实解包安装逻辑；沿用 `DefaultRuntimeService` 通用 `tar.gz` 下载 → strip-components=1 解压路径即可，不做 Kotlin 特有的 `bin/kotlinc` 二次校验或字节码验证。
- **不**触碰 IntelliJ IDEA / Android Studio 内嵌的 Kotlin plugin，仅识别独立发行版 `kotlin-compiler-*.zip` 或 sdkman 管理的 `~/.sdkman/candidates/kotlin/`。
- **不**新增 uv / pnpm 的"运行时安装向导"；假定用户已经通过 brew / curl 安装了 `uv` 与 `pnpm` CLI。若未安装，UI 展示与 [PipMissingView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/PipMissingView.swift) 相同的空态提示。
- **不**支持在 pnpm workspace / uv workspace 内的按项目 registry 覆盖（仅处理全局配置）。
- **不**修改现有 npm / pip / cargo / gem / composer 模块的既有行为；三者的存在与否互相独立。

## Background & Context
- 项目当前所有 Provider 均以 [VersionProvider](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/RuntimeService.swift#L28-L31) 协议实现（见 [JavaProvider.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/Providers/JavaProvider.swift) / [NodeProvider.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/Providers/NodeProvider.swift)），使用 `internal static func decode(data:arch:)` 暴露给测试。
- Kotlin 官方分发通过 GitHub Releases，产物是 `kotlin-compiler-<version>.zip`（跨平台，非架构相关），下载地址形如 `https://github.com/JetBrains/kotlin/releases/download/v2.0.0/kotlin-compiler-2.0.0.zip`。RuntimeKind 需要暴露 `binaryName = "kotlinc"`，`SystemRuntimeDetector` 会通过 PATH 查找并 `kotlinc -version`。
- 侧边栏项目由 [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift#L127-L139) 硬编码，"nav.devEnvironments" section 需追加 `.devEnv(.kotlin)`。项目规则明确：新 RuntimeKind 必须在此显式配置。
- Packages 分区已存在 npm/pip 完整的"三 Tab"结构（Registry / Global Packages / Cache），uv 与 pnpm 直接复用该结构，仅替换服务实现。侧边栏在 `nav.packagesLangs` section 追加 `.packagesUv` / `.packagesPnpm`。
- 所有写入配置文件的动作必须先生成 `.envmatrix.bak` 备份（[BackupService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/BackupService.swift)）。pnpm 用户级配置文件默认在 `~/.npmrc`（复用当前 npm 备份逻辑）或 `~/.config/pnpm/rc`，需要分开处理。
- 已有约束：i18n 全部走 Localization+*.swift，不允许硬编码；单文件 ≤500 行；所有子进程调用走 [ProcessExecutor.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessExecutor.swift) 数组参数，避免 shell 拼接。

## Functional Requirements
- **FR-1**：`RuntimeKind.kotlin` 与 `displayName = "Kotlin"`、`binaryName = "kotlinc"` 存在于枚举中；`allCases` 包含它。
- **FR-2**：`KotlinProvider.listAvailable()` 通过 `https://api.github.com/repos/JetBrains/kotlin/releases?per_page=30` 拉取，剔除 `prerelease == true` 与 `draft == true` 的项，解码为 `RuntimeVersion`，`downloadURL` 指向 `kotlin-compiler-*.zip` 资产；网络异常时抛 `RuntimeServiceError.network`，JSON 异常时抛 `RuntimeServiceError.decoding`。
- **FR-3**：`SystemRuntimeDetector` 能通过 PATH 上的 `kotlinc -version` 输出（stderr）解析出 `x.y.z` 格式版本；`RuntimeKind+Branding.swift` 提供 Kotlin 图标与紫色品牌色（Kotlin 官方橙紫渐变可简化为 `Color(red:0.44, green:0.32, blue:0.98)`）。
- **FR-4**：Dashboard 与 Runtime 三分栏对 Kotlin 显示与其他运行时同构的 UI，无 crash、无 layout 破坏。
- **FR-5**：`UvService` 提供 5 个方法：`isAvailable() -> Bool`、`currentRegistry() -> URL?`（读 `UV_INDEX_URL` / `~/.config/uv/uv.toml`）、`setRegistry(_ preset:)`（写入前备份 `uv.toml.envmatrix.bak`，preset 至少含官方 PyPI / 清华 TUNA / 阿里云 / 腾讯云）、`listGlobalTools() -> [UvTool]`（解析 `uv tool list` 输出）、`uninstallTool(_ name:)`、`cacheStats() -> UvCacheStats`（`du -sh $(uv cache dir)`）、`cacheClean()`（`uv cache clean`）。
- **FR-6**：`PnpmService` 提供对称的 5 个方法：`isAvailable()`、`currentRegistry()`（`pnpm config get registry`）、`setRegistry(_ preset:)`（调用 `pnpm config set registry <url>`，preset 与 npm 对齐）、`listGlobalPackages()`（`pnpm ls -g --depth 0 --json`）、`uninstallGlobal(_ name:)`（`pnpm remove -g <pkg>`）、`storeStats()`（基于 `pnpm store path` + `du -sh`）、`storePrune()`（`pnpm store prune`）。
- **FR-7**：新增两个导航项 `NavigationItem.packagesUv` / `NavigationItem.packagesPnpm`，在 [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 的 `allCases`、`displayName`、`systemImage`、`allSections.nav.packagesLangs` 中一并登记。
- **FR-8**：uv / pnpm 视图在 CLI 缺失时展示与 [NpmMissingView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/NpmMissingView.swift) 一致的空态（图标、说明、安装建议）。
- **FR-9**：所有新增用户可见字符串通过 `L("...")` 从 `Localization+En.swift` / `Localization+Zh.swift` 读取；两个文件的 key 集合完全对称（缺一即测试失败）。

## Non-Functional Requirements
- **NFR-1（性能）**：`KotlinProvider.listAvailable()` 单次网络请求返回 ≤ 30 条，端到端解码时间 < 100 ms（p95）。`UvService.listGlobalTools()` / `PnpmService.listGlobalPackages()` 在 100 个全局包场景下 UI 阻塞时间 = 0（全部 `Task.detached(priority: .utility)`）。
- **NFR-2（可回滚）**：任何对 `uv.toml` / `~/.npmrc` / `~/.config/pnpm/rc` 的写入必须先生成时间戳后缀备份（如 `uv.toml.20260730-153000.bak`），入口统一走 [BackupService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/BackupService.swift)。
- **NFR-3（安全）**：所有子进程调用禁止 shell 字符串拼接；参数以 `[String]` 形式交给 `ProcessExecutor`。禁止把用户输入拼进命令 `-c` 参数中。
- **NFR-4（可测试）**：`KotlinProvider` 暴露 `internal static func decode(data:) throws -> [RuntimeVersion]`；`UvService` / `PnpmService` 的输出解析函数抽取为 `internal` 纯函数，测试用固定 fixture 覆盖。
- **NFR-5（代码规模）**：任何单文件 ≤ 500 行；若接近上限则拆分（例如把 preset 常量抽到 `UvRegistryPresets.swift`）。
- **NFR-6（i18n）**：新增 key 数量在 En 与 Zh 侧必须一致；缺失 key 由已有 [SkillsServiceTests.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests) 风格的测试守护（或在 EnvMatrixTests.swift 中新增一个 assert）。

## Constraints
- **Technical**：Swift 5.9 / macOS 13+ / SwiftUI；SPM 单模块；仅 Foundation + AppKit + SwiftUI，不引入第三方依赖。
- **Business**：单次交付一个可运行的 v0.4 里程碑；不阻塞现有 v0.3 已发布功能。
- **Dependencies**：Kotlin 依赖 GitHub Releases API（匿名 60 req/hr 足够）；uv/pnpm 依赖用户机器已装对应 CLI。

## Assumptions
- 用户已通过 `curl -LsSf https://astral.sh/uv/install.sh | sh` 或 `brew install uv` 安装 uv；未安装场景走空态。
- 用户已通过 `brew install pnpm` 或 `npm i -g pnpm` 安装 pnpm；未安装场景走空态。
- Kotlin GitHub Releases 中 `kotlin-compiler-*.zip` 命名稳定（自 1.4+ 已如此）；若某个 release 只发布 `.tar.gz` 会被跳过而非崩溃。
- 用户不期望在 EnvMatrix 内完成 uv/pnpm 的初次安装。

## Acceptance Criteria

### AC-1: Kotlin 进入 RuntimeKind 与侧边栏
- **Given**：一台安装了 Kotlin（如 `brew install kotlin`）的 macOS 13 机器。
- **When**：启动 EnvMatrix。
- **Then**：侧边栏"开发运行时"分组下出现"Kotlin"条目；点击后 Runtime 三分栏显示：Installed 至少一条 System badge 记录、Usage 显示磁盘占用；Dashboard 首屏出现 Kotlin 卡片。
- **Verification**：`human-judgment`

### AC-2: KotlinProvider 解码 GitHub Releases JSON
- **Given**：一个 fixture JSON 模拟 6 条 releases（其中 2 条 prerelease、1 条 draft）。
- **When**：调用 `KotlinProvider.decode(data:)`。
- **Then**：返回恰好 3 条 `RuntimeVersion`，全部含非空 `downloadURL` 且 URL 结尾包含 `kotlin-compiler-`；prerelease 与 draft 被过滤。
- **Verification**：`programmatic`

### AC-3: KotlinProvider 网络异常处理
- **Given**：注入的 URLSession 返回 HTTP 500。
- **When**：调用 `KotlinProvider().listAvailable()`。
- **Then**：抛出 `RuntimeServiceError.network(_:)`，不返回部分结果。
- **Verification**：`programmatic`

### AC-4: uv 镜像切换与备份
- **Given**：本机装有 uv 且 `~/.config/uv/uv.toml` 存在或不存在。
- **When**：在 uv Registry 页选择"清华 TUNA"并点击"应用"。
- **Then**：`uv.toml` 中 `[[index]]` 段落包含 TUNA URL；同目录出现 `uv.toml.<timestamp>.bak`；再次读取 `currentRegistry()` 返回 TUNA。
- **Verification**：`programmatic`（写入 + 备份 + 二次读回）

### AC-5: uv 全局工具卸载二次确认
- **Given**：`uv tool install ruff` 已执行、`ruff` 出现在列表。
- **When**：点击 `ruff` 行的"卸载"按钮。
- **Then**：弹出确认对话框；点击确认后调用 `uv tool uninstall ruff`；列表刷新后 `ruff` 消失；未装 uv 时按钮禁用并 tooltip 说明。
- **Verification**：`human-judgment`

### AC-6: pnpm registry 切换与全局包卸载
- **Given**：本机装有 pnpm，全局装有 `typescript`。
- **When**：将 registry 切换到"淘宝"；然后在 Global Packages 卸载 `typescript`。
- **Then**：`pnpm config get registry` 输出 `https://registry.npmmirror.com/`（或所选镜像 URL）；卸载后 `pnpm ls -g --depth 0 --json` 中不再包含 `typescript`；写入前生成 `.envmatrix.bak` 备份。
- **Verification**：`programmatic`

### AC-7: pnpm store 统计与 prune
- **Given**：本机装有 pnpm，`pnpm store path` 返回一个非空目录。
- **When**：进入 pnpm Cache Tab 并点击"清理"。
- **Then**：UI 展示清理前后 store 大小差值 ≥ 0；`pnpm store prune` 子进程 exitCode == 0；异常时 UI 展示 stderr 前 500 字。
- **Verification**：`programmatic`

### AC-8: 缺失 CLI 空态
- **Given**：未安装 uv（`which uv` 无输出）。
- **When**：点击侧边栏"uv"条目。
- **Then**：中央区域展示空态：图标 + "uv is not installed" + 建议命令 `brew install uv` 或官方安装脚本；无 crash。
- **Verification**：`human-judgment`

### AC-9: i18n 双语对称
- **Given**：本次新增了 uv/pnpm/kotlin 相关 key。
- **When**：运行测试。
- **Then**：`L10n.enPackages ∪ enRuntime ∪ enNavigation` 的 key 集合与对应 zh 版本严格相等；单元测试断言 `enKeys == zhKeys` 通过。
- **Verification**：`programmatic`

### AC-10: 全量测试通过
- **Given**：所有新增代码与测试合并到工作副本。
- **When**：执行 `swift test`。
- **Then**：全部测试通过；测试数量比基线（242）增加 ≥ 8。
- **Verification**：`programmatic`

## Open Questions
- [ ] uv 的镜像配置到底写 `UV_INDEX_URL` 环境变量还是 `uv.toml`？决策：优先 `uv.toml`（持久化），保留将来切换为环境变量的空间。
- [ ] pnpm 是否需要额外识别 `~/.config/pnpm/rc` 与 `~/.npmrc` 的双源配置？决策：本期读写 `~/.npmrc`（pnpm 默认继承），不接管 `~/.config/pnpm/rc`，避免与 npm 模块相互踩踏。
- [ ] Kotlin 的 `binaryName` 用 `kotlinc` 还是 `kotlin`？决策：`kotlinc`，因为 `kotlin` 只是 REPL wrapper，`kotlinc -version` 输出更稳定。
