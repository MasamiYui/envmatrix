# Spec: /etc/hosts 管理（Hosts Manager）

## 1. 背景 & 目标

在 EnvMatrix 已具备 [Shell 本地环境管理](../shell-env-manager/spec.md) 的基础上，为「System」分组再补充一个高频刚需——**/etc/hosts 可视化管理**：

- 逐条查看、增删改 hosts 记录（IP + 主机名 + 注释）。
- 通过「注释切换」实现**启用 / 禁用**单条记录，避免破坏性删除。
- 支持**分组 / Profile 切换**：预设多套 hosts 方案（如 `default`、`dev`、`no-ads`），一键写入 `/etc/hosts`。
- 写入 `/etc/hosts` 需要 root 权限，采用 **AppleScript `with administrator privileges`** 拉起系统授权弹窗，避免维护 privileged helper。

## 2. 范围

### 2.1 In Scope

- 读取 `/etc/hosts` 原文（无 sudo，全用户可读）。
- 解析 hosts 语法：`IP  HOSTNAME [ALIAS...] [# COMMENT]`，支持注释行、空行。
- 结构化视图：
  - 每行渲染为 IP、主机名（多个 alias 以空格分隔）、注释、启用开关（禁用即在行首加 `#`）。
  - 支持新增 / 编辑 / 删除；批量启停一段区域（`# ==== dev ====` block）。
- 原文视图：等宽字体 TextEditor，直接编辑纯文本。
- 双视图**无损往返**（未识别的行进入 `.unparsed(...)` 保底）。
- Profile 管理：
  - 用户可保存多套 hosts 文本到应用私有目录 `~/Library/Application Support/EnvMatrix/hosts/profiles/`。
  - 通过 Profile 选择器一键把某个 profile 内容写入 `/etc/hosts`。
  - 提供「另存为」「重命名」「删除」「设为默认」。
- 写入流程：
  - 先在 `/tmp/envmatrix-hosts-<timestamp>` 生成候选文件。
  - 通过 `osascript -e 'do shell script "cp ... /etc/hosts && chmod 644 /etc/hosts" with administrator privileges'` 提权覆盖。
  - 同时把覆盖前的 `/etc/hosts` 备份为 `~/Library/Application Support/EnvMatrix/hosts/backups/hosts.<yyyyMMdd-HHmmss>.bak`（用户目录，无需提权）。
- 完整中英文本地化。

### 2.2 Out of Scope

- 远程 hosts 订阅（下拉合并 `hosts.example.com` 之类的 blocklist）。
- 域名可达性 / DNS 解析健康检查。
- IPv6 特殊语法的智能补全（保留能力，仅按普通 hosts 行解析）。
- 与 `dscacheutil -flushcache` / `killall -HUP mDNSResponder` 的联动（后续增强）。

## 3. 用户故事

1. 作为 macOS 开发者，我想在 `/etc/hosts` 里加一行 `127.0.0.1 gitlab.company.internal`，希望**不用打开终端**。
2. 作为测试人员，我要在 `dev` / `prod` 两套 hosts 间快速切换，避免每次改文件。
3. 作为普通用户，我不想删除一行 hosts，只想暂时停用它——期望像 checkbox 一样点一下就注释掉。
4. 作为谨慎用户，我希望写入前系统会弹一次 Touch ID / 密码授权，且**每次覆盖都留备份**。

## 4. 功能需求

### FR-1 侧边栏：Profile 列表
- 显示所有本地 Profile；`default` 由应用首次启动时自动初始化，等同当前 `/etc/hosts` 内容快照。
- 顶部工具条：新建、另存为、重命名、删除、设为默认。
- 高亮"当前系统 hosts 对应的 profile"（如果匹配某个 profile 文本则打勾）。

### FR-2 内容区：双视图
- Segmented Picker 切换 `Structured / Raw`。
- 结构化视图：
  - 表格式或卡片式，一行一条 hosts 记录。
  - 列：Enabled(toggle) / IP / Hostnames / Comment / 删除按钮。
  - 顶部按钮：`Add Entry`。
- 原文视图：等宽 TextEditor。
- 切换视图时无损往返。

### FR-3 保存与应用
- 保存 Profile：写入 `~/Library/Application Support/EnvMatrix/hosts/profiles/<name>.hosts`，无需授权。
- 应用到系统：
  - 生成临时文件；
  - 通过 osascript 提权 `cp` + `chmod 644`；
  - 备份原 `/etc/hosts` 到用户目录；
  - 成功后刷新"当前系统 hosts"缓存并 diff 高亮。

### FR-4 错误处理
- 用户取消授权：显示 friendly banner，不清空编辑器内容。
- 提权失败或 IO 错误：显示错误消息，且不删除已生成的临时文件（便于排查）。
- 无法读取 `/etc/hosts`（罕见）：给出兜底空文档并允许"另存为 Profile"。

## 5. 非功能需求

- **性能**：hosts 通常 < 100KB，直接一次读入内存即可；解析在主线程完成也很快，但仍走后台 `Task.detached(priority: .utility)` 以保持一致的架构。
- **安全**：仅当用户点击"Apply to system"时才触发提权；只 `cp` 一个临时文件，不执行任何用户输入 shell。
- **一致性**：目录、命名、错误类型、备份文件名格式与 [ShellEnvService.swift](../../Sources/EnvMatrix/Services/ShellEnvService.swift) 保持一致。
- **可测性**：Service 与 Parser 均通过 protocol 注入；写入器（`HostsPrivilegedWriter`）可被 Mock，让 ViewModel 测试无需真实提权。
- **i18n**：所有 UI 文案落到 `Localization+En.swift` / `Localization+Zh.swift`。

## 6. 系统约束

- macOS 13+；使用 `Process` 调用系统内置 `/usr/bin/osascript`，无第三方依赖。
- `/etc/hosts` 编码固定为 UTF-8（macOS 默认）。
- 应用私有数据目录：`~/Library/Application Support/EnvMatrix/hosts/`。

## 7. 数据模型（Draft）

```swift
public enum HostsEntryKind { case entry, comment, blank, unparsed }

public struct HostsEntry: Identifiable, Hashable {
    public let id: UUID
    public var isEnabled: Bool     // false => 行首带 `#`
    public var ip: String
    public var hostnames: [String]
    public var comment: String?    // 尾注释，去掉前导 `#`
}

public enum HostsLine: Identifiable, Hashable {
    case entry(HostsEntry)
    case comment(String)   // 纯注释行
    case blank
    case unparsed(String)
}

public struct HostsDocument: Hashable {
    public var lines: [HostsLine]
    public var lineEnding: String
    public var trailingNewline: Bool
}

public struct HostsProfile: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var isDefault: Bool
}
```

## 8. 关键交互流程

1. 应用启动 → `HostsViewModel.refresh()`：
   - 读取 `/etc/hosts` → 生成 `system` 快照；
   - 扫描 profiles 目录 → 加载列表；
   - 若目录为空，自动把系统快照写为 `default.hosts` 并设为默认；
   - 选中当前"系统一致"的 profile 或第一个。
2. 用户编辑 Profile → `save()` 写入用户目录，不动系统。
3. 用户点击 `Apply to system`：
   - 写入临时文件；
   - 备份 `/etc/hosts` → 用户目录；
   - 调用 osascript 提权覆盖；
   - 结束后清理临时文件，成功回调刷新 UI。

## 9. 验收标准

- 侧边栏 System 分组下出现 **"Hosts 管理"** 入口，带 `externaldrive.connected.to.line.below` 或 `network` 图标。
- 结构化视图可增删改，双视图无损往返（unparsed 行原样保留）。
- 通过 checkbox 禁用一条记录后保存 profile，原文视图能看到行首 `#`。
- Profile 新建 / 另存为 / 重命名 / 删除 / 切换正常。
- 点击 `Apply to system` 触发系统授权，通过后 `/etc/hosts` 内容与所选 profile 完全一致；备份文件生成于 `~/Library/Application Support/EnvMatrix/hosts/backups/`。
- 中英文界面切换无遗漏。

## 10. 风险与回滚

- 用户可能因权限授权失败而卡住 → 每次写入前先备份，UI 提供"打开备份目录"和"还原上一个备份"入口。
- 若 osascript 版本差异导致命令失败，回退到读取失败态并提示用户手动 sudo（暴露临时文件路径供人工 cp）。
