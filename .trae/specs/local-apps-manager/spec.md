# Local Apps Manager - Product Requirement Document

## Overview
- **Summary**: 在 EnvMatrix 中新增「本地软件 APP 管理」模块。扫描 `/Applications` 与 `~/Applications` 下已安装的 macOS 应用（.app bundle），提取名称、版本、Bundle ID、大小、来源（Brew Cask / Mac App Store / 手动）、图标等元信息，并支持：打开应用、在 Finder 中显示、移动到废纸篓卸载、扫描并清理残余（`~/Library/{Preferences,Caches,Application Support,Logs,Saved Application State}` 中匹配 Bundle ID 的目录）。
- **Purpose**: 弥补现有 Homebrew 模块仅面向 CLI 层面的空白，让用户在同一应用内一站式盘点系统上真正安装的 GUI 应用，并按来源分组辅助卸载决策，杜绝"拖入废纸篓仍留下几百 MB 残余"的常见痛点。
- **Target Users**: macOS 开发者与 Power User，尤其是需要定期整理磁盘、追踪多渠道安装（brew cask、DMG 手动拖入、App Store）的用户。

## Goals
- 一屏枚举本机已安装的 macOS 应用，展示核心元信息（名称/版本/Bundle ID/大小/来源/位置/图标）。
- 支持按来源筛选：Brew Cask、Mac App Store、手动安装（Other）。
- 支持关键字搜索（名称 / Bundle ID）。
- 支持"打开应用 / 在 Finder 中显示 / 移到废纸篓"三类操作。
- 卸载后扫描 `~/Library` 相关目录列出残余候选，用户勾选后二次确认再一并删除。
- 与既有 System 分组、双语本地化、备份、异步 IO、MVVM + DI 架构保持一致。

## Non-Goals (Out of Scope)
- 不做 Login Items / Launch Agents 的可视化管理（后续可迭代）。
- 不做应用升级检测（brew upgrade / MAS 更新已由系统或 Homebrew 模块覆盖）。
- 不接管系统级 `/System/Applications`（Apple 官方应用，只读只展示）。
- 不做进程杀掉 / Activity Monitor 类能力。
- 不涉及签名 / 公证 / 权限（TCC）审计。
- 不做 iOS/iPadOS "Designed for iPad" 应用识别。

## Background & Context
- 项目采用 SwiftUI + Swift Concurrency + MVVM + 依赖注入，Service 层暴露 protocol 便于测试（参见 [HomebrewService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/HomebrewService.swift)、[HostsService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/HostsService.swift)）。
- 侧边栏由 [AppNavigation.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift) 集中定义，System 分组已含 `.systemShellEnv` / `.systemHosts`。
- 双语文案落地在 [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) / [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift)，硬编码字符串禁止直接写入 UI。
- 单文件不超过 500 行；测试落在 [Tests/EnvMatrixTests](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Tests/EnvMatrixTests)。

## Functional Requirements
- **FR-1**: 扫描 `/Applications` 与 `~/Applications` 下 `*.app` 目录（含一级子目录如 `/Applications/Utilities`），解析每个 bundle 的 `Info.plist`，抽取 `CFBundleName` / `CFBundleDisplayName` / `CFBundleShortVersionString` / `CFBundleVersion` / `CFBundleIdentifier` / `CFBundleIconFile`。
- **FR-2**: 计算每个 .app bundle 的磁盘占用（递归 `allocatedSize`）。
- **FR-3**: 识别 App 来源：存在 `Contents/_MASReceipt/receipt` → `.appStore`；否则查询 `brew list --cask --versions` 输出，命中的对应 Cask token → `.brewCask`；其余标记为 `.other`。
- **FR-4**: 提供关键字搜索（大小写不敏感，匹配名称与 Bundle ID）、按来源筛选（All / Brew / App Store / Other）、按名称/大小/来源排序。
- **FR-5**: 支持"打开应用"（`NSWorkspace.open`）、"在 Finder 中显示"（`NSWorkspace.activateFileViewerSelecting`）。
- **FR-6**: 支持"移到废纸篓"：调用 `FileManager.trashItem(at:resultingItemURL:)`，二次确认后执行；系统受保护路径（`/System/Applications`、`/Applications/Utilities` 中的 Apple 预装应用如 `Terminal.app`）禁止操作，UI 展示灰化提示。
- **FR-7**: 卸载完成后启动残余扫描：在 `~/Library/Preferences`、`~/Library/Caches`、`~/Library/Application Support`、`~/Library/Logs`、`~/Library/Saved Application State`、`~/Library/Containers`、`~/Library/Group Containers` 中查找路径名包含目标 Bundle ID 的文件/目录，展示列表 + 大小，允许勾选删除，二次确认后一并 `trashItem`。
- **FR-8**: 全部 IO 在后台线程（`Task.detached(priority: .utility)`）执行，UI 主线程零阻塞。
- **FR-9**: 侧边栏 `System` 分组新增 `.systemLocalApps` 入口，图标 `app.badge.checkmark`。
- **FR-10**: 中英文本地化 key 完整覆盖（`nav.localApps`、`localApps.title` 等）。

## Non-Functional Requirements
- **NFR-1**: 扫描 200 个应用应在 5 秒内完成（Apple Silicon，SSD）；使用并发 `TaskGroup` 分批解析 Info.plist。
- **NFR-2**: `~/Library` 残余扫描避免全盘 spotlight，采用按目录 + 名称匹配的 O(N) 遍历，深度限制为 3 层，单次扫描超 3 秒时提前返回已发现结果。
- **NFR-3**: 所有 UI 文案通过 `L("...")` 落到 [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 与 [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift)，禁止硬编码。
- **NFR-4**: 单个源文件不超过 500 行；违反将拆分。
- **NFR-5**: 单元测试覆盖 Service 解析逻辑（Info.plist、来源识别、残余匹配），使用 `FileManager` 临时目录构造 fixture，禁止依赖真机 `/Applications`。
- **NFR-6**: 危险操作（移动到废纸篓、删除残余）必须二次确认，且默认按钮为「取消」。

## Constraints
- **Technical**: 
  - SwiftUI + Swift Concurrency
  - macOS 13+
  - 不使用私有 API；MAS 识别仅依赖 `_MASReceipt` 存在性（不解析证书）
  - `brew list --cask --versions` 依赖用户已安装 brew；未安装时降级为「未识别」且不阻塞其它来源识别
- **Business**: 无
- **Dependencies**: 现有 [Shell.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils) 命令执行封装、[HomebrewService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/HomebrewService.swift)（可选注入以复用 brewPath）

## Assumptions
- 用户具备对 `/Applications` 与 `~/Applications` 的常规读权限。
- 磁盘占用统计允许存在 <5% 的误差（不同 FS 场景 allocatedSize 与 totalSize 略有差异）。
- 用户理解"移动到废纸篓"仍可从系统回收站恢复，Trash 由 macOS 管理。
- brew 未安装时接受来源标记为 `.other`。

## Acceptance Criteria

### AC-1: 应用列表可枚举并展示核心元信息
- **Given**: 用户在 `/Applications` 下存在 `Safari.app`、`Xcode.app`、`Foo.app` 三个 bundle
- **When**: 打开侧边栏 System → Local Apps
- **Then**: 列表展示上述 3 项，每项显示 name、version、bundleId、size（如 "12.3 MB"）、source badge、icon
- **Verification**: `programmatic`

### AC-2: 来源识别正确
- **Given**: `Xcode.app` 存在 `Contents/_MASReceipt/receipt`；`Foo.app` 无 receipt 且 `brew list --cask --versions` 输出中含 `foo 1.0`；`Bar.app` 二者皆无
- **When**: 扫描完成
- **Then**: 三者分别标记为 `.appStore` / `.brewCask` / `.other`
- **Verification**: `programmatic`

### AC-3: 关键字搜索与来源筛选
- **Given**: 列表包含 20 个应用
- **When**: 在搜索框输入 "xcod" 并将来源筛选设为 App Store
- **Then**: 只显示名称或 Bundle ID 匹配 "xcod" 且来源为 App Store 的应用
- **Verification**: `programmatic`

### AC-4: 打开应用与在 Finder 中显示
- **Given**: 选中某个应用
- **When**: 点击「Open」/「Reveal in Finder」
- **Then**: 分别调用 `NSWorkspace.open(URL)` 与 `NSWorkspace.activateFileViewerSelecting([URL])`，不抛异常
- **Verification**: `human-judgment`
- **Notes**: 抽象为 `AppLauncher` 协议，测试用 mock；真机场景由 reviewer 手动验证

### AC-5: 移到废纸篓需要二次确认
- **Given**: 选中一个可卸载的应用
- **When**: 点击「Move to Trash」
- **Then**: 弹出确认对话框，默认按钮为「取消」；确认后调用 `FileManager.trashItem`，成功后列表刷新
- **Verification**: `programmatic` + `human-judgment`

### AC-6: 系统受保护应用禁止卸载
- **Given**: 选中 `/System/Applications` 下的应用，或 `/Applications/Utilities` 中受保护的 Apple 应用（例：Terminal.app、Console.app）
- **When**: 查看操作按钮
- **Then**: 「Move to Trash」按钮禁用，Tooltip 提示 "System-managed app cannot be removed"
- **Verification**: `programmatic`

### AC-7: 卸载后残余扫描
- **Given**: 应用 `com.example.foo` 已通过本模块卸载，且 `~/Library/Preferences/com.example.foo.plist` 与 `~/Library/Application Support/Foo/` 存在
- **When**: 卸载成功后触发残余扫描
- **Then**: 弹出残余清单，包含上述两条，各显示相对路径与大小；勾选并二次确认后调用 `trashItem` 移除
- **Verification**: `programmatic`

### AC-8: 全异步无 UI 阻塞
- **Given**: 系统安装了 100+ 应用
- **When**: 打开 Local Apps 页面
- **Then**: 主线程保持响应（可继续点击其它侧边栏项），扫描期间显示 loading indicator
- **Verification**: `human-judgment`

### AC-9: 完整双语本地化
- **Given**: 切换应用语言为中文 / English
- **When**: 打开 Local Apps 页面
- **Then**: 侧边栏、标题、按钮、确认对话框、空状态文案均随语言切换而变化，且英文/中文键值一一对应
- **Verification**: `programmatic`

### AC-10: 单元测试覆盖 Service 层
- **Given**: 项目根目录执行 `swift test --filter LocalApps`
- **When**: 测试运行
- **Then**: LocalAppsScannerTests / LocalAppsServiceTests / LocalAppsViewModelTests 全部通过
- **Verification**: `programmatic`

## Open Questions
- [ ] 是否需要展示应用签名者 / Team ID？（当前先不做，后续按需迭代）
- [ ] 是否需要按 App 分组显示 Container 大小（`~/Library/Containers/<bundle-id>`）作为运行时占用？（当前归入残余扫描）
- [ ] 卸载 Brew Cask 时是否直接调用 `brew uninstall --cask <token>` 而非 `trashItem`？（当前一律 `trashItem`，后续可加"Uninstall via brew"分支）
