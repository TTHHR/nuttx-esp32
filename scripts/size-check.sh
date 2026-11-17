#!/usr/bin/env bash

set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image=${1:-"$root_dir/nuttx/nuttx.bin"}
limit=$((0x140000))

if [ ! -f "$image" ]; then
  echo "Missing image: $image" >&2
  exit 1
fi

size=$(stat -c '%s' "$image")
printf "image=%s bytes (%d KiB)\n" "$size" "$((size / 1024))"
printf "limit=%s bytes (%d KiB)\n" "$limit" "$((limit / 1024))"

if [ "$size" -gt "$limit" ]; then
  echo "FAIL: image exceeds the nuttx partition." >&2
  exit 1
fi

echo "PASS: image fits the nuttx partition."
