# Docker / Podman 上下文管理 - Product Requirement Document

## Overview
- **Summary**：在 EnvMatrix 的 System 侧边栏分组下新增「Container Runtimes」入口，为 macOS 开发者提供 **Docker** 和 **Podman** 的**上下文（context/connection）**可视化管理能力：查看所有已配置的上下文、切换 active context、创建 / 编辑 / 删除自定义 context，并附带对当前 daemon 端点、client 版本、可选连通性探测的读展示。写操作全部走对应 CLI（`docker context ...` / `podman system connection ...`），无 root、无守护进程改动。
- **Purpose**：开发者日常在本地 Docker Desktop、Colima、Rancher Desktop、远程 SSH 主机、以及 rootful / rootless Podman machine 之间频繁切换 `DOCKER_HOST` / `podman system connection default`。当前只能靠 shell 别名或反复敲命令，缺一个可视化中心。EnvMatrix 已具备 [Shell 环境](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ShellEnvService.swift) / [Hosts](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/HostsService.swift) / [Local Apps](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/LocalAppsService.swift) 系列 System 模块的沉淀，本模块自然接入，形成"上下文即环境"这一体化体验。
- **Target Users**：macOS 上使用多 Docker / Podman endpoint（Desktop、Colima、Rancher、远程 SSH、Podman machine）的后端 / 平台工程师；需要在 dev / staging / prod 集群 endpoint 间快速切换的 DevOps。

## Goals
- G1：**双引擎并列**——在同一页面里以 Segmented Picker 或双分栏形式同时展示 Docker 和 Podman 的 context 列表，各自独立可用性检测与操作。
- G2：**上下文可视化 CRUD**——列出、切换 active、新增、编辑、删除自定义 context / connection；系统内置 context（如 `default`、`desktop-linux`）禁止删除但允许查看与切换。
- G3：**Endpoint 与 identity 展示**——每条 context 展示其 host / socket、TLS 状态（Docker）或 identity 文件路径（Podman `ssh://` 连接）。
- G4：**可选连通性探测**——用户主动点击"Ping"时才执行 `docker version --context X --format ...` / `podman --connection X system info`，避免每次进入页面就 fork 一堆进程。
- G5：**优雅降级 & i18n**——CLI 缺失、Docker Desktop 未启动、Podman machine 停止等场景下给出 empty state 引导，中英双语完整对称。

## Non-Goals (Out of Scope)
- ❌ 容器 / 镜像 / 卷 / 网络的 CRUD 管理（EnvMatrix 定位为**环境**而非**运行时**管理器，`docker ps`、`docker images` 等能力交给 Docker Desktop / OrbStack / lazydocker）。
- ❌ Docker Desktop / Podman machine 生命周期管理（`podman machine start/stop/init`、Colima `colima start` 等），后续版本再考虑。
- ❌ Kubernetes kubeconfig context 切换（虽然思路类似，但属于另一模块）。
- ❌ 编辑 `~/.docker/daemon.json`、`registries.conf` 之类的守护进程配置文件。
- ❌ 图形化管理镜像仓库凭据（`docker login`）。
- ❌ Docker Compose / Kompose / Buildx builder 管理。

## Background & Context
- 现有 System 分组下已有 [ShellEnvView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System) / [HostsView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System) / [LocalAppsView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System) 三个模块，`AppNavigation.swift` 中的 `system` 分组是本模块的自然归宿。
- 项目已有的 CLI 服务范式（[CargoService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/CargoService.swift) / [ComposerService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ComposerService.swift)）通过 [ShellPathResolver](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ShellPathResolver.swift) 解析 CLI 位置，用 `Process` + JSON 输出解析结果，本模块复用同一套约定。
- Docker 官方支持 `docker context ls --format '{{json .}}'` 输出 JSON Lines；每条含 `Name`、`Description`、`DockerEndpoint`、`ContextType`、`Current`。
- Podman 使用 `podman system connection list --format json` 输出数组；每条含 `Name`、`URI`、`Identity`、`Default`。
- 两条命令都是 client 侧操作，无需守护进程运行、无需 root。
- Roadmap 中已明确列出 "Docker / Podman 上下文管理" 待办（见 [README.md](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md) Roadmap 段）。

## Functional Requirements
- **FR-1 CLI 可用性检测**：进入页面时并行 `which docker` / `which podman`（通过 [ShellPathResolver](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ShellPathResolver.swift)），任一缺失时对应分区显示"未检测到 xxx"空状态 + 安装建议链接，不阻塞另一引擎。
- **FR-2 列出上下文**：
  - Docker：`docker context ls --format '{{json .}}'`，解析为 `DockerContext { name, description, endpoint, contextType, isCurrent }`；额外调用 `docker context inspect --format '{{json .Endpoints.docker}}'` 补 `tls`、`skipTLSVerify` 字段（Endpoints 结构差异较大，做防御性解析，字段解析不到时不影响主流程）。
  - Podman：`podman system connection list --format json`，解析为 `PodmanConnection { name, uri, identity, isDefault, isReadWrite }`。
- **FR-3 切换 active**：
  - Docker：`docker context use <name>`。
  - Podman：`podman system connection default <name>`。
  - 成功后主动刷新列表并高亮新 active。
- **FR-4 新增自定义 context**：
  - Docker：`docker context create <name> --docker "host=<host>[,ca=...,cert=...,key=...,skip-tls-verify=true]" --description "<desc>"`。UI 支持三种 endpoint 快捷模式：`unix://` 本地 socket、`tcp://host:port` + 可选 TLS 证书、`ssh://user@host`。
  - Podman：`podman system connection add [--default] [--identity <path>] <name> <uri>`。UI 支持两种 uri 模板：`unix:///run/user/UID/podman/podman.sock`、`ssh://user@host[:port]/run/user/UID/podman/podman.sock`。
- **FR-5 编辑 context**：
  - Docker：`docker context update <name> ...`（同 create 参数集）。
  - Podman：无 update，前端以"remove + add"两步事务实现，失败时尝试回滚（重新 add 旧值）。
- **FR-6 删除 context**：
  - Docker：`docker context rm <name>`，禁止删除内置的 `default`（UI 层置灰按钮）。
  - Podman：`podman system connection remove <name>`，若删除当前 default，删除后 UI 提示"当前默认已失效，请重新选择"。
  - 全部走**二次确认**。
- **FR-7 连通性 Ping**：
  - Docker：`docker --context <name> version --format '{{json .}}'`，成功则显示 client / server 版本，失败展示原始 stderr 前 500 字。
  - Podman：`podman --connection <name> system info --format json`（`--connection` 是 client 侧参数，无需目标 host 联通即可尝试）。成功展示 Host.Arch / Host.Kernel。
  - **不自动执行**，仅在用户点击行内 "Ping" 按钮时触发；每次 ping 有 5 秒超时。
- **FR-8 分组与折叠**：Docker / Podman 两个 Section 各自可折叠、右侧显示 count badge，遵循项目已有分组风格（参考 [MCPServersView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/AI)）。
- **FR-9 导航接入**：`NavigationItem` 新增 `.systemContainerContexts`，`AppNavigation.allSections` 的 `system` 分组内插到 `.systemShellEnv / .systemHosts / .systemLocalApps` 之后、`.settings` 之前，避免影响 Settings 位置。
- **FR-10 全局搜索接入（可选）**：`SearchAggregator` 增加 `containerContext` source，允许按 name / endpoint 搜索并回跳该页面（若时间不足，可挪到下一迭代）。

## Non-Functional Requirements
- **NFR-1 性能**：进入页面 500ms 内展示骨架屏，1s 内完成 `context ls`；Ping 操作严格异步，5s 超时。
- **NFR-2 一致性**：文件命名、目录、错误类型、二次确认 UX 与 [CargoService](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/CargoService.swift) / [ComposerService](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ComposerService.swift) 保持一致；单文件 ≤ 500 行。
- **NFR-3 安全**：只调用 CLI 子命令，不拼接用户输入到 shell 字符串（避免注入）；不落盘任何凭据；SSH identity 路径以 URL 展示且不读文件内容。
- **NFR-4 可测性**：Service 层通过 protocol + `Process` 抽象（`ProcessExecutor` protocol）注入，Test 用 mock executor 提供 stdout / stderr。
- **NFR-5 i18n**：所有 UI 文案落在 `Localization+En.swift` / `Localization+Zh.swift`，key 前缀 `container.*` 或 `nav.containerContexts`。
- **NFR-6 优雅降级**：CLI 缺失、Docker Desktop 未启动（socket 连不上 → `context ls` 仍能返回）、Podman machine 未 init（`connection list` 返回空数组）等场景 UI 不崩溃、给出明确提示。
- **NFR-7 macOS 目标**：仅 macOS 13+，纯 SwiftUI，不引入新第三方依赖。

## Constraints
- **Technical**：Swift 5.9、SwiftUI、Swift Concurrency；仅使用 `Foundation.Process` 调用外部 CLI。
- **Business**：功能属于 Roadmap 待办，无 KPI 时限，但要求 Phase 内可 ship。
- **Dependencies**：客户端 `docker` ≥ 20.10 或 `podman` ≥ 4.0（更早版本 `--format json` 输出可能不全，做兼容性防御但不强保证）。

## Assumptions
- 用户至少安装 `docker` CLI 或 `podman` CLI 之一（EnvMatrix 会在两者皆缺失时展示空状态）。
- 用户已通过 Docker Desktop / Colima / Rancher / Podman machine 中的**任一方式**产生了初始 context / connection。
- `docker context ls --format '{{json .}}'` 与 `podman system connection list --format json` 输出格式在支持范围内的版本足够稳定。
- 用户对 CLI 操作的 stderr 有心理预期（远程 SSH 端点 ping 失败等属于正常场景）。

## Acceptance Criteria

### AC-1: 侧边栏出现入口
- **Given**：任意状态下打开 EnvMatrix。
- **When**：查看左侧 System 分组。
- **Then**：可见「Container Contexts」（中文：「容器上下文」）条目，图标为 `shippingbox.and.arrow.backward` 或 `cablecar.fill`（视图库最终定），点击可打开 [ContainerContextsView](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System)。
- **Verification**：`programmatic`
- **Notes**：`NavigationItem.systemContainerContexts.displayName` 单测覆盖。

### AC-2: 双引擎独立展示
- **Given**：本机同时安装 docker 与 podman。
- **When**：打开页面。
- **Then**：页面出现两个 Section："Docker Contexts"、"Podman Connections"，各自展示条目列表与 count badge。
- **Verification**：`human-judgment`

### AC-3: 缺失 CLI 时优雅降级
- **Given**：本机仅安装 podman，未安装 docker（`which docker` 返回空）。
- **When**：打开页面。
- **Then**：Docker Section 内显示"未检测到 docker CLI"空状态与安装建议；Podman Section 正常渲染，交互不受影响。
- **Verification**：`programmatic`（Service 层 `isDockerAvailable() == false` 时 ViewModel `dockerContexts == []` 且 `dockerUnavailableReason != nil`）。

### AC-4: 列出上下文并高亮 active
- **Given**：本机 `docker context ls` 返回三条：`default`（active）、`desktop-linux`、`colima`。
- **When**：打开页面。
- **Then**：Docker Section 列出三条，`default` 行左侧显示"● Active"或 filled `checkmark.circle.fill` 蓝色图标；其余灰色。
- **Verification**：`programmatic`

### AC-5: 切换 active
- **Given**：Docker Section 有多条 context。
- **When**：点击某条非 active 行右侧 "Use" 按钮并确认。
- **Then**：调用 `docker context use <name>` 成功，UI 刷新后该行变为 active。
- **Verification**：`programmatic`（ViewModel 测试 mock executor，`useDocker(name)` 结束后 `currentDockerContext == name`）。

### AC-6: 创建自定义 Docker context
- **Given**：Docker Section 顶部有"+"按钮。
- **When**：填写 name / endpoint（`tcp://` 模式）/ description 后点击 Create。
- **Then**：调用 `docker context create <name> --docker "host=..." --description "..."`，成功后列表出现新条目。
- **Verification**：`programmatic`

### AC-7: 编辑 Docker context
- **Given**：非内置 context 存在。
- **When**：点击 "Edit" 修改 description 与 endpoint 并保存。
- **Then**：调用 `docker context update`，字段变化在 UI 反映。
- **Verification**：`programmatic`

### AC-8: 删除 context（二次确认 & 保护）
- **Given**：Docker Section 有 `default`（内置） 与自建 `mytcp`。
- **When**：`default` 行的 Delete 按钮不可点（禁用 + tooltip："system context cannot be removed"）；`mytcp` 行 Delete 弹出二次确认，确认后调用 `docker context rm mytcp`。
- **Then**：`mytcp` 从列表消失。
- **Verification**：`programmatic`

### AC-9: Podman connection CRUD
- **Given**：本机 podman 已安装。
- **When**：分别执行 add（含 `--identity`）/ 切换 default / edit（remove + add） / remove。
- **Then**：所有操作调用对应 CLI，UI 状态同步。
- **Verification**：`programmatic`

### AC-10: Ping 连通性
- **Given**：Docker 或 Podman Section 内某条 context。
- **When**：点击 "Ping" 按钮。
- **Then**：出现 loading 指示器，随后展示成功（client/server 版本或 Host.Arch）或失败原因（stderr 前 500 字）；5 秒无响应视为超时并展示 timeout 消息。
- **Verification**：`programmatic`

### AC-11: 国际化对称
- **Given**：中英双语切换。
- **When**：切换到英文 / 中文。
- **Then**：所有本模块 UI 文本（nav / section / button / dialog / empty state）随之切换，`Localization+En.swift` 与 `Localization+Zh.swift` 中的 key 集合完全一致。
- **Verification**：`programmatic`（新增单测：`ContainerContextsLocalizationTests` 校验 key 对称）。

### AC-12: 单文件 ≤ 500 行
- **Given**：本次新增所有源文件。
- **When**：运行 `scripts/check_file_lines.sh`。
- **Then**：脚本 exit code 为 0，无超行提示。
- **Verification**：`programmatic`

### AC-13: 构建与测试
- **Given**：完成实现。
- **When**：`swift build -c debug` 与 `swift test` 分别执行。
- **Then**：build 无 warning / error；test 全绿，含至少 3 组新增测试（DockerService、PodmanService、ViewModel）。
- **Verification**：`programmatic`

## Open Questions
- [ ] 是否需要在 Dashboard 增加一个 "Container Contexts" 卡片（展示 active docker / podman context）？——建议 v1 不做，v2 视需求再加。
- [ ] SSH endpoint 的 identity 是否允许在 UI 内拖拽选择文件？——v1 只允许手输路径，避免涉及 macOS 沙盒文件访问权限。
- [ ] 是否要将当前 active context 写入 Diagnostic Report？——建议 v1 顺手加入 [DiagnosticReportService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DiagnosticReportService.swift)（一行 `docker context show` + `podman system connection list --format '{{.Default}}'`）。
- [ ] Ping 超时时长 5s 是否合适？远程 SSH 冷连接可能需要 10s+。默认 5s，未来放到 Settings。
