# 包管理与项目环境 完整迭代优化 - The Implementation Plan

## [x] Task 1: 侧边栏 IA 重构 —— 拆分「包管理」为三层分组
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 修改 [AppNavigation.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift) 中 `NavigationItem.allSections`：
    - 将当前单一 `nav.packages` Section 拆为：`nav.packagesSystem`（只含 `packagesBrew`）、`nav.packagesLangs`（含 Maven/Go/Node/Python/Ruby/Rust/PHP/.NET）、`nav.projectEnvGroup`（只含 `packagesProjectEnv`）。
    - 顺序：`overview → devEnvironments → packagesSystem → packagesLangs → projectEnvGroup → aiEnvironments → system`。
  - `NavigationItem` 枚举本身不变（case 保持向后兼容）。
  - 在 [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) / [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 新增 3 个键：
    - `nav.packagesSystem` = "系统包管理" / "System Packages"
    - `nav.packagesLangs` = "语言全局环境" / "Language Globals"
    - `nav.projectEnvGroup` = "项目本地环境" / "Project Environments"
- **Acceptance Criteria Addressed**: AC-1
- **Test Requirements**:
  - `programmatic` TR-1.1: `NavigationItem.allSections` 返回 6 个 Section（原为 5），且第 3/4/5 个的 title key 分别为上述三个键。
  - `human-judgment` TR-1.2: 打开 App，肉眼看到侧边栏「包管理」不再是一个单一分组，出现三个新的语义化分组，视觉分层清晰。
- **Notes**: 不改动 case 名称，避免 UserDefaults 中已保存的 `NavigationItem.id` 失效。

## [x] Task 2: 命名统一 —— "XX 仓库" → "XX 全局环境"
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 修改 Zh 字典中以下键的值：`nav.mavenRepo`、`nav.goRepo`、`nav.nodeRepo`、`nav.pythonRepo`、`nav.rubyRepo`、`nav.rustRepo`、`nav.phpRepo`、`nav.dotnetRepo`，将"XX 仓库"改为"XX 全局环境"。
  - 修改 En 字典中对应键的值为 "XX Global"（例："Node Global"）。
  - 修改 `nav.projectEnv` 中文值："项目环境" → "项目本地环境"；英文对应 "Project Environments"（若原为 "Project Env" 则改为完整词）。
  - 不改动详情页内部标题（`nodeRepo.title` 等），只改导航栏显示。
- **Acceptance Criteria Addressed**: AC-2
- **Test Requirements**:
  - `programmatic` TR-2.1: `grep -c "XX 仓库" Sources/EnvMatrix/Utils/Localization+Zh.swift` 返回 0（除详情页 title 内部）；侧边栏对应 8 个 nav 键的值均包含"全局环境"。
  - `programmatic` TR-2.2: Zh/En 两侧对应 8 个键的存在性一致，无缺失键。
- **Notes**: 详情页内部 `title` 保持"Node 仓库"这类专有称呼可，用户看到的层级是"侧边栏（全局环境）→ 详情页（仓库/Registry）"，此为设计意图。若 PM 希望完全统一亦可后续再改。

## [x] Task 3: 语言全局环境图标视觉统一
- **Priority**: P1
- **Depends On**: Task 1
- **Description**:
  - 修改 [AppNavigation.swift systemImage](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift#L63-L94) 中 `packagesMaven`、`packagesGo`、`packagesNode`、`packagesPython`、`packagesRuby`、`packagesRust`、`packagesPhp`、`packagesDotnet` 全部改为同一 SF Symbol（选用 `shippingbox.fill`）。
  - Homebrew 保留 `cube.box.fill`；ProjectEnv 保留 `folder.badge.gearshape`。
  - Sidebar 中通过 [SidebarView](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/SidebarView.swift) 的 `Label` 保持默认渲染；如需前景色可在 Task 3.5（本 Task 内联）为语言项加 `.foregroundStyle(kindColor)`。为最小改动，本任务仅统一形状，颜色差异化留待后续微调。
- **Acceptance Criteria Addressed**: AC-3
- **Test Requirements**:
  - `programmatic` TR-3.1: 上述 8 个 case 在 `systemImage` switch 中均返回 `"shippingbox.fill"`。
  - `human-judgment` TR-3.2: 打开 App，侧边栏"语言全局环境"分组的 8 项图标形状一致，视觉像"同一组产品"。
- **Notes**: 若担心失去可识别性，本 Task 只做形状统一，后续可通过 Label 自定义 style 加品牌色，不影响本次 AC。

## [x] Task 4: ProjectEnv 模型扩展 —— 4 种新类型
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 修改 [ProjectEnv.swift ProjectEnvKind](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Models/ProjectEnv.swift#L10-L23)，新增枚举分支：`rustTarget`、`xcodeDerivedData`、`gradleCache`、`mavenTarget`。
  - 补齐 `shortLabel`：分别为 "Rust target"、"Xcode DerivedData"、"Gradle cache"、"Maven target"。
  - 新增计算属性 `iconName: String` 与 `iconColor: Color`（Color 需要 SwiftUI import；模型层建议只暴露 `iconName` 与 `themeHex: String`，UI 层做 Color 转换，避免 Model 依赖 SwiftUI）。
  - **实现细节**: 因原有 `packageManager: JSPackageManager?` 与 `pythonVersion: String?` 依赖字段仅对特定类型有效，其他新类型保持它们为 nil 即可。
- **Acceptance Criteria Addressed**: AC-4（模型侧）
- **Test Requirements**:
  - `programmatic` TR-4.1: `ProjectEnvKind.allCases.count == 6`。
  - `programmatic` TR-4.2: 各新枚举的 `shortLabel` 非空且不重复。
- **Notes**: 保持 `ProjectEnvironment` 结构体字段兼容，避免破坏现有序列化/存储。

## [x] Task 5: ProjectEnvScanner 扩展扫描逻辑
- **Priority**: P0
- **Depends On**: Task 4
- **Description**:
  - 修改 [ProjectEnvScanner.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ProjectEnvScanner.swift):
    - 更新 `skipDirNames`：移除 `target`、`.gradle`，因为它们现在是要主动识别的目标；保留 `Library`、`.git` 等。
    - 新增 `detectRustTarget(at:fm:)`：当 `dir.lastPathComponent == "target"` 且父目录存在 `Cargo.toml` 时匹配。
    - 新增 `detectGradleCache(at:fm:)`：当 `dir.lastPathComponent == ".gradle"` 且父目录存在任一 `build.gradle` / `build.gradle.kts` / `settings.gradle*` 时匹配。
    - 新增 `detectMavenTarget(at:fm:)`：当 `dir.lastPathComponent == "target"` 且父目录存在 `pom.xml` 时匹配（与 Rust 同名不冲突，用父目录 sentinel 区分）。
    - Xcode DerivedData 作为特殊根：新增一个可选静态方法 `detectXcodeDerivedData(fm:) -> [ProjectEnvironment]`，扫描 `~/Library/Developer/Xcode/DerivedData/*` 一级子目录（不递归），每个子目录作为一个 `xcodeDerivedData` 条目；仅在用户显式启用时被 ViewModel 调用。
  - 与现有 `detectVenv` / `detectNodeModules` 共存，在 `inspect` 内按顺序判断：venv → nodeModules → mavenTarget → rustTarget → gradleCache。
  - 命中即返回，不再递归进入该目录（与原设计一致）。
- **Acceptance Criteria Addressed**: AC-4
- **Test Requirements**:
  - `programmatic` TR-5.1: 在 `/tmp` 下构造 fixture 目录（含 `Cargo.toml + target/`、`pom.xml + target/`、`build.gradle + .gradle/`），调用 `scanner.scan(roots:)`，返回结果包含对应三种 kind。
  - `programmatic` TR-5.2: 无 sentinel 的裸 `target/` 目录不应被识别为任何 kind。
- **Notes**: 严格保留 `Self.` 前缀调用静态方法（依据 project_memory 教训）。

## [x] Task 6: ProjectEnvViewModel —— 排序、健康度、多选、扫描增强
- **Priority**: P0
- **Depends On**: Task 4, Task 5
- **Description**:
  - 在 [ProjectEnvViewModel.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/ViewModels/ProjectEnvViewModel.swift) 中新增：
    - `enum ProjectEnvSortOption: String, CaseIterable`：`sizeDesc`、`sizeAsc`、`mtimeAsc`、`mtimeDesc`；默认 `sizeDesc`。
    - `@Published var sortOption: ProjectEnvSortOption = .sizeDesc`。
    - `@Published var selectedEnvIDs: Set<String> = []`（多选）。
    - `@Published var includeXcodeDerivedData: Bool` 持久化到 UserDefaults（key: `projenv.includeXcodeDerivedData.v1`）。
    - 新增计算属性 `visibleEnvironments`：先按 filter，再按 `sortOption` 排序。
    - 新增派生属性 `healthTag(for:) -> ProjectEnvHealth`（活跃/闲置/废弃）与 `abandonedEnvironments: [ProjectEnvironment]`。
    - 新增方法 `deleteMany(_ ids: Set<String>)`：批量并行 `moveToTrash`，失败合并 errorMessage。
    - 新增方法 `deleteAllAbandoned()`：语义等价于 `deleteMany(abandonedEnvironments.ids)`。
    - `rescan()` 内部：若 `includeXcodeDerivedData == true`，追加调用 `ProjectEnvScanner.detectXcodeDerivedData` 结果合并。
  - `ProjectEnvHealth` 定义（放 Models 或 ViewModel 内均可）：
    - `.active`（≤ 30 天，绿）
    - `.idle`（31–180 天，黄）
    - `.abandoned`（> 180 天 或 mtime 缺失，灰）
- **Acceptance Criteria Addressed**: AC-5, AC-6, AC-7, AC-8, AC-11
- **Test Requirements**:
  - `programmatic` TR-6.1: 构造 3 个环境（不同 size 与 mtime），设置 `sortOption`，验证 `visibleEnvironments` 顺序符合预期。
  - `programmatic` TR-6.2: 构造 mtime 分别为 10/90/400 天前的 3 个环境，验证 `healthTag(for:)` 返回 active/idle/abandoned。
  - `programmatic` TR-6.3: 构造 3 个环境，调用 `deleteMany`，验证 3 项从 `environments` 移除，`totalBytes` 相应更新，`selectedEnvIDs` 清空。
  - `human-judgment` TR-6.4: 主线程扫描期间 UI 无卡顿。
- **Notes**: 避免同一 `@MainActor` 里直接遍历大量文件；`deleteMany` 可用 `withThrowingTaskGroup` 并行。

## [x] Task 7: ProjectEnvView —— 排序控件 + 健康度徽标 + 总览卡 + 多选批量
- **Priority**: P0
- **Depends On**: Task 6
- **Description**:
  - 修改 [ProjectEnvView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/Packages/ProjectEnvView.swift):
    - `toolbar` 中在过滤 Picker 右侧新增排序 Menu：`Menu(sortLabel) { ForEach(ProjectEnvSortOption.allCases)... }`。
    - `header` 下新增 `overviewCard`：展示 [总数量 | 可回收总空间 | 废弃项数量 & 体积 | "清理所有废弃项" 按钮]（button 点击调 `vm.deleteAllAbandoned()` 走确认 Sheet）。
    - `envList` 改为支持多选：`List(selection: $vm.selectedEnvIDs)`，`.tag(env.id)`；当 `selectedEnvIDs` 非空时 `toolbar` 追加"删除选中 (X)"按钮。
    - `row(for:)` 尾部增加健康度小圆点 + 文字（`Circle().frame(6)` + `Text(healthLabel)`）。
    - `envDetail` 顶部（`Text(env.kind.shortLabel)` 旁）增加健康度 chip。
    - 根管理 Sheet 新增开关"扫描 Xcode DerivedData"，绑定 `vm.includeXcodeDerivedData`。
  - 新增 Sheet：`batchDeleteConfirmSheet` 显示待删除路径列表 + 总大小；`abandonedCleanupSheet` 相同结构复用。
  - 新增本地化键（详见 Task 8）。
- **Acceptance Criteria Addressed**: AC-5, AC-6, AC-7, AC-8
- **Test Requirements**:
  - `programmatic` TR-7.1: `swift build` 通过。
  - `human-judgment` TR-7.2: 打开项目环境页面，看到排序 Menu、总览卡、健康度徽标同时呈现；多选后工具栏出现批量删除按钮。
  - `human-judgment` TR-7.3: 点击"清理所有废弃项"能看到确认 Sheet 展示路径列表，确认后列表刷新。
- **Notes**: 保留原有单选详情右侧栏；多选时右侧栏可显示"已选 X 项 / Y GB"占位（避免与单选详情冲突）。

## [x] Task 8: 本地化字符串补齐
- **Priority**: P0
- **Depends On**: Task 1, Task 2, Task 6, Task 7
- **Description**:
  - 在 [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) 与 [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 中新增以下键（键名以 `projenv.` 前缀为主）：
    - `projenv.sort.title` / `.sizeDesc` / `.sizeAsc` / `.mtimeAsc` / `.mtimeDesc`
    - `projenv.health.active` / `.idle` / `.abandoned`
    - `projenv.overview.title` / `.totalCount` / `.reclaimableSpace` / `.abandonedCount` / `.cleanAbandoned`
    - `projenv.batch.delete` / `.confirmTitle` / `.confirmBody`
    - `projenv.kind.rustTarget` / `.xcodeDerivedData` / `.gradleCache` / `.mavenTarget`
    - `projenv.rootsEditor.includeXcode`（"扫描 Xcode DerivedData"）
  - Zh/En 两侧键集合必须一致。
- **Acceptance Criteria Addressed**: AC-9
- **Test Requirements**:
  - `programmatic` TR-8.1: `grep -oE '"projenv\.[^"]+"' Localization+Zh.swift | sort -u` 与 En 侧结果一致。
  - `programmatic` TR-8.2: 各页面运行时不出现原始 key（可通过肉眼检查）。
- **Notes**: 避免翻译歧义，"废弃"英文用 "Abandoned"，"闲置"用 "Idle"，"活跃"用 "Active"。

## [x] Task 9: 构建与最终验证
- **Priority**: P0
- **Depends On**: Task 1–8
- **Description**:
  - 运行 `swift build`（Debug）确认无 error / 无新增 warning。
  - 启动 App，进入侧边栏、项目环境页，逐项肉眼确认所有 AC。
  - 如出现死锁/闪退/编译错误，回归到具体 Task 修复。
- **Acceptance Criteria Addressed**: AC-10, AC-11
- **Test Requirements**:
  - `programmatic` TR-9.1: `swift build` exit code 0，stderr 中无 `warning:` 新增行（对照本次改动之前的基线）。
  - `human-judgment` TR-9.2: 应用启动、导航、扫描、排序、删除完整链路无异常。
- **Notes**: 若发现 UI 与 spec 不一致，返回对应 Task 修改后再回到本 Task。
