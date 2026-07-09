#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Step 1: swift build"
swift build \
    --disable-sandbox \
    --cache-path /tmp/envmatrix_cache \
    --config-path /tmp/envmatrix_config \
    --security-path /tmp/envmatrix_security

echo "==> Step 2: swift test"
swift test \
    --disable-sandbox \
    --cache-path /tmp/envmatrix_cache \
    --config-path /tmp/envmatrix_config \
    --security-path /tmp/envmatrix_security

echo "==> Step 3: line-count check"
find Sources Tests -name "*.swift" | while read f; do
    lines=$(wc -l < "$f")
    if [ "$lines" -gt 500 ]; then
        echo "TOO LONG: $f ($lines)"
        exit 1
    fi
done
echo "All files <=500 lines"

echo "VERIFY OK"
