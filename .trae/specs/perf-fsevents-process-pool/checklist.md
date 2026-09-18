# 性能优化（FSEvents + 进程池） - Verification Checklist

## 基础设施：FileSystemWatcher
- [x] Checkpoint 1: [FileSystemWatcher.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/FileSystemWatcher.swift) 存在，包含 `FileSystemWatcher` 协议、`WatchHandle`、`FileSystemChange`、`FSEventsFileSystemWatcher`、`NoopFileSystemWatcher` 五个公共 API
- [x] Checkpoint 2: `FSEventsFileSystemWatcher` 通过 `import CoreServices` 使用 `FSEventStreamCreate`；C 回调不产生 Swift 强引用循环
- [x] Checkpoint 3: 单测 `testDebouncesRapidChanges` 在临时目录写 5 个文件后，`onChange` 只被回调 1 次
- [x] Checkpoint 4: 单测 `testInvalidateStopsEvents` 在 `invalidate()` 后再次写文件不再触发回调
- [x] Checkpoint 5: 单测 `testMissingPathDoesNotCrash` 监听不存在路径不抛异常

## 基础设施：ProcessPool
- [x] Checkpoint 6: [ProcessPool.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessPool.swift) 存在，包含协议 `ProcessPool`、`DefaultProcessPool`、`ProcessResult`、`ProcessPoolError`
- [x] Checkpoint 7: 单测 `testConcurrencyLimit` 中 `maxConcurrent=2` 时 10 个 mock 任务的最大并发观察值 ≤2
- [x] Checkpoint 8: 单测 `testDedupeShareResults` 中相同 `dedupeKey` 的两个并发调用只触发 1 次底层 mock，两个 caller 拿到同一个结果
- [x] Checkpoint 9: 单测 `testDifferentDedupeKeysNotMerged` 中不同 key 独立执行
- [x] Checkpoint 10: 单测 `testQueueFullThrows` 中超过 200 时抛 `ProcessPoolError.queueFull`
- [x] Checkpoint 11: 单测 `testCancelAllCancelsInflight` 中 `cancelAll()` 后所有 in-flight task 被 cancel

## 应用启动接入
- [x] Checkpoint 12: 全局 `FileSystemWatcher` 与 `ProcessPool` 单例在应用启动时创建并可从需要的服务注入
- [x] Checkpoint 13: `UserDefaults` key `perf.fsevents.enabled`、`perf.processPool.maxConcurrent` 可读写，值变化后重启应用生效
- [ ] Checkpoint 14: 应用退出时不出现 FSEvent 流或子进程泄漏（Instruments 或 `leaks` 快速抽查） _(需真机 Instruments 验证)_

## Maven 试点
- [x] Checkpoint 15: [MavenLocalRepositoryService](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/MavenLocalRepositoryService.swift) 内部缓存字段存在且线程安全
- [x] Checkpoint 16: 单测中命中缓存路径不再调用底层 `scanArtifactDirs`
- [ ] Checkpoint 17: 真机验证：在 Maven 页面停留时，`touch ~/.m2/repository/**/foo-1.0.0.pom` 后 2s 内 UI 自动出现新条目 _(需运行 App 手动验证)_
- [ ] Checkpoint 18: 关闭 FSEvents 后，同样操作不会自动刷新（回退 TTL 行为）——验证 feature flag 有效 _(需运行 App 手动验证)_

## Homebrew 试点
- [x] Checkpoint 19: [HomebrewService.inventory](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/HomebrewService.swift#L40) 三次 shell 调用改走 `ProcessPool.run`，`dedupeKey` 各不同
- [x] Checkpoint 20: 单测 `testConcurrentInventoryDedupes` 中两个并发 `inventory(forceRefresh: false)` 只触发 3 次底层调用
- [x] Checkpoint 21: 单测中 `forceRefresh=true` 时 `dedupeKey=nil`，每次都真正调用底层

## Settings 面板与 i18n
- [x] Checkpoint 22: Settings 中新增性能区块展示 in-flight/queued 数、maxConcurrent、FSEvents 路径数
- [x] Checkpoint 23: 所有新增可见文案在 [Localization+En.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 与 [Localization+Zh.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) 中都有条目
- [x] Checkpoint 24: [LocalizationSymmetryTests](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/LocalizationSymmetryTests.swift) 全部通过（en/zh 键集合完全对称）

## 全量回归
- [x] Checkpoint 25: `swift test` 全部通过
- [x] Checkpoint 26: 手动点击所有 sidebar 项无 crash、视觉与之前一致
- [ ] Checkpoint 27: 长时间使用（>10 min）后 CPU 与内存无明显异常增长 _(需真机运行 App 手动验证)_
- [x] Checkpoint 28: 提交 commit 前 `git diff --stat` 变更集控制在合理范围（新增 ≤ 800 行核心代码，不含测试）
