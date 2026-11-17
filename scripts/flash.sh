#!/usr/bin/env bash

set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
nuttx_dir=${NUTTX_DIR:-"$root_dir/nuttx"}
port=${1:-}
no_erase=${2:-}

if [ -z "$port" ]; then
  echo "Usage: $0 <serial-port> [--no-erase]" >&2
  exit 1
fi

if [ -n "$no_erase" ] && [ "$no_erase" != "--no-erase" ]; then
  echo "Unknown option: $no_erase" >&2
  exit 1
fi

if [ ! -f "$nuttx_dir/nuttx.bin" ]; then
  echo "Missing $nuttx_dir/nuttx.bin. Run scripts/build.sh first." >&2
  exit 1
fi

if ! command -v esptool.py >/dev/null 2>&1; then
  echo "esptool.py is required: python3 -m pip install --user 'esptool>=4.8.1'" >&2
  exit 1
fi

cd "$nuttx_dir"

artifacts="$root_dir/artifacts"
bootloader=${BOOTLOADER_BIN:-"$artifacts/bootloader-esp32c3.bin"}
partition_table="$artifacts/partition-table-esp32c3.bin"

if [ ! -f "$bootloader" ]; then
  bootloader="$root_dir/prebuilt/bootloader-esp32c3.bin"
fi

if [ ! -f "$bootloader" ]; then
  echo "Missing ESP-IDF bootloader image." >&2
  exit 1
fi

if [ ! -f "$partition_table" ]; then
  echo "Generating partition table from partitions.csv"
  python3 "$root_dir/scripts/gen_partition.py" "$root_dir/partitions.csv" \
    "$partition_table"
fi

if [ -z "$no_erase" ]; then
  esptool.py --chip esp32c3 --port "$port" erase_flash
fi

# 0x0    : ESP-IDF second stage bootloader
# 0x8000 : partition table
# 0x10000: NuttX application image

esptool.py --chip esp32c3 --port "$port" -b 460800 write_flash \
  0x0 "$bootloader" \
  0x8000 "$partition_table" \
  0x10000 "$nuttx_dir/nuttx.bin"
