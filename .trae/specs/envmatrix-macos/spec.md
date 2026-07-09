# EnvMatrix - macOS 原生环境管理器 - 产品需求文档

## Overview
- **Summary**: EnvMatrix 是一款基于 SwiftUI 构建的 macOS 原生 GUI 应用，用于统一管理本地开发环境（Node.js、Python、Java、Go、Rust）以及 AI 相关环境（Claude/Trae Skills、AI CLI 配置、MCP 服务器）。应用采用自建的独立管理逻辑，自主完成运行时的下载、安装、切换与卸载，界面美观简约，符合 macOS Human Interface Guidelines。
- **Purpose**: 解决 macOS 开发者需要在多个终端管理器（nvm/pyenv/jenv/gvm/rustup）之间来回切换、命令记忆负担重、AI 工具配置分散难以维护的痛点，提供统一的图形化入口。
- **Target Users**: macOS 平台的开发者、AI 应用/Agent 开发者、多语言项目维护者。

## Goals
- 提供一个原生 macOS GUI 应用，通过 SwiftUI 呈现美观简约的现代化界面。
- 支持五种主流开发语言运行时（Node.js、Python、Java、Go、Rust）的版本安装、切换、卸载。
- 支持 AI 环境管理：Skills（Claude/Trae）目录管理、AI CLI 配置（Claude Code、Trae CLI、Gemini CLI 等）编辑、MCP 服务器管理。
- 自建独立管理逻辑，不依赖 nvm/pyenv 等第三方版本管理器（可与其共存但独立运作）。
- 通过修改 shell 配置（如 `~/.zshrc`、`~/.bash_profile`）或维护 `~/.envmatrix/shims` 目录来实现 PATH 切换。

## Non-Goals (Out of Scope)
- 不支持 Windows / Linux 平台。
- 不接管或修改已有的 nvm/pyenv/jenv/gvm/rustup 的内部行为；仅可作为独立层次共存。
- 不提供本地 LLM（Ollama、LM Studio）的运行时管理（本期）。
- 不提供云端账户体系、同步或团队协作功能。
- 不提供 IDE 插件形态。
- 不涉及集成开发工具链（如 Xcode、Android Studio）的下载。

## Background & Context
- 工作目录 `/Users/yinyijun/OpenSourceProjects/EnvMatrix` 目前仅有 LICENSE，为空白项目。
- macOS 官方推荐使用 SwiftUI + Swift 构建原生桌面应用。目标最低系统版本 macOS 13 (Ventura) 及以上，以便使用较新的 SwiftUI API（NavigationSplitView 等）。
- 版本二进制来源建议使用各语言官方镜像：
  - Node.js: https://nodejs.org/dist/
  - Python: python-build-standalone (astral-sh)
  - Java: Adoptium (Temurin)
  - Go: https://go.dev/dl/
  - Rust: rustup 官方分发（作为二进制发行的例外，仍可自建管理其 toolchain 目录）
- AI 环境目录约定：
  - Claude skills: `~/.claude/skills/`
  - Trae skills: `~/.trae-cn/skills/` 或 `~/.trae/skills/`
  - CLI 配置: `~/.claude/settings.json`、`~/.trae-cn/config.json` 等
  - MCP 配置: `~/.claude/mcp.json` 或应用内 `~/Library/Application Support/EnvMatrix/mcp.json`

## Functional Requirements
- **FR-1**: 应用启动后展示侧边栏（NavigationSplitView）分类：Dashboard、Dev Environments、AI Environments、Settings。
- **FR-2**: Dev Environments 下每种语言（Node.js/Python/Java/Go/Rust）拥有独立子页面，展示已安装版本列表和"当前激活版本"标识。
- **FR-3**: 支持从远端获取可安装版本列表（在线拉取），并允许用户选择版本进行下载安装。
- **FR-4**: 支持将某个已安装版本设置为"当前激活版本"（通过 shim 或 PATH 修改）。
- **FR-5**: 支持卸载已安装版本，并二次确认防止误删。
- **FR-6**: 下载/安装过程需展示进度条、当前状态（下载中/解压中/校验中/完成/失败）以及错误信息。
- **FR-7**: AI Environments -> Skills 页面：扫描 `~/.claude/skills`、`~/.trae-cn/skills`、`~/.trae/skills` 目录，展示 Skill 列表（名称、路径、启用/禁用状态），支持启用/禁用（重命名 skill 目录添加 `.disabled` 后缀）、打开目录、删除。
- **FR-8**: AI Environments -> AI CLI 配置页面：识别常见 CLI 的配置文件路径，允许在 GUI 中查看和编辑关键字段（模型名、API base URL、API Key 掩码显示）。
- **FR-9**: AI Environments -> MCP 服务器页面：读取和写入 MCP 配置（如 `~/.claude/mcp.json`），支持新增 / 编辑 / 删除 MCP server 条目，字段包括 name、command、args、env。
- **FR-10**: Dashboard 显示总览：每种语言的当前版本、Skills 总数、MCP 服务器数量、磁盘占用摘要。
- **FR-11**: Settings 页面：应用主题（跟随系统/浅色/深色）、镜像源自定义、清理缓存、关于页面。
- **FR-12**: 所有操作生成审计日志，可在 Settings -> Logs 页面查看。

## Non-Functional Requirements
- **NFR-1 (性能)**: 应用启动到首屏可交互 ≤ 1.5 秒（M 系列芯片）。
- **NFR-2 (体验)**: 界面遵循 macOS HIG，采用 SF Symbols 图标、系统色板、native controls，视觉美观简约。
- **NFR-3 (安全)**: API Key 等敏感字段以掩码方式展示，编辑时通过 `TextField(text:).textContentType(.password)` 或系统 Keychain 存储。
- **NFR-4 (兼容)**: 支持 macOS 13.0 及以上，Apple Silicon (arm64) 原生，Intel (x86_64) 通过 Universal Binary 支持。
- **NFR-5 (稳定)**: 下载中断、网络异常等场景可优雅恢复或明确提示。
- **NFR-6 (可维护)**: 项目采用模块化架构 (MVVM)，单文件不超过 500 行；核心模块含单元测试。

## Constraints
- **Technical**: Swift 5.9+，SwiftUI，Xcode 15+，macOS 13.0+ 部署目标，使用 SPM 管理依赖。
- **Business**: 开源项目 (LICENSE 已存在)，无商业化诉求。
- **Dependencies**: 尽量使用 Apple 原生 API（URLSession、FileManager、Process），避免重量级第三方依赖；如需第三方，仅可引入 `swift-log` 等轻量库。

## Assumptions
- 用户已经安装 Xcode Command Line Tools（`xcode-select --install`）。
- 用户具备对 `~/.zshrc` 或 `~/.bash_profile` 的写入权限（默认情况满足）。
- 用户使用的默认 shell 为 zsh 或 bash（macOS 默认 zsh）。
- 网络可访问 Node.js/Adoptium/Go 官方分发源；若被墙则由 Settings 中镜像源解决。

## Acceptance Criteria

### AC-1: 应用启动与主界面
- **Given**: 首次启动 EnvMatrix.app
- **When**: 用户双击打开
- **Then**: 应用在 1.5 秒内出现主窗口，展示 NavigationSplitView，侧边栏包含 Dashboard、Dev Environments (下辖 Node/Python/Java/Go/Rust)、AI Environments (Skills/CLI/MCP)、Settings。
- **Verification**: `human-judgment`
- **Notes**: 检查视觉是否遵循 macOS HIG。

### AC-2: 语言运行时版本列表
- **Given**: 用户已进入 Node.js 页面
- **When**: 点击"可用版本"标签
- **Then**: 应用从远端获取版本列表并渲染 ≥ 10 条最近的 LTS/Current 版本，含版本号、发布日期、平台适配标签。
- **Verification**: `programmatic`

### AC-3: 语言运行时安装
- **Given**: 网络正常，用户已选中某个 Node.js 版本
- **When**: 点击"安装"
- **Then**: 应用下载对应 tarball 至 `~/.envmatrix/versions/node/<version>/`，展示进度条，安装完成后该版本出现在"已安装"列表。
- **Verification**: `programmatic`

### AC-4: 语言运行时切换
- **Given**: 已安装 ≥ 2 个 Node.js 版本
- **When**: 用户点击某版本旁的"设为当前"
- **Then**: `~/.envmatrix/shims/node` 符号链接指向所选版本；在新终端执行 `node -v` 输出正确版本号。
- **Verification**: `programmatic`

### AC-5: 语言运行时卸载
- **Given**: 已安装某语言版本
- **When**: 用户点击卸载并二次确认
- **Then**: 对应版本目录被删除，若为当前激活版本则清除 shim 并提示用户重新选择。
- **Verification**: `programmatic`

### AC-6: Skills 管理
- **Given**: `~/.claude/skills/` 存在若干子目录
- **When**: 用户进入 Skills 页面
- **Then**: 展示所有 skills（名称、路径、状态），点击"禁用"后该目录被重命名添加 `.disabled` 后缀且状态变为 Disabled。
- **Verification**: `programmatic`

### AC-7: AI CLI 配置管理
- **Given**: 存在 `~/.claude/settings.json`
- **When**: 用户在 CLI 页面编辑模型字段并保存
- **Then**: 配置文件被更新，API Key 字段以掩码 (`****`) 展示，未在 UI 泄露原文。
- **Verification**: `programmatic`

### AC-8: MCP 服务器管理
- **Given**: 用户已进入 MCP 页面
- **When**: 用户新增 MCP server 条目（name、command、args）并保存
- **Then**: 配置文件写入正确 JSON，重启应用后条目仍然存在。
- **Verification**: `programmatic`

### AC-9: Dashboard 总览
- **Given**: 已安装若干语言版本并存在 Skills/MCP 数据
- **When**: 用户进入 Dashboard
- **Then**: 展示各语言当前版本、Skills 数、MCP 数、磁盘占用。
- **Verification**: `programmatic`

### AC-10: 界面美观简约
- **Given**: 应用主界面
- **When**: 用户在浅色 / 深色模式间切换
- **Then**: 所有页面均正确适配主题，无控件错位或对比度问题。
- **Verification**: `human-judgment`

### AC-11: 单文件规模约束
- **Given**: 项目已实现完毕
- **When**: 检查所有 `.swift` 文件行数
- **Then**: 无单文件超过 500 行。
- **Verification**: `programmatic`

### AC-12: 项目可构建
- **Given**: 全部代码已提交
- **When**: 在项目根目录执行 `swift build`（或 `xcodebuild -scheme EnvMatrix`）
- **Then**: 构建成功且无 error 级别输出。
- **Verification**: `programmatic`

## Open Questions
- [ ] Rust 的运行时管理是否需要托管 rustup 目录 `~/.rustup`？（本期决定：仅提供 rustup 检测 + toolchain 切换代理命令。）
- [ ] Python 建议使用 python-build-standalone；对于依赖 pip/venv 的操作，本期只切换 python 可执行文件，不管理 site-packages。
- [ ] Java 版本清单来源是 Adoptium API，是否需要多厂商 (Zulu/Corretto)？（本期只对接 Adoptium。）
