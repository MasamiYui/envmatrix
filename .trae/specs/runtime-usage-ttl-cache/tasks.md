# Runtime Usage 引入 TTL 缓存 & 持久化折叠状态 - The Implementation Plan

## [x] Task 1: 在 RuntimeViewModel 中引入 usageLoadedAt / usageTTL / force 参数
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 在 [RuntimeViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/RuntimeViewModel.swift) 顶部新增静态常量 `public static let usageTTL: TimeInterval = 5 * 60`。
  - 新增 `@Published public private(set) var usageLoadedAt: Date? = nil`。
  - 新增只读 helper：`public func isUsageFresh(ttl: TimeInterval = RuntimeViewModel.usageTTL) -> Bool`，规则：`usageLoadedAt` 非空且 `Date().timeIntervalSince(loadedAt) < ttl`。
  - 将 `refreshUsage()` 签名改为 `refreshUsage(force: Bool = false) async`：
    - `force == false && isUsageFresh()` 时立即 `return`，不置 `isLoadingUsage`、不启动 `Task.detached`。
    - 否则维持既有扫描逻辑，扫描完成时更新 `usageLoadedAt = Date()`。
  - 在 `install(_:)` / `uninstall(_:)` / `activate(_:)` 完成后追加 `self.usageLoadedAt = nil`（保留 `usageByVersionID` 数据）。
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-3, AC-4, AC-5
- **Test Requirements**:
  - `programmatic` TR-1.1：新增/扩充 [RuntimeViewModelTests.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/RuntimeViewModelTests.swift) 测试 `refreshUsage(force: false)` 在 TTL 内不重复扫描；用 MockRuntimeService + 注入的 fake `installPath` 或断言 `usageLoadedAt` 无变化验证。
  - `programmatic` TR-1.2：测试 `refreshUsage(force: true)` 无视 TTL；调用两次并断言 `usageLoadedAt` 被更新（间隔时间戳变化）。
  - `programmatic` TR-1.3：测试 `activate` / `uninstall` 后 `usageLoadedAt` 被置为 `nil`。
  - `programmatic` TR-1.4：`isUsageFresh(ttl: 0)` 始终返回 `false`；`isUsageFresh(ttl: .infinity)` 在有 `usageLoadedAt` 时返回 `true`。
  - `programmatic` TR-1.5：`swift build` 全项目通过，无警告。
- **Notes**: 保持 `refreshUsage` 现有 `Task.detached(priority: .utility)` 与 `FolderSizeCalculator` 调用不变；只在函数入口加短路判断。

## [x] Task 2: 让 RuntimeDetailView / UsageListView 触发点尊重 TTL
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 修改 [RuntimeDetailView.onChange(of: selectedTab)](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/DevEnv/RuntimeDetailView.swift#L53-L57)：将条件 `viewModel.usageByVersionID.isEmpty && !viewModel.isLoadingUsage` 改为 `!viewModel.isUsageFresh() && !viewModel.isLoadingUsage`；调用 `refreshUsage(force: false)`。
  - 修改 RuntimeDetailView header 的"刷新"按钮：并行调用 `loadAvailable()` / `refreshInstalled()` / `refreshUsage(force: true)`。
  - 修改 [UsageListView 的 "重新计算"](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/DevEnv/UsageListView.swift#L50) 按钮：调用 `refreshUsage(force: true)`。
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-3, AC-4, AC-8
- **Test Requirements**:
  - `programmatic` TR-2.1：`swift build` 通过。
  - `programmatic` TR-2.2：`swift test` 全部通过（含 Task 1 新增用例）。
  - `human-judgement` TR-2.3：手动或截图验证——第一次进入 Usage 有 ProgressView，快速切走再切回不出现 ProgressView 闪烁；点击"刷新"或"重新计算"重新出现 spinner。评审者应确认无卡顿、无空态回闪。
- **Notes**: 若视图当前从 `.task` 内也有 `refreshUsage()` 调用，需一并改为传入 `force: false`（若无则跳过）。

## [x] Task 3: 使用 @AppStorage 持久化 Installed 分组折叠状态
- **Priority**: P1
- **Depends On**: None
- **Description**:
  - 修改 [InstalledListView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/DevEnv/InstalledListView.swift#L4-L12)：
    - 移除 `@State private var managedExpanded / systemExpanded`。
    - 改为在 `init(vm:)` 中根据 `vm.kind.rawValue` 动态构造两个 `@AppStorage`：
      - `envmatrix.runtime.installed.managedExpanded.<kind>`
      - `envmatrix.runtime.installed.systemExpanded.<kind>`
      - 默认值为 `true`。
    - 若 SwiftUI 属性包装器不便在 init 中动态命名，改用 `@AppStorage` 的字符串常量组合：可保留 `@AppStorage` 但通过 computed key 需借助 `UserDefaults.standard` 直接读写并搭配 `@State` 同步——推荐方案：使用 `@AppStorage(_ key: String)` 初始化并把 key 名放在 `init` 中：`_managedExpanded = AppStorage(wrappedValue: true, "envmatrix.runtime.installed.managedExpanded.\(vm.kind.rawValue)")`。
  - 保留既有 groupHeader UI 与动画，不改视觉。
- **Acceptance Criteria Addressed**: AC-6, AC-7
- **Test Requirements**:
  - `programmatic` TR-3.1：`swift build` 通过；`swift test` 通过。
  - `programmatic` TR-3.2：在测试或轻量脚本中，将 `UserDefaults.standard` 的 key `envmatrix.runtime.installed.systemExpanded.node` 设为 `false`，构造 `InstalledListView(vm: RuntimeViewModel(kind: .node, ...))`，Reflection / snapshot 断言 `systemVersions` 分组默认不展开。或在 `RuntimeViewModelTests` 补一个更简的单元：读取该 key 默认值 nil 时按 `true` 处理。
  - `human-judgement` TR-3.3：手动或截图验证——在 Node 折叠 System，重启应用后仍折叠；在 Python 同一分组仍默认展开（key 独立）。评审者确认 Node 与 Python 折叠状态相互独立、跨会话保留。
- **Notes**: 若 `@AppStorage` 的动态 key 在 `init` 中赋值遇到编译问题，可退化为 `UserDefaults.standard.bool(forKey:)` + `@State` 手动同步（读取一次、变更时写回）。测试文档应在实现时明确采用哪种。

## [x] Task 4: 更新 README TODO 项并核对文档
- **Priority**: P2
- **Depends On**: Task 1, Task 2, Task 3
- **Description**:
  - 将 [README.md 第 395 行](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md#L395-L395) 的 `[ ] Runtime Usage 引入 TTL 缓存 & 持久化折叠状态` 更新为 `[x]`。
  - 仅修改该行，不改动其它 TODO 项。
- **Acceptance Criteria Addressed**: —（收尾任务，不直接映射业务 AC）
- **Test Requirements**:
  - `programmatic` TR-4.1：`grep -n "Runtime Usage 引入 TTL" README.md` 显示前缀为 `- [x]`。
  - `human-judgement` TR-4.2：评审者浏览 README 变更 diff，确认无副作用改动。
- **Notes**: 只有当 Task 1~3 均通过测试后再执行本任务。
