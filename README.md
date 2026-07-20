# EnvMatrix

<p align="center">
  <img src="Sources/EnvMatrix/Resources/AppIcon.icns" alt="EnvMatrix" width="128" height="128" />
</p>

<p align="center">
  <b>一站式 macOS 开发环境与包管理可视化工具</b><br/>
  Visualize, switch and clean up your dev runtimes, package managers and AI CLIs — all in one native SwiftUI app.
</p>

<p align="center">
  <a href="https://github.com/MasamiYui/envmatrix/actions"><img src="https://img.shields.io/badge/swift-5.9-orange.svg" alt="Swift 5.9" /></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-13%2B-blue.svg" alt="macOS 13+" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-green.svg" alt="License" /></a>
  <a href="#"><img src="https://img.shields.io/badge/i18n-EN%20%7C%20中文-purple.svg" alt="i18n" /></a>
</p>

---

## ✨ 简介 | Introduction

**EnvMatrix** 是一款面向 macOS 开发者的原生桌面应用，采用 SwiftUI 构建，帮助你在一个界面里管理**多语言运行时**、**包管理器仓库/镜像**、**Homebrew 应用**以及 **AI CLI/MCP 服务**。

告别在 `~/.bashrc`、`~/.npmrc`、`~/.m2/settings.xml`、`go env`、`brew list` 之间来回切换的碎片化体验 —— EnvMatrix 把日常最高频的"环境切换、镜像切换、缓存清理"操作汇聚到侧边栏，让配置**可视化、可回滚、可搜索**。

## 🎯 核心特性 | Features

### 🖥️ Dashboard 总览
- 一屏展示已安装运行时、包管理器、Homebrew、AI 工具的健康状态
- 检测 PATH、版本、缓存大小、异常配置

### 🔧 开发运行时（Dev Environments）
支持 11 种主流运行时的**版本检测、路径查看、多版本切换**：

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

### 📦 包管理与仓库镜像（Packages）
一站式管理开发者最关心的四大包生态：

- **🍺 Homebrew**：可视化列表、搜索、依赖树、卸载、cask/formula 区分
- **☕ Maven**：`~/.m2/settings.xml` 镜像管理（阿里 / 华为 / 腾讯 / 中央）+ 本地仓库构件浏览、按 GAV 搜索、批量删除
- **🐹 Go**：`GOPROXY` 一键切换（官方 / goproxy.cn / goproxy.io / 阿里云）+ `GOMODCACHE` 本地依赖扫描、按模块/版本删除
- **📗 Node.js (npm)**：
  - `.npmrc` registry 镜像切换（官方 / 淘宝 / 腾讯 / 华为），写入前自动备份
  - 全局包列表（`npm ls -g --depth=0 --json`）+ 二次确认卸载
  - `~/.npm/_cacache` 大小统计与 `npm cache clean --force`

### 🤖 AI 环境（AI Environments）
- **Skills**：AI 助手技能集合管理
- **AI CLI**：常见 AI CLI 工具的版本与配置查看
- **MCP Servers**：Model Context Protocol 服务清单

### 🛡️ 安全与可回滚
- 所有对配置文件的写入操作**自动生成 `.envmatrix.bak` 备份**
- 危险操作（卸载、清理、删除）均带**二次确认**
- 命令执行使用受控 Shell，不注入敏感变量

### 🌍 完整国际化
内置**中文 / English** 双语，切换即时生效，本地化 key 在两个字典中完全对称。

## 📸 截图 | Screenshots

> 首次运行请自行截图并放入 `docs/screenshots/`，然后取消下方注释：

<!--
| Dashboard | Homebrew | Maven | Node |
|:---:|:---:|:---:|:---:|
| ![](docs/screenshots/dashboard.png) | ![](docs/screenshots/brew.png) | ![](docs/screenshots/maven.png) | ![](docs/screenshots/node.png) |
-->

## 🚀 快速开始 | Quick Start

### 系统要求

- **macOS 13 Ventura** 及以上
- **Swift 5.9+**（Xcode 15 或独立 Swift toolchain）
- 可选：`brew`、`npm`、`go`、`mvn` 等 CLI（EnvMatrix 会在缺失时优雅降级并给出提示）

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
# 参考 tools/ 或 scripts/ 目录下的打包脚本
swift build -c release
# 手动组装 EnvMatrix.app bundle 并拷贝 Resources/AppIcon.icns
```

## 🗂️ 项目结构 | Project Structure

```
EnvMatrix/
├── Package.swift              # SPM 配置
├── start.sh                   # 一键启动脚本
├── LICENSE                    # Apache-2.0
├── Sources/EnvMatrix/
│   ├── App/                   # 应用入口、导航、路由
│   ├── Models/                # 数据模型（RuntimeKind、MavenRepository、GoRepository、NodeRepository...）
│   ├── Services/              # 业务服务层（含 Providers 版本探测）
│   │   ├── MavenSettingsService.swift
│   │   ├── MavenLocalRepositoryService.swift
│   │   ├── GoEnvService.swift
│   │   ├── GoLocalCacheService.swift
│   │   ├── NpmrcService.swift
│   │   ├── NpmService.swift
│   │   └── HomebrewService.swift
│   ├── ViewModels/            # 响应式状态管理（@Published）
│   ├── Views/                 # SwiftUI 视图
│   │   ├── Dashboard/         # 总览
│   │   ├── DevEnv/            # 开发运行时页面
│   │   ├── Packages/          # Brew / Maven / Go / Node
│   │   ├── AI/                # AI 相关页面
│   │   └── Settings/          # 设置
│   ├── Utils/                 # 工具类（Localization、Shell 执行等）
│   └── Resources/             # 图标等资源
├── Tests/EnvMatrixTests/      # 单元测试
├── scripts/                   # 辅助脚本
└── tools/                     # 打包工具
```

## 🧑‍💻 开发指南 | Development

### 架构原则

- **MVVM + 依赖注入**：Service 层暴露 protocol，ViewModel 通过构造函数注入，方便测试与替换
- **异步优先**：所有 IO / Shell 操作使用 Swift Concurrency (`async/await`)，避免主线程阻塞
- **纯 SwiftUI**：无 AppKit 桥接（仅少量 `NSPasteboard` 等系统 API），保持声明式风格
- **文件行数约束**：每个源文件保持在 500 行以内，超出即拆分

### 运行测试

```bash
swift test
```

### 常用命令

```bash
swift build              # Debug 构建
swift build -c release   # Release 构建
swift build --show-bin-path
./start.sh               # 一键构建 + 启动
```

### 添加新的运行时 / 包管理器

1. 在 [RuntimeKind.swift](Sources/EnvMatrix/Models/RuntimeKind.swift) 中新增 case
2. 在 `Services/Providers/` 添加对应 VersionProvider
3. 在 [AppNavigation.swift](Sources/EnvMatrix/App/AppNavigation.swift) 注册侧边栏入口
4. 在 [DetailView.swift](Sources/EnvMatrix/App/DetailView.swift) 添加路由
5. 在 `Localization+En.swift` / `Localization+Zh.swift` 补充双语文案

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

- [ ] Dashboard 支持自定义卡片顺序
- [ ] 支持 pip / cargo / gem 镜像管理
- [ ] Docker / Podman 上下文管理
- [ ] 环境快照导入导出（一键迁移到新机器）
- [ ] Universal Binary（Apple Silicon + Intel）发布产物
- [ ] Homebrew tap 分发

## ❓ FAQ

**Q: EnvMatrix 会修改我的系统配置吗？**
A: 只有你在界面上**主动点击**"应用/切换/删除"时才会写入。所有写操作在覆盖前都会生成 `.envmatrix.bak` 备份文件，可随时手动还原。

**Q: 没有安装 `go` / `npm` / `mvn` 会怎样？**
A: 对应模块会显示"未检测到 xxx"的空状态并提示安装建议，不会崩溃或误报。

**Q: 支持 Linux / Windows 吗？**
A: 当前仅支持 macOS 13+。技术栈是 SwiftUI + macOS 专属 API，跨平台需要较大重构。

**Q: 为什么不用 Electron？**
A: 我们希望做一个**低资源占用、启动快、系统集成好**的原生工具。SwiftUI 让二进制体积保持在个位数 MB。

## 📄 License

本项目基于 [Apache License 2.0](LICENSE) 开源。

## 🙏 致谢 | Acknowledgements

- SwiftUI & Swift Concurrency
- 所有 Homebrew / Maven / Go / Node 生态的维护者
- 灵感来源：日常在多语言项目间切换配置的痛苦体验

---

<p align="center">
  Made with ❤️ on macOS · If EnvMatrix helps you, please ⭐ this repo!
</p>
