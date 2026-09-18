# 性能优化（FSEvents + 进程池） - The Implementation Plan (Decomposed and Prioritized Task List)

## [x] Task 1: 定义协议与数据类型（`FileSystemWatcher` / `ProcessPool`）
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 新建 [FileSystemWatcher.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/FileSystemWatcher.swift)：定义 `public protocol FileSystemWatcher`、`public struct FileSystemChange { let path: String; let flags: UInt32 }`、`public final class WatchHandle`（含 `invalidate()`）、`public final class NoopFileSystemWatcher`。
  - 新建 [ProcessPool.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessPool.swift)：定义 `public protocol ProcessPool`、`public struct ProcessResult { let exitCode: Int32; let stdout: String; let stderr: String }`、错误枚举 `ProcessPoolError`（含 `queueFull`）。
  - 定义 `AsyncSemaphore` 内部类型（基于 `AsyncStream<Void>` continuation 或 `CheckedContinuation` 数组），用于 permits 限流。
- **Acceptance Criteria Addressed**: AC-1, AC-3, AC-4
- **Test Requirements**:
  - `programmatic` TR-1.1: 编译通过；`Noop` 实现调用 `watch()` 立即返回 handle，`invalidate()` 无副作用
  - `programmatic` TR-1.2: `AsyncSemaphore(permits: 2)` 在 3 个并发 `wait/signal` 场景下第三个必须等待
- **Notes**: 全部类型 `public`，方便测试与后续扩展；不实现 FSEvents/Shell 调用，只是骨架

## [x] Task 2: `FSEventsFileSystemWatcher` 实现（FSEvents 桥接）
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 使用 `FSEventStreamCreate` 创建流；context 通过 `Unmanaged.passUnretained(self)` 传递
  - 回调 C 函数将事件路径数组写入 actor-safe 队列
  - 用 `Task { for await batch in stream ... }` 实现 `debounceInterval` 合并逻辑
  - `invalidate()` 必须 `FSEventStreamStop + FSEventStreamInvalidate + FSEventStreamRelease` 并置空引用
  - `latency` 参数默认 0.5s，`debounceInterval` 默认 0.25s
- **Acceptance Criteria Addressed**: AC-1, AC-2
- **Test Requirements**:
  - `programmatic` TR-2.1: 在临时目录连续写 5 个文件，`onChange` 只回调 1 次（±100ms 容差）
  - `programmatic` TR-2.2: `invalidate()` 后再写入，`onChange` 不再触发
  - `programmatic` TR-2.3: 路径不存在时 `watch()` 不抛异常，只记录 warning
- **Notes**: 需要引入 `import CoreServices`；C 回调里禁止 Swift 引用循环

## [x] Task 3: `DefaultProcessPool` 实现（限流 + 去重）
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 使用 `AsyncSemaphore` 保证 `maxConcurrent` permits
  - 维护 `[String: Task<ProcessResult, Error>]` 作为 in-flight 去重表；`dedupeKey == nil` 时不参与去重
  - 底层调用 [Shell.run](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift#L24) 执行真实命令
  - 队列上限 200，超过抛 `ProcessPoolError.queueFull`
  - 提供 `cancelAll()` 遍历所有 in-flight task 调用 `cancel()`
- **Acceptance Criteria Addressed**: AC-3, AC-4
- **Test Requirements**:
  - `programmatic` TR-3.1: `maxConcurrent=2` 下 10 个 `sleep 0.2` 任务总耗时 [0.8, 1.4]s
  - `programmatic` TR-3.2: 相同 `dedupeKey` 的两个并发调用，注入 Mock `ShellRunner` 只被调用 1 次
  - `programmatic` TR-3.3: 不同 `dedupeKey` 或 `nil` 时各自独立执行
- **Notes**: 通过 `ShellRunner` 协议注入 mock；避免真实 `/bin/sleep` 进入单测（可用 mock executor）

## [x] Task 4: 应用启动接入（DI 注入）
- **Priority**: P0
- **Depends On**: Task 2, Task 3
- **Description**:
  - 在应用启动位置（`EnvMatrixApp`/`AppServices` 或等价 DI 容器）创建单例 `FileSystemWatcher` 与 `ProcessPool`
  - 通过 `UserDefaults` 读取 `perf.fsevents.enabled`（默认 true）与 `perf.processPool.maxConcurrent`（默认 4）
  - 若 FSEvents 关闭，使用 `NoopFileSystemWatcher`
  - `applicationWillTerminate` 里调用 `cancelAll()` 与所有 handle 的 `invalidate()`
- **Acceptance Criteria Addressed**: AC-8
- **Test Requirements**:
  - `programmatic` TR-4.1: 单测通过 UserDefaults override 读取 `maxConcurrent = 0` 时，`DefaultProcessPool` 行为等同不限流（直接透传）
  - `human-judgement` TR-4.2: 手动关闭 FSEvents 后，Maven 缓存回退到 TTL 逻辑，UI 无异常

## [x] Task 5: Maven 试点接入（FSEvents 失效缓存）
- **Priority**: P1
- **Depends On**: Task 4
- **Description**:
  - 在 [MavenLocalRepositoryService](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/MavenLocalRepositoryService.swift) 内增加 `cachedArtifacts` + `cachedAt` 字段（actor 或 `os_unfair_lock` 保护）
  - 首次调用 `list()` 全量扫；后续调用命中缓存直接返回
  - 应用启动时对 `~/.m2/repository` 注册 FSEvents 监听；收到事件后清缓存并 post `envMatrixSearchCorpusInvalidated(object: .maven)`
  - 保留 5 分钟 TTL 兜底
- **Acceptance Criteria Addressed**: AC-5
- **Test Requirements**:
  - `programmatic` TR-5.1: 第二次调用 `list()` 时不再调用 `scanArtifactDirs`（通过间接计数）
  - `human-judgement` TR-5.2: 真机环境下 `touch` 新增 pom，Maven 视图在 2s 内自动出现新条目

## [x] Task 6: Homebrew 试点接入（ProcessPool 去重）
- **Priority**: P1
- **Depends On**: Task 4
- **Description**:
  - 修改 [HomebrewService.inventory](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/HomebrewService.swift#L40) 内的三次 shell 调用，改为通过 `ProcessPool.run` 并传 `dedupeKey`（如 `"brew:info:v2"` / `"brew:outdated:v2"` / `"brew:version"`）
  - 不改变返回值语义
  - 保留 `forceRefresh` 参数：`forceRefresh=true` 时 `dedupeKey=nil` 绕过合并
- **Acceptance Criteria Addressed**: AC-6
- **Test Requirements**:
  - `programmatic` TR-6.1: Mock ProcessPool 情况下，两个并发 `inventory(forceRefresh: false)` 只触发 3 次底层调用（info+outdated+version），不是 6 次
  - `programmatic` TR-6.2: `forceRefresh=true` 时每次都真正调用（不去重）

## [x] Task 7: Settings 观察面板（性能状态块）
- **Priority**: P2
- **Depends On**: Task 4
- **Description**:
  - 在 Settings/诊断视图中新增一个"性能"区块（不新增顶层导航），展示：
    - FSEvents 已注册路径数
    - ProcessPool 当前 in-flight / queued 数量
    - `maxConcurrent` 值与开关状态
  - 数据每 2s 拉一次（`Task.sleep + while`）；离开视图停止
  - 全部文案走 i18n
- **Acceptance Criteria Addressed**: AC-8, AC-9, NFR-8
- **Test Requirements**:
  - `programmatic` TR-7.1: [LocalizationSymmetryTests](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/LocalizationSymmetryTests.swift) 对新增键通过
  - `human-judgement` TR-7.2: 视觉与既有 Settings 风格一致

## [x] Task 8: 单元测试与集成测试
- **Priority**: P0
- **Depends On**: Task 2, Task 3, Task 5, Task 6
- **Description**:
  - 新增 `Tests/EnvMatrixTests/FileSystemWatcherTests.swift`（覆盖 AC-1/AC-2）
  - 新增 `Tests/EnvMatrixTests/ProcessPoolTests.swift`（覆盖 AC-3/AC-4）
  - 新增 `Tests/EnvMatrixTests/MavenCacheIntegrationTests.swift`（用 mock watcher）
  - 新增 `Tests/EnvMatrixTests/HomebrewDedupeTests.swift`（用 mock pool）
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-3, AC-4, AC-6, AC-10
- **Test Requirements**:
  - `programmatic` TR-8.1: `swift test` 全部通过
  - `programmatic` TR-8.2: 新增测试文件里断言总数 ≥ 15
- **Notes**: FSEvents 相关测试可能对宿主环境敏感，需要 XCTSkip 兜底

## [x] Task 9: 端到端手动验证 & 回归测试
- **Priority**: P1
- **Depends On**: Task 5, Task 6, Task 7
- **Description**:
  - 走一遍主要路径：Dashboard → 所有 packages 页 → Runtimes → AI → System
  - 观察日志确认 ProcessPool 生效、FSEvents 事件到达
  - 无回归、无泄漏（Instruments Leaks 快速跑一次）
- **Acceptance Criteria Addressed**: AC-5, AC-7
- **Test Requirements**:
  - `human-judgement` TR-9.1: 无 crash，视觉一致
  - `human-judgement` TR-9.2: `~/.m2` 变更后 2s 内 UI 自动刷新
