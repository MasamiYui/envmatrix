# EnvMatrix

<p align="center">
  <img src="Sources/EnvMatrix/Resources/AppIcon.icns" alt="EnvMatrix" width="128" height="128" />
</p>

<p align="center">
  <b>一站式 macOS 开发环境与包管理可视化工具</b><br/>
  Visualize, switch and clean up your dev runtimes, package managers and AI CLIs — all in one native SwiftUI app.
</p>

<p align="center">
  <a href="https://github.com/MasamiYui/envmatrix/actions/workflows/ci.yml"><img src="https://github.com/MasamiYui/envmatrix/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://github.com/MasamiYui/envmatrix/actions/workflows/lint.yml"><img src="https://github.com/MasamiYui/envmatrix/actions/workflows/lint.yml/badge.svg" alt="Lint" /></a>
  <a href="#"><img src="https://img.shields.io/badge/swift-5.9-orange.svg" alt="Swift 5.9" /></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-13%2B-blue.svg" alt="macOS 13+" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-green.svg" alt="License" /></a>
  <a href="#"><img src="https://img.shields.io/badge/i18n-EN%20%7C%20中文-purple.svg" alt="i18n" /></a>
</p>

---

## ✨ 简介 | Introduction

**EnvMatrix** 是一款面向 macOS 开发者的原生桌面应用，采用 SwiftUI 构建，帮助你在一个界面里管理**多语言运行时**、**包管理器仓库/镜像**、**Homebrew 应用**以及 **AI CLI / MCP 服务**。

告别在 `~/.bashrc`、`~/.npmrc`、`~/.m2/settings.xml`、`~/.config/pip/pip.conf`、`go env`、`brew list` 之间来回切换的碎片化体验 —— EnvMatrix 把日常最高频的 "环境切换、镜像切换、缓存清理、备份恢复" 汇聚到侧边栏，让配置**可视化、可回滚、可搜索、可诊断**。

## 🆕 最近亮点 | What's New

以下功能在 v0.3（Phase 1–3）中陆续落地：

- � **Python (pip) 包管理**：`pip.conf` `index-url` 一键切换（清华 / 阿里 / 腾讯 / USTC / 官方）、`pip list --user` 可视化 + 二次确认卸载、`~/Library/Caches/pip` 尺寸统计 + `pip cache purge`
- �🔍 **全局搜索 (⌘F)**：跨 Brew / Maven / Go / npm / **pip** 聚合搜索，按 Source 分组、每组显示条数徽标，5 分钟 TTL 缓存 + 主动失效
- 📊 **诊断报告**：一键导出 Markdown 报告，包含 OS / brew / mvn / go / npm / **pip** 系统信息
- 💾 **备份历史面板**：集中管理所有 `.envmatrix.bak` 文件，支持在线恢复 / 删除
- 🔔 **系统通知**：长耗时任务完成后触发原生通知（可在 Settings 关闭）
- 🧱 **性能优化**：Brew 列表虚拟化 (`LazyVStack` + 200ms debounce)、Dashboard 5 分钟 TTL + 骨架屏、`SearchAggregator` TTL 缓存
- 🗂️ **视图分组**：Runtime Installed 按 Managed / System 分组、Skills 按 source 分组、MCP Servers 按 transport (`npx / uvx / node / python / other`) 分组，全部可折叠 + 计数徽标
- 📐 **Runtime Usage 分栏**：Runtime Detail 新增第三分栏，展示每个已安装版本的磁盘占用与 Managed / System 标签

## 🎯 核心特性 | Features

### 🖥️ Dashboard 总览
- 一屏展示已安装运行时、包管理器、Homebrew、AI 工具的健康状态
- 检测 PATH、版本、缓存大小、异常配置
- 缓存大小 ≥ 5 GB 自动标记 **"需要关注"**
- **手动刷新** + **5 分钟 TTL** + **骨架加载**，避免频繁扫盘
- 点击任意卡片直达对应管理模块

### 🔧 开发运行时（Dev Environments）

支持 11 种主流运行时的**版本检测、路径查看、多版本切换、磁盘占用统计**：

| 运行时 | 版本管理器 | 说明 |
|-------|---------|------|
| Node.js | nvm / fnm / volta | 全局版本切换 |
| Python | pyenv / conda | 系统 & 虚拟环境 |
| Java | jenv / SDKMAN | JDK 版本切换 |
| Go | 系统 / gvm | GOROOT / GOPATH |
| Rust | rustup | toolchain 管理 |
| Ruby | rbenv / rvm | Ruby 版本 |
| PHP | 系统 / phpbrew | - |
| Deno | 系统 | - |
| Bun | 系统 | - |
| .NET | 系统 | - |
| Erlang | 系统 / kerl | - |

每个 Runtime Detail 提供三分栏视图：

- **Installed**：已安装版本，按 Managed / System 分组、可折叠，一键切换活动版本、卸载（系统托管路径受保护）
- **Available**：远端可用版本列表，支持下载安装（部分 provider）
- **Usage**：磁盘占用汇总 + 每版本大小 + Managed / System 标签

### 📦 包管理与仓库镜像（Packages）

一站式管理开发者最关心的五大包生态：

- **🍺 Homebrew**：可视化 formulae / cask 列表、200ms debounce 搜索、依赖树、卸载、虚拟化滚动
- **☕ Maven**：`~/.m2/settings.xml` 镜像管理（阿里 / 华为 / 腾讯 / 中央）+ 本地仓库构件浏览、按 GAV 搜索、批量删除；服务器密码写入 macOS Keychain 而非明文
- **🐹 Go**：`GOPROXY` 一键切换（官方 / goproxy.cn / goproxy.io / 阿里云）+ `GOMODCACHE` 本地依赖扫描、按模块/版本删除
- **📗 Node.js (npm)**：
  - `.npmrc` registry 镜像切换（官方 / 淘宝 / 腾讯 / 华为），写入前自动生成 `.envmatrix.bak` 备份
  - 全局包列表（`npm ls -g --depth=0 --json`）+ 二次确认卸载
  - `~/.npm/_cacache` 大小统计与 `npm cache clean --force`
- **🐍 Python (pip)**：
  - `~/.config/pip/pip.conf` `index-url` 镜像切换（清华 TUNA / 阿里云 / 腾讯 / USTC / PyPI 官方），写入前自动生成 `pip.conf.envmatrix.bak` 备份
  - `pip list --user --format=json` 解析出用户级安装包（**不动系统 Python**），一键搜索 / 卸载
  - `~/Library/Caches/pip` 尺寸统计与 `pip cache purge`

### 🤖 AI 环境（AI Environments）

- **Skills**：AI 助手技能集合管理，按 `source` 分组、可折叠、每组计数徽标
- **AI CLI**：常见 AI CLI 工具的模型 / API Base URL / API Key 配置
- **MCP Servers**：Model Context Protocol 服务清单，按 `transport` (`npx / uvx / node / python / other`) 自动分组、可折叠

### 🔍 全局搜索（Global Search）

- 按 **⌘F** 打开搜索面板，跨 Brew / Maven / Go / npm / pip 语料聚合
- 结果按 Source 分组，每组显示条数徽标
- **180 ms 输入防抖** + **5 分钟 TTL 缓存**，避免频繁扫盘
- 支持 **Return** 键直达详情页

### 🛡️ 安全与可回滚

- 所有对配置文件的写入操作**自动生成 `.envmatrix.bak` 备份**
- 危险操作（卸载、清理、删除）均带**二次确认**
- 命令执行使用受控 Shell，不注入敏感变量
- 系统托管路径下的 runtime 不允许直接删除（需包管理器 / sudo）
- Maven 服务器密码写入 macOS Keychain，从不落盘

### 💾 备份 & 诊断（Settings）

- **Backups Tab**：集中扫描并管理全部 `.envmatrix.bak` 历史备份，支持在线还原 / 删除
- **Diagnostics Tab**：一键导出 Markdown 诊断报告，包含系统版本、brew / mvn / go / npm / pip CLI 信息，方便贴到 Issue

### 🔔 系统通知

长耗时任务（卸载、缓存清理、镜像切换）完成时触发 macOS 原生通知，可在 **Settings → General** 中关闭。

### 🌍 完整国际化

内置 **中文 / English** 双语，切换即时生效，本地化 key 在 [Localization+En.swift](Sources/EnvMatrix/Utils/Localization+En.swift) / [Localization+Zh.swift](Sources/EnvMatrix/Utils/Localization+Zh.swift) 中完全对称。

## ⌨️ 快捷键 | Shortcuts

| 快捷键 | 说明 |
|-------|-----|
| ⌘ F | 打开全局搜索 |
| ⌘ , | 打开设置 |
| ⌘ Q | 退出应用 |
| ⌘ W | 关闭窗口 |
| Return | 全局搜索中打开选中结果 |
| Esc | 关闭全局搜索面板 |

## 📸 截图 | Screenshots

> 首次运行请自行截图并放入 `docs/screenshots/`，然后取消下方注释：

<!--
| Dashboard | Homebrew | Maven | Node |
|:---:|:---:|:---:|:---:|
| ![](docs/screenshots/dashboard.png) | ![](docs/screenshots/brew.png) | ![](docs/screenshots/maven.png) | ![](docs/screenshots/node.png) |

| Runtime Usage | Global Search | Backups | Diagnostics |
|:---:|:---:|:---:|:---:|
| ![](docs/screenshots/runtime-usage.png) | ![](docs/screenshots/search.png) | ![](docs/screenshots/backups.png) | ![](docs/screenshots/diagnostics.png) |
-->

## 🚀 快速开始 | Quick Start

### 系统要求

- **macOS 13 Ventura** 及以上
- **Swift 5.9+**（Xcode 15 或独立 Swift toolchain）
- 可选：`brew`、`npm`、`pip3`、`go`、`mvn` 等 CLI（EnvMatrix 会在缺失时优雅降级并给出提示）

### 从源码构建

```bash
git clone https://github.com/MasamiYui/envmatrix.git
cd envmatrix

# 方式 1：一键启动脚本（推荐）
./start.sh

# 方式 2：手动构建
swift build -c release
.build/release/EnvMatrix
```

启动脚本 `start.sh` 会自动检测 `.build` 目录，跳过重复构建，直接运行 Debug 版本。

### 打包为 .app（可选）

```bash
swift build -c release
# 手动组装 EnvMatrix.app bundle 并拷贝 Resources/AppIcon.icns
```

## 🗂️ 项目结构 | Project Structure

```
EnvMatrix/
├── Package.swift              # SPM 配置
├── start.sh                   # 一键启动脚本
├── LICENSE                    # Apache-2.0
├── .github/workflows/         # CI: build / lint / release
├── Sources/EnvMatrix/
│   ├── App/                   # 应用入口、导航、路由
│   ├── Models/                # 数据模型（RuntimeKind、MavenRepository、Skill、MCPServer …）
│   ├── Services/              # 业务服务层
│   │   ├── Providers/         # 11 个运行时版本 Provider
│   │   ├── HomebrewService.swift
│   │   ├── MavenSettingsService.swift
│   │   ├── MavenLocalRepositoryService.swift
│   │   ├── GoEnvService.swift
│   │   ├── GoLocalCacheService.swift
│   │   ├── NpmrcService.swift
│   │   ├── NpmService.swift
│   │   ├── PipService.swift              # pip3 CLI + pip.conf INI 读写
│   │   ├── SearchAggregator.swift        # 全局搜索聚合器 + TTL 缓存
│   │   ├── BackupService.swift           # .envmatrix.bak 扫描 / 恢复
│   │   ├── DiagnosticReportService.swift # Markdown 诊断报告
│   │   ├── SystemNotifier.swift          # UNUserNotificationCenter 封装
│   │   └── SystemRuntimeDetector.swift   # 系统运行时探测
│   ├── ViewModels/            # 响应式状态管理（@Published）
│   ├── Views/                 # SwiftUI 视图
│   │   ├── Dashboard/         # 总览（含骨架屏）
│   │   ├── DevEnv/            # Installed / Available / Usage 三分栏
│   │   ├── Packages/          # Brew / Maven / Go / Node / Python
│   │   ├── AI/                # Skills / CLI / MCP
│   │   ├── Settings/          # General / Backups / Diagnostics
│   │   └── GlobalSearchView.swift        # ⌘F 全局搜索面板
│   ├── Utils/                 # 工具类（Localization、Shell 执行等）
│   └── Resources/             # 图标等资源
├── Tests/EnvMatrixTests/      # 单元测试（含 11 个 Provider decoding tests）
├── scripts/                   # 辅助脚本（check_file_lines.sh、verify.sh）
└── tools/icon-picker/         # AppIcon 生成器
```

## 🧑‍💻 开发指南 | Development

### 架构原则

- **MVVM + 依赖注入**：Service 层暴露 protocol，ViewModel 通过构造函数注入，方便测试与替换
- **异步优先**：所有 IO / Shell 操作使用 Swift Concurrency (`async/await`)，避免主线程阻塞
- **纯 SwiftUI**：无 AppKit 桥接（仅少量 `NSPasteboard` / `NSWorkspace` 等系统 API），保持声明式风格
- **性能优先**：长列表虚拟化、TTL 缓存、Task detached 卸载重扫盘操作
- **文件行数约束**：每个源文件保持在 500 行以内，超出即拆分（`scripts/check_file_lines.sh`）
- **i18n 硬约束**：任何 UI 文案必须落到 `Localization+En.swift` / `Localization+Zh.swift`，禁止硬编码

### 运行测试

```bash
swift test
```

### 常用命令

```bash
swift build                 # Debug 构建
swift build -c release      # Release 构建
swift build --show-bin-path
./start.sh                  # 一键构建 + 启动
./scripts/verify.sh         # 综合校验（build + test + lint）
./scripts/check_file_lines.sh   # 检查源文件行数约束
swiftlint                   # 代码风格检查
```

### 添加新的运行时 / 包管理器

1. 在 [RuntimeKind.swift](Sources/EnvMatrix/Models/RuntimeKind.swift) 中新增 case（并在 UI 图标 / 分区中显式配置）
2. 在 `Services/Providers/` 添加对应 VersionProvider
3. 在 [AppNavigation.swift](Sources/EnvMatrix/App/AppNavigation.swift) 注册侧边栏入口
4. 在 [DetailView.swift](Sources/EnvMatrix/App/DetailView.swift) 添加路由
5. 在 `Localization+En.swift` / `Localization+Zh.swift` 补充双语文案
6. 编写 `Tests/EnvMatrixTests/*ProviderDecodingTests.swift` 单元测试

## 🤝 贡献 | Contributing

欢迎任何形式的贡献！

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feat/awesome-feature`
3. 提交遵循 [Conventional Commits](https://www.conventionalcommits.org/)：`feat(scope): xxx` / `fix(scope): xxx`
4. Push 到你的 Fork 并发起 Pull Request
5. 确保 `swift build` 无警告、无错误，新增代码有必要的单元测试

### 提交规范

- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档
- `refactor`: 重构（不改变外部行为）
- `perf`: 性能优化
- `chore`: 构建 / 工具链
- `test`: 测试

## 🗺️ Roadmap

- [x] Homebrew / Maven / Go / Node / Python 包管理
- [x] 11 语言运行时的版本探测与切换
- [x] 全局搜索 (⌘F) + 结果分组
- [x] 备份历史 & 诊断报告
- [x] Runtime Usage 分栏 + Managed/System 分组
- [x] Skills / MCP Servers 分组视图
- [ ] Dashboard 支持自定义卡片顺序
- [ ] 支持 cargo / gem / composer 镜像管理
- [ ] Docker / Podman 上下文管理
- [ ] 环境快照导入导出（一键迁移到新机器）
- [ ] Runtime Usage 引入 TTL 缓存 & 持久化折叠状态
- [ ] Universal Binary（Apple Silicon + Intel）发布产物
- [ ] Homebrew tap 分发

## ❓ FAQ

**Q: EnvMatrix 会修改我的系统配置吗？**
A: 只有你在界面上**主动点击**"应用/切换/删除"时才会写入。所有写操作在覆盖前都会生成 `.envmatrix.bak` 备份文件，可随时通过 **Settings → Backups** 面板一键还原。

**Q: 没有安装 `go` / `npm` / `pip3` / `mvn` 会怎样？**
A: 对应模块会显示"未检测到 xxx"的空状态并提示安装建议，不会崩溃或误报。

**Q: 为什么 System 版本的运行时无法删除？**
A: 通过 brew / sdkman / nvm / pkg 安装的运行时受包管理器管理，直接删除会破坏 metadata 或需要 sudo。EnvMatrix 会提示你使用对应包管理器的卸载命令；仅托管在用户可写目录（如 `~/Library/Java/JavaVirtualMachines`）中的版本才能直接卸载。

**Q: 全局搜索为什么第一次比后续慢？**
A: 首次触发时需要扫描 Brew / Maven / Go / npm / pip 的完整语料，之后会缓存 5 分钟。执行安装 / 卸载 / 缓存清理等操作时会**主动失效**对应 Source 的缓存，确保数据实时。

**Q: 支持 Linux / Windows 吗？**
A: 当前仅支持 macOS 13+。技术栈是 SwiftUI + macOS 专属 API，跨平台需要较大重构。

**Q: 为什么不用 Electron？**
A: 我们希望做一个**低资源占用、启动快、系统集成好**的原生工具。SwiftUI 让二进制体积保持在个位数 MB。

## 📄 License

本项目基于 [Apache License 2.0](LICENSE) 开源。

## 🙏 致谢 | Acknowledgements

- SwiftUI & Swift Concurrency
- 所有 Homebrew / Maven / Go / Node / Python 生态的维护者
- 灵感来源：日常在多语言项目间切换配置的痛苦体验

---

<p align="center">
  Made with ❤️ on macOS · If EnvMatrix helps you, please ⭐ this repo!
</p>
