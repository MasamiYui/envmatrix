# 容器镜像与实例管理 - Product Requirement Document

## Overview
- **Summary**：在既有「Container Contexts」页面内新增 **Images**（镜像）与 **Containers**（实例）两个 Tab，覆盖 Docker 与 Podman 两大引擎，支持镜像的 list / pull / tag / rm / prune / inspect 与实例的 list / start / stop / restart / rm / logs（tail）/ inspect，并在 Dashboard 增加当前 active 引擎的镜像 / 运行中实例 / 停止实例概览卡片。
- **Purpose**：让 EnvMatrix 从「上下文切换」进一步覆盖到日常最高频的镜像与实例操作，避免用户在终端 `docker images` / `docker ps` / `podman images` / `podman ps` 之间来回切换。
- **Target Users**：本机同时使用 Docker Desktop / colima / Rancher Desktop / Podman 等运行时，希望以可视化方式管理镜像与容器实例的 macOS 开发者。

## Goals
- G1：在 `ContainerContextsView` 中新增 Tab 切换（Contexts / Images / Containers），共享上下文选择状态
- G2：镜像分区支持 list / pull（含实时进度）/ tag / rm / prune / inspect，并可按 repository / tag 过滤
- G3：实例分区支持 list（含 all）/ start / stop / restart / rm / logs（tail N，可复制）/ inspect，并可按状态过滤（running / exited / all）
- G4：所有破坏性操作（rm / prune / stop / restart）均走二次确认；pull 与 logs 输出以实时/流式方式反馈到 UI
- G5：Dashboard 新增「容器概览」卡片，展示当前 active docker context / podman default connection 下的镜像数、运行中容器数、停止容器数，点击跳转到对应 Tab
- G6：所有 CLI 参数以数组形式传入 `Process`，禁止 shell 字符串拼接；沿用现有的 `ProcessExecutor` 抽象

## Non-Goals (Out of Scope)
- 不实现 `docker exec` / `docker attach` / `docker cp` / `docker commit` / `docker build` 等生命周期外的高阶操作（v2 再评估）
- 不实现网络（network）/ 卷（volume）/ Compose 管理
- 不支持镜像仓库登录（`docker login`）与凭据管理
- 不支持镜像层浏览、镜像大小趋势图等高阶视图
- 不做多主机并发管理（仅当前 active context / default connection）
- 不实现 Podman machine 生命周期管理
- 不做实例 `stats` 实时监控（CPU / MEM 曲线，v2 再评估）

## Background & Context
- 上一阶段（[.trae/specs/container-context-manager](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.trae/specs/container-context-manager)）已经落地 [ContainerContext.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/ContainerContext.swift)、[DockerContextService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DockerContextService.swift)、[PodmanContextService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/PodmanContextService.swift)、[ContainerContextsView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerContextsView.swift) 及配套 ViewModel、路由与本地化文案。
- [ProcessExecutor.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/ProcessExecutor.swift) 已经封装 `run(executable:args:timeout:)` 接口，本次需要为 pull / logs 增加**流式 stdout / stderr** 回调支持。
- 现有 MVVM 分层与 `@MainActor` + `@Published` + `Task.detached(priority: .utility)` 主线程零阻塞的模式必须继续沿用。
- 单文件 ≤ 500 行是硬约束，需要通过分文件（`DockerImageService.swift` / `DockerContainerService.swift` / `PodmanImageService.swift` / `PodmanContainerService.swift`）来落地。

## Functional Requirements

### 镜像（Images）
- **FR-1**：镜像列表通过 `docker images --format '{{json .}}'` / `podman images --format json` 获取，解析为 `ContainerImage { id, repository, tag, digest?, sizeBytes, createdAt, engine }`
- **FR-2**：支持按 repository / tag 关键字前缀模糊过滤，支持按 size / createdAt 排序
- **FR-3**：`Pull` 操作接收 `image:tag` 输入，调用 `docker pull <ref>` / `podman pull <ref>`，通过流式 stdout 将每一行进度回写到底部 log 面板，成功后刷新列表
- **FR-4**：`Tag` 操作接收 `src, dst` 两个 reference，调用 `docker tag src dst` / `podman tag src dst`
- **FR-5**：`Rm` 操作对选中镜像执行 `docker rmi <id>` / `podman rmi <id>`，二次确认；若被容器占用则展示原始 stderr
- **FR-6**：`Prune` 执行 `docker image prune -f` / `podman image prune -f`（默认仅 dangling），二次确认；执行后展示回收字节数（解析 stdout）
- **FR-7**：`Inspect` 执行 `docker inspect <id>` / `podman inspect <id>`，把 JSON 原文放入等宽只读文本查看器，可复制

### 实例（Containers）
- **FR-8**：实例列表通过 `docker ps -a --format '{{json .}}'` / `podman ps -a --format json` 获取，解析为 `ContainerInstance { id, names, image, command, state, status, portsSummary, createdAt, engine }`
- **FR-9**：状态过滤支持 running / exited / all；关键字支持按 name / image / id 前缀模糊
- **FR-10**：行内操作按状态动态启用/禁用：running 显示 Stop/Restart/Logs/Inspect/Rm(禁用)；exited 显示 Start/Rm/Logs/Inspect；禁用 rm 时 tooltip 提示"请先停止"
- **FR-11**：`Start`/`Stop`/`Restart` 调用对应 CLI，破坏性操作（`Stop`/`Restart`/`Rm`）走二次确认
- **FR-12**：`Rm` 调用 `docker rm <id>` / `podman rm <id>`；如需强制，UI 提供「已停止后再删」提示，不隐式加 `-f`
- **FR-13**：`Logs` 调用 `docker logs --tail 200 <id>` / `podman logs --tail 200 <id>`，展示在弹窗内，可复制、可切换 tail 大小（100/200/500/1000）
- **FR-14**：`Inspect` 与镜像 inspect 一致，JSON 原文只读展示

### 集成
- **FR-15**：`ContainerContextsView` 头部增加分段控制器（Segmented Control），三 Tab：Contexts / Images / Containers；切换 Tab 不重复请求 Contexts，Images/Containers 首次进入时按需加载
- **FR-16**：切换 Docker context 或 Podman default connection 后，Images 与 Containers 分区标记为 stale 并触发刷新
- **FR-17**：Dashboard 增加「容器概览」卡片，展示：当前 docker context 名称 + 镜像数 + 运行中容器数 + 停止容器数（Podman 同理），点击卡片跳转到 `.systemContainerContexts` 并预选对应 Tab
- **FR-18**：Diagnostic Report 追加 `## Container Images (top 20 by size)` 与 `## Container Instances (running only)` 章节
- **FR-19**：全局搜索（⌘F）新增 `containerImage` / `containerInstance` 两个 source，返回 image reference / container name 命中项，点击回跳到对应 Tab

## Non-Functional Requirements
- **NFR-1**：所有 CLI 调用在 `Task.detached(priority: .utility)` 中执行，UI 主线程零阻塞；ProgressView / isBusy 状态可视化
- **NFR-2**：pull / logs 之外的所有命令 5s timeout；pull 无 timeout 但需可取消（通过 `Process.terminate()`）
- **NFR-3**：单文件 ≤ 500 行；`scripts/check_file_lines.sh` 对新增文件必须通过
- **NFR-4**：所有 UI 文案通过 `L("...")` 落到 En + Zh 双字典且 key 集合完全对称
- **NFR-5**：`swift build -c debug` 无 warning；`swift test` 全绿
- **NFR-6**：Service 通过 protocol 注入，`ProcessExecutor` 可 mock，覆盖成功/失败/超时/解析错误路径
- **NFR-7**：进程参数一律数组传入，禁止 `sh -c` / shell 拼接；镜像 reference 与实例 id 在 UI 层做基本合法性校验（无空格、无控制字符）

## Constraints
- **技术**：Swift 5.10 / SwiftUI / macOS 14+ / SPM；沿用 MVVM
- **业务**：向后兼容既有 Container Contexts 页面，用户升级后原有交互路径必须保留
- **依赖**：仅依赖用户机器上的 `docker` / `podman` CLI，不引入 Swift 侧新库

## Assumptions
- 用户机器上至少安装了 `docker` 或 `podman` 之一；两者都未安装时对应 Tab 展示空态而非报错
- `docker images --format '{{json .}}'` 输出为一行一 JSON 对象（jsonl），`podman images --format json` 输出为标准 JSON 数组 —— Service 层各自解析
- Pull 输出格式在不同 Docker Desktop / Podman 版本之间存在差异，UI 不做结构化解析，仅按行显示
- 用户不希望 GUI 隐式使用 `-f` 强删，语义上尊重 CLI 默认行为

## Acceptance Criteria

### AC-1：三 Tab 切换
- **Given**：进入 `.systemContainerContexts` 页面
- **When**：切换 Contexts / Images / Containers Tab
- **Then**：视图无闪烁，Images/Containers 首次切换时展示 ProgressView 并异步加载，后续切换命中缓存直接显示
- **Verification**：`human-judgment`

### AC-2：镜像列表解析
- **Given**：mock ProcessExecutor 返回预置 `docker images --format '{{json .}}'` 输出
- **When**：调用 `DockerImageService.list()`
- **Then**：返回值数量与 mock 输出行数一致，repository / tag / size 解析正确
- **Verification**：`programmatic`

### AC-3：Pull 实时进度
- **Given**：进入 Images Tab，输入 `alpine:3.19` 并点击 Pull
- **When**：ProcessExecutor 以流式方式吐出多行 stdout
- **Then**：底部 log 面板逐行追加，最终列表刷新出新增镜像；期间点击「取消」可 `Process.terminate()` 中止
- **Verification**：`human-judgment`

### AC-4：镜像 Prune 二次确认
- **Given**：在 Images Tab 点击 Prune
- **When**：弹出二次确认弹窗，选择确认
- **Then**：调用 `docker image prune -f`，成功后展示"回收 X MB" toast，列表刷新
- **Verification**：`human-judgment`

### AC-5：实例列表状态过滤
- **Given**：mock 返回 3 个 running + 2 个 exited 的 `docker ps -a` 输出
- **When**：切换过滤到 running
- **Then**：UI 仅展示 3 项，状态 badge 与 tooltip 正确
- **Verification**：`programmatic` + `human-judgment`

### AC-6：实例 Stop / Rm 二次确认
- **Given**：一个 running 容器行
- **When**：点击 Stop，二次确认后
- **Then**：调用 `docker stop <id>`；调用完成后行状态刷新为 Exited，Rm 按钮可用
- **Verification**：`human-judgment`

### AC-7：Logs 弹窗
- **Given**：一个 running / exited 容器行
- **When**：点击 Logs
- **Then**：弹窗以等宽字体展示最近 200 行日志，可切换 100/200/500/1000，Copy 按钮可复制全部内容
- **Verification**：`human-judgment`

### AC-8：Inspect 只读 JSON
- **Given**：任一镜像或实例行
- **When**：点击 Inspect
- **Then**：Sheet 展示格式化 JSON，等宽字体，可选中复制，不可编辑；关闭后不影响列表
- **Verification**：`human-judgment`

### AC-9：Context 切换联动
- **Given**：Images/Containers 已加载数据
- **When**：在 Contexts Tab 切换到另一个 docker context 或 podman default connection
- **Then**：Images / Containers 分区被标记 stale 并触发自动刷新
- **Verification**：`programmatic`

### AC-10：Dashboard 概览卡片
- **Given**：Docker 与 Podman 至少一个可用
- **When**：进入 Dashboard
- **Then**：新增卡片按引擎分组展示 context 名 + 镜像数 + running 数 + stopped 数；点击卡片跳到 `.systemContainerContexts` 并预选对应 Tab
- **Verification**：`human-judgment`

### AC-11：Diagnostic Report 追加
- **Given**：DiagnosticReportService 生成报告
- **When**：Docker/Podman 中至少一个可用
- **Then**：Markdown 输出包含 `## Container Images (top 20 by size)` 与 `## Container Instances (running only)`
- **Verification**：`programmatic`

### AC-12：全局搜索
- **Given**：⌘F 打开搜索
- **When**：输入镜像名或容器名前缀
- **Then**：结果包含 `Container Images` / `Container Instances` source 分组，点击回跳到对应 Tab
- **Verification**：`human-judgment`

### AC-13：安全 - 参数数组传递
- **Given**：任一命令执行
- **When**：审阅代码
- **Then**：所有 `Process.arguments` 为字符串数组，无 `sh -c` / shell 拼接；镜像 reference 与 id 经过合法性校验后再入参
- **Verification**：`programmatic`

### AC-14：主线程零阻塞
- **Given**：任一耗时操作（list/pull/logs）
- **When**：操作进行中
- **Then**：`isBusy` 驱动 ProgressView，UI 可继续滚动/切换 Tab；主线程不被阻塞
- **Verification**：`human-judgment`

### AC-15：本地化对称
- **Given**：容器镜像与实例相关的新增 L10n key
- **When**：运行 `ContainerImagesLocalizationTests` / `ContainerInstancesLocalizationTests`
- **Then**：所有 `container.image.*` / `container.instance.*` key 在 en / zh 集合完全一致，值非空
- **Verification**：`programmatic`

## Open Questions
- [ ] Prune 默认策略：仅 dangling（`docker image prune`）还是 all unused（`-a`）？当前 spec 采用仅 dangling，UI 加二级开关 `Include unused`（默认关）
- [ ] Rootless Podman 在 macOS 上通过 `podman machine` 桥接，用户机器未启动 podman machine 时 `podman ps` 会报错；本次通过错误 banner 展示原始 stderr，不主动引导 `podman machine start`
- [ ] 日志弹窗是否需要 follow 模式（`--follow`）？当前 spec 仅做 tail 快照，follow 留待 v2
