# Go & Node 包管理 - 验证清单 (Checklist)

## 结构与导航
- [x] Checkpoint 1: 侧栏"包管理"分组内可以看到 `Homebrew` / `Maven 仓库` / `Go 仓库` / `Node 仓库` 4 个入口，图标与文本符合 UI 风格
- [x] Checkpoint 2: 中英语切换时 `nav.goRepo` 与 `nav.nodeRepo` 显示正确译文，无 raw key

## Go GOPROXY
- [x] Checkpoint 3: Go 仓库 → GOPROXY Tab 加载后能正确显示 `go env GOPROXY` 的当前值
- [x] Checkpoint 4: 应用"goproxy.cn"预设后，`go env GOPROXY` 更新为 `https://goproxy.cn,direct`，UI 同步刷新
- [x] Checkpoint 5: 自定义 URL 输入并保存后能生效；空输入被禁用/校验拒绝

## Go GOMODCACHE
- [x] Checkpoint 6: Go 仓库 → 本地依赖 Tab 能扫描到本地 `GOMODCACHE`，正确显示 module 与版本，`!` 前缀路径已被转义为大写
- [x] Checkpoint 7: 顶部展示总大小、模块数与 GOMODCACHE 路径
- [x] Checkpoint 8: 搜索、排序（名称/大小/修改时间/升降序）功能正常
- [x] Checkpoint 9: 展开 module 可以看到所有版本；单版本或整模块的"删除"操作有二次确认，删除后目录消失且列表刷新（即使原目录只读）

## Node 镜像
- [x] Checkpoint 10: Node 仓库 → npm 镜像 Tab 显示 `~/.npmrc` 中的 `registry`；未设置时显示官方默认值
- [x] Checkpoint 11: 应用预设（淘宝/腾讯/华为/官方）后 `.npmrc` 中 `registry=` 行被更新，其他行保留；文件不存在时会自动创建；写入前生成 `.npmrc.envmatrix.bak` 备份

## Node 全局包
- [x] Checkpoint 12: Node 仓库 → 全局包 Tab 使用 `npm ls -g --depth=0 --json` 展示全局包列表
- [x] Checkpoint 13: 卸载按钮弹二次确认，确认后 `npm uninstall -g <name>` 执行且列表刷新
- [x] Checkpoint 14: 无网络或 npm 未安装时页面显示明确的错误提示，不崩溃

## Node 缓存
- [x] Checkpoint 15: 缓存 Tab 显示 `~/.npm/_cacache` 大小
- [x] Checkpoint 16: 点击"清理"按钮，二次确认后调用 `npm cache clean --force`，大小重新计算

## 缺失 CLI 降级
- [x] Checkpoint 17: `go` 不在 PATH 时，Go 仓库两 Tab 均显示"未检测到 Go"，无崩溃
- [x] Checkpoint 18: `npm` 不在 PATH 时，Node 仓库三 Tab 均显示"未检测到 npm"，无崩溃

## 代码质量
- [x] Checkpoint 19: `swift build` 零 error、零 warning
- [x] Checkpoint 20: 每个新增源文件 <500 行
- [x] Checkpoint 21: `Localization.swift` 中所有 `goRepo.*` / `nodeRepo.*` key 在 en 与 zh 两个字典中完全同集合
