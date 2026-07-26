# 包管理与项目环境 完整迭代优化 - Verification Checklist

- [x] Checkpoint 1: 侧边栏「包管理」不再是单一分组，出现"系统包管理 / 语言全局环境 / 项目本地环境"三个新 Section，顺序位于「开发环境」之后、「AI 环境」之前。
- [x] Checkpoint 2: 语言全局环境分组下 8 个入口的中文文案统一为"XX 全局环境"（例："Node 全局环境"），英文为 "XX Global"；侧边栏中不再出现"XX 仓库"字样。
- [x] Checkpoint 3: 项目环境入口在侧边栏显示为"项目本地环境"/"Project Environments"。
- [x] Checkpoint 4: 语言全局环境分组下 8 个入口的图标形状一致（均为 `shippingbox.fill`），Homebrew 与项目环境保持独立图标。
- [x] Checkpoint 5: `ProjectEnvKind` 枚举包含 6 个 case：`venv / nodeModules / rustTarget / xcodeDerivedData / gradleCache / mavenTarget`，且各自 `shortLabel` 唯一非空。
- [x] Checkpoint 6: 在临时目录构造 Rust/Maven/Gradle fixture 后调用扫描器，扫描结果分别包含 `rustTarget` / `mavenTarget` / `gradleCache` 条目；无 sentinel 的裸 `target/` 不被误识别。
- [x] Checkpoint 7: 项目环境页面工具栏出现排序 Menu，支持 4 种排序选项，切换后列表顺序正确变化。
- [x] Checkpoint 8: 列表每一行末尾展示健康度徽标（活跃 / 闲置 / 废弃），颜色与语义匹配；详情页顶部也有同步的健康度 chip。
- [x] Checkpoint 9: 页面顶部展示"回收总览"卡，包含总数、可回收空间、废弃项数量与体积、"清理所有废弃项"按钮。
- [x] Checkpoint 10: 点击"清理所有废弃项"弹出二次确认 Sheet 显示路径列表；确认后所有废弃项被移入回收站，列表刷新，废弃项数量归零。
- [x] Checkpoint 11: List 支持 Cmd/Shift 多选；有选中项时工具栏出现"删除选中 (X)"按钮；点击确认后批量移入回收站。
- [x] Checkpoint 12: 根管理 Sheet 中出现"扫描 Xcode DerivedData"开关，开启后重新扫描能看到对应 `xcodeDerivedData` 条目。
- [x] Checkpoint 13: 所有新增本地化键在 Zh 和 En 字典中同时存在，键集合完全一致（可用 grep 交叉比对）。
- [x] Checkpoint 14: 界面上无残留原始 key（如 "projenv.sort.title"），切换中英文两种语言均正常显示。
- [x] Checkpoint 15: `swift build` 在本次改动完成后 exit code 0，无新增 warning。
- [ ] Checkpoint 16: 扫描运行期间主线程 UI 无卡顿；切换排序、切换过滤、开始批量删除均即时响应。（needs human review）
- [x] Checkpoint 17: 批量删除、单项删除、清理废弃项均通过回收站（可在 Finder 回收站中看到被删项）。
- [ ] Checkpoint 18: 项目环境页视觉与既有 App 风格一致（间距、圆角、字体层级、色系）。（needs human review）
