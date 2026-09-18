# 性能优化（FSEvents + 进程池） - Product Requirement Document

## Overview
- **Summary**: 为 EnvMatrix 引入两个基础设施型性能优化模块——`FileSystemWatcher`（基于 FSEvents 的文件系统监听器）与 `ProcessPool`（受限并发的进程执行池），用来替换/增强当前完全依赖"用户触发 + TTL 缓存 + 全量目录枚举 + 无节流子进程"的实现方式。V1 只落地基础设施与两个试点接入点（Maven 本地仓库 + Homebrew inventory），V2 及以后再逐步铺开。
- **Purpose**: 目前 [DashboardViewModel.scanPackages()](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/DashboardViewModel.swift#L197-L231) 一次刷新会对 `~/.m2/repository`、`~/go/pkg/mod`、`~/Library/Caches/Homebrew`、`~/.npm/_cacache` 各跑一遍全量 `FileManager.enumerator`；[MavenLocalRepositoryService.scanArtifactDirs](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/MavenLocalRepositoryService.swift#L99) 每次都要重新遍历上万个 artifact 目录；[HomebrewService.inventory](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/HomebrewService.swift#L40) 在多个 ViewModel 中被反复 spawn 三次子进程；且项目中 **完全没有** 任何 FSEvents/DispatchSource 层的文件监听，导致缓存失效只能通过手工按钮或 5 分钟 TTL 兜底。这些开销累积成"打开 Dashboard 卡顿数秒 / 频繁产生数十个并发子进程 / 磁盘持续被枚举"的用户体验问题。
- **Target Users**: EnvMatrix 现有 macOS 桌面用户；尤其是本地仓库/缓存目录规模大（Maven 仓库 >10GB、node_modules 数量众多）或频繁切换视图的开发者。

## Goals
- 引入统一的 [FileSystemWatcher](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/FileSystemWatcher.swift) 组件，基于 macOS FSEvents API，能对指定目录集合注册监听并把事件聚合、去抖后回调给上层。
- 引入统一的 [ProcessPool](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessPool.swift) 组件，为 Shell/Process 执行提供**全局并发上限**（默认 4）与**基于命令行的去重合并**（同一 in-flight 命令共享 future）能力。
- V1 试点：让 Maven 本地仓库缓存（`~/.m2/repository`）与 Homebrew inventory 通过 FileSystemWatcher 主动失效缓存，用 ProcessPool 序列化 `brew info/outdated` 调用。
- 为后续所有目录扫描与子进程调用提供可复用的基础设施，不引入行为回归。
- 提供可关闭的 feature flag（默认开启 FSEvents，进程池全局启用），并在设置里可见状态。

## Non-Goals (Out of Scope)
- **不**替换现有 [Shell.run](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift#L24) 与 [DefaultProcessExecutor](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessExecutor.swift#L40) 的底层执行原语，只在其之上增加"排队 + 去重"薄层。
- **不**在 V1 中把 FSEvents 接入到 pnpm store / uv cache / Go module cache / node_modules 等所有场景，只做 Maven & Homebrew 两个试点。
- **不**引入跨进程 IPC、外部守护进程或 XPC service。
- **不**改动 UI 视觉；仅在必要时新增一个"缓存新鲜度"小指示。
- **不**处理 Sandbox 权限申请对话框问题（默认宿主环境是非沙箱开发环境，用户已授权 Full Disk Access）。
- **不**做 Linux/Windows 跨平台方案。

## Background & Context
- macOS FSEvents (`FSEventStreamCreate`) 是系统级别的目录级监听 API，比 `kqueue`/`DispatchSource.makeFileSystemObjectSource` 更适合"监视一整个大目录"的场景（合并同类事件、支持子孙路径、latency 可配）。
- Swift 中调用 FSEvents 需要 Core Services C API，回调是 C 函数指针，通过 `Unmanaged.passUnretained(self)` 拿到 context。
- 现状：所有目录扫描 100% 是"打开界面 → `.task { await refresh() }`"驱动；相关分析已在调研中列出（见 [SearchAggregator](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/SearchAggregator.swift) 的 5 分钟 TTL 与 [DashboardViewModel.performRefresh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/DashboardViewModel.swift#L123) 的三阶段流水线）。
- 现状：Shell 执行没有全局限流，[ProcessExecutor.run](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessExecutor.swift#L40) 每次都新建 `Process()`；`SearchAggregator` 一次搜索会 `async let` 8 个 corpus，其中多个会 spawn 子进程。
- 项目遵循协议 + 默认实现 + DI 的架构（如 [UvService](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/UvService.swift) / [PnpmService](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/PnpmService.swift)），本次新增两个模块应保持一致。
- 项目 i18n 硬约束（见 project_memory）：任何新增用户可见文本必须走 [Localization+En.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+En.swift) / [Localization+Zh.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift)。
- 项目已有单测框架（XCTest）；新增模块必须可测。

## Functional Requirements

### FileSystemWatcher
- **FR-1**: 提供协议 `FileSystemWatcher`，方法 `watch(paths: [URL], latency: TimeInterval, onChange: @escaping ([FileSystemChange]) -> Void) -> WatchHandle`；`WatchHandle` 支持 `invalidate()`。
- **FR-2**: 提供默认实现 `FSEventsFileSystemWatcher`，基于 macOS `FSEventStreamCreate`；事件在专用 `DispatchQueue` 上派发，回调固定切换到 MainActor 前先在 `.utility` 队列合并批次。
- **FR-3**: 事件去抖：同一 `WatchHandle` 内的连续事件在 `debounceInterval`（默认 250ms）内合并成一次回调。
- **FR-4**: 支持批量注册多个路径，路径不存在时不 crash，只记录 warning。
- **FR-5**: 应用退出/`invalidate()` 时必须 `FSEventStreamStop + FSEventStreamInvalidate + FSEventStreamRelease`，不泄漏。
- **FR-6**: 提供 `NoopFileSystemWatcher` 用于测试与降级（返回空 handle）。

### ProcessPool
- **FR-7**: 提供协议 `ProcessPool`，方法 `run(executable: String, args: [String], env: [String: String]?, dedupeKey: String?) async throws -> ProcessResult`；返回结构同 [Shell.Result](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift)。
- **FR-8**: 提供默认实现 `DefaultProcessPool`，内部维护 `maxConcurrent`（默认 4，可配）个 permits，使用 async semaphore（`AsyncSemaphore` 或基于 `AsyncStream` 的信号量）限流。
- **FR-9**: 去重：若 `dedupeKey` 不为 nil 且当前存在同 key 的 in-flight 任务，则**新调用者复用**同一 `Task`，共享结果；一个任务完成后 dedupe 表项立即清理。
- **FR-10**: 底层调用现有 [Shell.run](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift#L24)（避免重复实现管道读逻辑）；只在其上加"排队/去重"。
- **FR-11**: 支持 `cancelAll()` 方法（应用退出/切换用户时清理）。

### 试点接入
- **FR-12**: 为 [MavenLocalRepositoryService](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/MavenLocalRepositoryService.swift) 增加缓存层：内存缓存扫描结果 + FileSystemWatcher 监听 `~/.m2/repository`，收到事件后失效缓存并 `NotificationCenter` 广播 `envMatrixSearchCorpusInvalidated(object: .maven)`。
- **FR-13**: 为 [HomebrewService.inventory](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/HomebrewService.swift#L40) 的三次子进程（`brew info` / `brew outdated` / `brew --version`）改走 ProcessPool，`dedupeKey` 分别为完整命令行；同一时刻多个 ViewModel 请求 inventory 时只跑一次。
- **FR-14**: FSEvents / ProcessPool 都在应用启动时初始化并注入到需要它们的服务；提供全局单例 `AppServices.shared.fileSystemWatcher` / `AppServices.shared.processPool`（或已有 DI 容器等价物）。

### 可观察性
- **FR-15**: 在 Settings 视图（或诊断报告）新增一段"性能"区块，展示 ProcessPool 当前 in-flight/queued 数、FSEvents 已注册的路径数。
- **FR-16**: 所有新逻辑打印 `NSLog`/`os_log` 日志（tag: `envmatrix.perf`），便于排查。

## Non-Functional Requirements
- **NFR-1（性能）**: 在 `~/.m2/repository` 有 5000+ artifact 目录的机器上，第二次打开 Maven 页面（缓存命中）耗时 <200ms（相较冷启动 >2s）。
- **NFR-2（并发上限）**: 全局同时执行的 Shell 子进程数不超过 `maxConcurrent`（默认 4），并可通过设置调整（4/8/16 或"不限"）。
- **NFR-3（内存）**: FileSystemWatcher 单实例常驻内存开销 <2MB；ProcessPool 队列不无限膨胀（超过 200 时拒绝新入队并 throw）。
- **NFR-4（稳定性）**: 应用退出、系统睡眠恢复不出现文件描述符或 FSEvents 流泄漏；`leaks` 工具无本模块相关泄漏。
- **NFR-5（可测试性）**: 两个新模块都必须提供协议 + Mock；单测覆盖率关键路径（合并/去抖/去重/限流）≥80%。
- **NFR-6（可关闭）**: 通过 `UserDefaults` key `perf.fsevents.enabled` (默认 true) 与 `perf.processPool.maxConcurrent`（默认 4，0 表示不限）可关闭/降级；关闭 FSEvents 后回退到原有"TTL + 手动刷新"逻辑。
- **NFR-7（无 UI 回归）**: 现有页面视觉与交互行为完全不变；除设置页新增性能状态块外，无任何用户可见改动。
- **NFR-8（i18n）**: 所有新增用户可见文本走资源表；覆盖 en/zh。

## Constraints
- **Technical**:
  - 语言：Swift 5.9+；目标平台 macOS 13+（现项目 Package.swift 已声明）
  - 需要引入 `CoreServices` 框架（FSEvents 所在）
  - 不能引入新的第三方依赖（保持零依赖策略）
  - 必须与现有 [ShellPathResolver](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ShellPathResolver.swift) / [Shell](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift) 协同，不重复读环境变量
- **Business**:
  - 用户偏好增量交付（V1 → V2）：本次只交付基础设施 + 2 处试点
  - 不允许改动 Sandbox entitlements（现无沙箱）
- **Dependencies**:
  - Apple `CoreServices.FSEvents`
  - 现有 `MavenLocalRepositoryService`、`HomebrewService`

## Assumptions
- 用户已授予 Full Disk Access（`~/.m2` 可读监听）。若未授予，FSEvents 会静默无事件——不影响正确性，只降级到 TTL 行为。
- 5 分钟 TTL 兜底逻辑保留：即便 FSEvents 无事件，也不会导致缓存无限老旧。
- 项目现在 [Package.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Package.swift) 已经允许链接 `CoreServices`（无需 entitlement 更改）。
- FSEvents 的路径 recursion 语义足够满足需求（不需要额外的手动子树注册）。

## Acceptance Criteria

### AC-1: FileSystemWatcher 单元行为
- **Given**: 使用 `FSEventsFileSystemWatcher` 监听一个临时目录，`debounceInterval = 200ms`
- **When**: 在 100ms 内往目录中新增 5 个文件
- **Then**: `onChange` 回调恰好被触发 1 次，携带非空的 `[FileSystemChange]`
- **Verification**: `programmatic`
- **Notes**: 使用 XCTestExpectation + 临时目录，允许 ±100ms 误差

### AC-2: FileSystemWatcher 资源释放
- **Given**: 创建并 `invalidate()` 一个 `WatchHandle`
- **When**: 再次向目录写入文件
- **Then**: `onChange` 不再触发；`leaks` 检查无 FSEvent 流残留
- **Verification**: `programmatic`

### AC-3: ProcessPool 限流
- **Given**: `DefaultProcessPool(maxConcurrent: 2)`
- **When**: 并发发起 10 个 `run(executable: "/bin/sleep", args: ["0.2"])`
- **Then**: 任意时刻同时执行的 Shell 数 ≤2；10 个任务全部返回 exitCode = 0；总耗时约 1.0s（10/2 × 0.2s，允许 ±20%）
- **Verification**: `programmatic`

### AC-4: ProcessPool 去重
- **Given**: `DefaultProcessPool(maxConcurrent: 4)`
- **When**: 同一 `dedupeKey = "brew:info"` 的两个 `run()` 几乎同时发起
- **Then**: 底层 `Shell.run` 只被调用 1 次（通过注入 Mock 计数）；两个调用者拿到相同的 `ProcessResult`
- **Verification**: `programmatic`

### AC-5: Maven 缓存自动失效
- **Given**: Maven 页面首次加载完成，`Recent artifacts` 列表已缓存
- **When**: 通过命令行 `touch ~/.m2/repository/com/foo/bar/1.0.0/bar-1.0.0.pom`（新增一个 artifact）
- **Then**: 在 <2s 内 Maven 视图上的最近 artifact 列表刷新出现新条目（无需按刷新按钮）
- **Verification**: `human-judgment`
- **Notes**: 需要一台真实 macOS 环境；由用户在 checklist 阶段验证

### AC-6: Homebrew inventory 去重
- **Given**: Dashboard 与 Brew 页面同时打开
- **When**: 两个 ViewModel 几乎同时调用 `inventory(forceRefresh: false)`
- **Then**: `brew info` / `brew outdated` 各自只被真正 spawn 一次（可通过日志计数）
- **Verification**: `programmatic`

### AC-7: 无 UI 回归
- **Given**: 全新构建
- **When**: 点击所有既有 sidebar 项（Dashboard/各语言 packages/Runtimes/AI/System）
- **Then**: 无 crash，视觉与之前一致，命令执行成功率无下降
- **Verification**: `human-judgment`

### AC-8: 可关闭
- **Given**: 用户在 Settings 关闭 FSEvents 或将 `maxConcurrent` 设为 0
- **When**: 重新触发一次 Maven / Brew 操作
- **Then**: 系统行为回退到当前实现（TTL + 无限并发），无异常
- **Verification**: `programmatic`

### AC-9: i18n 对称
- **Given**: 新增所有性能相关用户可见文本
- **When**: 运行 [LocalizationSymmetryTests](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/LocalizationSymmetryTests.swift)
- **Then**: en/zh 键完全对称，无缺失
- **Verification**: `programmatic`

### AC-10: 单测覆盖
- **Given**: 新增 `FileSystemWatcherTests` 与 `ProcessPoolTests`
- **When**: 运行 `swift test`
- **Then**: 关键路径断言全部通过（合并、去抖、去重、限流、release）
- **Verification**: `programmatic`

## Open Questions
- [ ] `maxConcurrent` 是否需要根据 CPU 核心数动态调整？V1 采用固定默认 4，是否可接受？
- [ ] Maven 缓存内存驻留过大时（10 万级 artifact）是否需要磁盘持久化？V1 暂不做，只做内存缓存。
- [ ] 是否将 `SearchAggregator` 的 5 分钟 TTL 一同拉长至 30 分钟（因为 FSEvents 会主动失效）？V1 保持不变，V2 再评估。
