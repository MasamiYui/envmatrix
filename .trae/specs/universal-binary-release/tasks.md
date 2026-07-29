# Universal Binary（Apple Silicon + Intel）发布产物 - The Implementation Plan

## [x] Task 1: 抽取 scripts/assemble_app.sh 公共脚本
- **Priority**: P0
- **Depends On**: None
- **Description**:
  - 新建 `scripts/assemble_app.sh`，将 [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh#L119-L180) 中 assemble .app bundle 的逻辑抽取过来。
  - CLI：`assemble_app.sh --bin <bin> --out <dir> --version <ver> [--icon <icns>] [--sign adhoc|none] [--bundle-id <id>] [-h|--help]`。默认 `--sign adhoc`、`--bundle-id dev.envmatrix.app`、`LSMinimumSystemVersion=13.0`、`LSApplicationCategoryType=public.app-category.developer-tools`。
  - 行为：
    1. 若 `<out>/EnvMatrix.app` 已存在则先删除（幂等）。
    2. 建立 `Contents/MacOS` 与 `Contents/Resources`。
    3. 拷贝 `--bin` 指向的二进制到 `Contents/MacOS/EnvMatrix`，chmod +x。
    4. 拷贝 `--bin` 所在目录下的 `*.bundle`（SwiftPM 资源）到 `Contents/Resources/`（`nullglob` 处理无匹配）。
    5. 若 `--icon` 传入且文件存在，拷贝到 `Contents/Resources/AppIcon.icns` 并在 Info.plist 加入 `CFBundleIconFile` 键。
    6. 写 `Info.plist`（keys 与 [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh#L154-L172) 严格一致）。
    7. 若 `--sign adhoc` 则执行 `codesign --force --deep --sign - <app>`（失败仅告警不中止）。
    8. 结尾输出 `lipo -archs <bin>` 结果（信息性输出，不 fail）。
  - 保持 `set -euo pipefail`；跟随现有脚本的 pretty-printing 风格（`info/ok/warn/die`）。
- **Acceptance Criteria Addressed**: AC-3, AC-6（间接）
- **Test Requirements**:
  - `programmatic` TR-1.1：`bash -n scripts/assemble_app.sh` 通过（无语法错误）。
  - `programmatic` TR-1.2：`bash scripts/assemble_app.sh --help` 打印用法且 exit 0。
  - `programmatic` TR-1.3：`swift build -c release` 后执行 `scripts/assemble_app.sh --bin $(swift build -c release --show-bin-path)/EnvMatrix --out /tmp/envmatrix-assemble-t1 --version 0.0.0-test --icon Sources/EnvMatrix/Resources/AppIcon.icns --sign adhoc`，重复两次均 exit 0，且 `/tmp/envmatrix-assemble-t1/EnvMatrix.app/Contents/MacOS/EnvMatrix` 存在且 executable。
  - `programmatic` TR-1.4：调用生成的 bundle 需包含 `Contents/Info.plist`、`Contents/Resources/AppIcon.icns`；`plutil -lint Contents/Info.plist` 通过。
- **Notes**: 用 `printf` 或 heredoc 生成 Info.plist；避免依赖 `plutil -replace`。SwiftPM resource bundle 名称是 `EnvMatrix_EnvMatrix.bundle`。

## [x] Task 2: 让 scripts/install.sh 复用 scripts/assemble_app.sh
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - 将 [install.sh L119-L180](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh#L119-L180) 的 assemble 逻辑替换为调用 `scripts/assemble_app.sh`（`APP_STAGE` 输出目录仍是临时目录，`--icon` 传入 `$ICON_SRC` 当且仅当文件存在）。
  - 保留所有 [install.sh](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/scripts/install.sh) 现有 CLI 与行为（`--prefix`、`--no-universal`、`--launch`、`--uninstall`、`--help`）。
  - 保留 install / codesign / xattr / launch 等 post-assemble 步骤。
- **Acceptance Criteria Addressed**: AC-2, AC-3
- **Test Requirements**:
  - `programmatic` TR-2.1：`bash -n scripts/install.sh` 通过。
  - `programmatic` TR-2.2：`scripts/install.sh --uninstall` 在没有已安装 App 时可以安全运行并 exit 0（不写盘，只打印提示）。
  - `programmatic` TR-2.3：`scripts/install.sh --prefix $(mktemp -d) --no-universal` 完整跑通，生成的 App 存在且 `plutil -lint Info.plist` 通过。（不强制 universal 以缩短测试耗时；universal 分支由 CI 覆盖。）
- **Notes**: 保持行数在 500 行以内；若删除 assemble 内联代码后行数进一步下降更好。

## [x] Task 3: 更新 .github/workflows/release.yml 复用脚本 + 架构断言 + Release notes
- **Priority**: P0
- **Depends On**: Task 1
- **Description**:
  - "Assemble EnvMatrix.app bundle" 步骤改为：`scripts/assemble_app.sh --bin "$BIN_PATH/EnvMatrix" --out . --version "$VERSION" --icon Sources/EnvMatrix/Resources/AppIcon.icns --sign adhoc`。
  - 新增独立步骤 "Verify universal architectures"，命令：
    ```bash
    set -euxo pipefail
    ARCHS=$(lipo -archs EnvMatrix.app/Contents/MacOS/EnvMatrix)
    echo "$ARCHS"
    echo "$ARCHS" | grep -qw arm64
    echo "$ARCHS" | grep -qw x86_64
    ```
    任一 grep 失败即 job fail。将 `$ARCHS` 通过 `>> $GITHUB_OUTPUT` 暴露为下游 output（用于 release notes）。
  - "Publish GitHub Release" 步骤：使用 `body`（inline）或写入 `RELEASE_NOTES.md` 后用 `body_path`，包含固定段落 `Architectures: arm64 x86_64`、二进制大小 `stat -f %z`、`sha256`。仍保留 `generate_release_notes: true`（GitHub 自动 changelog）配合 append 自定义段落。
- **Acceptance Criteria Addressed**: AC-1, AC-4, AC-6
- **Test Requirements**:
  - `programmatic` TR-3.1：YAML 语法有效（`python -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` 通过）。
  - `programmatic` TR-3.2：release.yml 中出现字符串 `lipo -archs`、`grep -qw arm64`、`grep -qw x86_64`、`assemble_app.sh`。
  - `programmatic` TR-3.3：zip 名字保持 `EnvMatrix-${VERSION}-macOS-universal.zip` 未变更。
  - `human-judgement` TR-3.4：评审 workflow diff 语义正确，验证步骤放在 assemble 之后、zip 之前；release body 拼接方式无 YAML 转义错误。
- **Notes**: `softprops/action-gh-release@v2` 支持 `body_path` + `append_body`；若使用 append 可保留 auto-generated notes。

## [x] Task 4: 更新 README（Quick Start / Roadmap / FAQ）
- **Priority**: P1
- **Depends On**: Task 1, Task 3
- **Description**:
  - 在 [README.md "快速开始"](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md#L226-L255) 章节，在 "从源码构建" 之前新增 "### 下载预编译产物"，示例：
    ```bash
    # 从 GitHub Releases 下载 Universal Binary（同时支持 Apple Silicon 与 Intel）
    curl -LO https://github.com/MasamiYui/envmatrix/releases/latest/download/EnvMatrix-<version>-macOS-universal.zip
    unzip EnvMatrix-<version>-macOS-universal.zip
    xattr -dr com.apple.quarantine EnvMatrix.app
    mv EnvMatrix.app /Applications/
    open /Applications/EnvMatrix.app
    ```
  - 说明二进制包含 `arm64` 与 `x86_64` 两个 slice，无需 Rosetta。
  - Roadmap 中 [L396](file:///Users/yinyijun/OpenSourceProjects/EnvMatrix/README.md#L396) 的 `[ ] Universal Binary（Apple Silicon + Intel）发布产物` 更新为 `[x]`。
  - 仅修改必要行，不影响相邻 TODO 或章节。
- **Acceptance Criteria Addressed**: AC-5
- **Test Requirements**:
  - `programmatic` TR-4.1：`grep -n "Universal Binary" README.md` 至少出现在 "快速开始" 与 Roadmap 两处。
  - `programmatic` TR-4.2：`grep -n "\\- \\[x\\] Universal Binary" README.md` 输出非空。
  - `human-judgement` TR-4.3：评审 README diff 语气与既有章节一致（中英夹杂、emoji 用法、代码块语言标注 `bash`）。
- **Notes**: 保持章节顺序整洁，不改动其他 Roadmap 条目状态。
