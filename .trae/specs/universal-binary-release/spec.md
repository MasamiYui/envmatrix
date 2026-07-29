# Universal Binary（Apple Silicon + Intel）发布产物 - Product Requirement Document

## Overview
- **Summary**：将现有 Release 流程加固为可验证、可复现的 Universal Binary 发布产物：在 CI 侧新增架构断言步骤（`lipo -info` / `file`），补齐产物 metadata（AppIcon、发布说明中的架构信息），并抽取共用的"assemble .app bundle"逻辑到独立脚本，让 CI 与本地 [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh) 走同一份打包代码。同时在 README 中明确标注下载产物支持 Apple Silicon 与 Intel。
- **Purpose**：项目当前已在 [release.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/release.yml#L49-L52) 中使用 `swift build -c release --arch arm64 --arch x86_64` 产出 universal 二进制，但缺少：(1) 对产物架构的显式断言，一旦某天工具链变化只出单一架构也不会 fail（silent regression 风险）；(2) CI 打的 .app bundle 与 [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh) 打的 bundle 结构不一致（CI 没有 AppIcon、没有 codesign、没有 SwiftPM resource bundle 拷贝），导致下载压缩包和本地 install 出来的 App 用户体验不同；(3) README 未告知用户下载的是 Universal 产物。用户在 Roadmap 中把此项列为 `[ ]`，正是要求把这三点补齐并可验证。
- **Target Users**：EnvMatrix 的最终用户（下载 Release zip 的开发者，涵盖 M1/M2/M3 与 Intel Mac 两类）；以及项目维护者（发布流程与本地安装脚本行为一致，减少调试成本）。

## Goals
- CI Release 流程必须**验证并断言**产物中的 Mach-O 二进制同时包含 `arm64` 与 `x86_64` slice，否则 build fail。
- Release zip 中的 `.app` bundle 与 `./scripts/install.sh` 生成的 bundle 具有**一致的结构**（同样带 AppIcon、Info.plist 字段完整、SwiftPM resource bundle 完整）。
- 在 README 中标注下载产物为 Universal Binary，明确"Apple Silicon 与 Intel 均可直接运行"。
- 提供一个可复用的 shell 函数或脚本（`scripts/assemble_app.sh` 或将 [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh#L119-L180) 的 assemble 逻辑抽取），使 [release.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/release.yml) 与本地脚本共享同一份 assemble 代码。
- 将 [README.md#L396](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md#L396) 的 TODO 项 `[ ] Universal Binary…` 更新为 `[x]`。

## Non-Goals (Out of Scope)
- 不引入 Apple Developer 账号签名 / notarization 流程（保持 ad-hoc codesign 现状）。
- 不改造 [ci.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/ci.yml)（CI 里的 `swift build` 冒烟仍只跑主机架构；本项只加固 release.yml）。
- 不发布 DMG / pkg 格式；沿用 zip。
- 不做 rosetta 兜底逻辑（Universal Binary 本身覆盖了这一场景）。
- 不引入 Homebrew tap 相关变更（那是 [README.md#L397](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md#L397) 的另一个 TODO 项，独立追踪）。

## Background & Context
- 现状：[release.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/release.yml#L49-L88) 在 `push tags v*` 时构建 universal binary、组装最小 .app、`ditto -c -k --sequesterRsrc --keepParent` 打包成 `EnvMatrix-<version>-macOS-universal.zip` 并上传到 GitHub Release。产物名已含 `universal` 关键字。
- [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh#L119-L180) 的 assemble 步骤更完整：包含 AppIcon 复制、Info.plist 中的 `CFBundleIconFile`、SwiftPM 生成的 `EnvMatrix_EnvMatrix.bundle` 拷贝、ad-hoc codesign。CI 缺失全部这些。
- macOS 上验证 Universal Binary 的标准方式：`lipo -archs <binary>` 输出 `arm64 x86_64`，或 `file <binary>` 输出 `Mach-O universal binary with 2 architectures: [arm64:...] [x86_64:...]`。
- Runner 使用 `macos-14`（Apple Silicon 主机），Xcode 15.4，Swift 5.9+。
- 项目文件行数上限为 500 行（`scripts/check_file_lines.sh`），新脚本需遵循同样约束（sh 不在扫描范围，但建议保持简洁）。

## Functional Requirements
- **FR-1**：新增脚本 `scripts/assemble_app.sh`，以参数化方式生成 `.app` bundle：入参为 `--bin`（编译产物二进制路径）、`--out`（输出目录）、`--version`、`--icon`（可选，icns 路径）、`--sign`（可选，`adhoc` 或 `none`），产物结构与当前 [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh) 保持一致。
- **FR-2**：[install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh) 复用 `scripts/assemble_app.sh` 完成 assemble 步骤（去重）；保留其 CLI 兼容性（`--prefix`、`--no-universal`、`--launch`、`--uninstall`）。
- **FR-3**：[release.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/release.yml) 的 "Assemble EnvMatrix.app bundle" 步骤改为调用 `scripts/assemble_app.sh`；产物包含 AppIcon 与 SwiftPM resource bundle。
- **FR-4**：[release.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/release.yml) 在 assemble 之后新增 "Verify universal architectures" 步骤，执行 `lipo -archs EnvMatrix.app/Contents/MacOS/EnvMatrix`，断言输出同时包含 `arm64` 与 `x86_64`；若缺失任一则 `exit 1`。
- **FR-5**：[release.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/release.yml) 在 "Publish GitHub Release" 步骤的 `body` 中追加一段自动生成的说明，包含产物的 `lipo -archs` 结果、二进制大小与 sha256（借助 `softprops/action-gh-release` 的 `body_path` 或 `body` 输入）。
- **FR-6**：`scripts/assemble_app.sh` 完成后自身执行 `lipo -archs` 打印架构信息（不 fail，仅信息输出），使本地 install 也能看到产物架构。
- **FR-7**：README 快速开始章节 "从源码构建" 之后新增 "下载预编译产物"，说明从 Releases 下载 `EnvMatrix-<version>-macOS-universal.zip`，支持 Apple Silicon 与 Intel。
- **FR-8**：README Roadmap 中 `[ ] Universal Binary（Apple Silicon + Intel）发布产物` 更新为 `[x]`。

## Non-Functional Requirements
- **NFR-1**（可复现）：`scripts/assemble_app.sh` 在同一 checkout 下多次运行结果 idempotent（先删除旧 `.app` 再组装）。
- **NFR-2**（可测试）：新增 shell 脚本必须能在 macOS 13/14 上通过 `bash -n` 静态语法检查，且提供 `--help` 打印用法。
- **NFR-3**（无回归）：现有 `swift build` / `swift test` 用例保持 100% 通过；`scripts/verify.sh` 不受影响。
- **NFR-4**（可读性）：CI YAML step name、脚本 usage 说明与 README 用词统一使用「Universal Binary」而非 fat / multi-arch，与 Apple 官方术语对齐。
- **NFR-5**（性能）：universal 构建时间控制在 30 分钟以内（现有 `timeout-minutes: 30` 不变）。

## Constraints
- **Technical**：仅使用 macOS 自带 `swift`、`lipo`、`ditto`、`codesign`、`shasum`、`file`；不引入外部 GH Action 除已用的 `actions/checkout@v4` / `actions/cache@v4` / `actions/upload-artifact@v4` / `softprops/action-gh-release@v2`。
- **Business**：无签名 / 无 notarization，用户仍需 `xattr -dr com.apple.quarantine` 或右键"打开"绕过 Gatekeeper（保持现状，在 README 中一并说明）。
- **Dependencies**：Xcode 15.4 与 macOS 13 SDK。

## Assumptions
- GitHub Actions macos-14 runner 长期提供 `lipo`（属于 Xcode 命令行工具，默认可用）。
- Swift 5.9+ 的 `swift build --arch arm64 --arch x86_64` 稳定输出 fat binary（历史已验证，此项主要防 silent regression）。
- 用户会通过 Releases 页面下载 zip，然后 `xattr -dr com.apple.quarantine` + 双击运行（README 说明已覆盖此提示）。

## Acceptance Criteria

### AC-1：CI 构建的产物必然是 Universal Binary
- **Given**：Push 一个 `v*` tag，触发 [release.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/release.yml)
- **When**：Workflow 执行 "Verify universal architectures" 步骤
- **Then**：`lipo -archs EnvMatrix.app/Contents/MacOS/EnvMatrix` 输出同时包含 `arm64` 和 `x86_64`；步骤 exit 0；若任一缺失则 exit 1 使整个 job fail
- **Verification**：`programmatic`

### AC-2：CI 与本地 install 输出的 .app 结构一致
- **Given**：checkout 同一 commit
- **When**：分别运行 CI 的 assemble 步骤 与 `./scripts/install.sh --prefix $(mktemp -d)`
- **Then**：两处得到的 `EnvMatrix.app` 内文件清单一致（都包含 `Contents/MacOS/EnvMatrix`、`Contents/Info.plist`、`Contents/Resources/AppIcon.icns`、`Contents/Resources/EnvMatrix_EnvMatrix.bundle`），Info.plist 内的 keys 一致
- **Verification**：`programmatic`

### AC-3：assemble 脚本可独立、幂等调用
- **Given**：已完成一次 `swift build -c release --arch arm64 --arch x86_64`
- **When**：连续两次运行 `scripts/assemble_app.sh --bin <binPath>/EnvMatrix --out /tmp/out --version 9.9.9 --icon Sources/EnvMatrix/Resources/AppIcon.icns --sign adhoc`
- **Then**：`/tmp/out/EnvMatrix.app` 每次都被正确重建；无 "File exists" 或残留错误
- **Verification**：`programmatic`

### AC-4：Release 说明包含架构信息
- **Given**：一次成功的 tag build
- **When**：GitHub Release 页面渲染
- **Then**：Release body 中出现 `Architectures: arm64 x86_64`（或等价文本）与 sha256 值
- **Verification**：`programmatic`（可通过检查 workflow 上传的 body 文件内容验证）

### AC-5：README 明确宣告 Universal Binary
- **Given**：用户浏览项目 README
- **When**：定位到 "快速开始 | Quick Start" 章节
- **Then**：可看到 "下载预编译产物" 小节，说明 Release 提供 Universal Binary（Apple Silicon + Intel），并给出去除 quarantine 属性的一行命令；Roadmap 中对应条目被勾选
- **Verification**：`human-judgment`（评审 README 变更 diff 语义准确、语调一致）

### AC-6：产物文件名保留 `universal` 语义标识
- **Given**：CI 生成 zip
- **When**：查看上传 artifact
- **Then**：文件名匹配 `EnvMatrix-<version>-macOS-universal.zip`；对应 sha256 文件为 `EnvMatrix-<version>-macOS-universal.zip.sha256`
- **Verification**：`programmatic`

### AC-7：无回归
- **Given**：改动完成
- **When**：本地运行 `swift build` 与 `swift test`
- **Then**：均 exit 0；无新增警告
- **Verification**：`programmatic`

## Open Questions
- [ ] 是否需要在 [ci.yml](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/.github/workflows/ci.yml) PR 触发时也构建 universal？→ 决策：**不做**（Non-Goals 已明确，PR CI 只跑主机架构以控制耗时）。
- [ ] 是否为 `scripts/assemble_app.sh` 添加 `--zip` 选项直接产出发布 zip？→ 决策：暂不做，保持"assemble 只输出 .app"、"打包由调用方 ditto"的单一职责。
