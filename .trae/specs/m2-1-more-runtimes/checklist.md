# M2.1 · 新增 Runtime — Verification Checklist

- [x] Checkpoint 1: `RuntimeKind.allCases.count == 11`，且新增 6 case 的 `displayName`/`binaryName` 与 spec FR-1 完全一致（`RuntimeKindTests` 单测覆盖）。
- [x] Checkpoint 2: 侧边栏 Dev Environments 分区、Dashboard 卡片均自动增加 6 项；SF Symbol 图标无灰色 "?" fallback。
- [x] Checkpoint 3: `RubyProvider.decode` 从 fixture 稳定解析版本，剔除 preview/rc。
- [x] Checkpoint 4: `PhpProvider.decode` 从 JSON fixture 至少解析 3 条版本。
- [x] Checkpoint 5: `DenoProvider.decode` 与 `BunProvider.decode` 正确剥前缀、过滤 prerelease/draft。
- [x] Checkpoint 6: `DotnetProvider.decode` 从 releases-index fixture 拿到 `latest-sdk`；`ErlangProvider.decode` 剥离 `OTP-`。
- [x] Checkpoint 7: 所有 provider 在网络返回 500 / 非 2xx 时降级为空数组或明确抛 `RuntimeServiceError.network`，绝不 crash。
- [x] Checkpoint 8: `SystemRuntimeDetector.parseVersion` 对 6 门语言的典型 `--version` 输出全部返回预期版本号。
- [x] Checkpoint 9: 临时目录构造 `~/.rbenv/versions/3.3.0/bin/ruby` 可执行脚本后，`detector.detect(.ruby)` 至少返回 1 条 `isSystem == true`。
- [x] Checkpoint 10: 使用 rbenv / phpenv / kerl 路径的 `RuntimeVersion` 调用 `uninstall` 抛 `permissionDenied`，`suggestion` 与 spec FR-10 匹配。
- [x] Checkpoint 11: `swift build` 无警告；`swift test --parallel` 汇总 ≥ 79 tests 全绿。
- [x] Checkpoint 12: `./scripts/check_file_lines.sh 500` exit 0；每个新 provider 文件 ≤ 200 行。
- [ ] Checkpoint 13: `git push` 后 GitHub Actions 的 CI 与 Lint workflow 均 success。
