# Local Apps Manager - The Implementation Plan (Decomposed and Prioritized Task List)

## [x] Task 1: Models 层定义
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 新建 `Sources/EnvMatrix/Models/LocalApp.swift`
  - 定义 `LocalApp`（id / name / displayName / version / bundleId / bundlePath: URL / sizeBytes / source / isProtected / iconPath）
  - 定义 `LocalAppSource` 枚举：`.appStore / .brewCask(token: String) / .other`
  - 定义 `LocalAppLeftover`（url: URL / sizeBytes: Int64 / kind: preferences|caches|appSupport|logs|savedState|containers|groupContainers）
  - 全部 `Codable` + `Hashable` + `Identifiable`
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-7
- **Test Requirements**:
  - `programmatic` TR-1.1: 结构体 `Codable` 往返序列化保持相等
  - `programmatic` TR-1.2: `LocalAppSource` 三种 case 与 rawValue 稳定
- **Notes**: 文件保持 <200 行

## [x] Task 2: Scanner - 应用枚举与解析
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 新建 `Sources/EnvMatrix/Services/LocalAppsScanner.swift`
  - `LocalAppsScanner` 协议：`func scan(roots: [URL]) async throws -> [LocalApp]`
  - Default 实现：并发 `TaskGroup` 遍历 roots（含一级子目录如 `Utilities`），过滤 `*.app`
  - 每个 bundle 解析 `Contents/Info.plist`（`PropertyListSerialization`）抽取 name / version / bundleId / iconFile
  - 计算 bundle 大小（递归 `URLResourceValues.totalFileAllocatedSize`）
  - `.appStore` 判定：存在 `Contents/_MASReceipt/receipt`
- **Acceptance Criteria Addressed**: AC-1, AC-8, NFR-1
- **Test Requirements**:
  - `programmatic` TR-2.1: fixture 目录含 3 个假 .app，扫描返回 3 项且 name/version/bundleId 正确
  - `programmatic` TR-2.2: `_MASReceipt/receipt` 存在时 source == `.appStore`
  - `programmatic` TR-2.3: 空 roots 返回 `[]` 而非抛异常
- **Notes**: 文件保持 <350 行

## [x] Task 3: Brew Cask 来源识别
- **Priority**: P0
- **Depends On**: Task 2
- **Description**:
  - 在 `LocalAppsScanner` 中新增 `BrewCaskProbe` 协议：`func caskTokenMap() async -> [String: String]`（key = artifact basename lowercased，value = cask token）
  - Default 实现执行 `brew list --cask --versions` + `brew info --cask --json=v2 <token>`（可选），或直接 `brew list --cask -1` + `brew --cask --caskroom` 中 `<token>/*/*.app` 名称映射
  - 简化版：`brew list --cask -1` 拿到所有 token 列表 → 对每个 token 执行 `brew list --cask <token>` 输出的路径基名建立 map
  - 扫描时：若 bundle 非 `.appStore`，用 basename 查 map；命中即 `.brewCask(token)`
  - brew 不存在时 map 为空，全部落 `.other`（不抛错）
- **Acceptance Criteria Addressed**: AC-2
- **Test Requirements**:
  - `programmatic` TR-3.1: 注入 mock BrewCaskProbe（返回 `["foo.app": "foo"]`），basename 为 `Foo.app` 的 bundle 被标记为 `.brewCask("foo")`
  - `programmatic` TR-3.2: mock 返回空 map 时全部 fallback 到 `.other`
- **Notes**: 保持 brew 调用可注入 mock，避免测试依赖真实 brew

## [x] Task 4: LocalAppsService - 操作层
- **Priority**: P0
- **Depends On**: Task 2, Task 3
- **Description**:
  - 新建 `Sources/EnvMatrix/Services/LocalAppsService.swift`
  - 协议方法：
    - `func openApp(_ app: LocalApp) throws`（`NSWorkspace.open`）
    - `func revealInFinder(_ app: LocalApp)`（`NSWorkspace.activateFileViewerSelecting`）
    - `func moveToTrash(_ app: LocalApp) throws -> URL`（`FileManager.trashItem`，返回废纸篓 URL）
    - `func scanLeftovers(bundleId: String) async -> [LocalAppLeftover]`
    - `func trashLeftovers(_ items: [LocalAppLeftover]) throws`
  - `isProtected(_ app: LocalApp) -> Bool`：根据路径前缀（`/System/Applications`、`/Applications/Utilities/{Terminal,Console,Disk Utility,...}.app`）与 bundleId 前缀 `com.apple.*` 判定
  - 将 `NSWorkspace` 与 `FileManager` 抽象为可注入的 `AppLauncher` / `Trasher` 协议以便测试
- **Acceptance Criteria Addressed**: AC-4, AC-5, AC-6, AC-7
- **Test Requirements**:
  - `programmatic` TR-4.1: `isProtected` 对 `/System/Applications/Foo.app` 返回 true，对 `/Applications/Foo.app` 返回 false
  - `programmatic` TR-4.2: `moveToTrash` 调用注入的 mock Trasher 并返回 mock URL
  - `programmatic` TR-4.3: `scanLeftovers` 对 fixture `~/Library/**` 中存在 `com.example.foo.plist` 与 `com.example.foo/` 目录返回 2 条
  - `programmatic` TR-4.4: `trashLeftovers` 对每一项调用 Trasher.trash
- **Notes**: 文件保持 <400 行

## [x] Task 5: LocalAppsViewModel
- **Priority**: P0
- **Depends On**: Task 4
- **Description**:
  - 新建 `Sources/EnvMatrix/ViewModels/LocalAppsViewModel.swift`
  - `@MainActor final class LocalAppsViewModel: ObservableObject`
  - `@Published`：`apps`, `filteredApps`, `searchText`, `sourceFilter`, `sortKey`, `isBusy`, `errorMessage`, `pendingLeftovers`
  - 方法：`refresh()`, `openSelected()`, `revealSelected()`, `requestUninstall(_:)`, `confirmUninstall(_:)`, `dismissLeftovers()`, `confirmLeftoverTrash(selection:)`
  - 所有 IO 使用 `Task.detached(priority: .utility)`，切回 MainActor 更新状态
- **Acceptance Criteria Addressed**: AC-3, AC-5, AC-7, AC-8
- **Test Requirements**:
  - `programmatic` TR-5.1: `refresh()` 后 `apps` 与 scanner mock 返回一致
  - `programmatic` TR-5.2: 修改 `searchText = "xcod"` 且 `sourceFilter = .appStore` 后 `filteredApps` 只留下匹配项
  - `programmatic` TR-5.3: `confirmUninstall` 触发 service.moveToTrash，成功后从 `apps` 中移除并写入 `pendingLeftovers`
  - `programmatic` TR-5.4: `confirmLeftoverTrash` 调用 service.trashLeftovers 并清空 `pendingLeftovers`
- **Notes**: 文件保持 <400 行

## [x] Task 6: LocalAppsView (SwiftUI)
- **Priority**: P0
- **Depends On**: Task 5
- **Description**:
  - 新建 `Sources/EnvMatrix/Views/System/LocalAppsView.swift`
  - 顶部：搜索框、来源筛选 segmented、排序菜单、刷新按钮
  - 主体：`List` 展示 name / icon / version / bundleId / size / source badge
  - 每行右侧：Open / Reveal / Uninstall 三按钮（Uninstall 对 `isProtected` 禁用并 tooltip 提示）
  - 卸载二次确认：`.alert` (destructive)，默认按钮为 Cancel
  - 卸载完成后弹出 Leftovers Sheet：Toggle 勾选 + 大小展示 + Trash / Cancel
  - 空状态：无 app 时展示 icon + `L("localApps.empty")`
- **Acceptance Criteria Addressed**: AC-1, AC-3, AC-5, AC-6, AC-7, AC-8, AC-9
- **Test Requirements**:
  - `human-judgment` TR-6.1: 视觉上信息层级清晰，源标签色彩区分明显
  - `human-judgment` TR-6.2: 二次确认对话框默认按钮为 Cancel，destructive 按钮为红色
- **Notes**: 文件保持 <500 行；如超限拆出 `LocalAppRow.swift` / `LocalAppLeftoversSheet.swift`

## [x] Task 7: 导航接入
- **Priority**: P1
- **Depends On**: Task 6
- **Description**:
  - 修改 [AppNavigation.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift)：新增 `.systemLocalApps` case，systemImage `app.badge.checkmark`，加入 `nav.system` 分组
  - 修改 [DetailView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/DetailView.swift)：路由到 `LocalAppsView`
- **Acceptance Criteria Addressed**: AC-9
- **Test Requirements**:
  - `programmatic` TR-7.1: `NavigationItem.allCases` 包含 `.systemLocalApps` 且 `id` 唯一
  - `human-judgment` TR-7.2: 侧边栏 System 分组显示 Local Apps 入口，图标合理

## [x] Task 8: 本地化文案
- **Priority**: P1
- **Depends On**: Task 6
- **Description**:
  - 在 [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) / [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) 中新增：
    - `nav.localApps`
    - `localApps.title`, `localApps.searchPlaceholder`, `localApps.empty`
    - `localApps.source.all`, `localApps.source.brew`, `localApps.source.appStore`, `localApps.source.other`
    - `localApps.action.open`, `localApps.action.reveal`, `localApps.action.uninstall`
    - `localApps.uninstall.title`, `localApps.uninstall.message`, `localApps.uninstall.confirm`, `localApps.uninstall.cancel`
    - `localApps.leftovers.title`, `localApps.leftovers.message`, `localApps.leftovers.trashSelected`
    - `localApps.protected.tooltip`
    - `localApps.sort.name`, `localApps.sort.size`, `localApps.sort.source`
    - `localApps.error.brewMissing`, `localApps.error.moveToTrashFailed`
- **Acceptance Criteria Addressed**: AC-9
- **Test Requirements**:
  - `programmatic` TR-8.1: EN/ZH 两个字典对应 key 集合完全相等（可通过 diff 验证）

## [x] Task 9: 单元测试
- **Priority**: P0
- **Depends On**: Task 2, Task 3, Task 4, Task 5
- **Description**:
  - `Tests/EnvMatrixTests/LocalAppsScannerTests.swift`：fixture 目录构造假 .app（含 Info.plist / _MASReceipt），验证扫描、来源识别
  - `Tests/EnvMatrixTests/LocalAppsServiceTests.swift`：mock Trasher / AppLauncher / BrewCaskProbe，验证 protected 判定、moveToTrash、scanLeftovers、trashLeftovers
  - `Tests/EnvMatrixTests/LocalAppsViewModelTests.swift`：mock service，验证 refresh、search + filter、uninstall 流程、leftovers 流程
- **Acceptance Criteria Addressed**: AC-10
- **Test Requirements**:
  - `programmatic` TR-9.1: `swift test --filter LocalApps` 全部 PASS
  - `programmatic` TR-9.2: 覆盖 scanner、service、viewModel 三层核心路径

## [x] Task 10: README 更新与 Git 提交
- **Priority**: P2
- **Depends On**: Task 9
- **Description**:
  - 在 [README.md](file:///Users/masamiyui/OpenSoureProjects/envmatrix/README.md) 「What's New」「Features」「Project Structure」「Roadmap」中补充 Local Apps 模块
  - 提交单次 Conventional Commit：`feat(local-apps): add /Applications inventory, source detection and safe uninstall with leftovers cleanup`
- **Acceptance Criteria Addressed**: —
- **Test Requirements**:
  - `programmatic` TR-10.1: `swift build` 无警告、无错误
  - `programmatic` TR-10.2: `swift test` 全量通过
  - `human-judgment` TR-10.3: README 段落语言与既有章节风格一致
