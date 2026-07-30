# 新增 Provider：Kotlin / uv / pnpm - The Implementation Plan (Decomposed and Prioritized Task List)

> 说明：本文件由 Spec Mode 生成，用于跟踪任务进度。每完成一个子任务立即更新对应 checkbox 与 [checklist.md](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.trae/specs/providers-kotlin-uv-pnpm/checklist.md)。

## [x] Task 1: 扩展 RuntimeKind 与品牌元数据以支持 Kotlin
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 在 [RuntimeKind.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/RuntimeKind.swift) 追加 `case kotlin`，同步 `displayName` 返回 `"Kotlin"`、`binaryName` 返回 `"kotlinc"`。
  - 在 [RuntimeKind+Branding.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/RuntimeKind+Branding.swift) 追加 `initial`、`iconName`、`brandColor` 分支（推荐 Kotlin 紫 `Color(red:0.44, green:0.32, blue:0.98)`；icon `"k.square"`）。
- **Acceptance Criteria Addressed**: AC-1
- **Test Requirements**:
  - `programmatic` TR-1.1：`RuntimeKind.allCases.contains(.kotlin) == true`。
  - `programmatic` TR-1.2：`RuntimeKind.kotlin.binaryName == "kotlinc"`、`displayName == "Kotlin"`。
  - `programmatic` TR-1.3：调用 `RuntimeKind.kotlin.iconName / brandColor / initial` 不 crash 且非默认值。
- **Notes**：更新 `RuntimeKindTests.swift` 中的枚举断言（若有 caseCount 校验）。

## [x] Task 2: 实现 KotlinProvider（GitHub Releases 解码 + 网络错误处理）
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 新建 [KotlinProvider.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/Providers/KotlinProvider.swift)，实现 `VersionProvider`；GET `https://api.github.com/repos/JetBrains/kotlin/releases?per_page=30`。
  - 暴露 `internal static func decode(data:) throws -> [RuntimeVersion]`：跳过 `prerelease == true` 与 `draft == true`；从 `assets[]` 中匹配 `kotlin-compiler-*.zip`，得到 `downloadURL`；`version = tag_name.dropFirst("v")`。
  - 在 [RuntimeService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/RuntimeService.swift#L64-L76) 的默认 provider 字典追加 `defaults[.kotlin] = KotlinProvider()`。
- **Acceptance Criteria Addressed**: AC-2, AC-3
- **Test Requirements**:
  - `programmatic` TR-2.1：新增 `KotlinProviderDecodingTests.swift`，用 6 条 fixture（含 2 prerelease + 1 draft）验证返回恰好 3 条。
  - `programmatic` TR-2.2：解码结果的 `downloadURL` 均包含 `kotlin-compiler-` 与 `.zip`。
  - `programmatic` TR-2.3：非法 JSON 抛 `RuntimeServiceError.decoding`；HTTP 500 抛 `RuntimeServiceError.network`（用注入的 URLProtocol mock）。
- **Notes**：GitHub API 匿名限流；provider 内 `URLRequest` 应 `setValue("EnvMatrix", forHTTPHeaderField: "User-Agent")`。

## [x] Task 3: 侧边栏 & Dashboard 接入 Kotlin
- **Priority**: P0
- **Depends On**: Task 1, Task 2
- **Description**:
  - 在 [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 的 `systemImage`、`allSections` "nav.devEnvironments" 中追加 `.devEnv(.kotlin)`（配 `"k.square"`）。
  - 校验 [DashboardView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Dashboard/DashboardView.swift) 是否遍历 `RuntimeKind.allCases`；若是，无需改动，否则手动添加 Kotlin 卡片。
- **Acceptance Criteria Addressed**: AC-1
- **Test Requirements**:
  - `human-judgment` TR-3.1：启动应用后侧边栏"开发运行时"分组能看到 Kotlin。
  - `human-judgment` TR-3.2：Dashboard 显示 Kotlin 卡片；点击后跳到 Runtime Detail 三分栏无报错。

## [x] Task 4: 新增 uv 数据模型与 UvService
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 新建 [UvRepository.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/UvRepository.swift)：`UvRegistryPreset`、`UvTool`、`UvCacheStats`。
  - 新建 [UvService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/UvService.swift)：`isAvailable() / currentRegistry() / setRegistry(preset:) / listGlobalTools() / uninstallTool(name:) / cacheStats() / cacheClean()`。
  - 备份走 [BackupService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/BackupService.swift)。
  - 内部解析函数抽为 `internal static`，接收 stdout 字符串。
- **Acceptance Criteria Addressed**: AC-4, AC-5, AC-8
- **Test Requirements**:
  - `programmatic` TR-4.1：`UvService.parseToolList(stdout:)` 对已知 fixture（3 个 tool，其中 1 个带 sub-entries）返回 3 条。
  - `programmatic` TR-4.2：`UvService.setRegistry(_:)` 在临时目录中生成带时间戳后缀的 `uv.toml.*.bak` 且写入后 `currentRegistry()` 返回新 URL。
  - `programmatic` TR-4.3：CLI 缺失时 `isAvailable() == false` 且其他方法抛错而不 crash。

## [x] Task 5: uv ViewModel + View + Missing 空态
- **Priority**: P1
- **Depends On**: Task 4
- **Description**:
  - 新建 [UvRegistryViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/UvRegistryViewModel.swift) / [UvGlobalToolsViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/UvGlobalToolsViewModel.swift) / [UvCacheViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/UvCacheViewModel.swift)。
  - 新建 [UvRepositoryView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/UvRepositoryView.swift)（3 Tab）+ [UvMissingView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/UvMissingView.swift)。
  - 在 [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 追加 `case packagesUv`。
- **Acceptance Criteria Addressed**: AC-4, AC-5, AC-8
- **Test Requirements**:
  - `human-judgment` TR-5.1：uv 页面 3 Tab 布局与 [PythonRepositoryView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/PythonRepositoryView.swift) 对齐；空态视觉一致。
  - `programmatic` TR-5.2：ViewModel 在 mock service 下测试 `applyPreset` / `refreshTools` / `uninstall` 的状态迁移（loading→data / error）。

## [x] Task 6: 新增 pnpm 数据模型与 PnpmService
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 新建 [PnpmRepository.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/PnpmRepository.swift)：`PnpmRegistryPreset`、`PnpmGlobalPackage`、`PnpmStoreStats`。
  - 新建 [PnpmService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/PnpmService.swift)：`isAvailable / currentRegistry / setRegistry / listGlobalPackages / uninstallGlobal / storeStats / storePrune`。
  - 复用 [NpmService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/NpmService.swift) 的 `findBinary` 模式。
  - 备份 `~/.npmrc` 之前通过 BackupService。
- **Acceptance Criteria Addressed**: AC-6, AC-7, AC-8
- **Test Requirements**:
  - `programmatic` TR-6.1：`PnpmService.parseGlobalPackages(json:)` 解析 fixture（含 `dependencies` 空对象与 3 个包）返回 3 条。
  - `programmatic` TR-6.2：`PnpmService.parseStorePath(stdout:)` 剔除尾部换行、tab。
  - `programmatic` TR-6.3：CLI 缺失时 `isAvailable() == false`。

## [x] Task 7: pnpm ViewModel + View + Missing 空态
- **Priority**: P1
- **Depends On**: Task 6
- **Description**:
  - 新建 [PnpmRegistryViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/PnpmRegistryViewModel.swift) / [PnpmGlobalPackagesViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/PnpmGlobalPackagesViewModel.swift) / [PnpmStoreViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/PnpmStoreViewModel.swift)。
  - 新建 [PnpmRepositoryView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/PnpmRepositoryView.swift) + [PnpmMissingView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/PnpmMissingView.swift)。
  - 在 [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 追加 `case packagesPnpm`。
- **Acceptance Criteria Addressed**: AC-6, AC-7, AC-8
- **Test Requirements**:
  - `human-judgment` TR-7.1：pnpm 页面视觉与 npm 页面一致（3 Tab、preset segmented picker、卸载二次确认）。
  - `programmatic` TR-7.2：ViewModel 状态迁移测试（loading→data / error）。

## [x] Task 8: i18n 双语 key 完整登记 + 对称性测试
- **Priority**: P0
- **Depends On**: Task 1, Task 4, Task 6
- **Description**:
  - 在 [Localization+En.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 与 [Localization+Zh.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) 添加所有新 key（`nav.kotlin` / `nav.uvRepo` / `nav.pnpmRepo` / `uv.*` / `pnpm.*`）。
  - 若命名空间过大，拆分为 [Localization+PackagesExtra.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization+PackagesExtra.swift) 的扩展。
  - 新建 `LocalizationSymmetryTests.swift`（或在现有 tests 中新增一个）断言两侧 key 集合相等。
- **Acceptance Criteria Addressed**: AC-9
- **Test Requirements**:
  - `programmatic` TR-8.1：`Set(enUv.keys) == Set(zhUv.keys)`、`Set(enPnpm.keys) == Set(zhPnpm.keys)`。
  - `programmatic` TR-8.2：`L("nav.kotlin")` / `L("nav.uvRepo")` / `L("nav.pnpmRepo")` 均非空。

## [x] Task 9: DetailView / DashboardView 路由接入新 Nav 项
- **Priority**: P1
- **Depends On**: Task 5, Task 7
- **Description**:
  - 在 [DetailView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/DetailView.swift) 的 switch 分支中路由 `.packagesUv` → `UvRepositoryView`、`.packagesPnpm` → `PnpmRepositoryView`、`.devEnv(.kotlin)` 复用现有 `RuntimeDetailView`。
  - Dashboard 若有 packages 卡片列表（如 [DashboardPackageCard.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Dashboard/DashboardPackageCard.swift)），追加 uv/pnpm 卡片并可点击跳转。
- **Acceptance Criteria Addressed**: AC-1, AC-4, AC-6
- **Test Requirements**:
  - `human-judgment` TR-9.1：从 Dashboard 点击 uv/pnpm 卡片能正确跳转对应 View；侧边栏 uv/pnpm 条目可点击展示 View。

## [x] Task 10: 全量测试与 lint 通过
- **Priority**: P0
- **Depends On**: Task 1–9
- **Description**:
  - 运行 `swift build`、`swift test`、`./scripts/check_file_lines.sh`、`.swiftlint`（若 CI 使用）。
  - 修复所有失败测试与 lint 报错；确保测试数量比基线（≥242）多至少 8。
- **Acceptance Criteria Addressed**: AC-10
- **Test Requirements**:
  - `programmatic` TR-10.1：`swift test 2>&1 | tail -20` 显示 `Test Suite ... passed`。
  - `programmatic` TR-10.2：`check_file_lines.sh` 输出 0 个 > 500 行文件。

