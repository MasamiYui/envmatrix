# Tasks: /etc/hosts 管理

按优先级从上到下执行；同一文件的多处修改合并为一个 Task。

## T1 [P0] Models：`HostsFile.swift`
- 位置：[Sources/EnvMatrix/Models/HostsFile.swift](../../Sources/EnvMatrix/Models/HostsFile.swift)
- 定义 `HostsEntry` / `HostsLine` / `HostsDocument` / `HostsProfile`。
- 数据类型需 `Hashable` + `Identifiable`，`HostsProfile.url` 使用应用支持目录路径。

## T2 [P0] Services：`HostsParser.swift`
- 位置：[Sources/EnvMatrix/Services/HostsParser.swift](../../Sources/EnvMatrix/Services/HostsParser.swift)
- `parse(_ text: String) -> HostsDocument`：识别注释行 / 空行 / `#IP HOST` 禁用行 / `IP HOST [ALIAS] [# comment]` 启用行；其他保留为 `.unparsed`。
- `serialize(_ doc: HostsDocument) -> String`：无损重建，禁用行以 `#IP HOST` 输出，注释以 ` # comment` 输出。
- 保证 `serialize(parse(x)) == x` 对常见 hosts 文本成立（换行、空行、tab / 多空格分隔等等）。

## T3 [P0] Services：`HostsService.swift`
- 位置：[Sources/EnvMatrix/Services/HostsService.swift](../../Sources/EnvMatrix/Services/HostsService.swift)
- Protocol：
  ```swift
  public protocol HostsService {
      func readSystemHosts() throws -> String
      func writeSystemHosts(text: String) throws -> URL   // 返回备份 URL
      func profilesDirectory() -> URL
      func backupsDirectory() -> URL
      func listProfiles() -> [HostsProfile]
      func readProfile(_ p: HostsProfile) throws -> String
      @discardableResult func writeProfile(name: String, text: String) throws -> HostsProfile
      func renameProfile(_ p: HostsProfile, to newName: String) throws -> HostsProfile
      func deleteProfile(_ p: HostsProfile) throws
      func setDefaultProfile(_ p: HostsProfile) throws
      func defaultProfileID() -> UUID?
  }
  ```
- `DefaultHostsService` 实现：
  - 应用目录 = `~/Library/Application Support/EnvMatrix/hosts/{profiles,backups}`，首次访问自动创建。
  - 默认 profile 元数据存 `hosts/profiles/.meta.json`（记录 `defaultID`）。
  - `writeSystemHosts` 内部使用 `HostsPrivilegedWriter`：
    - 生成 `/tmp/envmatrix-hosts-<yyyyMMdd-HHmmss>-<uuid>`；
    - 调用 `/usr/bin/osascript` 执行：
      ```
      do shell script "/bin/cp -f '<TMP>' /etc/hosts && /bin/chmod 644 /etc/hosts" with administrator privileges
      ```
    - 完成后清理临时文件；异常时保留临时文件供排查。
  - 覆盖前将 `/etc/hosts` 复制到 `backups/hosts.yyyyMMdd-HHmmss.bak`。
- 错误类型 `HostsServiceError`：`.readFailed / .writeFailed / .authCancelled / .backupFailed / .invalidName`。

## T4 [P0] ViewModel：`HostsViewModel.swift`
- 位置：[Sources/EnvMatrix/ViewModels/HostsViewModel.swift](../../Sources/EnvMatrix/ViewModels/HostsViewModel.swift)
- `@MainActor` + `ObservableObject`。
- Published：`profiles`, `selection`, `rawText`, `document`, `viewMode`, `systemHostsText`, `isDirty`, `isBusy`, `errorMessage`, `lastBackupURL`.
- 方法：
  - `refresh()` 初始化 profiles + 系统 hosts。
  - `select(_ profile)`；`switchMode(to:)`；
  - Entry CRUD：`addEntry`, `updateEntry`, `removeEntry`, `toggleEntryEnabled`；
  - Profile：`createProfile(name:)`, `duplicateAsProfile(name:)`, `renameProfile`, `deleteProfile`, `setDefault`。
  - `saveProfile()`：写入用户目录。
  - `applyToSystem()`：调用 `service.writeSystemHosts`。
- 所有 IO 走 `Task.detached(priority: .utility)`。

## T5 [P0] View：`HostsView.swift`
- 位置：[Sources/EnvMatrix/Views/System/HostsView.swift](../../Sources/EnvMatrix/Views/System/HostsView.swift)
- HStack 双栏：左侧 profile 列表 + 工具条；右侧标题 + Segmented + 内容。
- Structured 视图：`LazyVStack` 渲染 entry 行（Toggle + IP + hostnames + comment + 删除）。
- Raw 视图：等宽 `TextEditor`。
- Toolbar：`Save Profile` / `Apply to system`（后者高亮，红色，二次确认）。
- Empty state：`network` icon + 提示文案。

## T6 [P1] 导航接入
- [AppNavigation.swift](../../Sources/EnvMatrix/App/AppNavigation.swift)：新增 `.systemHosts`，`systemImage = "externaldrive.connected.to.line.below"`（或 `network`）；`allCases` + `allSections`（"system" 分组）追加。
- [DetailView.swift](../../Sources/EnvMatrix/App/DetailView.swift)：`case .systemHosts: HostsView()`。

## T7 [P1] 本地化
- 在 [Localization+Zh.swift](../../Sources/EnvMatrix/Utils/Localization+Zh.swift) / [Localization+En.swift](../../Sources/EnvMatrix/Utils/Localization+En.swift) 增加：
  - `nav.hosts`、`hosts.title`、`hosts.mode.structured/raw`、`hosts.entry.enabled/ip/hostnames/comment`、`hosts.addEntry/removeEntry`、`hosts.profiles`、`hosts.newProfile/duplicate/rename/delete/setDefault`、`hosts.saveProfile/applyToSystem/applyConfirm`、`hosts.currentSystem`、`hosts.errors.authCancelled/writeFailed/readFailed` 等。

## T8 [P1] 单元测试
- [Tests/EnvMatrixTests/HostsParserTests.swift](../../Tests/EnvMatrixTests/HostsParserTests.swift)：解析 / 序列化 / 往返、启用禁用、注释保留、tab 分隔、CRLF。
- [Tests/EnvMatrixTests/HostsServiceTests.swift](../../Tests/EnvMatrixTests/HostsServiceTests.swift)：使用临时 home 目录测试 profile CRUD、默认 profile 元数据读写；通过依赖注入的 mock writer 覆盖 `writeSystemHosts`。
- [Tests/EnvMatrixTests/HostsViewModelTests.swift](../../Tests/EnvMatrixTests/HostsViewModelTests.swift)：模拟 service，验证 refresh、CRUD、切换视图、apply 调用。

## T9 [P0] 构建验证
- `swift build -c debug`
- `swift test`

## T10 [P1] 文档与提交
- 更新 [README.md](../../README.md)：在 System 章节补充 hosts 能力，roadmap 勾选。
- 提交 Conventional Commit：`feat(system): add /etc/hosts manager with profiles and priv writer`。
