# Gradle 全局缓存扫描 - Verification Checklist

- [x] Checkpoint 1: `~/.gradle/caches/modules-2/files-2.1/` 存在时 `GradleCacheService.scanArtifacts` 能返回带 group/artifact/version/size 的正确条目；不存在时返回空数组无异常。
- [x] Checkpoint 2: `~/.gradle/wrapper/dists/gradle-*/` 存在时 `scanWrapperDists` 返回条目，versionLabel 包含正确版本号。
- [x] Checkpoint 3: GradleCacheViewModel 的 visibleArtifacts / visibleWrappers 按 sortOption 排序；searchText 过滤生效。
- [x] Checkpoint 4: 「Java 全局环境」页面顶部 Tab Picker 出现 3 个 Tab；切换到「Gradle 缓存」后正确呈现 GradleCacheView。
- [x] Checkpoint 5: Gradle Cache 页面顶部展示 Artifacts / Wrappers / 合计 三个体积统计块。
- [x] Checkpoint 6: Artifacts / Wrappers 双段落均支持多选，右键菜单含"在 Finder 中显示"与"移入回收站"。
- [x] Checkpoint 7: 点击"删除选中"弹二次确认；确认后对应目录进入回收站，列表刷新，统计更新。
- [x] Checkpoint 8: `~/.gradle` 不存在时空态显示：图标 + 文案 + 打开 Gradle 官网按钮。
- [x] Checkpoint 9: 所有新增本地化键 Zh/En 双语齐全，diff 输出为空。
- [x] Checkpoint 10: `swift build` exit 0，无新增 warning kind。
- [x] Checkpoint 11: 单文件 Swift 源 < 500 行。
- [x] Checkpoint 12: 所有 Gradle 侧删除操作都走 `NSWorkspace.recycle` 或 `FileManager.trashItem`，无 `removeItem` 调用。
