#!/usr/bin/env bash
#
# install.sh — Build EnvMatrix from source and install/reinstall it into /Applications.
#
# Usage:
#   ./scripts/install.sh                     # install (or reinstall) to /Applications
#   ./scripts/install.sh --prefix ~/Applications
#   ./scripts/install.sh --uninstall         # remove installed app
#   ./scripts/install.sh --no-universal      # build only for host arch (faster)
#   ./scripts/install.sh --launch            # open the app after install
#   ./scripts/install.sh -h | --help
#
# Requirements: macOS 13+, Xcode command-line tools (swift), /usr/bin/ditto.

set -euo pipefail

# ------------------------- config ---------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="EnvMatrix"
BUNDLE_ID="dev.envmatrix.app"
ICON_SRC="$PROJECT_DIR/Sources/EnvMatrix/Resources/AppIcon.icns"
MIN_MACOS="13.0"

INSTALL_PREFIX="/Applications"
BUILD_UNIVERSAL=1
LAUNCH_AFTER_INSTALL=0
UNINSTALL_ONLY=0

# ------------------------- pretty printing ------------------------------------
if [[ -t 1 ]]; then
    BOLD="$(printf '\033[1m')"
    DIM="$(printf '\033[2m')"
    RED="$(printf '\033[31m')"
    GRN="$(printf '\033[32m')"
    YLW="$(printf '\033[33m')"
    BLU="$(printf '\033[34m')"
    RST="$(printf '\033[0m')"
else
    BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi

info()  { printf "%s==>%s %s\n"  "$BLU$BOLD" "$RST" "$*"; }
ok()    { printf "%s✓%s %s\n"   "$GRN"      "$RST" "$*"; }
warn()  { printf "%s!%s %s\n"   "$YLW"      "$RST" "$*"; }
die()   { printf "%s✗%s %s\n"   "$RED"      "$RST" "$*" >&2; exit 1; }

# ------------------------- arg parsing ----------------------------------------
print_help() {
    sed -n '2,15p' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)          print_help; exit 0 ;;
        --prefix)           shift; INSTALL_PREFIX="${1:?--prefix requires a path}" ;;
        --prefix=*)         INSTALL_PREFIX="${1#*=}" ;;
        --no-universal)     BUILD_UNIVERSAL=0 ;;
        --launch)           LAUNCH_AFTER_INSTALL=1 ;;
        --uninstall)        UNINSTALL_ONLY=1 ;;
        *)                  die "Unknown option: $1" ;;
    esac
    shift || true
done

# Expand a leading ~ manually since we may not be in a login shell
INSTALL_PREFIX="${INSTALL_PREFIX/#\~/$HOME}"

APP_BUNDLE="$INSTALL_PREFIX/$APP_NAME.app"

# ------------------------- prerequisites --------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This installer only supports macOS."
command -v swift  >/dev/null || die "Swift toolchain not found. Install Xcode / Command Line Tools first."
command -v ditto  >/dev/null || die "/usr/bin/ditto is required."

# ------------------------- uninstall mode -------------------------------------
if [[ $UNINSTALL_ONLY -eq 1 ]]; then
    if [[ -d "$APP_BUNDLE" ]]; then
        info "Removing $APP_BUNDLE ..."
        if [[ -w "$INSTALL_PREFIX" ]]; then
            rm -rf "$APP_BUNDLE"
        else
            sudo rm -rf "$APP_BUNDLE"
        fi
        ok "Uninstalled $APP_NAME."
    else
        warn "$APP_BUNDLE does not exist. Nothing to do."
    fi
    exit 0
fi

# ------------------------- version ---------------------------------------------
# Prefer the latest git tag (strip leading `v`); fall back to a date stamp.
cd "$PROJECT_DIR"
if VERSION="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    VERSION="${VERSION#v}"
else
    VERSION="0.0.0-$(date +%Y%m%d)"
fi
info "Version: ${BOLD}${VERSION}${RST}"

# ------------------------- build ----------------------------------------------
BUILD_ARGS=(-c release)
if [[ $BUILD_UNIVERSAL -eq 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
    info "Building universal (arm64 + x86_64) release binary ..."
else
    info "Building release binary for host arch only ..."
fi

swift build "${BUILD_ARGS[@]}"
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BIN_FILE="$BIN_PATH/$APP_NAME"

[[ -x "$BIN_FILE" ]] || die "Built binary not found at $BIN_FILE"
ok "Built: $BIN_FILE"

# ------------------------- assemble .app --------------------------------------
STAGE_DIR="$(mktemp -d -t envmatrix-install)"
trap 'rm -rf "$STAGE_DIR"' EXIT

APP_STAGE="$STAGE_DIR/$APP_NAME.app"
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"

cp "$BIN_FILE" "$APP_STAGE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_STAGE/Contents/MacOS/$APP_NAME"

if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP_STAGE/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    warn "AppIcon.icns not found at $ICON_SRC, skipping icon."
    ICON_KEY=""
fi

cat > "$APP_STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.developer-tools</string>
    $ICON_KEY
</dict>
</plist>
PLIST

# Ad-hoc codesign so Gatekeeper / launchd accepts the fresh bundle on modern macOS.
if command -v codesign >/dev/null; then
    codesign --force --deep --sign - "$APP_STAGE" >/dev/null 2>&1 || \
        warn "codesign (ad-hoc) failed; the app should still run for local use."
fi

ok "Assembled bundle at $APP_STAGE"

# ------------------------- install --------------------------------------------
NEEDS_SUDO=0
if [[ ! -w "$INSTALL_PREFIX" ]]; then
    NEEDS_SUDO=1
fi

if [[ -d "$APP_BUNDLE" ]]; then
    info "Existing installation found — reinstalling."
    # If the app is running, ask launchservices to quit it first.
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        warn "$APP_NAME is currently running; requesting it to quit ..."
        osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
        # give it up to ~3s to exit cleanly
        for _ in 1 2 3 4 5 6; do
            pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
            sleep 0.5
        done
        pkill -x "$APP_NAME" 2>/dev/null || true
    fi

    if [[ $NEEDS_SUDO -eq 1 ]]; then
        sudo rm -rf "$APP_BUNDLE"
    else
        rm -rf "$APP_BUNDLE"
    fi
fi

info "Installing to $APP_BUNDLE ..."
mkdir -p "$INSTALL_PREFIX" 2>/dev/null || true

if [[ $NEEDS_SUDO -eq 1 ]]; then
    sudo /usr/bin/ditto "$APP_STAGE" "$APP_BUNDLE"
else
    /usr/bin/ditto "$APP_STAGE" "$APP_BUNDLE"
fi

# Clear the quarantine flag (in case the source tree came from a browser download)
if [[ $NEEDS_SUDO -eq 1 ]]; then
    sudo xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
else
    xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
fi

ok "Installed $APP_NAME $VERSION → $APP_BUNDLE"

# ------------------------- launch ---------------------------------------------
if [[ $LAUNCH_AFTER_INSTALL -eq 1 ]]; then
    info "Launching $APP_NAME ..."
    open "$APP_BUNDLE"
fi

echo
echo "${DIM}Tip:${RST} run ${BOLD}open \"$APP_BUNDLE\"${RST} to start the app,"
echo "     or ${BOLD}$0 --uninstall${RST} to remove it."
