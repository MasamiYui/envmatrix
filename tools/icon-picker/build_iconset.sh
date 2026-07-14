#!/usr/bin/env bash
set -euo pipefail

SRC="tools/icon-picker/generated/AppIcon-final.png"
SET="tools/icon-picker/generated/AppIcon.iconset"

if [[ ! -f "$SRC" ]]; then
  echo "Source not found: $SRC" >&2
  exit 1
fi

rm -rf "$SET"
mkdir -p "$SET"

# size:name pairs required by macOS iconset
specs=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for spec in "${specs[@]}"; do
  size="${spec%%:*}"
  name="${spec##*:}"
  sips -z "$size" "$size" "$SRC" --out "$SET/$name" >/dev/null
  echo "  ${size}x${size}  ->  $name"
done

echo
echo "iconset ready at $SET:"
ls -la "$SET"
