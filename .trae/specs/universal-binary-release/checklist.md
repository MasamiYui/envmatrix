# Universal Binary（Apple Silicon + Intel）发布产物 - Verification Checklist

- [x] Checkpoint 1：`scripts/assemble_app.sh` 存在、可执行、`bash -n` 语法检查通过、`--help` 打印用法且 exit 0。
- [x] Checkpoint 2：`scripts/assemble_app.sh` 具备 `--bin / --out / --version / --icon / --sign / --bundle-id / --help` 完整 CLI；未识别参数使脚本以非零码退出并打印错误提示。
- [x] Checkpoint 3：连续两次调用 `scripts/assemble_app.sh` 得到相同结构的 `.app`（幂等），且 `plutil -lint` 通过、`ls Contents/MacOS/EnvMatrix` 存在、`Contents/Resources/AppIcon.icns` 存在（当传入 `--icon` 时）。
- [x] Checkpoint 4：`scripts/install.sh` 内部通过调用 `scripts/assemble_app.sh` 完成 assemble；`--uninstall`、`--prefix`、`--no-universal`、`--launch`、`--help` 保持原有语义，`bash -n` 通过，行数仍在 500 以内。
- [x] Checkpoint 5：`.github/workflows/release.yml` 中调用了 `scripts/assemble_app.sh` 而非内联 heredoc 生成 Info.plist。
- [x] Checkpoint 6：`.github/workflows/release.yml` 新增独立 "Verify universal architectures" 步骤，同时对 `arm64` 与 `x86_64` 做 `grep -qw` 硬断言；缺失任一使 job fail。
- [x] Checkpoint 7：`.github/workflows/release.yml` 生成的 Release body 包含产物架构信息（`arm64` / `x86_64` 关键字）与 sha256；`generate_release_notes` 自动 changelog 得以保留。
- [x] Checkpoint 8：Release zip 名字保持为 `EnvMatrix-${VERSION}-macOS-universal.zip`，sha256 sidecar 命名一致。
- [x] Checkpoint 9：README `快速开始` 章节新增 "下载预编译产物" 小节，包含 `curl` + `unzip` + `xattr -dr com.apple.quarantine` + `open` 完整流程说明。
- [x] Checkpoint 10：README Roadmap 中 `Universal Binary（Apple Silicon + Intel）发布产物` 变为 `[x]`，且其他相邻 TODO 项状态未被改动。
- [x] Checkpoint 11：本地 `swift build` 无 warning、无 error；`swift test` 全部通过（无回归）。
- [x] Checkpoint 12：`.github/workflows/release.yml` 通过 `python -c "import yaml; yaml.safe_load(...)"` 或等价 YAML 语法校验；步骤顺序为 checkout → toolchain → build → assemble → verify archs → zip → upload artifact → publish。
