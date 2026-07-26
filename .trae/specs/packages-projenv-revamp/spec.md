# 包管理与项目环境 完整迭代优化 - Product Requirement Document

## Overview
- **Summary**: 对 EnvMatrix 应用中"包管理"侧边栏分组与"项目环境"功能模块进行一次完整的产品级迭代。重点包括：重构信息架构（Information Architecture, IA）以消除概念层级混乱；统一"XX 仓库"命名与图标视觉语言；将「项目环境」从当前只覆盖 Python venv / node_modules 的最小可用状态，升级为覆盖多语言、支持排序/健康度/聚合/批量清理的一体化"项目本地环境清理中心"。
- **Purpose**: 当前侧边栏「包管理」把 3 个不同抽象层（系统包管理器 Homebrew / 语言全局仓库 / 项目局部环境）平铺为 10 个并列项，用户认知负担大、命名歧义（"XX 仓库" ≠ Repository/Registry/Cache）；「项目环境」仅覆盖两种类型、缺排序/健康度/批量能力，无法真正解决"电脑硬盘被历史项目吃满"的核心用户痛点。本次迭代要打通信息架构、视觉一致性、功能完整性三层问题。
- **Target Users**:
  - 拥有多个语言项目的本机开发者（macOS）
  - 定期需要清理老旧项目、回收硬盘空间的开发者
  - 需要在多语言技术栈中快速切换全局镜像/查看全局包的开发者

## Goals
- G1: 侧边栏「包管理」重组为分层清晰的结构，用户能一眼分辨"系统级 / 语言全局 / 项目本地"三个抽象层。
- G2: "XX 仓库" 类命名与图标视觉统一，消除"Repository / Registry / Cache"歧义。
- G3: 「项目环境」扩展扫描能力，覆盖至少 6 种典型高占用目录（Python venv、node_modules、Rust `target`、Xcode `DerivedData`、Gradle `.gradle`、Maven `target`）。
- G4: 「项目环境」列表支持按体积/修改时间排序，且默认展示"最值得清理"的一屏。
- G5: 「项目环境」为每个条目打健康度标签（活跃 / 闲置 / 废弃），帮助用户识别可安全清理项。
- G6: 「项目环境」顶部提供总览卡（总数量、可回收空间、废弃项数量、一键清理废弃项入口）。
- G7: 「项目环境」支持列表多选与批量删除（移入回收站）。
- G8: 全部功能落地后 `swift build` 通过，无新增编译警告。
- G9: 中英文本地化字典对齐补齐，无 Missing Key。

## Non-Goals (Out of Scope)
- 不重写 Ruby / Rust / PHP / .NET 详情页现有 Tab 结构（当前实现已可用，仅微调）。
- 不引入网络后端或云端同步功能。
- 不做 Dashboard 卡片联动（列为后续迭代）。
- 不做 Python venv 的"根据 requirements 一键重建"功能（列为后续迭代）。
- 不引入 SwiftData/CoreData 等新持久化框架，配置仍走 UserDefaults。
- 不做自动定时后台扫描（本次仅支持"进入页面时"或"手动刷新"）。
- 不改动「开发环境」「AI 环境」「系统」三大分组的现有结构与文案。
- 不引入新的第三方依赖。

## Background & Context
- 项目为 macOS SwiftUI 桌面应用，使用 Swift Package Manager，源码根目录 [Sources/EnvMatrix](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix)。
- 导航单一数据源：[AppNavigation.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift)（`NavigationItem` 枚举 + `allSections`）。
- 路由分发：[DetailView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/DetailView.swift)。
- 项目环境模型/扫描/操作已有：[ProjectEnv.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Models/ProjectEnv.swift) / [ProjectEnvScanner.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ProjectEnvScanner.swift) / [ProjectEnvOperations.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ProjectEnvOperations.swift) / [ProjectEnvViewModel.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/ViewModels/ProjectEnvViewModel.swift) / [ProjectEnvView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/Packages/ProjectEnvView.swift)。
- 本地化通过 [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) / [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 硬编码字典。
- 硬约束（来自 `project_memory.md`）：
  - View 根元素不得使用 `.id(localization.language)`；
  - Scan/Size 计算必须走后台线程；
  - `ProjectEnvScanner.inspect` 需显式 `Self.` 前缀；
  - 窗口最小 820×620、默认 1120×720。

## Functional Requirements
- **FR-1（IA 重构）**: [NavigationItem.allSections](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift#L107-L128) 中「包管理」分组拆分为两个语义化的分组：
  - `nav.packagesSystem`（系统包管理）：仅含 `packagesBrew`。
  - `nav.packagesLangs`（语言全局仓库）：含 `packagesMaven`、`packagesGo`、`packagesNode`、`packagesPython`、`packagesRuby`、`packagesRust`、`packagesPhp`、`packagesDotnet`。
  - `packagesProjectEnv` 从「包管理」中分离，独立为顶层分组 `nav.projectEnvGroup` 或并入语言全局仓库之下的专属分区（本 spec 采用独立顶层分组方案，更符合"项目本地 vs 语言全局"的层级对照）。
- **FR-2（命名统一）**: 中英文文案将"XX 仓库"归一为"XX 全局环境"（Zh）/"XX Global"（En），并在语言全局仓库分组标题中体现此层级；Homebrew 项文案与图标不变，但归属显式为系统级；`nav.projectEnv` 更名为「项目本地环境」/"Project Environments"。
- **FR-3（图标一致性）**: 语言全局仓库分组下的 8 项统一采用同系列图标（`shippingbox.*` 系列或 `cylinder.*` 系列），保持形状一致，仅通过前景色区分（Node 蓝、Python 紫、Java 橙、Go 青、Rust 棕橙、Ruby 红、PHP 蓝紫、.NET 深紫）。Homebrew 保留 `cube.box.fill`，项目环境保留 `folder.badge.gearshape`。
- **FR-4（扫描扩展）**: [ProjectEnvKind](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Models/ProjectEnv.swift#L10-L23) 新增枚举分支：`.rustTarget` / `.xcodeDerivedData` / `.gradleCache` / `.mavenTarget`。扫描器 [ProjectEnvScanner](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ProjectEnvScanner.swift) 新增对应检测函数：
  - Rust `target`：目录名为 `target` 且同级或上级存在 `Cargo.toml`。
  - Xcode DerivedData：路径为 `~/Library/Developer/Xcode/DerivedData/*`（作为特殊根，用户可通过设置开启/关闭）。
  - Gradle `.gradle`：目录名为 `.gradle` 且同级存在 `build.gradle` 或 `build.gradle.kts` 或 `settings.gradle*`。
  - Maven `target`：目录名为 `target` 且同级存在 `pom.xml`。
  - **注意**：需将当前 `skipDirNames` 中的 `target`、`.gradle` 移除或改为条件跳过，否则永远扫不到。
- **FR-5（排序）**: 「项目环境」列表新增排序控件（Menu 或 Segmented），支持：
  - 体积降序（默认）
  - 体积升序
  - 修改时间升序（最久未用在前）
  - 修改时间降序
- **FR-6（健康度）**: 基于 `modifiedAt` 与当前日期计算健康度标签：
  - `<= 30 天`：活跃（绿点）
  - `31–180 天`：闲置（黄点）
  - `> 180 天` 或 `modifiedAt == nil`：废弃（灰点 + 醒目底纹）
  - 标签展示在列表行末尾、详情页顶部。
- **FR-7（总览卡）**: 顶部 header 追加一行"回收总览"区，展示：
  - 环境总数
  - 可回收总空间（`totalBytes`）
  - 废弃项数量 + 废弃项体积
  - 一键"清理所有废弃项"按钮（点击弹二次确认 Sheet，展示将被移入回收站的路径列表，确认后并行删除）。
- **FR-8（多选批量）**: List 支持多选（`selection: Set<String>`），工具栏在有选中项时显示"删除选中 (X GB)"按钮，点击弹二次确认后批量移入回收站。
- **FR-9（本地化）**: 所有新增字符串键必须在 [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) 与 [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 中同时补齐，命名遵循现有 `projenv.*` / `nav.*` 前缀。
- **FR-10（编译通过）**: 全部改动完成后 `swift build` 无报错、无新增警告。

## Non-Functional Requirements
- **NFR-1（性能）**: 扫描器新增 4 种检测不得使单次扫描时长在 100 项目、平均深度 4 的场景下超过 5s（macOS SSD，M 系列）。
- **NFR-2（响应性）**: 排序切换、多选、健康度计算必须在主线程完成 ≤ 16ms/帧（visibleEnvironments 派生属性 O(n log n) 可接受）。
- **NFR-3（安全性）**: 所有批量删除路径必须走 `NSWorkspace.recycle`（回收站），不使用 `FileManager.removeItem` 直接删除。DerivedData 是唯一例外：若用户显式开启，允许移入回收站。
- **NFR-4（可复现）**: 扫描结果对同一根目录多次调用需一致（除时间戳）。
- **NFR-5（可用性）**: 空态、扫描态、错误态均有明确 UI 表达。

## Constraints
- **Technical**:
  - Swift 5 Concurrency，`@MainActor` 隔离；避免捕获 `FileManager`/`RuntimeService` 等非 Sendable 类型到 Sendable 闭包（依据 `project_memory.md` 教训）。
  - 遵守窗口最小尺寸与 NavigationSplitView 宽度约束。
  - 不引入新第三方依赖。
- **Business**:
  - 单次迭代交付，不做灰度。
- **Dependencies**:
  - 现有 [ProjectEnvOperations](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ProjectEnvOperations.swift) 的 `moveToTrash`。
  - 现有 [ByteFormatter](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Models/ProjectEnv.swift#L157-L165)。

## Assumptions
- 用户机器为 macOS，桌面环境有回收站可用。
- 用户拥有对项目根目录的读写权限；DerivedData 归当前用户所有。
- 现有 Ruby/Rust/PHP/.NET 详情页 Tab 结构无需重做。
- 现有 Node/Python/Maven 详情页 Tab 结构无需重做。
- 用户能接受"进入页面时扫描 / 手动刷新"的策略（非后台预扫）。

## Acceptance Criteria

### AC-1: 侧边栏分组重构
- **Given**: 用户打开 App
- **When**: 查看左侧 Sidebar
- **Then**: 「包管理」不再是单一分组；应看到：`系统包管理`（含 Homebrew）、`语言全局环境`（含 Maven/Go/Node/Python/Ruby/Rust/PHP/.NET）、`项目本地环境`（含 项目环境项）三个独立 Section，顺序在 `开发环境` 之后、`AI 环境` 之前。
- **Verification**: `human-judgment`
- **Notes**: 各 Section 内部顺序与原始一致，不引入排序变化。

### AC-2: 命名统一
- **Given**: 用户切换到中文
- **When**: 查看语言全局仓库分组下的 8 项
- **Then**: 全部显示为"XX 全局环境"格式（例："Node 全局环境"），不再出现"XX 仓库"字样；项目环境项显示为"项目本地环境"。
- **Verification**: `programmatic`
- **Notes**: 英文侧对应 "XX Global" / "Project Environments"。

### AC-3: 图标视觉一致
- **Given**: 用户查看语言全局仓库分组
- **When**: 观察 8 项图标
- **Then**: 8 项图标统一为同一形状族（`shippingbox.*` 或 `cylinder.*`）；用户能感知"这是一组同类项"。
- **Verification**: `human-judgment`
- **Notes**: 前景色由 `RuntimeKind+Branding` 中现有色卡驱动。

### AC-4: 扫描扩展到 6 种类型
- **Given**: 用户项目根目录下有一个 Rust 项目（含 `Cargo.toml` 与 `target/`）和一个 Maven 项目（含 `pom.xml` 与 `target/`）
- **When**: 点击"重新扫描"
- **Then**: 列表中出现对应的 `rustTarget` 与 `mavenTarget` 条目，行标题正确、大小非零。
- **Verification**: `programmatic`
- **Notes**: 单元测试可通过临时目录 fixture 验证；亦可运行时观察。

### AC-5: 排序切换
- **Given**: 列表中已有多个环境
- **When**: 用户切换排序为"修改时间升序"
- **Then**: 列表顶部为最久未修改的条目；再切换回"体积降序"时列表恢复为体积最大者在前。
- **Verification**: `programmatic`
- **Notes**: 通过 ViewModel 层单元测试 `visibleEnvironments` 排序结果验证。

### AC-6: 健康度标签
- **Given**: 列表中包含 modifiedAt 分别为 10 天前、90 天前、400 天前的三个条目
- **When**: 用户查看列表
- **Then**: 三条目分别显示"活跃/闲置/废弃"三种标签，颜色区分明显。
- **Verification**: `programmatic`
- **Notes**: 通过 ViewModel 派生属性验证；UI 侧同时肉眼确认颜色。

### AC-7: 总览卡与一键清理废弃项
- **Given**: 列表中含至少 2 个"废弃"条目
- **When**: 用户点击总览卡"清理所有废弃项"
- **Then**: 弹出确认 Sheet 显示待清理路径列表；点击确认后所有废弃项被移入回收站；总览卡废弃项数量归零。
- **Verification**: `programmatic`
- **Notes**: 通过在临时目录构造 fixture 项目 + 手动 mtime 设置进行验证。

### AC-8: 多选批量删除
- **Given**: 用户在列表中按住 Cmd 键选中 3 项
- **When**: 工具栏出现"删除选中 (X GB)"按钮，用户点击并确认
- **Then**: 3 项被并行移入回收站，列表移除对应条目，`totalBytes` 相应减少。
- **Verification**: `human-judgment`
- **Notes**: 主要是交互体验的人工验证；同时可写单元测试验证 `deleteMany` 的批量语义。

### AC-9: 本地化补齐
- **Given**: 所有新增字符串键
- **When**: 应用切换到英文/中文
- **Then**: 界面上不出现原始 key（如 "projenv.sort.title"），只出现自然语言。
- **Verification**: `programmatic`
- **Notes**: 可通过 grep 交叉比对 Zh/En 字典键集合是否一致。

### AC-10: 编译通过
- **Given**: 全部改动落地
- **When**: 执行 `swift build`
- **Then**: exit code 0，无新增 warnings。
- **Verification**: `programmatic`

### AC-11: 后台线程安全
- **Given**: 扫描运行中
- **When**: 用户切换排序、切换过滤
- **Then**: 主线程 UI 不卡顿；`isScanning` 状态正确切换；无死锁。
- **Verification**: `human-judgment`

## Open Questions
- [ ] Xcode DerivedData 是否默认开启扫描？（建议：默认关闭，用户在根管理 Sheet 中显式勾选；本 spec 采用此方案）
- [ ] 一键清理废弃项是否需要"备份/导出清单"能力？（本 spec 不做，回收站已提供 undo 能力）
- [ ] 批量删除是否需要显示进度条？（本 spec：仅在项目数 > 20 时显示 ProgressView，其他并行完成后一次性刷新）
