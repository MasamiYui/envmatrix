#!/usr/bin/env bash
#
# assemble_app.sh — Assemble an EnvMatrix.app bundle from a built binary.
#
# Usage:
#   assemble_app.sh --bin <bin> --out <dir> --version <ver> \
#                   [--icon <icns>] [--sign adhoc|none] \
#                   [--bundle-id <id>] [-h|--help]
#
# Defaults:
#   --sign        adhoc
#   --bundle-id   dev.envmatrix.app
#
# Behavior:
#   1. If <out>/EnvMatrix.app exists, remove it first (idempotent).
#   2. Create Contents/MacOS and Contents/Resources.
#   3. Copy --bin to Contents/MacOS/EnvMatrix and chmod +x.
#   4. Copy *.bundle next to --bin into Contents/Resources/ (nullglob safe).
#   5. If --icon points at an existing file, copy to Contents/Resources/
#      AppIcon.icns and register CFBundleIconFile in Info.plist.
#   6. Write Info.plist (LSMinimumSystemVersion=13.0,
#      LSApplicationCategoryType=public.app-category.developer-tools).
#   7. If --sign adhoc, run `codesign --force --deep --sign - <app>`
#      (warn-only on failure).
#   8. Emit `lipo -archs <bin>` at the end (informational).

set -euo pipefail

# ------------------------- config ---------------------------------------------
APP_NAME="EnvMatrix"
MIN_MACOS="13.0"
DEFAULT_BUNDLE_ID="dev.envmatrix.app"
CATEGORY="public.app-category.developer-tools"

BIN=""
OUT=""
VERSION=""
ICON=""
SIGN="adhoc"
BUNDLE_ID="$DEFAULT_BUNDLE_ID"

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

# ------------------------- help -----------------------------------------------
print_help() {
    sed -n '2,25p' "$0"
}

# ------------------------- arg parsing ----------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)      print_help; exit 0 ;;
        --bin)          shift; BIN="${1:?--bin requires a path}" ;;
        --bin=*)        BIN="${1#*=}" ;;
        --out)          shift; OUT="${1:?--out requires a directory}" ;;
        --out=*)        OUT="${1#*=}" ;;
        --version)      shift; VERSION="${1:?--version requires a value}" ;;
        --version=*)    VERSION="${1#*=}" ;;
        --icon)         shift; ICON="${1:?--icon requires a path}" ;;
        --icon=*)       ICON="${1#*=}" ;;
        --sign)         shift; SIGN="${1:?--sign requires adhoc|none}" ;;
        --sign=*)       SIGN="${1#*=}" ;;
        --bundle-id)    shift; BUNDLE_ID="${1:?--bundle-id requires a value}" ;;
        --bundle-id=*)  BUNDLE_ID="${1#*=}" ;;
        *)              die "Unknown option: $1" ;;
    esac
    shift || true
done

[[ -n "$BIN" ]]     || die "--bin is required"
[[ -n "$OUT" ]]     || die "--out is required"
[[ -n "$VERSION" ]] || die "--version is required"
[[ -f "$BIN" ]]     || die "Binary not found: $BIN"

case "$SIGN" in
    adhoc|none) ;;
    *)          die "--sign must be 'adhoc' or 'none' (got: $SIGN)" ;;
esac

# ------------------------- prepare output -------------------------------------
mkdir -p "$OUT"
APP_STAGE="$OUT/$APP_NAME.app"

if [[ -e "$APP_STAGE" ]]; then
    info "Removing existing bundle: $APP_STAGE"
    rm -rf "$APP_STAGE"
fi

mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"

# ------------------------- copy binary ----------------------------------------
cp "$BIN" "$APP_STAGE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_STAGE/Contents/MacOS/$APP_NAME"
ok "Copied binary to $APP_STAGE/Contents/MacOS/$APP_NAME"

# ------------------------- copy SwiftPM resource bundles ----------------------
BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
shopt -s nullglob
RESOURCE_BUNDLES=("$BIN_DIR"/*.bundle)
shopt -u nullglob
if (( ${#RESOURCE_BUNDLES[@]} > 0 )); then
    for bundle in "${RESOURCE_BUNDLES[@]}"; do
        cp -R "$bundle" "$APP_STAGE/Contents/Resources/"
        ok "Included SwiftPM resource bundle: $(basename "$bundle")"
    done
else
    warn "No SwiftPM resource bundle found in $BIN_DIR; Bundle.module lookups may fail."
fi

# ------------------------- icon -----------------------------------------------
ICON_KEY=""
if [[ -n "$ICON" ]]; then
    if [[ -f "$ICON" ]]; then
        cp "$ICON" "$APP_STAGE/Contents/Resources/AppIcon.icns"
        ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
        ok "Included app icon: $(basename "$ICON")"
    else
        warn "Icon file not found at $ICON, skipping."
    fi
fi

# ------------------------- Info.plist -----------------------------------------
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
    <key>LSApplicationCategoryType</key> <string>$CATEGORY</string>
    $ICON_KEY
</dict>
</plist>
PLIST
ok "Wrote Info.plist"

# ------------------------- codesign -------------------------------------------
if [[ "$SIGN" == "adhoc" ]]; then
    if command -v codesign >/dev/null; then
        if codesign --force --deep --sign - "$APP_STAGE" >/dev/null 2>&1; then
            ok "Ad-hoc codesign applied."
        else
            warn "codesign (ad-hoc) failed; the app should still run for local use."
        fi
    else
        warn "codesign not available; skipping ad-hoc signing."
    fi
fi

# ------------------------- lipo (informational) -------------------------------
if command -v lipo >/dev/null; then
    ARCHS="$(lipo -archs "$APP_STAGE/Contents/MacOS/$APP_NAME" 2>/dev/null || true)"
    info "Architectures: ${ARCHS:-unknown}"
fi

ok "Assembled bundle at $APP_STAGE"
