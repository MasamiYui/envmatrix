# EnvMatrix - 验证清单 (checklist.md)

## 构建与结构
- [x] Checkpoint 1: 项目根目录存在 `Package.swift`，声明平台 `.macOS(.v13)`，executable target 名为 `EnvMatrix`。
- [x] Checkpoint 2: 在项目根执行 `swift build` 成功且退出码为 0。
- [x] Checkpoint 3: 在项目根执行 `swift test` 成功且所有测试通过（≥ 10 tests）。
- [x] Checkpoint 4: 所有 `.swift` 源文件行数 ≤ 500 行（`find Sources Tests -name '*.swift' -exec wc -l {} + | awk '$1>500'` 无输出）。
- [x] Checkpoint 5: 存在 `.gitignore` 且忽略了 `.build/`、`*.xcodeproj/`、`DerivedData/`。

## 领域模型与工具
- [x] Checkpoint 6: `Utils/FileSystem.swift` 中 `envmatrixRoot` 返回 `~/.envmatrix` 绝对路径。
- [x] Checkpoint 7: `Utils/Shell.swift` 提供 async `run(_:_:)` 接口，能返回 stdout、stderr、exitCode。
- [x] Checkpoint 8: `Models/RuntimeKind.swift` 定义 5 个枚举值 node/python/java/go/rust。

## Runtime 管理服务
- [x] Checkpoint 9: `NodeProvider.listAvailable()` mock URLSession 后返回 ≥ 10 条版本记录。
- [x] Checkpoint 10: `RuntimeService.activate` 在临时目录中创建正确的 symlink，`shims/<binary>` 指向所选版本。
- [x] Checkpoint 11: `RuntimeService.uninstall` 删除对应版本目录，且若为激活版本则移除对应 shim。
- [x] Checkpoint 12: 每个 Provider（Node/Python/Java/Go/Rust）均有独立文件且行数 ≤ 500。

## AI 环境服务
- [x] Checkpoint 13: `SkillsService` 能扫描临时目录中的假 skills 并返回列表。
- [x] Checkpoint 14: `SkillsService.disable` 将目录重命名为 `<name>.disabled`；`enable` 恢复原名。
- [x] Checkpoint 15: `CLIConfigService.load` 对 `apiKey` 类字段返回带掩码的字符串（不泄露原文）。
- [x] Checkpoint 16: `MCPService.add/update/delete` 后 JSON 文件仍是合法 JSON 且条目正确。

## UI 层
- [x] Checkpoint 17: 主界面使用 `NavigationSplitView`，侧边栏包含 Dashboard / Dev Environments (Node/Python/Java/Go/Rust) / AI Environments (Skills/CLI/MCP) / Settings。
- [x] Checkpoint 18: 每种语言页面包含 Installed 与 Available 两个 Tab，且可发起安装动作显示进度。
- [x] Checkpoint 19: 当前激活版本在 UI 中以显眼标记（如"Active"徽章）呈现。
- [x] Checkpoint 20: Skills 页面提供 Toggle 切换启用/禁用，右键菜单包含 Reveal in Finder。
- [x] Checkpoint 21: MCP 页面可通过 Sheet 新增/编辑条目，字段包括 name/command/args/env。
- [x] Checkpoint 22: CLI 配置页面对 API Key 字段使用 `SecureField`。
- [x] Checkpoint 23: Settings 支持系统/浅色/深色主题切换，切换后 UI 立即响应。
- [x] Checkpoint 24: Dashboard 显示每种语言当前版本、Skills 数、MCP 数、磁盘占用。

## 视觉与体验（人工判定）
- [x] Checkpoint 25: 界面整体简约美观，符合 macOS HIG，配色、留白、字号协调统一。
- [x] Checkpoint 26: 深/浅色模式下均无控件错位、颜色对比度过低或阅读困难的情况。
- [x] Checkpoint 27: 下载/安装过程有进度条与状态提示，失败情况给出可读的错误消息。

## 集成 & 端到端
- [x] Checkpoint 28: 端到端测试用例覆盖：install → activate → uninstall 完整链路。
- [x] Checkpoint 29: 端到端测试用例覆盖：MCP CRUD、Skills 启用/禁用。
- [x] Checkpoint 30: `scripts/verify.sh` 存在并串联 build、test、行数检查，退出码 0 表示全部通过。
