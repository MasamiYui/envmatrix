# 容器镜像与实例管理 - The Implementation Plan (Decomposed and Prioritized Task List)

按优先级从上到下执行；同一文件的多处修改合并为一个 Task；每个新增源文件严格 ≤ 500 行。

## [x] Task 1: Models — ContainerImage / ContainerInstance 数据模型
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 在 [Sources/EnvMatrix/Models/ContainerImage.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/ContainerImage.swift) 定义：
    - `public struct ContainerImage: Identifiable, Hashable, Sendable, Codable { id, repository, tag, digest?, sizeBytes, createdAt, engine }`
    - `public enum ContainerImageSort { name, size, createdAt }`
    - `public struct ImagePruneResult { reclaimedBytes: Int64, rawStdout: String, engine: ContainerEngine }`
  - 在 [Sources/EnvMatrix/Models/ContainerInstance.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/ContainerInstance.swift) 定义：
    - `public struct ContainerInstance: Identifiable, Hashable, Sendable, Codable { id, names, image, command, state, status, portsSummary, createdAt, engine }`
    - `public enum ContainerInstanceState: String, Sendable, Codable { running, exited, paused, created, restarting, dead, unknown }`
    - `public enum ContainerInstanceFilter { all, running, exited }`
  - 扩展 [Sources/EnvMatrix/Models/ContainerContext.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/ContainerContext.swift) 中的 `ContainerContextsError` 新增 case：`case notRunning(ContainerEngine, String)`
- **Acceptance Criteria Addressed**: AC-2, AC-5, AC-15
- **Test Requirements**:
  - `programmatic` TR-1.1：`ContainerImage` / `ContainerInstance` JSON 编解码往返测试
  - `programmatic` TR-1.2：`ContainerInstanceState.init(rawValue:)` 对 CLI 未知值回落 `.unknown`
- **Notes**：单文件 ≤ 500 行；只放数据模型与枚举

## [ ] Task 2: Services — 流式扩展 ProcessExecutor
- **Priority**: P0
- **Depends On**: T1
- **Description**:
  - 为 [Sources/EnvMatrix/Services/ProcessExecutor.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessExecutor.swift) 新增流式接口：
    ```swift
    public protocol StreamingProcessExecutor: ProcessExecutor {
        func stream(executable: URL, args: [String], onLine: @Sendable @escaping (String) -> Void) async throws -> ProcessResult
        func spawn(executable: URL, args: [String], onLine: @Sendable @escaping (String) -> Void) -> StreamingHandle
    }
    public final class StreamingHandle: Sendable { public func cancel() { ... } }
    ```
  - `DefaultProcessExecutor` 提供默认实现：基于 `Pipe.fileHandleForReading.readabilityHandler` 按 UTF-8 逐行回调；`spawn` 返回可 `terminate()` 的句柄
  - 需要保持既有 `run(executable:args:timeout:)` API 不变
- **Acceptance Criteria Addressed**: AC-3, AC-14
- **Test Requirements**:
  - `programmatic` TR-2.1：mock 一个 `echo "line1\nline2\n"` 场景，验证 onLine 被回调两次
  - `programmatic` TR-2.2：`StreamingHandle.cancel()` 触发 Process.terminate() 且 exitCode 非 0

## [x] Task 3: Services — DockerImageService
- **Priority**: P0
- **Depends On**: T1, T2
- **Description**:
  - 新建 [Sources/EnvMatrix/Services/DockerImageService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DockerImageService.swift)：
    ```swift
    public protocol DockerImageService {
        func list() async throws -> [ContainerImage]
        func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) -> StreamingHandle
        func tag(source: String, destination: String) async throws
        func remove(id: String) async throws
        func prune(includeUnused: Bool) async throws -> ImagePruneResult
        func inspect(id: String) async throws -> String
    }
    ```
  - 参数走数组：`["images", "--format", "{{json .}}"]`；`pull` 走 spawn
  - 参数校验：reference 不含空格 / 控制字符；invalid 抛 `ContainerContextsError.invalidInput`
- **Acceptance Criteria Addressed**: AC-2, AC-3, AC-4, AC-13
- **Test Requirements**:
  - `programmatic` TR-3.1：list 使用 mock 输出解析出预期数量
  - `programmatic` TR-3.2：prune 从 stdout 解析 `Total reclaimed space` 并写入 `reclaimedBytes`
  - `programmatic` TR-3.3：非法 reference（含空格）触发 `invalidInput`

## [ ] Task 4: Services — DockerContainerService
- **Priority**: P0
- **Depends On**: T1, T2
- **Description**:
  - 新建 [Sources/EnvMatrix/Services/DockerContainerService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DockerContainerService.swift)：
    ```swift
    public protocol DockerContainerService {
        func list(all: Bool) async throws -> [ContainerInstance]
        func start(id: String) async throws
        func stop(id: String) async throws
        func restart(id: String) async throws
        func remove(id: String) async throws
        func logs(id: String, tail: Int) async throws -> String
        func inspect(id: String) async throws -> String
    }
    ```
  - `logs` 使用 `--tail <n>` 一次性拉取；`state` 字段解析映射到 `ContainerInstanceState`
- **Acceptance Criteria Addressed**: AC-5, AC-6, AC-7, AC-13
- **Test Requirements**:
  - `programmatic` TR-4.1：list mock 数据解析 running / exited / paused 三种状态
  - `programmatic` TR-4.2：logs tail 参数被正确以 `["logs", "--tail", "\(n)", id]` 形式传入
  - `programmatic` TR-4.3：包含空格的 id 触发 `invalidInput`

## [x] Task 5: Services — PodmanImageService / PodmanContainerService
- **Priority**: P0
- **Depends On**: T1, T2
- **Description**:
  - 新建 [Sources/EnvMatrix/Services/PodmanImageService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/PodmanImageService.swift) 与 [Sources/EnvMatrix/Services/PodmanContainerService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/PodmanContainerService.swift)
  - Protocol 与 Docker 版对称；实现细节差异：
    - `podman images --format json`：标准 JSON 数组
    - `podman ps --format json`：标准 JSON 数组，字段名与 docker 略有差异（`Names` vs `Names[0]`）
  - `podman machine` 未启动时 stderr 会返回 `Cannot connect to Podman`，映射到 `ContainerContextsError.notRunning(.podman, stderr前500字)`
- **Acceptance Criteria Addressed**: AC-2, AC-5, AC-13
- **Test Requirements**:
  - `programmatic` TR-5.1：list mock 输出解析正确
  - `programmatic` TR-5.2：Cannot connect 场景抛 `notRunning`

## [x] Task 6: ViewModel — ContainerImagesViewModel / ContainerInstancesViewModel
- **Priority**: P0
- **Depends On**: T3, T4, T5
- **Description**:
  - 新建 [Sources/EnvMatrix/ViewModels/ContainerImagesViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/ContainerImagesViewModel.swift)：`@MainActor` + `@Published var images` + `sort` + `keyword` + `isBusy` + `pullLog: [String]` + `pullHandle: StreamingHandle?`
  - 新建 [Sources/EnvMatrix/ViewModels/ContainerInstancesViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/ContainerInstancesViewModel.swift)：`@Published var instances` + `filter: ContainerInstanceFilter` + `keyword` + `isBusy` + `logsSheet: LogsSheetState?`
  - 两个 ViewModel 均接收 `engine: ContainerEngine`，由父 View 在 Docker/Podman 分区各创建一份
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-3, AC-5, AC-6, AC-7, AC-9, AC-14
- **Test Requirements**:
  - `programmatic` TR-6.1：mock service 后 `refresh()` 成功写入 images / instances
  - `programmatic` TR-6.2：pull 失败会 append 错误行到 pullLog
  - `programmatic` TR-6.3：`cancelPull()` 触发 StreamingHandle.cancel 并置 isBusy=false

## [x] Task 7: ViewModel — 扩展 ContainerContextsViewModel 联动
- **Priority**: P1
- **Depends On**: T6
- **Description**:
  - 修改 [Sources/EnvMatrix/ViewModels/ContainerContextsViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/ContainerContextsViewModel.swift) 新增：
    - `@Published var selectedTab: ContainerContextsTab = .contexts` （枚举 contexts/images/containers）
    - 提供 `imagesVMDocker` / `imagesVMPodman` / `instancesVMDocker` / `instancesVMPodman` 懒加载 sub-VM
    - 在 `useDocker(_:)` / `setPodmanDefault(_:)` 成功后调用各 sub-VM 的 `markStale()`
- **Acceptance Criteria Addressed**: AC-1, AC-9
- **Test Requirements**:
  - `programmatic` TR-7.1：切换 context 后 sub-VM `isStale == true`

## [x] Task 8: View — Images 分区
- **Priority**: P0
- **Depends On**: T6, T7
- **Description**:
  - 新建 [Sources/EnvMatrix/Views/System/ContainerImagesTab.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerImagesTab.swift)：Docker + Podman 分组、搜索框、排序 Picker、Pull 输入 + Progress log、行操作 Tag/Rm/Inspect、Prune 按钮 + include-unused Toggle
  - 拆分行视图到 [Sources/EnvMatrix/Views/System/ContainerImageRow.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerImageRow.swift)
  - 拆分 Pull 弹窗到 [Sources/EnvMatrix/Views/System/ContainerImagePullSheet.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerImagePullSheet.swift)
  - 拆分 Inspect 弹窗到 [Sources/EnvMatrix/Views/System/ContainerInspectSheet.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerInspectSheet.swift)
- **Acceptance Criteria Addressed**: AC-1, AC-3, AC-4, AC-8, AC-14
- **Test Requirements**:
  - `human-judgement` TR-8.1：交互与视觉符合 spec；破坏性操作弹二次确认
  - `human-judgement` TR-8.2：Pull 期间可点击 Cancel，log 面板滚动到底

## [x] Task 9: View — Containers 分区
- **Priority**: P0
- **Depends On**: T6, T7, T8
- **Description**:
  - 新建 [Sources/EnvMatrix/Views/System/ContainerInstancesTab.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerInstancesTab.swift)
  - 拆分行到 [Sources/EnvMatrix/Views/System/ContainerInstanceRow.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerInstanceRow.swift)
  - 拆分 Logs 弹窗到 [Sources/EnvMatrix/Views/System/ContainerLogsSheet.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerLogsSheet.swift)（复用 ContainerInspectSheet）
- **Acceptance Criteria Addressed**: AC-1, AC-5, AC-6, AC-7, AC-8, AC-14
- **Test Requirements**:
  - `human-judgement` TR-9.1：状态过滤 Segmented Picker 交互正确
  - `human-judgement` TR-9.2：Logs 弹窗 tail 大小切换后自动重新拉取

## [x] Task 10: View — 三 Tab 集成入口
- **Priority**: P0
- **Depends On**: T8, T9
- **Description**:
  - 修改 [Sources/EnvMatrix/Views/System/ContainerContextsView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerContextsView.swift) 顶部加 Segmented Picker（Contexts / Images / Containers），根据 selectedTab 分发到子视图
  - 页头新增引擎选择 chip：Docker `docker:desktop-linux` / Podman `podman-default`
- **Acceptance Criteria Addressed**: AC-1, AC-9
- **Test Requirements**:
  - `human-judgement` TR-10.1：Tab 切换视觉平滑无闪烁；数据仅在首次进入时加载
  - `human-judgement` TR-10.2：切换 context 后 Images/Containers 自动刷新

## [x] Task 11: Dashboard 概览卡片
- **Priority**: P1
- **Depends On**: T3, T4, T5
- **Description**:
  - 修改 [Sources/EnvMatrix/Views/Dashboard/DashboardView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Dashboard/DashboardView.swift) 与对应 VM，新增 `ContainerOverviewCard`（可能拆到 [Sources/EnvMatrix/Views/Dashboard/ContainerOverviewCard.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Dashboard/ContainerOverviewCard.swift) 保持 500 行约束）
  - 展示：Docker context 名 / images count / running count / stopped count（Podman 同理）
  - 点击卡片 `AppState.selectedNavigation = .systemContainerContexts` 并置 selectedTab
- **Acceptance Criteria Addressed**: AC-10
- **Test Requirements**:
  - `human-judgement` TR-11.1：卡片布局与视觉与 Dashboard 其它卡片保持一致
  - `programmatic` TR-11.2：DashboardViewModel 单测覆盖计数逻辑

## [x] Task 12: Diagnostic Report 追加
- **Priority**: P2
- **Depends On**: T3, T4, T5
- **Description**:
  - 修改 [Sources/EnvMatrix/Services/DiagnosticReportService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DiagnosticReportService.swift) 追加 `## Container Images (top 20 by size)` 与 `## Container Instances (running only)` 章节
- **Acceptance Criteria Addressed**: AC-11
- **Test Requirements**:
  - `programmatic` TR-12.1：mock service 情况下报告 markdown 包含两个新段落

## [x] Task 13: 全局搜索接入
- **Priority**: P2
- **Depends On**: T3, T4, T5
- **Description**:
  - 修改 [Sources/EnvMatrix/Services/SearchAggregator.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/SearchAggregator.swift) 新增 `.containerImage` / `.containerInstance` source
  - 修改 [Sources/EnvMatrix/Views/GlobalSearchView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/GlobalSearchView.swift) 点击命中项回跳到 `.systemContainerContexts` 且预选对应 Tab（通过 AppState 或 NotificationCenter 传递 tab hint）
- **Acceptance Criteria Addressed**: AC-12
- **Test Requirements**:
  - `programmatic` TR-13.1：Aggregator 输出包含两个新 source
  - `human-judgement` TR-13.2：命中项回跳后 selectedTab 正确

## [x] Task 14: 本地化 keys（Container Images/Instances）
- **Priority**: P0
- **Depends On**: T6, T8, T9
- **Description**:
  - 新建 [Sources/EnvMatrix/Utils/Localization+ContainerImagesInstances.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+ContainerImagesInstances.swift)：
    ```swift
    extension L10n {
        static let enContainerImagesInstances: [String: String] = [...]
        static let zhContainerImagesInstances: [String: String] = [...]
    }
    ```
  - 修改 [Sources/EnvMatrix/Utils/Localization.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization.swift) 合并到 `L10n.strings`
  - 覆盖 keys：`container.tab.contexts / images / containers`、`container.image.pull / tag / rm / prune / inspect / logsBtn`、`container.instance.start / stop / restart / rm / logs / inspect`、`container.image.emptyState / container.instance.emptyState`、`container.logs.title / copy / tailPicker`、`container.podman.notRunning`、`dashboard.card.containersTitle` 等
- **Acceptance Criteria Addressed**: AC-15
- **Test Requirements**:
  - `programmatic` TR-14.1：`ContainerImagesLocalizationTests` / `ContainerInstancesLocalizationTests` 覆盖 en/zh key 对称与非空

## [ ] Task 15: 单元测试
- **Priority**: P0
- **Depends On**: T1..T7
- **Description**:
  - 新增 `Tests/EnvMatrixTests/DockerImageServiceTests.swift`（list/pull/tag/rm/prune/inspect 各覆盖 mock）
  - 新增 `Tests/EnvMatrixTests/DockerContainerServiceTests.swift`（list/start/stop/restart/rm/logs/inspect）
  - 新增 `Tests/EnvMatrixTests/PodmanImageServiceTests.swift` + `PodmanContainerServiceTests.swift`
  - 新增 `Tests/EnvMatrixTests/ContainerImagesViewModelTests.swift` + `ContainerInstancesViewModelTests.swift`
  - 新增 `Tests/EnvMatrixTests/ContainerImagesLocalizationTests.swift`（含 instance keys）
- **Acceptance Criteria Addressed**: AC-2, AC-3, AC-5, AC-9, AC-11, AC-13, AC-15
- **Test Requirements**:
  - `programmatic` TR-15.1：`swift test` 全绿

## [ ] Task 16: README + 文档
- **Priority**: P2
- **Depends On**: T1..T10
- **Description**:
  - 更新 [README.md](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md)：
    - What's New 补充"🖼️ 容器镜像与实例管理"条目
    - Container Contexts 章节改名为「容器工作台」，说明三 Tab 结构
    - Roadmap：将"Docker / Podman 镜像与实例管理"从 `[ ]` 迁移到 `[x]`（如原 Roadmap 无此条则新增 `[x]`）
    - 项目结构：追加 6 个新增 service 文件与 5 个新增 view 文件
- **Acceptance Criteria Addressed**: None（文档配套）
- **Test Requirements**:
  - `human-judgement` TR-16.1：中英文段落无编码乱码，Markdown 渲染正常

## [x] Task 17: 构建与格式校验
- **Priority**: P0
- **Depends On**: T1..T16
- **Description**:
  - `swift build -c debug` 无 warning
  - `swift test` 全绿
  - `bash scripts/check_file_lines.sh` 不新增 500 行超限文件
  - 环境若安装 swiftlint 则执行 `swiftlint --strict`
- **Test Requirements**:
  - `programmatic` TR-17.1：上述前三条命令 exit code = 0
