# Local Apps Manager - Verification Checklist

## Models & 数据结构
- [x] Checkpoint 1: `LocalApp` / `LocalAppSource` / `LocalAppLeftover` 三个类型定义齐全并均实现 `Codable + Hashable + Identifiable`
- [x] Checkpoint 2: `LocalAppSource` 覆盖 `.appStore / .brewCask(token) / .other`，`Codable` 往返序列化保持相等

## Scanner
- [x] Checkpoint 3: 扫描 `/Applications` 与 `~/Applications` 及一级子目录（如 `Utilities`），识别 `*.app` bundle
- [x] Checkpoint 4: 从 `Info.plist` 正确抽取 name / displayName / version / bundleId / iconFile
- [x] Checkpoint 5: bundle 大小通过 `totalFileAllocatedSize` 递归计算得出，单位 bytes
- [x] Checkpoint 6: 存在 `Contents/_MASReceipt/receipt` 时来源判定为 `.appStore`
- [x] Checkpoint 7: `TaskGroup` 并发解析，200 个 fixture 应用扫描 < 5s
- [x] Checkpoint 8: 空 roots / 权限受限目录不抛异常，返回可用结果

## Brew Cask 识别
- [x] Checkpoint 9: 抽象为 `BrewCaskProbe` 协议，Default 实现调用 brew CLI，缺失 brew 时返回空 map
- [x] Checkpoint 10: 命中 basename → cask token 映射时 source == `.brewCask(token)`
- [x] Checkpoint 11: 未命中且非 MAS 时 source == `.other`

## Service 操作
- [x] Checkpoint 12: `openApp` 通过注入的 `AppLauncher` 打开应用
- [x] Checkpoint 13: `revealInFinder` 通过 `AppLauncher.reveal(URL)` 触发 Finder
- [x] Checkpoint 14: `moveToTrash` 使用 `Trasher` 协议实现，成功返回废纸篓 URL；系统受保护应用（`/System/Applications`、`com.apple.*` bundleId、`/Applications/Utilities` 中 Apple 预装应用）不允许操作
- [x] Checkpoint 15: `scanLeftovers` 在 `~/Library/Preferences`、`Caches`、`Application Support`、`Logs`、`Saved Application State`、`Containers`、`Group Containers` 中匹配 Bundle ID 的文件/目录，返回 URL + 大小
- [x] Checkpoint 16: `trashLeftovers` 逐项调用 `Trasher.trash`，遇失败继续处理其余项并汇总错误

## ViewModel
- [x] Checkpoint 17: `refresh()` 后 `apps` 与 scanner 输出一致
- [x] Checkpoint 18: `searchText` + `sourceFilter` + `sortKey` 更改后 `filteredApps` 正确响应
- [x] Checkpoint 19: `requestUninstall` → `confirmUninstall` 流程调用 service.moveToTrash 并在成功后填充 `pendingLeftovers`
- [x] Checkpoint 20: `confirmLeftoverTrash(selection:)` 调用 service.trashLeftovers 并清空 `pendingLeftovers`
- [x] Checkpoint 21: 所有 IO 通过 `Task.detached` 在后台执行，`isBusy` 状态正确翻转

## View / UI
- [x] Checkpoint 22: 列表展示 icon / name / version / bundleId / size / source badge，视觉层级清晰
- [x] Checkpoint 23: 顶部包含搜索框、来源筛选 segmented、排序菜单、刷新按钮
- [x] Checkpoint 24: 卸载按钮对受保护应用禁用并展示 tooltip
- [x] Checkpoint 25: 卸载二次确认对话框默认按钮为 Cancel，destructive 按钮为红色
- [x] Checkpoint 26: 残余清单 Sheet 中每项可勾选，展示相对路径与大小，二次确认后清理
- [x] Checkpoint 27: 空状态展示图标 + 本地化文案

## 导航 & 本地化
- [x] Checkpoint 28: 侧边栏 System 分组新增 Local Apps 入口，图标 `app.badge.checkmark`
- [x] Checkpoint 29: `NavigationItem.allCases` 包含 `.systemLocalApps` 且 `id` 唯一
- [x] Checkpoint 30: `Localization+En.swift` 与 `Localization+Zh.swift` 中 `localApps.*` 和 `nav.localApps` key 集合完全一致
- [x] Checkpoint 31: 切换语言后 UI 文案随之切换，无硬编码

## 测试 & 构建
- [x] Checkpoint 32: `swift build` 通过且无警告
- [x] Checkpoint 33: `swift test` 全量通过（含新增 LocalApps* 测试）
- [x] Checkpoint 34: `swift test --filter LocalApps` 全部 PASS
- [x] Checkpoint 35: 每个新增源文件行数 < 500

## 文档 & 提交
- [x] Checkpoint 36: README 「What's New」「Features」「Project Structure」「Roadmap」四处均更新
- [x] Checkpoint 37: Git 单次 Conventional Commit 提交，信息包含变更概述
