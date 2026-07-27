# Checklist: 容器镜像与实例管理验收清单

## 入口与 Tab 结构
- [ ] Checkpoint 1：`ContainerContextsView` 顶部展示三段 Segmented Picker（Contexts / Images / Containers），默认停在 Contexts
- [ ] Checkpoint 2：切换 Tab 视觉无闪烁；Images / Containers 首次进入时展示 ProgressView 并异步加载
- [ ] Checkpoint 3：Docker / Podman 分区在每个 Tab 内互相隔离，任一 CLI 缺失或 podman machine 未启动时只影响自身分区

## 镜像 (Images) 分区
- [ ] Checkpoint 4：`docker images --format '{{json .}}'` / `podman images --format json` 输出被解析为 `ContainerImage`，`sizeBytes` 与 `createdAt` 显示正确
- [ ] Checkpoint 5：搜索框按 repository / tag 前缀过滤，排序 Picker 支持 name / size / createdAt
- [ ] Checkpoint 6：Pull 输入框接受 `image:tag`，点击 Pull 后底部 log 面板逐行追加进度，最终列表刷新
- [ ] Checkpoint 7：Pull 过程中可点击 Cancel，`StreamingHandle.cancel()` 生效并置 isBusy=false
- [ ] Checkpoint 8：Tag / Rm / Inspect 行内按钮工作正常；Rm 走二次确认
- [ ] Checkpoint 9：Prune 按钮弹二次确认，提供「包含未使用镜像」Toggle；成功后 toast 展示回收字节数
- [ ] Checkpoint 10：Inspect Sheet 展示格式化 JSON，等宽字体，可复制不可编辑

## 实例 (Containers) 分区
- [ ] Checkpoint 11：`docker ps -a --format '{{json .}}'` / `podman ps -a --format json` 输出被解析为 `ContainerInstance`，状态 badge 显示正确
- [ ] Checkpoint 12：状态 Segmented Filter（all / running / exited）交互正确，搜索框按 name / image / id 前缀命中
- [ ] Checkpoint 13：running 行显示 Stop/Restart/Logs/Inspect，Rm 禁用并 tooltip；exited 行显示 Start/Rm/Logs/Inspect
- [ ] Checkpoint 14：Stop / Restart / Rm 均走二次确认；调用完成后行状态刷新
- [ ] Checkpoint 15：Logs Sheet 展示最近 200 行，支持切换 100 / 200 / 500 / 1000 tail 大小，Copy 按钮复制全部日志

## Context 联动
- [ ] Checkpoint 16：切换 docker context 或 podman default connection 后，Images / Containers 分区自动标记 stale 并刷新
- [ ] Checkpoint 17：切换 Tab 期间 Contexts 数据不重复请求（缓存生效）

## Dashboard 卡片
- [ ] Checkpoint 18：Dashboard 新增「容器概览」卡片，按 Docker / Podman 分组显示 context 名 + 镜像数 + 运行中 + 停止
- [ ] Checkpoint 19：点击卡片跳转到 `.systemContainerContexts` 并预选 Images 或 Containers Tab

## Diagnostic Report / 全局搜索
- [ ] Checkpoint 20：诊断报告输出 `## Container Images (top 20 by size)` 段
- [ ] Checkpoint 21：诊断报告输出 `## Container Instances (running only)` 段
- [ ] Checkpoint 22：全局搜索新增 `Container Images` / `Container Instances` 两个 source，命中项回跳后预选正确 Tab

## 数据与安全
- [ ] Checkpoint 23：所有 `Process.arguments` 为字符串数组，无 `sh -c` / shell 拼接
- [ ] Checkpoint 24：镜像 reference 与实例 id 在入参前经过合法性校验（无空格、无控制字符），非法输入抛 `ContainerContextsError.invalidInput`
- [ ] Checkpoint 25：日志与错误消息不泄漏 identity 私钥或环境变量

## 代码质量
- [ ] Checkpoint 26：Models / Services / ViewModel / Views 严格分层
- [ ] Checkpoint 27：Service 通过 protocol 注入，`StreamingProcessExecutor` 可 mock
- [ ] Checkpoint 28：所有耗时 IO 在 `Task.detached(priority: .utility)` 中执行，主线程零阻塞（Instruments Time Profiler 不出现主线程阻塞）
- [ ] Checkpoint 29：每个新增源文件 ≤ 500 行（`scripts/check_file_lines.sh` 通过）
- [ ] Checkpoint 30：所有 UI 文案通过 `L("...")`；中英字典 key 集合完全对称
- [ ] Checkpoint 31：SwiftLint 无新增 warning

## 测试
- [ ] Checkpoint 32：`swift build -c debug` 通过，无 error / warning
- [ ] Checkpoint 33：`swift test` 全绿
- [ ] Checkpoint 34：`DockerImageServiceTests` 覆盖 list / pull（stream mock）/ tag / rm / prune（回收字节解析）/ inspect / invalidInput
- [ ] Checkpoint 35：`DockerContainerServiceTests` 覆盖 list / start / stop / restart / rm / logs（tail 参数）/ inspect / invalidInput
- [ ] Checkpoint 36：`PodmanImageServiceTests` / `PodmanContainerServiceTests` 覆盖以上镜像 / 实例操作 + notRunning 场景
- [ ] Checkpoint 37：`ContainerImagesViewModelTests` / `ContainerInstancesViewModelTests` 覆盖 refresh / pull cancel / logs sheet 状态
- [ ] Checkpoint 38：`ContainerImagesLocalizationTests` 校验中英字典 key 对称且非空

## 文档
- [ ] Checkpoint 39：README What's New 补充「🖼️ 容器镜像与实例管理」条目（无 emoji 编码乱码）
- [ ] Checkpoint 40：README「容器上下文」章节升级为「容器工作台」，说明三 Tab 结构
- [ ] Checkpoint 41：README Roadmap 补充「Docker / Podman 镜像与实例管理」并置为 `[x]`
- [ ] Checkpoint 42：README 项目结构追加新增的 Docker/Podman Image/Container Services 与 System/ Tab 视图
- [ ] Checkpoint 43：Conventional Commit：`feat(container): add image & instance manager`

## 可选增强（不阻塞验收）
- [ ] Checkpoint 44：Logs Sheet follow 模式（`--follow` 流式）
- [ ] Checkpoint 45：镜像分区支持批量选择 + 批量 rm
- [ ] Checkpoint 46：实例 stats 实时 CPU / MEM 曲线（v2 再评估）
