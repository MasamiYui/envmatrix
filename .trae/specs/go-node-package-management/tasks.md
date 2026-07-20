# Go & Node 包管理 - The Implementation Plan (Decomposed and Prioritized Task List)

## [x] Task 1: 新增导航入口与本地化 key 骨架
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 在 [AppNavigation.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/AppNavigation.swift) 中新增枚举 `packagesGo`、`packagesNode`，补齐 `id / displayName / systemImage`，并加入 `allCases` 与 `allSections[.packages]`。
  - 在 [DetailView.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/App/DetailView.swift) 增加对 `.packagesGo` / `.packagesNode` 的 case 路由到即将实现的 `GoRepositoryView` / `NodeRepositoryView`。
  - 在 [Localization.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization.swift) 中英两处字典中新增 `nav.goRepo`、`nav.nodeRepo`，以及 `goRepo.*` / `nodeRepo.*` 的完整 key 集合骨架（可先给出 tab 标题、按钮、空状态文案）。
- **Acceptance Criteria Addressed**: AC-1, AC-10
- **Test Requirements**:
  - `programmatic` TR-1.1: `swift build` 编译通过（此步骤会引用尚不存在的 View，需在此任务里同时新增最小空壳 View 以避免编译失败）。
  - `human-judgement` TR-1.2: 侧栏"包管理"分组能同时看到 4 个入口（Homebrew / Maven / Go / Node），中英切换时导航文本正确。
- **Notes**: 视图先只显示占位（`Text("Go Repository")`），实现在后续任务完成；避免大爆炸式合并。

## [x] Task 2: Go 数据模型与 GOMODCACHE 扫描服务
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 新建 `Sources/EnvMatrix/Models/GoRepository.swift`：定义 `GoModuleArtifact`（含 `path`、`modulePath`、`versions`、`totalSizeBytes`、`latestModified`）与 `GoModuleVersion`（`version`、`sizeBytes`、`modifiedAt`、`path`）。
  - 新建 `Sources/EnvMatrix/Services/GoLocalCacheService.swift`：协议 + 默认实现，负责解析 `GOMODCACHE`（优先 `go env GOMODCACHE`，回落 `$HOME/go/pkg/mod`），递归扫描 `<host>/<owner>/<repo>@<version>` 或 `!capitalized` 的 module 目录，聚合成 `[GoModuleArtifact]`；实现 `totalSize()`、`deleteModule()`、`deleteVersion()`（删除前 `chmod -R u+w`）。
- **Acceptance Criteria Addressed**: AC-3, AC-4
- **Test Requirements**:
  - `programmatic` TR-2.1: 单元式验证（可以在临时目录构造假 GOMODCACHE 结构，调用 `scan()` 得到期望的 `[GoModuleArtifact]`）——或者通过实机扫描存在的 `~/go/pkg/mod`，断言至少一个 module 被识别、总大小 > 0。
  - `programmatic` TR-2.2: 对只读目录调用 `deleteModule()` 后目录不存在。
- **Notes**: Go module 缓存中 module 目录使用 `!` 前缀表示大写字母（e.g. `!google.golang.org`）。解析后需 `unescapeGoModulePath` 还原。

## [x] Task 3: Go GOPROXY 配置服务
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 在 `Sources/EnvMatrix/Services/GoEnvService.swift`：协议 + 默认实现，封装 `go env GOPROXY`（读取）与 `go env -w GOPROXY=<value>`（写入）；同时提供 `presetProxies() -> [GoProxyPreset]`（direct / goproxy.cn / goproxy.io / aliyun / tencent）。
  - 数据模型 `GoProxyPreset { id, name, value }` 放在 [GoRepository.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Models/GoRepository.swift) 中。
  - 复用 [Shell.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift) 进行进程调用；处理"go 未安装"的错误路径抛出可本地化的错误。
- **Acceptance Criteria Addressed**: AC-2, AC-8
- **Test Requirements**:
  - `programmatic` TR-3.1: 调用 `readProxy()` 返回非 nil；调用 `writeProxy("https://goproxy.cn,direct")` 后再次 `readProxy()` 得到该值。
  - `programmatic` TR-3.2: 环境无 `go` 时 `readProxy()` 抛出 `.commandNotFound`。
- **Notes**: 测试完成后建议恢复用户原有 GOPROXY，避免污染。

## [x] Task 4: Go ViewModel 与视图（GOPROXY + 本地依赖 Tab）
- **Priority**: P0
- **Depends On**: Task 2, Task 3
- **Description**:
  - 新建 `Sources/EnvMatrix/ViewModels/GoProxyViewModel.swift`、`Sources/EnvMatrix/ViewModels/GoLocalCacheViewModel.swift`，参照 Maven 两个 VM 的写法。
  - 新建 `Sources/EnvMatrix/Views/Packages/GoRepositoryView.swift`（顶层 + Tab picker），并把 GOPROXY 子视图内嵌于其中；新建 `Sources/EnvMatrix/Views/Packages/GoLocalCacheView.swift` 用于本地依赖 Tab（复用 Maven Local Artifacts 的列表 / 搜索 / 排序 / 展开版本 / 删除确认 pattern）。
  - 保持 <500 行/文件；破坏性操作使用 `.alert(item:)` 二次确认。
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-3, AC-4, AC-8
- **Test Requirements**:
  - `programmatic` TR-4.1: `swift build` 编译通过并且这些新文件出现在 build 日志的 `Compiling ...` 行。
  - `human-judgement` TR-4.2: 手动点击 GOPROXY Tab 应用预设，UI 及时更新；本地依赖 Tab 可搜索/排序/展开/删除，且删除有二次确认。

## [x] Task 5: Node 数据模型与 .npmrc 服务
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 新建 `Sources/EnvMatrix/Models/NodeRepository.swift`：`NodeRegistryMirror { id, name, url, isPreset }`、`NodeGlobalPackage { id, name, version, path }`、`NodeCacheStats { path, sizeBytes }`。
  - 新建 `Sources/EnvMatrix/Services/NpmrcService.swift`：读取 `~/.npmrc`；提供 `readRegistry()`、`writeRegistry(url)`（保留其它行，写入前 `.envmatrix.bak` 备份）；`presetMirrors()` 返回 4 个国内/官方预设。
- **Acceptance Criteria Addressed**: AC-5
- **Test Requirements**:
  - `programmatic` TR-5.1: 给一段包含 `strict-ssl=false\nregistry=https://xxx\n` 的临时文件，调用 `writeRegistry("https://registry.npmmirror.com")` 后再读取，得到 `registry=` 更新为新值，`strict-ssl=false` 仍在。
  - `programmatic` TR-5.2: `.npmrc` 不存在时 `writeRegistry(...)` 会自动创建文件。

## [x] Task 6: Node 全局包与缓存服务
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 新建 `Sources/EnvMatrix/Services/NpmService.swift`：`listGlobalPackages()` 调用 `npm ls -g --depth=0 --json` 并解析；`uninstallGlobal(name)` 调用 `npm uninstall -g <name>`；`cacheStats()` 读取 `~/.npm/_cacache` 目录大小；`cacheClean()` 调用 `npm cache clean --force`。
  - 所有 `npm` 调用通过 [Shell.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Shell.swift)，缺失 `npm` 时抛可本地化错误。
- **Acceptance Criteria Addressed**: AC-6, AC-7, AC-8
- **Test Requirements**:
  - `programmatic` TR-6.1: `listGlobalPackages()` 返回非空数组（本机安装了任意全局包，如 `npm` 自身以外的一个）。
  - `programmatic` TR-6.2: `cacheStats().sizeBytes >= 0`；调用 `cacheClean()` 不抛出。
  - `programmatic` TR-6.3: 测试环境安装一个临时全局包（如 `is-thirteen`），`uninstallGlobal("is-thirteen")` 之后再次 `listGlobalPackages()` 中不再出现。（若测试环境不便，可退化为 `human-judgement`）

## [x] Task 7: Node ViewModel 与视图（3 Tab）
- **Priority**: P0
- **Depends On**: Task 5, Task 6
- **Description**:
  - 新建 `Sources/EnvMatrix/ViewModels/NodeRegistryViewModel.swift`、`NodeGlobalPackagesViewModel.swift`、`NodeCacheViewModel.swift`。
  - 新建 `Sources/EnvMatrix/Views/Packages/NodeRepositoryView.swift` 顶层 + segmented Tab picker（镜像 / 全局包 / 缓存）；
  - 新建 `Sources/EnvMatrix/Views/Packages/NodeRegistryView.swift`、`NodeGlobalPackagesView.swift`、`NodeCacheView.swift` 各自 <300 行；破坏性操作二次确认；空状态和错误横幅。
- **Acceptance Criteria Addressed**: AC-5, AC-6, AC-7, AC-8
- **Test Requirements**:
  - `programmatic` TR-7.1: `swift build` 编译通过，且新增 Node* 文件全部被编译。
  - `human-judgement` TR-7.2: 手动进入 Node 仓库，三个 Tab 均可用，切换镜像、卸载全局包、清缓存流程完整，含二次确认与错误提示。

## [x] Task 8: 完善本地化 & 编译校验
- **Priority**: P1
- **Depends On**: Task 4, Task 7
- **Description**:
  - 检查 [Localization.swift](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/Sources/EnvMatrix/Utils/Localization.swift) 是否所有 `goRepo.*` / `nodeRepo.*` 都同时在 zh 与 en 存在；补齐缺失。
  - 修饰空状态图标（`shippingbox` 类同 Maven），确保图标与"包管理"分组视觉一致。
  - 运行 `touch` + `swift build` 强制重建以验证所有新增文件确实进入编译流水线。
- **Acceptance Criteria Addressed**: AC-9, AC-10
- **Test Requirements**:
  - `programmatic` TR-8.1: 运行 `grep -Eo '"(goRepo|nodeRepo)\.[a-zA-Z.]+"' Sources/EnvMatrix/Utils/Localization.swift | sort -u`，中英分别的 key 集合完全相同。
  - `programmatic` TR-8.2: `swift build 2>&1 | grep -E 'warning|error'` 无输出。
  - `human-judgement` TR-8.3: 中英切换后所有可见文案均本地化，无 raw key 泄漏。
