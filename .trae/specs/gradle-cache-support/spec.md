# Gradle 全局缓存扫描 - Product Requirement Document

## Overview
- **Summary**: 在既有「Java 全局环境」页面下新增 Gradle 缓存扫描能力，覆盖 `~/.gradle/caches/modules-2` 第三方依赖与 `~/.gradle/wrapper/dists` 内的 Gradle 发行版；提供浏览、按大小排序、单项/批量移入回收站等操作。
- **Purpose**: 与 Maven 本地仓库形成完整的"Java 生态本地磁盘"视图；帮助用户回收 Gradle 长期堆积的高体积缓存（modules-2 常达数 GB、wrapper dists 每份约 200–300 MB）。
- **Target Users**: 使用 Gradle 构建工具的 Java / Kotlin / Android 开发者。

## Goals
- 支持扫描 `~/.gradle/caches/modules-2/files-2.1` 下的 (group, artifact, version) 依赖并汇总体积。
- 支持扫描 `~/.gradle/wrapper/dists/*` 下的 Gradle 发行版并汇总体积与最后使用时间。
- 提供按大小 / 时间排序、搜索过滤、单项移入回收站、批量删除等能力。
- 通过在 [MavenRepositoryView](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/Packages/MavenRepositoryView.swift) 新增第 3 个 Tab 呈现，与既有 Maven Mirrors / Maven Local Artifacts 并列。

## Non-Goals (Out of Scope)
- 不做 Gradle 镜像（init.gradle / gradle.properties）编辑；仅在未来迭代考虑只读展示。
- 不覆盖 `~/.gradle/daemon` 日志清理（价值低）。
- 不覆盖项目内 `.gradle/` 缓存（已由 [ProjectEnvScanner.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ProjectEnvScanner.swift) 的 `gradleCache` 分支处理）。
- 不做重装/重新下载 Gradle 发行版功能。

## Background & Context
- 现有 [MavenRepositoryView](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/Packages/MavenRepositoryView.swift) 已通过 `MavenTab` 枚举实现 Tab 切换（Mirrors / LocalArtifacts）。
- 现有 [MavenLocalRepositoryService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/MavenLocalRepositoryService.swift) 与 [MavenLocalRepositoryViewModel.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/ViewModels/MavenLocalRepositoryViewModel.swift) 提供 artifact 扫描、`moveToTrash`、排序等能力，可作为 Gradle 侧参考。
- 页面文案已在此前迭代改为「Java 全局环境」，语义天然可容纳 Gradle。

## Functional Requirements
- **FR-1**: 应用启动/用户手动刷新时，能扫描 `~/.gradle/caches/modules-2/files-2.1/<group>/<artifact>/<version>/` 三层目录并聚合成 GradleArtifact 列表。
- **FR-2**: 能扫描 `~/.gradle/wrapper/dists/gradle-*/` 目录并生成 GradleWrapperDist 列表（版本号、大小、mtime）。
- **FR-3**: Gradle Cache Tab 内以两段（Artifacts / Wrappers）展示两类数据，各自可排序（size↓ / size↑ / mtime↓ / mtime↑）。
- **FR-4**: 支持关键字过滤（Artifacts: `group:artifact` 或 `version`；Wrappers: 版本号子串匹配）。
- **FR-5**: 每一行支持右键菜单：在 Finder 中显示、移入回收站。
- **FR-6**: 支持批量选择后一键移入回收站（复用现有 Maven Artifacts 的多选模式）。
- **FR-7**: 顶部展示 Gradle Cache 总体积、Wrappers 总体积、可回收合计。
- **FR-8**: 当 `~/.gradle` 不存在时，显示友好空态提示。

## Non-Functional Requirements
- **NFR-1**: 扫描过程在后台线程执行，UI 主线程不卡顿（≤50ms 主线程时长）。
- **NFR-2**: modules-2 目录若含万级 artifact 也应在 5s 内完成扫描（Debug 构建、SSD）。
- **NFR-3**: 删除操作统一使用 `NSWorkspace.recycle(_:completionHandler:)` 或 `FileManager.trashItem`，绝不直接调用 `removeItem`。
- **NFR-4**: 单文件 Swift 源 < 500 行，符合项目架构约束。
- **NFR-5**: 本地化 Zh/En 键集合完全一致。

## Constraints
- **Technical**: SwiftUI + Swift Concurrency；沙盒未启用（App 可访问用户 Home）；仅 macOS。
- **Business**: 单迭代交付；不引入新依赖库。
- **Dependencies**: 复用 [ByteFormatter](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils)、[FileSystem.homeURL](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils)、Trash API。

## Assumptions
- 用户 Gradle 遵循默认路径 `~/.gradle`（未通过 `GRADLE_USER_HOME` 环境变量迁移）；本次迭代不检测该环境变量（后续可扩展）。
- modules-2 的三层结构 `<group>/<artifact>/<version>` 相对稳定（Gradle 6+ 沿用）。
- Wrapper dists 路径形如 `~/.gradle/wrapper/dists/gradle-8.5-all/abc123/gradle-8.5/`；识别时以 `gradle-*` 前缀的第一层目录为版本单元。

## Acceptance Criteria

### AC-1: Gradle Cache Tab 出现
- **Given**: 用户进入「Java 全局环境」页面。
- **When**: 观察顶部 Tab Picker。
- **Then**: 出现第 3 个 Tab「Gradle 缓存」/「Gradle Cache」；切换后展示 Gradle 内容区。
- **Verification**: `programmatic`

### AC-2: Artifacts 扫描
- **Given**: `~/.gradle/caches/modules-2/files-2.1/` 存在若干依赖。
- **When**: 打开 Gradle Cache Tab 或点击刷新。
- **Then**: 列表以 group:artifact 分组显示各 version 与其体积总和；总计与列表和一致。
- **Verification**: `programmatic`

### AC-3: Wrappers 扫描
- **Given**: `~/.gradle/wrapper/dists/gradle-*/` 存在若干发行版。
- **When**: 打开 Gradle Cache Tab。
- **Then**: 列表显示"gradle-X.Y.Z + 体积 + mtime"，按大小降序默认排序。
- **Verification**: `programmatic`

### AC-4: 排序与过滤
- **Given**: 已扫描出结果。
- **When**: 切换排序或输入关键字。
- **Then**: 列表根据 sortOption / searchText 实时更新。
- **Verification**: `programmatic`

### AC-5: 回收站操作
- **Given**: 用户选中一项或多项 artifact / wrapper。
- **When**: 右键"移入回收站"或点击工具栏"删除选中"。
- **Then**: 对应目录进入 Finder 回收站；列表移除；总计更新。
- **Verification**: `human-judgment`

### AC-6: 空态
- **Given**: `~/.gradle` 不存在或子目录为空。
- **When**: 打开 Gradle Cache Tab。
- **Then**: 显示"未检测到 Gradle 缓存"提示，附带"打开 Gradle 官网"链接（可选）。
- **Verification**: `human-judgment`

### AC-7: 构建
- **Given**: 全部实现完成。
- **When**: 运行 `swift build`。
- **Then**: exit 0，无新增 warning kind。
- **Verification**: `programmatic`

## Open Questions
- [ ] 是否需要检测 `GRADLE_USER_HOME` 环境变量？（本次不做，写入 Non-Goals，后续可迭代）
- [ ] 是否需要提供"打开 Gradle 官网"链接？（暂定加，AC-6 human-judgment）
