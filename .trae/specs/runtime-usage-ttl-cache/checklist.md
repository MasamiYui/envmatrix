# Runtime Usage 引入 TTL 缓存 & 持久化折叠状态 - Verification Checklist

- [x] Checkpoint 1：`RuntimeViewModel` 暴露 `usageTTL` 常量（值为 300 秒）、`usageLoadedAt` 已发布属性、`isUsageFresh(ttl:)` 方法，且 `refreshUsage(force:)` 具有 `force` 默认参数。
- [x] Checkpoint 2：`refreshUsage(force: false)` 在 `isUsageFresh()` 为 `true` 时立即 return，不启动 `Task.detached`、不切换 `isLoadingUsage`（单元测试断言时间戳与 loading 标记均未变化）。
- [x] Checkpoint 3：`refreshUsage(force: true)` 始终执行扫描并更新 `usageLoadedAt`（两次连续调用间时间戳递增或不为 nil）。
- [x] Checkpoint 4：`install / uninstall / activate` 完成后 `usageLoadedAt` 被置为 `nil`，`usageByVersionID` 保留旧值直到下次 refresh。
- [x] Checkpoint 5：`RuntimeDetailView.onChange(of: selectedTab)` 切到 Usage 分栏时以 `!vm.isUsageFresh()` 为触发条件，且顶栏"刷新"按钮走 `force: true` 路径。
- [x] Checkpoint 6：`UsageListView` 的"重新计算"按钮触发 `refreshUsage(force: true)`。
- [x] Checkpoint 7：`InstalledListView` 内 `managedExpanded` / `systemExpanded` 通过 `@AppStorage`（或等价 `UserDefaults` 读写）持久化，Key 形如 `envmatrix.runtime.installed.managedExpanded.<kind>` / `envmatrix.runtime.installed.systemExpanded.<kind>`，默认值 `true`。
- [x] Checkpoint 8：折叠状态 Key 中包含 `RuntimeKind.rawValue`；不同 kind（如 `node` vs `python`）读写互不干扰。
- [x] Checkpoint 9：`swift build` 无 warning、无 error；`swift test` 全部通过（包含 Task 1 新增用例）。
- [x] Checkpoint 10：手动 E2E——首次进入 Usage 有 spinner，5 分钟内切走再切回无 spinner、无空态闪烁；点击"重新计算"或顶栏"刷新"会重新扫描；`activate` / `uninstall` 后再次进入 Usage 会重扫。
- [x] Checkpoint 11：手动 E2E——在 Node 折叠 System 分组，重启 App 后仍折叠；同时打开 Python 详情页，Managed / System 均默认展开。
- [x] Checkpoint 12：README.md 第 395 行的 TODO 项被更新为 `[x]`，且未影响相邻 TODO 项。
