# Go & Node 包管理 - Product Requirement Document

## Overview
- **Summary**: 在 EnvMatrix 中新增两个与现有 Maven 仓库管理平级的包管理模块——Go 与 Node。Go 模块聚焦 `GOMODCACHE` 本地依赖清理和 `GOPROXY` 镜像切换；Node 模块聚焦 npm registry 镜像管理、全局包管理与 npm cache 清理。所有功能通过 SwiftUI 侧栏入口接入，复用现有 `NavigationItem` / `DetailView` 路由与本地化基础设施。
- **Purpose**: 目前项目仅提供 Homebrew 与 Maven 两类包管理入口，而 Go 与 Node 是本机常见的两类"下载体积大 + 需要国内镜像加速"的生态，用户需要一致的 UI 来清理本地依赖缓存并切换镜像。
- **Target Users**: 使用 EnvMatrix 的 macOS 开发者，尤其是从事 Go 或 Node.js 开发、经常受国内网络限制困扰、需要定期清理磁盘空间的开发者。

## Goals
- 在侧栏 `包管理` 分组下新增 **Go 仓库** 与 **Node 仓库** 两个独立入口。
- Go 模块实现：（a）扫描 `GOMODCACHE`（默认 `~/go/pkg/mod`）中的 module + 版本，支持按大小/名称排序、搜索、删除；（b）读取和写入 `go env` 中的 `GOPROXY`，提供常用国内镜像（`goproxy.cn`、`goproxy.io`、阿里云、腾讯云）一键切换。
- Node 模块实现：（a）读写 `~/.npmrc` 中的 `registry`，提供常用镜像（`npmmirror`、腾讯、华为、npm 官方）一键切换；（b）扫描 `npm root -g` 目录，列出全局包，支持卸载；（c）显示 `~/.npm/_cacache` 大小，提供一键 `npm cache clean --force`。
- 完整支持中英双语，与现有 `Localization.swift` 保持一致的 key 命名规范（`goRepo.*`、`nodeRepo.*`）。
- 与 Maven 相同的分层结构：`Models/` + `Services/` + `ViewModels/` + `Views/Packages/`。

## Non-Goals (Out of Scope)
- 不管理 Go 或 Node 的运行时版本本身（这已由现有 `RuntimeDetailView` / `GoProvider` / `NodeProvider` 覆盖）。
- 不支持 `yarn` / `pnpm` 的 registry 与全局包管理（用户已明确本次仅覆盖 npm）。
- 不支持 `GOSUMDB` / `GOPRIVATE` 复杂通配符设置（本次仅 GOPROXY + GOMODCACHE）。
- 不实现"批量下载/预下载"依赖包功能，仅做已下载依赖的**查看与清理**。
- 不做磁盘空间趋势可视化或历史统计。

## Background & Context
- 项目位于 [EnvMatrix](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix)，Swift Package + SwiftUI，macOS App。
- 现有包管理入口通过 [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 的 `NavigationItem` 定义，`packagesBrew` / `packagesMaven` 各占一项。
- Maven 的完整实现可作为模板：数据模型 [MavenRepository.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/MavenRepository.swift)、扫描服务 [MavenLocalRepositoryService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/MavenLocalRepositoryService.swift)、配置服务 [MavenSettingsService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/MavenSettingsService.swift)、视图模型 [MavenLocalRepositoryViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/MavenLocalRepositoryViewModel.swift) 与 [MavenSettingsViewModel.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/ViewModels/MavenSettingsViewModel.swift)、Tab 视图 [MavenRepositoryView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/MavenRepositoryView.swift) 与 [MavenLocalArtifactsView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/MavenLocalArtifactsView.swift)。
- Shell 调用工具位于 [Shell.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift)，用于执行 `go env`、`npm root -g`、`npm cache clean` 等命令。
- 本地化两套字典（英/中）在 [Localization.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization.swift)。

## Functional Requirements
- **FR-1**：侧栏 `包管理` 分组下新增 `Go 仓库` 与 `Node 仓库` 两个入口，图标区分明显（Go 使用 `g.square`/自选，Node 使用 `n.square`/自选）。
- **FR-2**：Go 视图采用两 Tab 布局：`GOPROXY 镜像` 与 `本地依赖 (GOMODCACHE)`。
- **FR-3**：Go GOPROXY Tab 需展示：当前 `go env GOPROXY` 值，"应用预设" 菜单（预设：`direct`、`https://goproxy.cn,direct`、`https://goproxy.io,direct`、`https://mirrors.aliyun.com/goproxy/,direct`、`https://mirrors.cloud.tencent.com/go/,direct`），自定义输入框；点击保存后调用 `go env -w GOPROXY=...`。
- **FR-4**：Go 本地依赖 Tab 需扫描 `GOMODCACHE`（默认 `$HOME/go/pkg/mod`，若 `go env GOMODCACHE` 返回值非空则以此为准），聚合每个 module 的所有版本，展示总大小与最近修改时间；支持搜索、按名称/大小/修改时间排序、展开版本、删除单个版本或整个 module（使用 `chmod -R u+w` 后 `rm -rf` 因为 go module cache 目录只读）。
- **FR-5**：Node 视图采用三 Tab 布局：`npm 镜像`、`全局包`、`缓存`。
- **FR-6**：Node 镜像 Tab 读取 `~/.npmrc` 中的 `registry=` 行，预设 4 个镜像（`https://registry.npmmirror.com`、`https://mirrors.cloud.tencent.com/npm/`、`https://mirrors.huaweicloud.com/repository/npm/`、`https://registry.npmjs.org/`）一键切换，也支持自定义 URL；写入时保留其余 npmrc 内容。
- **FR-7**：Node 全局包 Tab 通过 `npm ls -g --depth=0 --json` 获取全局包列表，展示 `name`、`version`，提供"卸载"按钮（执行 `npm uninstall -g <name>`）。
- **FR-8**：Node 缓存 Tab 展示 `~/.npm/_cacache` 目录大小；提供 `npm cache clean --force` 按钮，成功后刷新大小。
- **FR-9**：所有破坏性操作（删除依赖、卸载包、清理缓存、切换镜像写入配置文件）都需要弹窗二次确认。
- **FR-10**：所有 UI 字符串走 `L("...")` 走本地化，中英双语必须齐全。

## Non-Functional Requirements
- **NFR-1**：扫描 `GOMODCACHE` / `npm root -g` 目录必须在后台线程（`Task.detached`）执行，主线程不阻塞；界面提供 `ProgressView` 加载态。
- **NFR-2**：所有 Shell 调用使用 [Shell.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift) 现有工具，命令有超时保护与错误信息回显。
- **NFR-3**：写入 `~/.npmrc` 前需备份为 `~/.npmrc.envmatrix.bak`（同 Maven 模式）。
- **NFR-4**：`swift build` 编译零错误零警告；文件行数遵守 500 行硬上限。
- **NFR-5**：删除文件时若目录不存在或权限不足，需以本地化错误提示回显，不允许崩溃。

## Constraints
- **Technical**：Swift 5.9+、SwiftUI、macOS 13+；不引入新的 SwiftPM 依赖。
- **Business**：本次为一个连贯 PR 交付；同一个 spec 目录管理。
- **Dependencies**：宿主机需要安装 `go`（CLI）和 `npm`（CLI）以获取环境变量与执行命令；未安装时视图需给出友好提示。

## Assumptions
- 用户环境安装了 `go` 与 `npm`，且它们在 login shell 的 `PATH` 中（`ShellPathResolver` 已能解析）。
- `GOMODCACHE` 结构遵循 `<module>@<version>/` 的官方约定（如 `github.com/gin-gonic/gin@v1.9.0`）。
- `~/.npmrc` 采用 INI 格式，`registry=xxx` 位于顶级、单行。
- 全局 npm 包目录（`npm root -g`）为 `<prefix>/lib/node_modules`，一级子目录名即为包名（scoped 包位于 `@scope/name`）。

## Acceptance Criteria

### AC-1: 侧栏新增 Go / Node 入口
- **Given**：应用启动进入主界面
- **When**：用户展开左侧"包管理"分组
- **Then**：`Homebrew`、`Maven 仓库` 之外可以看到 `Go 仓库` 与 `Node 仓库` 两个新条目，图标/文案与整体风格一致
- **Verification**: `human-judgment`

### AC-2: GOPROXY 读取与切换
- **Given**：用户进入 Go 仓库 → GOPROXY Tab
- **When**：视图 `.task` 触发
- **Then**：显示 `go env GOPROXY` 当前值；点击"应用预设 → goproxy.cn"后，`go env GOPROXY` 更新为 `https://goproxy.cn,direct`
- **Verification**: `programmatic`

### AC-3: GOMODCACHE 扫描与聚合
- **Given**：`~/go/pkg/mod/cache/download` 或 `~/go/pkg/mod/<host>/<owner>` 目录存在
- **When**：Go 仓库 → 本地依赖 Tab 加载完成
- **Then**：列表显示 module 名、版本数、总大小、最近修改时间；点击展开可见每个版本
- **Verification**: `programmatic`

### AC-4: GOMODCACHE 删除
- **Given**：GOMODCACHE 列表中至少有一个 module
- **When**：用户点击某 module 的"删除"，确认后
- **Then**：目标目录被移除（即使只读也能成功），列表刷新，总大小减少
- **Verification**: `programmatic`

### AC-5: npm registry 切换
- **Given**：用户进入 Node 仓库 → npm 镜像 Tab
- **When**：点击"应用预设 → 淘宝 npmmirror"
- **Then**：`~/.npmrc` 中 `registry=` 行被更新为 `https://registry.npmmirror.com`；文件其他行原样保留
- **Verification**: `programmatic`

### AC-6: 全局包列表与卸载
- **Given**：`npm ls -g --depth=0 --json` 至少返回 1 个包
- **When**：Node 仓库 → 全局包 Tab 加载
- **Then**：可见每个包 name/version；点击卸载并确认后调用 `npm uninstall -g <name>`，列表刷新
- **Verification**: `programmatic`

### AC-7: npm 缓存清理
- **Given**：`~/.npm/_cacache` 存在
- **When**：Node 仓库 → 缓存 Tab 加载
- **Then**：显示缓存目录大小；点击"清理"并确认后执行 `npm cache clean --force`，大小重新计算并显示新值
- **Verification**: `programmatic`

### AC-8: 缺失 CLI 的降级提示
- **Given**：宿主机没有 `go` 或 `npm`
- **When**：进入对应视图
- **Then**：视图显示明确的本地化提示（"未检测到 Go/Node 命令，请先安装"），不崩溃
- **Verification**: `human-judgment`

### AC-9: 编译与代码规模
- **Given**：所有新增源文件已完成
- **When**：运行 `swift build`
- **Then**：编译成功，零 error / 零 warning；单个新增文件不超过 500 行
- **Verification**: `programmatic`

### AC-10: 双语本地化齐全
- **Given**：切换语言（`LocalizationManager` 提供 zh/en）
- **When**：浏览 Go / Node 页面的每个 Tab
- **Then**：所有可见文案均已本地化（无 raw key、无 English fallback 出现在 zh 环境下）
- **Verification**: `human-judgment`

## Open Questions
- [x] 是否引入 pnpm / yarn？→ 用户明确回答：不引入。
- [x] UI 是分开还是合并 Tab？→ 用户明确回答：分开两个侧栏入口。
- [x] 是否包含 GOSUMDB / GOPRIVATE？→ 用户明确回答：不包含。
