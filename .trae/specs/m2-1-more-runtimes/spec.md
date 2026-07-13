# M2.1 · 新增 Runtime（Ruby / PHP / Deno / Bun / .NET / Erlang）- 产品需求文档

## Overview
- **Summary**：为 EnvMatrix 追加 6 门主流 Runtime 的完整管理能力（列举、下载、激活、卸载、系统识别），复用现有 `VersionProvider` / `SystemRuntimeDetector` / `RuntimeService` 抽象，保持"Provider 即插件"的架构。
- **Purpose**：把 EnvMatrix 从"5 门语言"扩到覆盖前后端、脚本、桌面/工业多领域的 11 门语言，让更多开发者能作为**单一控制台**使用；同时验证 Provider 抽象在异构安装介质下的健壮性。
- **Target Users**：Ruby / Rails、PHP / Laravel、Deno、Bun、.NET / C#、Erlang / Elixir 开发者，以及需要多语言并存的全栈 / DevOps 工程师。

## Goals
- 新增 6 门语言的 `RuntimeKind`：`ruby`、`php`、`deno`、`bun`、`dotnet`、`erlang`。
- 每门语言至少支持：**在线版本列举**、**系统已装识别**、**Set Active（shim）**、**Uninstall（含 System 智能保护）**。
- 侧边栏 [SidebarView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/SidebarView.swift) 与 Dashboard [DashboardView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Dashboard/DashboardView.swift) 自动包含新增语言。
- 关键 Provider 有单元测试，`swift test` 全绿；单文件仍 < 500 行。

## Non-Goals (Out of Scope)
- **不做二进制真实下载/解压的完整安装**：Ruby/PHP/Erlang/.NET 原生分发多为源码或系统级 pkg，网络下载安装能力放到后续里程碑（复用 [DefaultRuntimeService.install](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/RuntimeService.swift)），本期仅**列表 & 识别 & 激活 & 卸载**。
- 不新增 macOS 权限申请、代码签名、GUI 大改（保持现有 Installed/Available 双 Tab UX）。
- 不集成 rbenv/phpenv/asdf 的写操作（读方向已由 detector 支持）。

## Background & Context
- 现有 5 门语言的 provider 遵循 [VersionProvider](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/RuntimeService.swift) 协议，各自访问官方 index 拉版本。
- 系统识别位于 [DefaultSystemRuntimeDetector](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/SystemRuntimeDetector.swift)，按 `RuntimeKind` 分派候选目录与版本命令。
- 新增 kind 只需三处硬点：`RuntimeKind` 枚举、`RuntimeService.init` 的默认 provider map、`SystemRuntimeDetector` 的候选目录 + 版本解析。

## Functional Requirements
- **FR-1**：`RuntimeKind` 增加 `ruby` / `php` / `deno` / `bun` / `dotnet` / `erlang` 六个 case，提供 `displayName` 与 `binaryName`。
- **FR-2**：`RubyProvider` 从 https://cache.ruby-lang.org/pub/ruby/index.txt 或 GitHub Releases API 拉版本（≥ 20 条稳定版）。
- **FR-3**：`PhpProvider` 从 https://www.php.net/releases/index.php?json&max=30 拉版本。
- **FR-4**：`DenoProvider` 从 https://api.github.com/repos/denoland/deno/releases 拉 tag，过滤 `v*`。
- **FR-5**：`BunProvider` 从 https://api.github.com/repos/oven-sh/bun/releases 拉 tag。
- **FR-6**：`DotnetProvider` 从 https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json 拉 channel 列表。
- **FR-7**：`ErlangProvider` 从 https://api.github.com/repos/erlang/otp/releases 拉版本。
- **FR-8**：`DefaultSystemRuntimeDetector` 扩展候选目录：
    - Ruby: `/opt/homebrew/opt/ruby/bin`、`~/.rbenv/versions/*/bin`、`~/.rvm/rubies/*/bin`
    - PHP: `/opt/homebrew/opt/php*/bin`、`~/.phpenv/versions/*/bin`
    - Deno: `~/.deno/bin`
    - Bun: `~/.bun/bin`
    - .NET: `/usr/local/share/dotnet`、`~/.dotnet`
    - Erlang: `/opt/homebrew/opt/erlang/bin`、`~/.kerl/installations/*/bin`
- **FR-9**：`versionArgs(for:)` 与 `parseVersion(_:kind:)` 覆盖新语言输出：
    - Ruby: `ruby --version` → `ruby 3.3.0p0 (...)`
    - PHP: `php --version` → `PHP 8.3.0 (...)`
    - Deno: `deno --version` → `deno 1.40.0 ...`
    - Bun: `bun --version` → `1.0.20`
    - Dotnet: `dotnet --version` → `8.0.100`
    - Erlang: `erl -eval "erlang:display(erlang:system_info(otp_release))"` 或 `erl -version` → 输出如 `Erlang (SMP,ASYNC_THREADS) (BEAM) emulator version 14.2.1`。
- **FR-10**：`RuntimeService.init` 默认注入 6 个新 provider；`packageManagerHint` 增加 rbenv/phpenv/kerl 提示；forbiddenPrefixes 保持不变（新语言若跑到 `/usr/local/share/dotnet` 只提示 sudo）。
- **FR-11**：UI 层无需改动即自动生效：`SidebarView` 遍历 `RuntimeKind.allCases`；`RuntimeDetailView` icon 增加对应 SF Symbol 或 fallback。

## Non-Functional Requirements
- **NFR-1**：单元测试新增 ≥ 12 条（每个 provider 至少 1 条 decode/parse 快乐路径 + 1 条系统版本 parse）。
- **NFR-2**：单个 Swift 文件仍 ≤ 500 行（守护脚本 [check_file_lines.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/check_file_lines.sh) 强制）。
- **NFR-3**：Provider 网络失败必须**降级**为返回空数组而非崩溃（与现有 `RustProvider` 一致）。
- **NFR-4**：`swift build` 与 `swift test` 全绿，CI 流水线 [ci.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/ci.yml) 通过。

## Constraints
- **Technical**：Swift 5.9 / macOS 13+；仅使用 Foundation，不引入外部依赖。
- **Business**：一个人日预算 ≤ 6d；不为此扩期。
- **Dependencies**：无新增第三方库；网络请求走既有 `URLSession`。

## Assumptions
- 官方 index/GitHub API 允许 anonymous 请求（未登录状态 60 req/hour 足够）；测试使用固定 JSON fixture，不依赖真实网络。
- 用户即使未安装某语言，也允许在 Available Tab 中浏览列表。
- Erlang 使用 `erl -version` 输出 stderr，需按现有 `runVersionCommand` 合并 stdout/stderr。

## Acceptance Criteria

### AC-1: 新枚举与显示名
- **Given**：编译通过后
- **When**：遍历 `RuntimeKind.allCases`
- **Then**：得到 11 个 case，且每个 case 的 `displayName`、`binaryName` 与 FR-1 定义一致。
- **Verification**：`programmatic`

### AC-2: 侧边栏与 Dashboard 自动扩展
- **Given**：`RuntimeKind` 增加 6 个 case
- **When**：应用启动
- **Then**：[SidebarView](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/SidebarView.swift) 的 Dev Environments 分区新增 6 行；Dashboard 卡片区新增 6 张 Runtime 卡片；不产生编译警告。
- **Verification**：`human-judgment`

### AC-3: 各 Provider 列表解析
- **Given**：捆绑的 JSON/HTML fixture（每语言一份最小样本）
- **When**：执行 `decode`（或 `parse`）
- **Then**：至少返回 1 条 `RuntimeVersion`，`version` 是纯语义版本号，不含前缀 `v`；`downloadURL` 是有效 HTTPS。
- **Verification**：`programmatic`

### AC-4: 版本命令输出解析
- **Given**：给每种语言的典型 `--version` 文本作为输入
- **When**：调用 `parseVersion(_:kind:)`
- **Then**：返回预期版本号（如 `3.3.0`、`8.3.0`、`1.40.0`、`1.0.20`、`8.0.100`、`26.2.1`）。
- **Verification**：`programmatic`

### AC-5: 系统识别路径
- **Given**：在临时目录构造类 `~/.rbenv/versions/3.3.0/bin/ruby` 的可执行伪 shell 脚本
- **When**：detector `detect(kind: .ruby)`
- **Then**：至少返回 1 条 `isSystem == true`、`installPath` 指向父目录的记录。
- **Verification**：`programmatic`

### AC-6: 网络失败降级
- **Given**：注入的 URLSession 返回 500
- **When**：`listAvailable()`
- **Then**：Provider 抛出 `RuntimeServiceError.network` 或返回空数组，绝不 crash；上层视图显示错误 toast。
- **Verification**：`programmatic`

### AC-7: 卸载建议命令
- **Given**：一个通过 rbenv 安装的 Ruby 3.3.0（installPath 含 `.rbenv/versions/`）
- **When**：`uninstall(version:)`
- **Then**：抛 `RuntimeServiceError.permissionDenied`，`suggestion == "rbenv uninstall 3.3.0"`。
- **Verification**：`programmatic`

### AC-8: 单元测试通过
- **Given**：分支代码
- **When**：`swift test --parallel`
- **Then**：本期新增 ≥ 12 条测试，全部为 passed，总计 ≥ 79 条测试全绿。
- **Verification**：`programmatic`

### AC-9: 文件行数守护
- **Given**：本期结束的仓库
- **When**：`./scripts/check_file_lines.sh 500`
- **Then**：exit 0，所有新 provider 文件 ≤ 200 行。
- **Verification**：`programmatic`

### AC-10: CI 绿
- **Given**：commit 推送到 origin
- **When**：GitHub Actions 运行 [ci.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/ci.yml) 与 [lint.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/lint.yml)
- **Then**：两条 workflow 都为 success。
- **Verification**：`programmatic`

## Open Questions
- [ ] 是否需要给 .NET 单独区分 SDK / Runtime？→ 本期先当作单一 SDK 列表处理。
- [ ] Erlang 与 Elixir 关系？→ 本期只做 Erlang/OTP；Elixir 后续单独立项。
- [ ] Ruby index 若 HTTP 429 频繁，是否需要缓存？→ 本期不做缓存；网络失败降级为空即可。
