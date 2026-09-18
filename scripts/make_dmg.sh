#!/usr/bin/env bash
#
# make_dmg.sh — Wrap an assembled EnvMatrix.app into a distributable .dmg.
#
# Usage:
#   make_dmg.sh --app <EnvMatrix.app> --out <dir> --version <ver> [--name <basename>]
#               [--volname <volume name>] [-h|--help]
#
# Produces:
#   <out>/<name>.dmg   (default name: EnvMatrix-<version>-macOS-universal)
#
# Layout:
#   The disk image contains EnvMatrix.app next to a symlink to /Applications,
#   which is the conventional drag-to-install arrangement.
#
#   We deliberately do NOT script a custom background image or icon positions.
#   That requires mounting the image and driving Finder over AppleScript, which
#   needs a GUI session and fails on headless CI runners. `hdiutil create
#   -srcfolder` is fully headless and deterministic.
#
# Notes:
#   - The .app is copied with `ditto` so extended attributes and the ad-hoc
#     signature survive.
#   - The image is compressed (UDZO) and read-only.
#   - A .dmg does not change Gatekeeper behaviour: an ad-hoc signed, un-notarized
#     app is blocked on first open whether it arrives in a zip or a dmg.

set -euo pipefail

APP=""
OUT=""
VERSION=""
NAME=""
VOLNAME=""

print_help() { sed -n '2,12p' "$0"; }

die() { printf "✗ %s\n" "$*" >&2; exit 1; }
info() { printf "==> %s\n" "$*"; }
ok() { printf "✓ %s\n" "$*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    print_help; exit 0 ;;
        --app)        shift; APP="${1:?--app requires a path}" ;;
        --app=*)      APP="${1#*=}" ;;
        --out)        shift; OUT="${1:?--out requires a path}" ;;
        --out=*)      OUT="${1#*=}" ;;
        --version)    shift; VERSION="${1:?--version requires a value}" ;;
        --version=*)  VERSION="${1#*=}" ;;
        --name)       shift; NAME="${1:?--name requires a value}" ;;
        --name=*)     NAME="${1#*=}" ;;
        --volname)    shift; VOLNAME="${1:?--volname requires a value}" ;;
        --volname=*)  VOLNAME="${1#*=}" ;;
        *)            die "Unknown option: $1" ;;
    esac
    shift || true
done

[[ -n "$APP" ]]     || die "--app is required"
[[ -n "$OUT" ]]     || die "--out is required"
[[ -n "$VERSION" ]] || die "--version is required"
[[ -d "$APP" ]]     || die "App bundle not found: $APP"
command -v hdiutil >/dev/null || die "hdiutil is required (macOS only)."

APP_BASENAME="$(basename "$APP")"
[[ "$APP_BASENAME" == *.app ]] || die "--app must point at a .app bundle"

NAME="${NAME:-EnvMatrix-${VERSION}-macOS-universal}"
VOLNAME="${VOLNAME:-EnvMatrix ${VERSION}}"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
DMG_PATH="$OUT/$NAME.dmg"

STAGE="$(mktemp -d -t envmatrix-dmg)"
trap 'rm -rf "$STAGE"' EXIT

info "Staging $APP_BASENAME ..."
/usr/bin/ditto "$APP" "$STAGE/$APP_BASENAME"
ln -s /Applications "$STAGE/Applications"

# A stale image would make hdiutil fail rather than overwrite silently.
rm -f "$DMG_PATH"

info "Creating disk image ..."
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    "$DMG_PATH"

[[ -f "$DMG_PATH" ]] || die "hdiutil did not produce $DMG_PATH"

# Prove the image mounts and carries the app, so a broken archive can never
# reach a release unnoticed.
info "Verifying image ..."
hdiutil verify "$DMG_PATH" -quiet || die "hdiutil verify failed for $DMG_PATH"

MOUNT_DIR="$(mktemp -d -t envmatrix-dmg-mount)"
if hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" -quiet; then
    if [[ -d "$MOUNT_DIR/$APP_BASENAME" ]] && [[ -L "$MOUNT_DIR/Applications" ]]; then
        ok "Image contains $APP_BASENAME and an Applications shortcut."
    else
        hdiutil detach "$MOUNT_DIR" -quiet || true
        rm -rf "$MOUNT_DIR"
        die "Mounted image is missing $APP_BASENAME or the Applications shortcut"
    fi
    hdiutil detach "$MOUNT_DIR" -quiet || true
fi
rm -rf "$MOUNT_DIR"

SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
ok "Created $DMG_PATH ($SIZE)"
echo "$DMG_PATH"
