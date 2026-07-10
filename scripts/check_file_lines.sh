#!/usr/bin/env bash
# Fail if any Swift source file exceeds a maximum line count.
# Usage: ./scripts/check_file_lines.sh [max_lines]

set -euo pipefail

MAX="${1:-500}"
ROOTS=("Sources" "Tests")

fail=0
biggest_path=""
biggest_lines=0

while IFS= read -r file; do
  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$biggest_lines" ]; then
    biggest_lines="$lines"
    biggest_path="$file"
  fi
  if [ "$lines" -gt "$MAX" ]; then
    printf "::error file=%s::%s has %s lines (> %s)\n" "$file" "$file" "$lines" "$MAX"
    fail=1
  fi
done < <(find "${ROOTS[@]}" -type f -name "*.swift" 2>/dev/null | sort)

if [ "$fail" -eq 1 ]; then
  echo ""
  echo "Some Swift files exceed the ${MAX}-line budget. Please split them." >&2
  exit 1
fi

echo "OK: no Swift file exceeds ${MAX} lines (largest: ${biggest_path} @ ${biggest_lines})"
