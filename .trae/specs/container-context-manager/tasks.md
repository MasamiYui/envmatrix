# Docker / Podman 上下文管理 - The Implementation Plan (Decomposed and Prioritized Task List)

按优先级从上到下执行；同一文件的多处修改合并为一个 Task。

## [x] Task 1: Models — ContainerContext / Podman 数据模型
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 在 [Sources/EnvMatrix/Models/ContainerContext.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/ContainerContext.swift) 定义：
    - `public enum ContainerEngine: String, CaseIterable { case docker, podman }`
    - `public struct DockerContext: Identifiable, Hashable { name, description, endpoint, contextType, isCurrent, tlsEnabled?, skipTLSVerify? }`
    - `public struct PodmanConnection: Identifiable, Hashable { name, uri, identity, isDefault, isReadWrite }`
    - `public enum ContainerContextsError: Error, LocalizedError { case cliMissing(ContainerEngine), commandFailed(ContainerEngine, String), parseFailed(ContainerEngine, String), timeout(ContainerEngine), invalidInput(String) }`
    - `public struct ContainerPingResult { engine, contextName, ok, latencyMS, summary, rawStderr }`
  - 所有类型 Hashable / Sendable / Codable-友好。
- **Acceptance Criteria Addressed**: AC-4, AC-9
- **Test Requirements**:
  - `programmatic` TR-1.1：`DockerContext` / `PodmanConnection` 从 JSON 反序列化的往返测试
  - `programmatic` TR-1.2：`ContainerContextsError.errorDescription` 覆盖所有 case
- **Notes**：单文件 ≤ 500 行；不放业务逻辑，只放数据模型与错误枚举。

## [x] Task 2: Services — 抽象 ProcessExecutor + DockerContextService
- **Priority**: P0
- **Depends On**: T1
- **Description**:
  - 若尚不存在，提取通用 `ProcessExecutor` protocol 到 [Sources/EnvMatrix/Services/ProcessExecutor.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessExecutor.swift)，签名：`func run(executable: URL, args: [String], timeout: TimeInterval?) async throws -> (stdout: String, stderr: String, exitCode: Int32)`；默认实现基于 `Foundation.Process`。（若现有代码里已有类似封装，直接复用并仅补 timeout 参数。）
  - 在 [Sources/EnvMatrix/Services/DockerContextService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DockerContextService.swift) 定义：
    ```swift
    public protocol DockerContextService {
        func isDockerAvailable() async -> Bool
        func listContexts() async throws -> [DockerContext]
        func useContext(_ name: String) async throws
        func createContext(name: String, host: String, description: String?,
                           tls: DockerTLSOptions?) async throws
        func updateContext(name: String, host: String?, description: String?,
                           tls: DockerTLSOptions?) async throws
        func removeContext(_ name: String) async throws
        func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult
    }
    ```
  - `DefaultDockerContextService` 使用 `ShellPathResolver` 找 `docker`，`listContexts()` 解析 `docker context ls --format '{{json .}}'` 的 JSON Lines；`ping` 使用 `docker --context <name> version --format '{{json .}}'` 并加 timeout。
  - 严格禁止把用户输入拼进 shell 字符串；所有参数以 `Process.arguments` 数组传入。
- **Acceptance Criteria Addressed**: AC-1, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8, AC-10
- **Test Requirements**:
  - `programmatic` TR-2.1：mock executor 返回样例 `docker context ls` JSON Lines，`listContexts()` 正确解析 3 条 + 高亮 `isCurrent`
  - `programmatic` TR-2.2：`useContext` / `createContext` / `updateContext` / `removeContext` 命令参数与顺序完全符合预期（断言 executor 收到的 `args`）
  - `programmatic` TR-2.3：`ping` 5s 超时时抛 `.timeout(.docker)`
  - `programmatic` TR-2.4：`listContexts` 遇到不完整 JSON 时抛 `.parseFailed` 且携带原文片段
- **Notes**：Endpoints inspect 字段做**best-effort 防御式解析**，字段缺失时降级为 `tlsEnabled = nil` 不报错。

## [x] Task 3: Services — PodmanContextService
- **Priority**: P0
- **Depends On**: T1, T2（复用 ProcessExecutor）
- **Description**:
  - 在 [Sources/EnvMatrix/Services/PodmanContextService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/PodmanContextService.swift) 定义：
    ```swift
    public protocol PodmanContextService {
        func isPodmanAvailable() async -> Bool
        func listConnections() async throws -> [PodmanConnection]
        func setDefault(_ name: String) async throws
        func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws
        func replaceConnection(oldName: String, newName: String, uri: String,
                               identity: String?, makeDefault: Bool) async throws
        func removeConnection(_ name: String) async throws
        func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult
    }
    ```
  - `listConnections()` 解析 `podman system connection list --format json`；`setDefault` 用 `podman system connection default <name>`；add / remove 对应命令；`replaceConnection` 通过 remove + add 事务，失败时补回原连接。
  - `ping`：`podman --connection <name> system info --format json`，5s timeout。
- **Acceptance Criteria Addressed**: AC-1, AC-3, AC-9, AC-10
- **Test Requirements**:
  - `programmatic` TR-3.1：mock executor 返回样例 JSON 数组，`listConnections()` 正确解析、`isDefault` 标记正确
  - `programmatic` TR-3.2：`replaceConnection` 遇到 add 失败时会调用 executor 回滚 add old value
  - `programmatic` TR-3.3：`removeConnection` 命令 args 精确匹配
- **Notes**：Podman `replaceConnection` 的原子性只在 CLI 层做尽力回滚，说明在文档中。

## [x] Task 4: ViewModel — ContainerContextsViewModel
- **Priority**: P0
- **Depends On**: T2, T3
- **Description**:
  - 位置：[Sources/EnvMatrix/ViewModels/ContainerContextsViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/ViewModels/ContainerContextsViewModel.swift)
  - `@MainActor final class ContainerContextsViewModel: ObservableObject`
  - Published：`dockerAvailable`、`podmanAvailable`、`dockerContexts`、`podmanConnections`、`isDockerBusy`、`isPodmanBusy`、`dockerError`、`podmanError`、`dockerCollapsed`、`podmanCollapsed`、`pingResults: [String: ContainerPingResult]`（按 `engine.rawValue + "/" + name` 作 key）
  - 方法：`refresh()`（并行两个引擎）、`useDocker(_:)` / `setPodmanDefault(_:)`、CRUD 各方法、`ping(engine:, name:)`（写入 pingResults）
  - 全部 IO 走 `Task.detached(priority: .utility)`；错误映射到 `dockerError` / `podmanError`。
- **Acceptance Criteria Addressed**: AC-3, AC-5..AC-10
- **Test Requirements**:
  - `programmatic` TR-4.1：mock services，`refresh()` 后 `dockerContexts.count == 3`
  - `programmatic` TR-4.2：`useDocker("colima")` 成功后 `dockerContexts.first { $0.isCurrent }?.name == "colima"`
  - `programmatic` TR-4.3：任一引擎不可用时 available 标志与 error 消息分别设置，不影响另一引擎数据流
- **Notes**：pingResults 用 dictionary + `String` key，方便 SwiftUI 按行读取。

## [x] Task 5: View — ContainerContextsView + 子视图
- **Priority**: P0
- **Depends On**: T4
- **Description**:
  - 位置：[Sources/EnvMatrix/Views/System/ContainerContextsView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Views/System/ContainerContextsView.swift)（≤ 500 行）；若单文件超过阈值，拆出：
    - `ContainerContextRow.swift`（单行渲染）
    - `ContainerContextEditorSheet.swift`（新增 / 编辑弹窗）
  - 顶部标题 + 说明；两个 Section："Docker Contexts"、"Podman Connections"，各自：
    - Section header：icon + title + count badge + collapse chevron + `+` 按钮 + refresh 按钮
    - 每行：Active 标记 / Name / Endpoint / small badges（内置 / TLS / ssh:// 等）/ 行内操作按钮（Use / Ping / Edit / Delete）
    - Ping 结果以 disclosure 展开或以 ephemeral toast 显示
  - Editor Sheet：
    - Docker：Name、Endpoint（enum picker：`unix://` / `tcp://` / `ssh://`）、Description、可选 TLS 三个证书路径 + skipTLSVerify toggle
    - Podman：Name、URI（unix / ssh 模板选择）、Identity、Make default toggle
  - Empty state：`shippingbox.circle` icon + "未检测到 xxx CLI，`brew install docker` / `brew install podman` 安装后重试"
  - 全部文案用 `L("...")`。
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-3, AC-4, AC-6, AC-7, AC-8, AC-9, AC-10
- **Test Requirements**:
  - `human-judgement` TR-5.1：交互一致性：Section 折叠 / count badge / 按钮 hover 风格与 [MCPServersView](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/AI/MCPServersView.swift) 一致
  - `human-judgement` TR-5.2：内置 context（Docker `default`）Delete 按钮 disabled 且有 tooltip
  - `human-judgement` TR-5.3：空态文案友好、图标合理
  - `programmatic` TR-5.4：View init 不做 IO；ViewModel 通过环境注入或 `.task { await vm.refresh() }` 触发

## [x] Task 6: 导航与路由接入
- **Priority**: P0
- **Depends On**: T5
- **Description**:
  - [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 新增 `.systemContainerContexts`：`id`、`displayName = L("nav.containerContexts")`、`systemImage = "shippingbox.and.arrow.backward.fill"`（若不合适可退回 `cablecar.fill`）；`allCases` 与 `allSections` 的 `nav.system` 分组在 `.systemLocalApps` 之后、`.settings` 之前追加。
  - [DetailView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/DetailView.swift) `switch` 新增 `case .systemContainerContexts: ContainerContextsView()`。
- **Acceptance Criteria Addressed**: AC-1
- **Test Requirements**:
  - `programmatic` TR-6.1：`NavigationItem.systemContainerContexts.id == "system.containerContexts"`；`.allCases` 包含该项
  - `programmatic` TR-6.2：`allSections` 中 `nav.system` 分组包含该项且位置正确

## [/] Task 7: 本地化 keys
- **Priority**: P0
- **Depends On**: T5, T6
- **Description**:
  - 在 [Localization+En.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+En.swift) / [Localization+Zh.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) 中双语对称新增以下 key（示意）：
    - `nav.containerContexts`
    - `container.title` / `container.subtitle`
    - `container.docker.section` / `container.podman.section`
    - `container.section.empty` / `container.section.cliMissing`
    - `container.row.active` / `container.row.builtIn` / `container.row.tls` / `container.row.ssh`
    - `container.action.use` / `container.action.ping` / `container.action.edit` / `container.action.delete` / `container.action.add`
    - `container.confirm.delete` / `container.confirm.setDefault` / `container.delete.protectedTooltip`
    - `container.editor.title.new` / `container.editor.title.edit`
    - `container.editor.name` / `container.editor.description` / `container.editor.endpoint.unix` / `container.editor.endpoint.tcp` / `container.editor.endpoint.ssh` / `container.editor.identity` / `container.editor.makeDefault` / `container.editor.tls.caCert` / `container.editor.tls.clientCert` / `container.editor.tls.clientKey` / `container.editor.tls.skipVerify`
    - `container.ping.success` / `container.ping.failed` / `container.ping.timeout`
    - `container.error.cliMissing` / `container.error.commandFailed` / `container.error.parseFailed` / `container.error.invalidInput`
- **Acceptance Criteria Addressed**: AC-11
- **Test Requirements**:
  - `programmatic` TR-7.1：新增 `ContainerContextsLocalizationTests`：断言两个字典所含 `container.*` / `nav.containerContexts` key 集合完全一致，且每个 value 非空

## [x] Task 8: 单元测试
- **Priority**: P0
- **Depends On**: T2, T3, T4, T7
- **Description**:
  - [Tests/EnvMatrixTests/DockerContextServiceTests.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/DockerContextServiceTests.swift)：mock executor 覆盖 list / use / create / update / rm / ping 与超时 / 解析失败路径
  - [Tests/EnvMatrixTests/PodmanContextServiceTests.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/PodmanContextServiceTests.swift)：list / setDefault / add / replace（含失败回滚）/ remove / ping
  - [Tests/EnvMatrixTests/ContainerContextsViewModelTests.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/ContainerContextsViewModelTests.swift)：并行 refresh、状态标志、错误上抛、ping 结果写入 map
  - [Tests/EnvMatrixTests/ContainerContextsLocalizationTests.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Tests/EnvMatrixTests/ContainerContextsLocalizationTests.swift)：中英双字典 key 对称与非空
- **Acceptance Criteria Addressed**: AC-3, AC-5..AC-11, AC-13
- **Test Requirements**:
  - `programmatic` TR-8.1：`swift test` 通过、四个测试文件全部执行
  - `programmatic` TR-8.2：新增测试对 3 个 Service protocol 的关键分支覆盖率主观 ≥ 80%

## [x] Task 9: 全局搜索接入（可选，可延后）
- **Priority**: P2
- **Depends On**: T2, T3
- **Description**:
  - 在 [SearchAggregator.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/SearchAggregator.swift) 追加 `containerContext` source：查询时并行拉 docker / podman，按 name / endpoint contains 关键字过滤；点击结果跳转到 `.systemContainerContexts`。
- **Acceptance Criteria Addressed**: FR-10（Non-blocking）
- **Test Requirements**:
  - `programmatic` TR-9.1：在有 mock docker/podman 数据时，搜索关键字命中并返回 source == `containerContext`
- **Notes**：如果时间紧张，可在下一 iteration 完成；不阻塞 P0。

## [x] Task 10: Diagnostic Report 输出 active context
- **Priority**: P2
- **Depends On**: T2, T3
- **Description**:
  - 在 [DiagnosticReportService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DiagnosticReportService.swift) 追加 `## Container Contexts` 段：
    - 当 docker 可用：`docker context show` 输出
    - 当 podman 可用：从 `podman system connection list --format json` 提取 `.Default = true`
- **Acceptance Criteria Addressed**: Open Question resolution
- **Test Requirements**:
  - `programmatic` TR-10.1：mock executor 情况下报告 markdown 包含 `## Container Contexts` 段落

## [x] Task 11: 构建与格式校验
- **Priority**: P0
- **Depends On**: T1..T8
- **Description**:
  - `swift build -c debug` 无 warning
  - `swift test` 全绿
  - `scripts/check_file_lines.sh` 通过
  - `swiftlint`（若安装）无新增 warning
- **Acceptance Criteria Addressed**: AC-12, AC-13
- **Test Requirements**:
  - `programmatic` TR-11.1：上述四条命令均返回 0

## [ ] Task 12: 文档与 Roadmap
- **Priority**: P1
- **Depends On**: T1..T11
- **Description**:
  - 更新 [README.md](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md)：
    - What's New 顶部新增 `Docker / Podman 上下文管理` 亮点
    - System 章节补一段"Container Contexts"介绍
    - Roadmap 中把 `Docker / Podman 上下文管理` 从 `[ ]` 迁到 `[x]`
    - 项目结构补充新增 Service / View / Model
  - 提交 Conventional Commit：`feat(system): add docker & podman context manager`（一次或按 Service/View 拆多次）。
- **Acceptance Criteria Addressed**: 汇总
- **Test Requirements**:
  - `human-judgement` TR-12.1：README 更新条目自然、无 emoji 编码乱码、Roadmap 状态一致
