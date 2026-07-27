# Checklist: Docker / Podman 上下文管理验收清单

## 侧边栏与导航
- [x] Checkpoint 1：`NavigationItem.systemContainerContexts` 已加入 `allCases` 和 `nav.system` 分组，位置在 `.systemLocalApps` 之后、`.settings` 之前
- [x] Checkpoint 2：侧边栏 System 分组下出现「Container Contexts / 容器上下文」入口，图标合理，中英双语切换后文案正确
- [x] Checkpoint 3：`DetailView` 路由到 `ContainerContextsView`，页面进入无崩溃

## Docker 分区
- [x] Checkpoint 4：`docker` CLI 缺失时展示专属空态（含安装建议），不影响 Podman 分区
- [x] Checkpoint 5：`docker context ls --format '{{json .}}'` 结果被解析为若干 `DockerContext`，`isCurrent` 高亮正确
- [x] Checkpoint 6：Section header 展示 count badge，支持折叠 / 展开与刷新
- [x] Checkpoint 7：内置 context（如 `default`）Delete 按钮 disabled + tooltip 明示原因
- [x] Checkpoint 8：Use / Edit / Delete / Ping 四个行内操作按预期调用对应 CLI，命令参数以数组传入（无 shell 拼接）
- [x] Checkpoint 9：Editor Sheet 支持 unix / tcp / ssh 三种 endpoint 模板，TLS 三个证书路径与 skipTLSVerify 可选可保存
- [x] Checkpoint 10：Ping 展示 client / server 版本或原始 stderr 前 500 字；超过 5s 显示 timeout

## Podman 分区
- [x] Checkpoint 11：`podman` CLI 缺失时展示专属空态，不影响 Docker 分区
- [x] Checkpoint 12：`podman system connection list --format json` 结果被解析为若干 `PodmanConnection`，`isDefault` 高亮正确
- [x] Checkpoint 13：Add / SetDefault / Edit（remove + add） / Remove / Ping 五个操作按预期调用 CLI
- [x] Checkpoint 14：Edit 走 remove + add 事务，若 add 失败会尝试回滚老连接并展示错误
- [x] Checkpoint 15：删除当前 default 后 UI 提示"当前默认已失效"

## Empty / 错误处理
- [x] Checkpoint 16：任一 CLI 命令失败时错误消息展示在对应分区，不影响另一分区
- [x] Checkpoint 17：`docker context ls` / `podman system connection list` 返回空数组时展示 "尚未配置任何 xxx" 空态而不是错误

## 数据与安全
- [x] Checkpoint 18：所有传递给 `Process.arguments` 的参数为数组形式，未出现 shell 拼接或 `sh -c` 调用
- [x] Checkpoint 19：SSH identity 路径仅作字符串展示 / 传参，不读取文件内容
- [x] Checkpoint 20：日志输出不包含 identity 私钥路径以外的敏感内容

## 代码质量
- [x] Checkpoint 21：Models / Services / ViewModel / Views 严格分层，遵循 MVVM
- [x] Checkpoint 22：Service 通过 protocol 注入，`ProcessExecutor` 可 mock
- [x] Checkpoint 23：所有 IO 在 `Task.detached(priority: .utility)` 中执行，主线程零阻塞
- [x] Checkpoint 24：每个新增源文件 ≤ 500 行（`scripts/check_file_lines.sh` 通过）
- [x] Checkpoint 25：所有 UI 文案均通过 `L("...")` 落到 En + Zh 双字典且 key 集合完全对称
- [ ] Checkpoint 26：SwiftLint 无新增 warning（未验证：环境中未安装 `swiftlint` 二进制，无法运行静态检查）

## 测试
- [x] Checkpoint 27：`swift build -c debug` 通过，无 error / warning
- [x] Checkpoint 28：`swift test` 全绿
- [x] Checkpoint 29：`DockerContextServiceTests` 覆盖 list / use / create / update / rm / ping / timeout / 解析失败
- [x] Checkpoint 30：`PodmanContextServiceTests` 覆盖 list / setDefault / add / replace（含失败回滚）/ remove / ping
- [x] Checkpoint 31：`ContainerContextsViewModelTests` 覆盖并行 refresh、错误上抛、ping 结果写入
- [x] Checkpoint 32：`ContainerContextsLocalizationTests` 校验中英字典 key 对称且非空

## 文档
- [x] Checkpoint 33：README What's New 补充 Docker / Podman 上下文管理条目（无 emoji 编码乱码）
- [x] Checkpoint 34：README System 章节新增 Container Contexts 说明段
- [x] Checkpoint 35：README Roadmap 将 "Docker / Podman 上下文管理" 从 `[ ]` 迁移到 `[x]`
- [x] Checkpoint 36：项目结构补充 [ContainerContext.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/ContainerContext.swift) / [DockerContextService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/DockerContextService.swift) / [PodmanContextService.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/PodmanContextService.swift) / [ContainerContextsView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/System/ContainerContextsView.swift)
- [x] Checkpoint 37：Conventional Commit：`feat(system): add docker & podman context manager`

## 可选增强（不阻塞验收）
- [x] Checkpoint 38：`SearchAggregator` 新增 `containerContext` source，可搜索并回跳
- [x] Checkpoint 39：`DiagnosticReportService` 输出 `## Container Contexts` 段
- [ ] Checkpoint 40：Dashboard 卡片展示当前 active docker / podman context（v2 再评估）（未实现：`DashboardView`/`DashboardViewModel` 中未见 docker/podman/container 相关代码，按 spec 说明 v2 再评估）
