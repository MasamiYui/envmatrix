# Runtime Usage 引入 TTL 缓存 & 持久化折叠状态 - Product Requirement Document

## Overview
- **Summary**：为 Runtime Detail 的 Usage 分栏引入 TTL（Time-To-Live）缓存，避免每次进入分栏都触发昂贵的磁盘目录枚举；同时将 Installed 分栏中 Managed / System 的分组折叠状态持久化到用户偏好中，跨会话保留。
- **Purpose**：`FolderSizeCalculator.compute(at:)` 会对每个已安装运行时的安装目录进行深度枚举，在 SDKMAN / conda / node_modules 类目录下可达数万文件。目前每次首次访问 Usage 分栏（`usageByVersionID.isEmpty` 判定）都会重扫，用户反馈"切一次卡一次、每次结果都在算但其实变化很少"。同时 Installed 视图的折叠状态存储在 `@State`，navigation pop / 侧栏切换 / App 重启后即被重置，与用户"这次收起就一直收起"的心智不符。
- **Target Users**：使用 EnvMatrix 多次进出 Runtime Detail 页面的开发者，特别是 Java / Node / Python 等多版本大目录场景用户。

## Goals
- 为 Runtime Usage 数据引入 5 分钟 TTL 缓存，命中缓存时立即渲染，不触发磁盘扫描。
- Usage 数据在下列时机主动失效：安装 / 卸载 / 激活操作完成后、用户按下 "重新计算" 按钮时、用户在 RuntimeDetailView 顶栏点击 "刷新" 时。
- Installed 分栏中 Managed / System 两个分组的折叠状态通过 `@AppStorage` 持久化，按 `RuntimeKind` 独立记忆，跨 App 重启保留。
- 保持既有 UI 布局与交互路径不变，不引入新的按钮或菜单项。

## Non-Goals (Out of Scope)
- 不对 Installed / Available 两个分栏的数据引入 TTL 缓存（RuntimeService 层与 SystemRuntimeDetector 已有各自缓存）。
- 不持久化 Managed 分组内单条版本行的展开 / 折叠状态。
- 不改动 [DashboardViewModel.packagesTTL](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/DashboardViewModel.swift#L43) 或全局搜索 TTL；沿用同一时长以保持全局一致，但不共享代码路径。
- 不改动 `FolderSizeCalculator` 的实现或统计口径。
- 不引入新的持久化后端（不使用 Core Data / SQLite），仅使用 `UserDefaults`。

## Background & Context
- Runtime Usage 分栏由 [UsageListView](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/DevEnv/UsageListView.swift) 呈现，由 [RuntimeViewModel.refreshUsage](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/ViewModels/RuntimeViewModel.swift#L30-L48) 计算磁盘占用。
- 首次进入 Usage 分栏由 [RuntimeDetailView.onChange(of: selectedTab)](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/DevEnv/RuntimeDetailView.swift#L53-L57) 触发，其条件仅检查 `usageByVersionID.isEmpty`，缺少"新鲜度"判断。
- Dashboard 已用 `packagesTTL: TimeInterval = 5 * 60` 建立了 5 分钟 TTL 的项目惯例，本次沿用同一常量数值。
- 折叠状态位于 [InstalledListView.managedExpanded / systemExpanded](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/DevEnv/InstalledListView.swift#L7-L8)，目前使用 `@State`。
- 项目 i18n 约定：文案需放入 [Localization+Runtime.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+Runtime.swift)（本次实际不新增文案，但如需状态提示则遵循此约定）。

## Functional Requirements
- **FR-1**：`RuntimeViewModel` 记录最近一次 `refreshUsage()` 成功完成的时间戳（`usageLoadedAt: Date?`），并暴露 `isUsageFresh(ttl:)` 判定方法。
- **FR-2**：`RuntimeViewModel.refreshUsage(force: Bool = false)` 增加 `force` 参数；当 `force == false` 且缓存新鲜时立即返回，不启动 `Task.detached` 扫盘。
- **FR-3**：安装 / 卸载 / 激活操作完成后（`install` / `uninstall` / `activate`），主动清空 `usageLoadedAt`（并保留 `usageByVersionID` 直到下次 refresh，以便 UI 有过渡而非闪回空态；下次进入 Usage 时会重扫）。
- **FR-4**：`RuntimeDetailView` 顶栏 "刷新" 按钮触发 `refreshUsage(force: true)`，同时刷新 Installed / Available。
- **FR-5**：`UsageListView` 中的 "重新计算" 按钮触发 `refreshUsage(force: true)`。
- **FR-6**：`RuntimeDetailView.onChange(of: selectedTab)` 切换到 Usage 分栏时的触发条件改为：`!isUsageFresh(ttl: RuntimeViewModel.usageTTL)` 且 `!isLoadingUsage`。
- **FR-7**：`InstalledListView` 中的 `managedExpanded` / `systemExpanded` 使用 `@AppStorage`，Key 形如 `envmatrix.runtime.installed.managedExpanded.<kind>` 与 `envmatrix.runtime.installed.systemExpanded.<kind>`，默认值为 `true`。
- **FR-8**：折叠状态的 Key 必须包含 `RuntimeKind.rawValue`，即每个运行时（node / python / java …）独立记忆。

## Non-Functional Requirements
- **NFR-1**（性能）：Usage 分栏在命中 TTL 缓存时的从 tap 到渲染耗时 ≤ 16ms（不启动 `Task.detached`）。
- **NFR-2**（一致性）：TTL 常量集中在 `RuntimeViewModel` 静态属性 `usageTTL: TimeInterval = 5 * 60`，与 Dashboard 保持相同时长值但不共享。
- **NFR-3**（可测试性）：`isUsageFresh(ttl:)` 与 `usageLoadedAt` 状态转换必须可通过 `RuntimeViewModelTests` 用注入的 mock service 验证，不依赖真实文件系统。
- **NFR-4**（安全性）：`@AppStorage` Key 命名不能与其它模块冲突；使用 `envmatrix.runtime.installed.*` 前缀。
- **NFR-5**（可维护性）：所有新增代码必须无编译警告；不新增 SwiftLint 类问题。

## Constraints
- **Technical**：SwiftUI + macOS 13+；沿用 `@ObservableObject` / `@Published`，不引入 Observation macro；`@AppStorage` 直接绑定 `UserDefaults.standard`。
- **Business**：保持"最小代码变更"原则，避免大面积重构 `RuntimeViewModel`。
- **Dependencies**：无新依赖；沿用 `FolderSizeCalculator`、`RuntimeService`。

## Assumptions
- 5 分钟 TTL 对 Usage 场景够用（与 Dashboard packagesTTL 一致，用户已建立预期）。
- 折叠状态用户级持久化即可，不需要按机器 / workspace 隔离。
- 用户不会通过 EnvMatrix 之外的方式（如 rm -rf）删除运行时目录后立即回到 Usage 分栏并期望零成本感知（这种情况下"刷新"按钮或 5 分钟后自然过期是可接受的兜底）。

## Acceptance Criteria

### AC-1：Usage 分栏首次访问会扫描并渲染
- **Given**：Runtime Detail 页刚打开，`usageByVersionID` 为空
- **When**：用户切换到 Usage 分栏
- **Then**：`refreshUsage(force: false)` 被调用，`isLoadingUsage` 短暂为 `true`，扫描完成后 `usageByVersionID` 有数据且 `usageLoadedAt` 被写入
- **Verification**：`programmatic`

### AC-2：Usage 分栏在 TTL 内切回不重扫
- **Given**：已完成一次 Usage 扫描，`usageLoadedAt` 距今 < 5 分钟
- **When**：用户切到 Installed 或 Available 再切回 Usage
- **Then**：`refreshUsage` **不**发起新的扫描任务；`isLoadingUsage` 始终为 `false`；界面立即渲染之前的 `usageByVersionID`
- **Verification**：`programmatic`

### AC-3：Usage TTL 过期后自动重扫
- **Given**：`usageLoadedAt` 距今 > 5 分钟
- **When**：用户切换到 Usage 分栏
- **Then**：`refreshUsage(force: false)` 被调用并因缓存不新鲜执行完整扫描
- **Verification**：`programmatic`

### AC-4：强制刷新按钮无视 TTL
- **Given**：`usageLoadedAt` 距今 1 秒（缓存新鲜）
- **When**：用户点击 UsageListView 的"重新计算"或 RuntimeDetailView 的"刷新"按钮
- **Then**：`refreshUsage(force: true)` 被调用并执行扫描，扫描结束后 `usageLoadedAt` 被更新
- **Verification**：`programmatic`

### AC-5：写操作会作废 Usage 缓存
- **Given**：`usageLoadedAt` 已被写入，缓存新鲜
- **When**：调用 `activate(_:)` / `uninstall(_:)` / `install(_:)` 中任意一个
- **Then**：`usageLoadedAt` 被清空；下次切换到 Usage 分栏时会重扫
- **Verification**：`programmatic`

### AC-6：Installed 折叠状态跨 App 生命周期保留
- **Given**：用户在 Node 的 Installed 分栏折叠了 "System" 分组
- **When**：关闭并重新打开该视图（或重启 App）
- **Then**：System 分组仍处于折叠状态，Managed 分组仍处于展开状态
- **Verification**：`programmatic`（可通过重置 `UserDefaults` key 验证）

### AC-7：不同 RuntimeKind 折叠状态互不影响
- **Given**：用户在 Node 折叠了 System 分组
- **When**：用户切换到 Python 的 Installed 分栏
- **Then**：Python 的 Managed / System 分组均按各自 `@AppStorage` key 独立记忆；Node 的折叠不影响 Python 默认展开
- **Verification**：`programmatic`

### AC-8：TTL 缓存命中时不出现 loading 抖动
- **Given**：AC-2 场景
- **When**：切回 Usage 分栏
- **Then**：不出现 ProgressView 抖动；Usage summary 直接显示 total bytes 数字，行内 usage 也直接是最终字节数
- **Verification**：`human-judgment`（人眼观察无骨架 / spinner 闪烁）

## Open Questions
- [ ] `install()` 完成后是否也应该主动作废 Usage？→ 已在 FR-3 决定"是"，保持一致性。
- [ ] 是否将 TTL 常量抽取到 `Configuration` 中共用？→ 暂不做；等第三处出现同类需求再重构。
