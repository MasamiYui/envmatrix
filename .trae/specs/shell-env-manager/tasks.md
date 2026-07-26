# Shell 本地环境管理 - 实施计划（分解与优先级）

## [x] Task 1: 定义 Shell 环境模型与解析/序列化器
- **Priority**: P0
- **Depends On**: None
- **Description**：
  - 新建 [ShellEnvFile.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Models/ShellEnvFile.swift)，定义：
    - `ShellRcKind`（zshrc / zprofile / zshenv / bashrc / bashProfile / profile；含 `defaultRelativePath` 与 `displayName`）。
    - `ShellEnvEntry`（`enum { .variable(ShellVariable), .pathAppend(ShellPathAppend), .unparsed(String) }`），其中 `ShellVariable` 含 `key: String, value: String, quoting: enum {.none,.single,.double}, isExported: Bool`；`ShellPathAppend` 含 `segments: [String], style: {.doubleQuoted, .unquoted}`。
    - `ShellEnvDocument` 保存有序的 `[ShellEnvEntry]` 与原始换行样式。
  - 新建 [ShellEnvParser.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ShellEnvParser.swift)：
    - `parse(_ text: String) -> ShellEnvDocument`：逐行解析；识别形如 `[export ]KEY=VALUE`（可选引号），并把 `PATH` 追加行拆成片段列表；不识别的行原样存入 `.unparsed`。
    - `serialize(_ doc: ShellEnvDocument) -> String`：把结构化模型回写成文本；未识别行原样输出。
- **Acceptance Criteria Addressed**：AC-3, AC-5
- **Test Requirements**：
  - `programmatic` TR-1.1：`parse("export FOO=\"bar baz\"\n")` 返回一个 `.variable(key:"FOO", value:"bar baz", quoting:.double, isExported:true)`。
  - `programmatic` TR-1.2：`parse("export PATH=\"$PATH:/opt/x/bin:/opt/y/bin\"\n")` 返回一个 `.pathAppend(segments:["/opt/x/bin","/opt/y/bin"], style:.doubleQuoted)`。
  - `programmatic` TR-1.3：`parse` 输入含注释、alias、函数、`source` 行；`serialize(parse(text))` 应恒等于原文（无损往返）。
  - `programmatic` TR-1.4：对 `.variable` 与 `.pathAppend` 进行修改后再 `serialize`，结果满足预期且未修改 `.unparsed` 行的相对位置。

## [x] Task 2: 实现 ShellEnvService（列出、读取、写入、备份）
- **Priority**: P0
- **Depends On**: Task 1
- **Description**：
  - 新建 [ShellEnvService.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Services/ShellEnvService.swift)：
    - `protocol ShellEnvService`：`func availableFiles() -> [ShellRcFile]`、`func read(_ file: ShellRcFile) throws -> String`、`func write(_ file: ShellRcFile, text: String) throws -> URL /* backup URL */`、`func currentShellKind() -> ShellRcKind?`。
    - `DefaultShellEnvService`：注入 `FileManager` 与 home URL；`availableFiles` 只返回真实存在的 rc 文件；`write` 先写 `<name>.envmatrix.<yyyyMMdd-HHmmss>.bak`，再用 `Data.write(to:options:.atomic)` 覆盖目标；`currentShellKind` 读取 `$SHELL` 环境变量识别 zsh/bash。
- **Acceptance Criteria Addressed**：AC-2, AC-4, AC-7
- **Test Requirements**：
  - `programmatic` TR-2.1：在临时 home 中放 `.zshrc` 与 `.zshenv`，`availableFiles` 返回两个文件，缺失文件不出现。
  - `programmatic` TR-2.2：`write(.zshrc, text:"NEW")` 在临时 home 中生成对应的 `.zshrc.envmatrix.<stamp>.bak`，其内容等于旧内容；`.zshrc` 的最终内容等于 `NEW`。
  - `programmatic` TR-2.3：`currentShellKind`：`SHELL=/bin/zsh` → `.zshrc`；`SHELL=/bin/bash` → `.bashrc`；`SHELL=/bin/dash` → `nil`。
  - `programmatic` TR-2.4：写入无权限目录时抛错，且目标文件保持原状（可选：通过设置只读权限验证）。

## [x] Task 3: 编写 ShellEnvViewModel
- **Priority**: P0
- **Depends On**: Task 1, Task 2
- **Description**：
  - 新建 [ShellEnvViewModel.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/ViewModels/ShellEnvViewModel.swift)，`@MainActor final class`：
    - `@Published var files: [ShellRcFile]`、`@Published var selection: ShellRcFile?`、`@Published var rawText: String`、`@Published var doc: ShellEnvDocument`、`@Published var viewMode: enum {.structured, .raw}`、`@Published var errorMessage: String?`、`@Published var isBusy: Bool`。
    - `refresh()` / `select(_:)` / `save()` / `switchMode(to:)`：`select` 与 `save` 通过 `Task.detached(priority: .utility)` 在后台读取或写入，再回到 main 线程更新 `@Published`。
    - `switchMode(to: .raw)` 前把 `doc` 序列化写回 `rawText`；`switchMode(to: .structured)` 前用解析器把 `rawText` 转回 `doc`。
    - 结构化编辑辅助方法：`addVariable`、`removeVariable(at:)`、`updateVariable(id:key:value:quoting:)`、`addPathSegment(_)`、`removePathSegment(at:)`。
- **Acceptance Criteria Addressed**：AC-3, AC-5, AC-6, AC-7
- **Test Requirements**：
  - `programmatic` TR-3.1：`select` → 修改 `doc` → `switchMode(to:.raw)` → `switchMode(to:.structured)`，`doc` 与原来一致（往返一致性）。
  - `programmatic` TR-3.2：`save` 成功后 `errorMessage == nil` 且 `rawText` 与磁盘一致。
  - `programmatic` TR-3.3：模拟 Service 抛错时，`errorMessage` 被设置、`rawText` 与 `doc` 保持编辑中的内容不被回滚。
  - `human-judgement` TR-3.4：代码审查确认 IO 明确使用了 `Task.detached` 或 `Task { await Task.detached }` 组合，主线程无阻塞。

## [x] Task 4: 实现 ShellEnvView（双视图 UI）
- **Priority**: P0
- **Depends On**: Task 3
- **Description**：
  - 新建 [ShellEnvView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/System/ShellEnvView.swift)：
    - 布局参考 [CLIConfigView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Views/AI/CLIConfigView.swift)：左侧 rc 文件列表（当前 shell 项旁边加一个圆角小标签"当前 shell"），右侧详情区顶部为文件路径与视图切换 `Picker`（结构化 / 原文）。
    - 结构化视图使用 `List` 展示变量（键、值、引号选择器、是否 export、删除按钮），下方独立小节展示 `PATH` 追加片段（可增删）；顶部"新增变量"按钮。
    - 原文视图使用等宽字体 `TextEditor`。
    - 工具栏右侧提供"刷新"与"保存"按钮，参考 CLIConfigView。
    - 错误横幅样式复用 CLIConfigView 的写法。
    - `.task { vm.refresh() }` + `onChange(of: vm.selection)` 触发加载。
- **Acceptance Criteria Addressed**：AC-1, AC-2, AC-6, AC-7
- **Test Requirements**：
  - `programmatic` TR-4.1：`swift build` 通过，无警告。
  - `human-judgement` TR-4.2：手动点击不同文件、切换视图、增删变量与路径片段体验流畅；错误横幅在制造错误时可见。
  - `human-judgement` TR-4.3：视觉一致（间距、按钮位置、字体）与 CLIConfigView 对齐。

## [x] Task 5: 接入导航与本地化
- **Priority**: P0
- **Depends On**: Task 4
- **Description**：
  - 在 [AppNavigation.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/AppNavigation.swift) 增加 `.systemShellEnv` case（`id="system.shellEnv"`，systemImage 建议 `terminal.fill` 或 `text.badge.gearshape`），加入 `allCases` 与 `allSections`（放到 `nav.system` 组内、`.settings` 之前）。
  - 在 [DetailView.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/App/DetailView.swift) 增加对应 switch 分支，展示 `ShellEnvView()`。
  - 在 [Localization+Zh.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+Zh.swift) 与 [Localization+En.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Sources/EnvMatrix/Utils/Localization+En.swift) 新增：
    - `nav.shellEnv`、`shellEnv.title`、`shellEnv.currentShell`、`shellEnv.mode.structured`、`shellEnv.mode.raw`、`shellEnv.addVariable`、`shellEnv.addPath`、`shellEnv.emptySelect`、`shellEnv.emptySelect.hint`、`shellEnv.save`、`shellEnv.refresh`、`shellEnv.error.readFailed`、`shellEnv.error.writeFailed`、`shellEnv.export`、`shellEnv.quoting.none/.single/.double`、`shellEnv.unparsedLines`。
- **Acceptance Criteria Addressed**：AC-1, AC-8
- **Test Requirements**：
  - `programmatic` TR-5.1：`swift build` 通过。
  - `programmatic` TR-5.2：新增本地化 key 在中/英两份文件中都存在（可用简单 diff 脚本或人工核对）。
  - `human-judgement` TR-5.3：切换应用语言后，模块内文字全部随之切换，无硬编码。

## [x] Task 6: 编写单元测试
- **Priority**: P1
- **Depends On**: Task 1, Task 2, Task 3
- **Description**：
  - 新建 [ShellEnvParserTests.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Tests/EnvMatrixTests/ShellEnvParserTests.swift) 覆盖 TR-1.1 到 TR-1.4。
  - 新建 [ShellEnvServiceTests.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Tests/EnvMatrixTests/ShellEnvServiceTests.swift) 覆盖 TR-2.1 到 TR-2.4；使用临时目录作为 home。
  - 新建 [ShellEnvViewModelTests.swift](file:///Users/masamiyui/OpenSoureProjects/envmatrix/Tests/EnvMatrixTests/ShellEnvViewModelTests.swift) 覆盖 TR-3.1 到 TR-3.3；使用 fake `ShellEnvService`。
- **Acceptance Criteria Addressed**：AC-3, AC-4, AC-5, AC-7
- **Test Requirements**：
  - `programmatic` TR-6.1：`swift test` 通过；新增测试全部绿色。

## [x] Task 7: 端到端验证与文档更新
- **Priority**: P1
- **Depends On**: Task 4, Task 5, Task 6
- **Description**：
  - 用真机 `~/.zshrc` 做一次"结构化改一个变量 → 保存 → 检查磁盘备份 → 切换原文视图 → 再改再存"的完整走查。
  - 更新 README 的功能列表（若需要），仅追加一行提到新的"Shell 本地环境"模块——**不新建文档文件**。
- **Acceptance Criteria Addressed**：AC-4, AC-6, AC-7
- **Test Requirements**：
  - `human-judgement` TR-7.1：走查通过、备份文件产生、UI 无卡顿、无本地化遗漏。
