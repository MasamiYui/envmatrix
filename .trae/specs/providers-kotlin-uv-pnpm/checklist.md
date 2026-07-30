# 新增 Provider：Kotlin / uv / pnpm - Verification Checklist

> 所有验证点由子代理执行黑盒验证。每一项完成后立即勾选并同步 [tasks.md](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.trae/specs/providers-kotlin-uv-pnpm/tasks.md)。

## Kotlin Runtime

- [x] Checkpoint 1：`RuntimeKind.allCases` 包含 `.kotlin`，且 `RuntimeKind.kotlin.binaryName == "kotlinc"`、`displayName == "Kotlin"`。
- [x] Checkpoint 2：`RuntimeKind.kotlin` 的 `iconName / brandColor / initial` 各自返回非空 / 非透明值。
- [x] Checkpoint 3：[AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 的 `allSections` "nav.devEnvironments" 分组包含 `.devEnv(.kotlin)`；侧边栏渲染时可见 Kotlin 条目。
- [x] Checkpoint 4：`KotlinProvider.decode(_:)` 对 6 条 fixture（含 2 prerelease + 1 draft）返回恰好 3 条 `RuntimeVersion`，全部 `downloadURL != nil` 且 URL 包含 `kotlin-compiler-` 与 `.zip`。
- [x] Checkpoint 5：`KotlinProvider` 面对 HTTP 500 与非法 JSON 分别抛出 `RuntimeServiceError.network(_:)` 与 `RuntimeServiceError.decoding(_:)`。
- [x] Checkpoint 6：`DefaultRuntimeService` 默认 provider 字典包含 `.kotlin` 映射；`listAvailable(kind: .kotlin)` 在 mock provider 下能返回数据。
- [x] Checkpoint 7：Runtime Detail 三分栏对 Kotlin 无 crash（Installed / Available / Usage 三个 Tab 均可加载空态或数据）。

## uv Package Manager

- [x] Checkpoint 8：新增 `NavigationItem.packagesUv`；`allCases` / `displayName` / `systemImage` / `allSections` 全部更新。
- [x] Checkpoint 9：`UvService.parseToolList(stdout:)` 对固定 fixture（3 个 tool）返回 3 条 `UvTool`。
- [x] Checkpoint 10：`UvService.setRegistry(_:)` 在临时目录中生成 `uv.toml.<timestamp>.bak` 备份文件，且写入后 `currentRegistry()` 返回新 URL。
- [x] Checkpoint 11：`UvService.isAvailable()` 在 `uv` 二进制不存在时返回 `false`；其他方法在缺失时抛错而不 crash。
- [x] Checkpoint 12：[UvRepositoryView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/UvRepositoryView.swift) 展示 3 Tab（Registry / Global Tools / Cache）；CLI 缺失时替换为 [UvMissingView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/UvMissingView.swift)。
- [x] Checkpoint 13：uv 卸载工具具备二次确认对话框；卸载操作调用 `uv tool uninstall <name>` 且参数以数组形式传给 `ProcessExecutor`。

## pnpm Package Manager

- [x] Checkpoint 14：新增 `NavigationItem.packagesPnpm`；`allCases` / `displayName` / `systemImage` / `allSections` 全部更新。
- [x] Checkpoint 15：`PnpmService.parseGlobalPackages(json:)` 对 fixture 返回预期的 `PnpmGlobalPackage` 列表；空 `dependencies` 场景返回空数组而非崩溃。
- [x] Checkpoint 16：`PnpmService.setRegistry(_:)` 在写入前生成 `.envmatrix.bak` 备份；写入后 `currentRegistry()` 返回新 URL。
- [x] Checkpoint 17：`PnpmService.storeStats()` 能返回 `PnpmStoreStats`；`storePrune()` 在 mock 子进程 exitCode == 0 时成功；非 0 时抛错并携带 stderr。
- [x] Checkpoint 18：[PnpmRepositoryView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/PnpmRepositoryView.swift) 三 Tab 布局与 npm 视觉一致；CLI 缺失时展示 [PnpmMissingView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Views/Packages/PnpmMissingView.swift)。

## 跨模块与工程质量

- [x] Checkpoint 19：i18n 双语 key 对称性测试通过（En 与 Zh 侧新增 key 集合完全相等）。
- [x] Checkpoint 20：[DetailView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/DetailView.swift) 已路由 `.packagesUv` / `.packagesPnpm` / `.devEnv(.kotlin)` 三个新 nav item。
- [x] Checkpoint 21：所有新增文件（含 tests）均 ≤ 500 行；`./scripts/check_file_lines.sh` 输出 0 违规。
- [x] Checkpoint 22：`swift build` 成功；`swift test` 全通过；测试总数不低于（旧基线 + 8）。
- [x] Checkpoint 23：所有新增 Service / Provider 的子进程调用无 shell 字符串拼接（参数全部走 `[String]`），代码 grep 无 `Shell.run("sh", ["-c",...])` 引入用户输入的场景。
- [x] Checkpoint 24：新增视图在 macOS 13 上启动无 crash（human-judgment：手动 smoke）。
