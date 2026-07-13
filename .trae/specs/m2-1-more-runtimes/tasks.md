# M2.1 · 新增 Runtime — 实现计划（Decomposed and Prioritized Task List）

## [x] Task 1: 扩展 RuntimeKind 与图标 / Dashboard 支持
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 在 [RuntimeKind.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/RuntimeKind.swift) 增加 6 个 case：`ruby`、`php`、`deno`、`bun`、`dotnet`、`erlang`；补 `displayName` 与 `binaryName`（`dotnet` 的 binaryName = `dotnet`，Erlang 用 `erl`）。
  - 在 [DashboardView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Dashboard/DashboardView.swift) 的 `Self.icon(for:)` 加入新 kind 到 SF Symbol 的映射（例：ruby→"gem"、php→"chevron.left.forwardslash.chevron.right"、deno→"pawprint"、bun→"laurel.trailing"、dotnet→"n.circle"、erlang→"antenna.radiowaves.left.and.right"）。
  - 若 [RuntimeDetailView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/DevEnv/RuntimeDetailView.swift) 存在 `kindIcon` 分支，也补齐。
- **Acceptance Criteria Addressed**: AC-1, AC-2
- **Test Requirements**:
  - `programmatic` TR-1.1: 新增 `RuntimeKindTests.testAllCasesCountIsEleven` — `RuntimeKind.allCases.count == 11`。
  - `programmatic` TR-1.2: 遍历新增 6 case，`displayName` 与 `binaryName` 非空且不含空格。
  - `human-judgement` TR-1.3: 侧边栏 Dev Environments 显示 11 行，Dashboard 出现 11 张 Runtime 卡片，图标无 fallback 感叹号。

## [x] Task 2: RubyProvider + PhpProvider
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 在 [Providers](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/Providers) 新建 `RubyProvider.swift`：抓取 https://cache.ruby-lang.org/pub/ruby/index.txt（纯文本每行一个 tarball 名），按 `ruby-<X.Y.Z>.tar.gz` 正则解析出稳定版；忽略 preview/rc；截取前 30 条。
  - 新建 `PhpProvider.swift`：请求 https://www.php.net/releases/index.php?json&max=30 解析 JSON。
  - 两个 provider 内部结构与 [GoProvider.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/Providers/GoProvider.swift) 保持一致：`init(session:indexURL:)`、`listAvailable()`、`static decode(...)`。
  - 每个 provider 单文件 ≤ 200 行。
- **Acceptance Criteria Addressed**: AC-3, AC-6
- **Test Requirements**:
  - `programmatic` TR-2.1: `RubyProviderTests.testDecodeParsesStableList` — 给定 fixture（含 `ruby-3.3.0.tar.gz`、`ruby-3.2.3.tar.gz`、`ruby-3.3.0-preview1.tar.gz`），返回 2 条稳定版，version 分别为 `3.3.0`、`3.2.3`。
  - `programmatic` TR-2.2: `PhpProviderTests.testDecodeParsesTopReleases` — fixture 输入返回 ≥ 3 条，`version` 匹配 `\d+\.\d+\.\d+`。
  - `programmatic` TR-2.3: 网络返回 500 → `listAvailable()` 抛 `RuntimeServiceError.network`。

## [x] Task 3: DenoProvider + BunProvider（GitHub Releases API）
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 新建 `DenoProvider.swift` 与 `BunProvider.swift`：都请求 `https://api.github.com/repos/{owner}/{repo}/releases?per_page=30`；解析 JSON 数组，取 `tag_name`（Deno 为 `v1.40.0`、Bun 为 `bun-v1.0.20` 或 `bun-v1.0.20`），剥去前缀得到纯版本号。
  - 抽出内部 `struct GHRelease: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool }`；过滤 `draft == false && prerelease == false`。
  - 为了 tests 无需真访问 GitHub，`decode(data:)` 设为 `internal static`。
- **Acceptance Criteria Addressed**: AC-3, AC-6
- **Test Requirements**:
  - `programmatic` TR-3.1: `DenoProviderTests.testDecodeStripsVPrefix` — fixture 三条 tag `v1.40.0`、`v1.39.4`、`v1.39.3-rc.1` → 返回 2 条，纯版本 `1.40.0`、`1.39.4`。
  - `programmatic` TR-3.2: `BunProviderTests.testDecodeStripsBunPrefix` — fixture 三条 `bun-v1.0.20`、`bun-v1.0.19`，返回版本 `1.0.20`、`1.0.19`。
  - `programmatic` TR-3.3: 空 JSON 数组 → 返回空数组，不抛。

## [x] Task 4: DotnetProvider + ErlangProvider
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - `DotnetProvider.swift`：请求 `https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json`，解析 `releases-index[].latest-sdk`（如 `8.0.100`）；返回不超过 20 条。
  - `ErlangProvider.swift`：请求 `https://api.github.com/repos/erlang/otp/releases?per_page=30`；tag 形如 `OTP-26.2.1`，去掉 `OTP-` 前缀。
- **Acceptance Criteria Addressed**: AC-3, AC-6
- **Test Requirements**:
  - `programmatic` TR-4.1: `DotnetProviderTests.testDecodeReturnsLatestSdk` — fixture 两个 channel → 返回两条，version 为 `8.0.100`、`7.0.404`。
  - `programmatic` TR-4.2: `ErlangProviderTests.testDecodeStripsOTPPrefix` — 返回 `26.2.1`。

## [x] Task 5: SystemRuntimeDetector 支持新语言
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 在 [DefaultSystemRuntimeDetector.candidateBinDirs(for:)](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/SystemRuntimeDetector.swift) `switch` 增加：
    - `.ruby`: `/opt/homebrew/opt/ruby/bin`、`~/.rbenv/versions/*/bin`、`~/.rvm/rubies/*/bin`
    - `.php`: `expandGlob("/opt/homebrew/opt/php*/bin")`、`~/.phpenv/versions/*/bin`
    - `.deno`: `~/.deno/bin`
    - `.bun`: `~/.bun/bin`
    - `.dotnet`: `/usr/local/share/dotnet`、`~/.dotnet`
    - `.erlang`: `/opt/homebrew/opt/erlang/bin`、`~/.kerl/installations/*/bin`
  - `versionArgs(for:)` 增加分支（Erlang 用 `["-version"]`；Bun `--version`；其余 `--version`）。
  - `parseVersion(_:kind:)` 增加正则：
    - `.ruby` → `#"ruby\s+(\d+\.\d+\.\d+)"#`
    - `.php` → `#"PHP\s+(\d+\.\d+\.\d+)"#`
    - `.deno` → `#"deno\s+(\d+\.\d+\.\d+)"#`
    - `.bun` → `#"^(\d+\.\d+\.\d+)"#`
    - `.dotnet` → `#"^(\d+\.\d+\.\d+)"#`
    - `.erlang` → `#"emulator version\s+(\d+(?:\.\d+){1,2})"#`（回退：`#"(\d+(?:\.\d+){1,2})"#`）
- **Acceptance Criteria Addressed**: AC-4, AC-5, AC-9
- **Test Requirements**:
  - `programmatic` TR-5.1: `SystemRuntimeDetectorTests.testParseRubyVersion` — 输入 `"ruby 3.3.0p0 (2023-12-25 revision xxx) [arm64-darwin23]"` → `3.3.0`。
  - `programmatic` TR-5.2: `testParsePhpVersion` — `"PHP 8.3.0 (cli) (built: ...)"` → `8.3.0`。
  - `programmatic` TR-5.3: `testParseDenoVersion` — `"deno 1.40.0 (release, aarch64-apple-darwin)"` → `1.40.0`。
  - `programmatic` TR-5.4: `testParseBunVersion` — `"1.0.20\n"` → `1.0.20`。
  - `programmatic` TR-5.5: `testParseDotnetVersion` — `"8.0.100"` → `8.0.100`。
  - `programmatic` TR-5.6: `testParseErlangVersion` — `"Erlang (SMP,ASYNC_THREADS) (BEAM) emulator version 14.2.1\n"` → `14.2.1`。
  - `programmatic` TR-5.7: `testDetectRbenvRubyFromTempDir` — 在临时 HOME 目录构造 `~/.rbenv/versions/3.3.0/bin/ruby` 为可执行 shell 脚本（`echo "ruby 3.3.0p0"`），`detect(.ruby)` 至少返回 1 条 `isSystem == true`。
- **Notes**: `RuntimeKind` switch 的 exhaustive 检查会强制我们补齐所有 6 种情况；测试脚本要用 `chmod +x` 才能被 `isExecutableFile` 判定通过。

## [ ] Task 6: RuntimeService 注入 + packageManagerHint 扩展
- **Priority**: P0
- **Depends On**: Task 2, 3, 4, 5
- **Description**:
  - 在 [DefaultRuntimeService.init](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/RuntimeService.swift) 的默认 provider map 追加 6 个新 provider。
  - 在 [packageManagerHint](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Services/RuntimeService.swift) 追加：
    - `.rbenv/versions/` → `rbenv uninstall <handle>`
    - `.rvm/rubies/` → `rvm remove <handle>`
    - `.phpenv/versions/` → `phpenv uninstall <handle>`
    - `.kerl/installations/` → `kerl delete installation <handle>`
    - `.deno`、`.bun`、`.dotnet` 无标准 uninstaller → 返回 nil（走目录删除 / sudo 提示）。
- **Acceptance Criteria Addressed**: AC-7
- **Test Requirements**:
  - `programmatic` TR-6.1: `RuntimeServiceTests.testUninstallRbenvRubyHintsCommand` — 构造 `RuntimeVersion(kind: .ruby, version: "3.3.0", installPath: URL(fileURLWithPath: "/Users/x/.rbenv/versions/3.3.0"), isSystem: true)`，`uninstall` 抛 `permissionDenied` 且 `suggestion == "rbenv uninstall 3.3.0"`。
  - `programmatic` TR-6.2: `testUninstallPhpenvHintsCommand` — 同上，`phpenv uninstall <handle>`。

## [x] Task 7: 收尾 — 测试 & Lint & CI
- **Priority**: P0
- **Depends On**: Task 6
- **Description**:
  - 本地执行 `swift build`、`swift test --parallel`、`./scripts/check_file_lines.sh 500` 三绿。
  - 若哪个新 provider 文件超行则拆分（helper struct 移到独立小文件）。
  - 提交 commit `feat(runtimes): add Ruby, PHP, Deno, Bun, .NET, Erlang providers`；push 到 origin/main；等待 GitHub Actions 全绿。
- **Acceptance Criteria Addressed**: AC-8, AC-9, AC-10
- **Test Requirements**:
  - `programmatic` TR-7.1: `swift test` 汇总 ≥ 79 tests 全绿（当前 67 + 至少新增 12）。
  - `programmatic` TR-7.2: `./scripts/check_file_lines.sh 500` exit 0。
  - `programmatic` TR-7.3: GitHub Actions CI 与 Lint 两条 workflow 均 success。
