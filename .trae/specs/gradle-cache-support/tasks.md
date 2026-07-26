# Gradle 全局缓存扫描 - Implementation Plan

## [x] Task G1: GradleCacheService —— modules-2 & wrapper dists 扫描
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 新增 [GradleCacheService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/GradleCacheService.swift)，提供：
    - `struct GradleArtifact: Identifiable, Sendable { id: String; group: String; artifact: String; version: String; url: URL; sizeBytes: Int64; modifiedAt: Date? }`
    - `struct GradleWrapperDist: Identifiable, Sendable { id: String; versionLabel: String; url: URL; sizeBytes: Int64; modifiedAt: Date? }`
    - `public static func scanArtifacts(fm:) -> [GradleArtifact]`：遍历 `~/.gradle/caches/modules-2/files-2.1/<group>/<artifact>/<version>/`，size = directorySize；不存在返回 `[]`。
    - `public static func scanWrapperDists(fm:) -> [GradleWrapperDist]`：遍历 `~/.gradle/wrapper/dists/gradle-*/`，取第一层匹配前缀 `gradle-` 的目录为版本单元。
    - `public static func moveToTrash(_ url: URL) throws`：调用 `NSWorkspace.shared.recycle` 或 `FileManager.default.trashItem(at:resultingItemURL:)`。
  - 参照 [MavenLocalRepositoryService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/MavenLocalRepositoryService.swift) 复用 directorySize 工具或抽出 helper。
- **Acceptance Criteria Addressed**: AC-2, AC-3, AC-5
- **Test Requirements**:
  - `programmatic` TR-G1.1: 在 tmp 下构造 fixture `fake-home/.gradle/caches/modules-2/files-2.1/org.slf4j/slf4j-api/2.0.0/xxxhash/slf4j-api-2.0.0.jar` (10 bytes 内容)，调用 scanArtifacts 应返回 1 项，group="org.slf4j"、artifact="slf4j-api"、version="2.0.0"、sizeBytes>=10。
  - `programmatic` TR-G1.2: 在 fixture 下构造 `.gradle/wrapper/dists/gradle-8.5-all/hash/gradle-8.5/bin/gradle`，scanWrapperDists 应返回 1 项 versionLabel 包含 "8.5"。
  - `programmatic` TR-G1.3: `~/.gradle` 缺失 → 两个方法返回 `[]` 无异常。
- **Notes**: 使用 `Self.` 前缀调用静态 helper（依据 project_memory）。

## [x] Task G2: GradleCacheViewModel
- **Priority**: P0
- **Depends On**: Task G1
- **Description**:
  - 新增 [GradleCacheViewModel.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/ViewModels/GradleCacheViewModel.swift) `@MainActor final class GradleCacheViewModel: ObservableObject`，含：
    - `@Published var artifacts: [GradleArtifact]`、`wrappers: [GradleWrapperDist]`
    - `@Published var artifactSort / wrapperSort: SortOption`（rawValue: sizeDesc/sizeAsc/mtimeDesc/mtimeAsc）
    - `@Published var searchText: String`（分别过滤 artifacts / wrappers）
    - `@Published var selectedArtifactIDs / selectedWrapperIDs: Set<String>`
    - `@Published var isScanning: Bool` / `errorMessage: String?`
    - 计算属性 `visibleArtifacts` / `visibleWrappers`（过滤 + 排序）
    - 计算属性 `artifactsTotalBytes` / `wrappersTotalBytes` / `grandTotalBytes`
    - `func refresh() async`：`Task.detached` 调用 scanner，回主线程赋值。
    - `func delete(_ url: URL) async`；`func deleteArtifacts(_ ids: Set<String>) async`；`func deleteWrappers(_ ids: Set<String>) async` — 全部走 `GradleCacheService.moveToTrash`。
- **Acceptance Criteria Addressed**: AC-2, AC-3, AC-4, AC-5
- **Test Requirements**:
  - `programmatic` TR-G2.1: 注入 3 个 artifact 后 visibleArtifacts 排序符合 sortOption；searchText 支持 group:artifact 与 version 子串匹配。
  - `programmatic` TR-G2.2: deleteArtifacts 成功后从数组移除、selectedArtifactIDs 清空、totalBytes 更新。
- **Notes**: 与 [MavenLocalRepositoryViewModel.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/ViewModels/MavenLocalRepositoryViewModel.swift) 风格保持一致。

## [x] Task G3: GradleCacheView
- **Priority**: P0
- **Depends On**: Task G2
- **Description**:
  - 新增 [GradleCacheView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/Packages/GradleCacheView.swift)：
    - 顶部 stats（Artifacts / Wrappers / 合计）
    - 内部 SegmentedControl 切换 Artifacts / Wrappers
    - 每段：搜索框 + 排序 Menu + 多选 List + 批量删除按钮
    - 空态：图标 + 文案 + 官网链接 (Button opens `https://gradle.org`)
  - 主文件 < 500 行；若超出，把 Artifacts 段落 / Wrappers 段落拆到 `GradleCacheView+Extras.swift`。
- **Acceptance Criteria Addressed**: AC-1, AC-4, AC-5, AC-6
- **Test Requirements**:
  - `programmatic` TR-G3.1: `swift build` 通过。
  - `human-judgment` TR-G3.2: 视觉与 [MavenLocalArtifactsView](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/Packages/MavenLocalArtifactsView.swift) 一致（间距 / 字体 / 颜色）。

## [x] Task G4: MavenRepositoryView 新增 gradleCache tab
- **Priority**: P0
- **Depends On**: Task G3
- **Description**:
  - 在 [MavenTab](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/Packages/MavenRepositoryView.swift#L3-L14) 添加 `case gradleCache`；title 用 `L("mavenRepo.tab.gradleCache")`。
  - `switch` 分支新增 `case .gradleCache: GradleCacheView(vm: gradleVM)`。
  - `MavenRepositoryView` 内新增 `@StateObject private var gradleVM = GradleCacheViewModel()`；在 `.task` 中调用 `await gradleVM.refresh()`。
  - Header 右侧 refresh Button 根据当前 tab 分发到对应 VM。
- **Acceptance Criteria Addressed**: AC-1
- **Test Requirements**:
  - `programmatic` TR-G4.1: MavenTab.allCases.count == 3。
  - `human-judgment` TR-G4.2: Tab 切换动画顺滑，无重叠 header。

## [x] Task G5: 本地化字符串补齐
- **Priority**: P0
- **Depends On**: Task G3, G4
- **Description**:
  - 为以下 keys 在 Zh/En 两侧同时补齐：
    - `mavenRepo.tab.gradleCache` = "Gradle 缓存" / "Gradle Cache"
    - `gradleCache.title` / `.subtitle`
    - `gradleCache.section.artifacts` / `.section.wrappers`
    - `gradleCache.total.artifacts` / `.total.wrappers` / `.total.combined`
    - `gradleCache.searchPlaceholder.artifacts` / `.searchPlaceholder.wrappers`
    - `gradleCache.column.groupArtifact` / `.column.version` / `.column.size` / `.column.mtime`
    - `gradleCache.action.reveal` / `.action.delete` / `.action.deleteSelected`
    - `gradleCache.empty.title` / `.empty.hint` / `.empty.openWebsite`
    - `gradleCache.confirmDelete.title` / `.confirmDelete.body` / `.confirmDelete.confirm`
- **Acceptance Criteria Addressed**: AC-1, AC-6
- **Test Requirements**:
  - `programmatic` TR-G5.1: `diff <(grep -oE '"gradleCache\.[^"]+"' Localization+Zh.swift | sort -u) <(grep -oE '"gradleCache\.[^"]+"' Localization+En.swift | sort -u)` 输出为空。
- **Notes**: 键顺序放在 `mavenRepo.*` 分组之后作为独立段。

## [x] Task G6: 构建与验证
- **Priority**: P0
- **Depends On**: Task G1–G5
- **Description**: `swift build` 通过；GetDiagnostics 零错误；grep 无残留原始 key。
- **Acceptance Criteria Addressed**: AC-7
- **Test Requirements**:
  - `programmatic` TR-G6.1: exit 0；warning 计数不高于 build 基线。
  - `programmatic` TR-G6.2: `grep -R "gradleCache\." Sources` 显示所有 key 都对应 Zh/En 存在项。
