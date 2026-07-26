# Checklist: /etc/hosts 管理验收清单

## 功能
- [ ] 侧边栏 "System" 分组下出现 **Hosts 管理** 入口，带图标
- [ ] 打开页面首次会自动创建 `~/Library/Application Support/EnvMatrix/hosts/{profiles,backups}` 目录
- [ ] 若无任何 profile，自动把当前 `/etc/hosts` 快照写为 `default.hosts` 并设为默认
- [ ] 结构化视图支持：新增、编辑 IP / hostnames / comment、启用/禁用（勾选切换 `#`）、删除
- [ ] 原文视图支持等宽字体编辑
- [ ] 双视图切换无损（unparsed 行保持原样）
- [ ] Profile 支持：新建、另存为、重命名、删除、设为默认
- [ ] 顶部按钮 `Save Profile` 只写用户目录，不弹权限窗
- [ ] 顶部按钮 `Apply to system` 会弹出系统授权（Touch ID / 密码）
- [ ] 授权成功后 `/etc/hosts` 内容与当前 profile 一致
- [ ] 授权取消 / 失败给出 friendly 提示，不清空编辑器
- [ ] `~/Library/Application Support/EnvMatrix/hosts/backups/hosts.<ts>.bak` 生成成功

## 数据 & 无损性
- [ ] `HostsParser.serialize(parse(x)) == x` 对常见 hosts 文件成立（含 tab、多空格、CRLF、末行有无换行）
- [ ] 禁用条目输出为 `#IP HOST`；启用条目不带前导 `#`
- [ ] 尾注释保留：`127.0.0.1 example.com # dev machine`

## 代码质量
- [ ] Models / Services / ViewModel / Views 分层，遵循 MVVM
- [ ] Service 通过 protocol 注入，`HostsPrivilegedWriter` 可 mock
- [ ] 所有 IO 在 `Task.detached(priority: .utility)`
- [ ] 每个源文件 ≤ 500 行（`scripts/check_file_lines.sh` 通过）
- [ ] 所有 UI 文案落地到 En + Zh 本地化 key
- [ ] SwiftLint 无新增 warning

## 测试
- [ ] `swift build` 通过，无 error / warning
- [ ] `swift test` 全绿
- [ ] 新增测试：HostsParserTests / HostsServiceTests / HostsViewModelTests

## 文档
- [ ] README.md 更新，介绍 hosts 管理与 profile 能力
- [ ] Roadmap 勾选相应条目
- [ ] git commit 遵循 Conventional Commits
