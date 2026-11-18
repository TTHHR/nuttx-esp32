#!/usr/bin/env bash

set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
nuttx_dir=${NUTTX_DIR:-"$root_dir/nuttx"}
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
defconfig="$root_dir/config/clawdmochi/defconfig"
config_stamp="$nuttx_dir/.clawdmochi-defconfig.sha256"
config_inputs=(
  "$defconfig"
)
# Only the defconfig determines the generated .config.  scripts/setup.sh is
# idempotent environment preparation (header shims, patches) and must not
# force a full distclean/reconfigure when it changes.
defconfig_hash=$(cat "${config_inputs[@]}" | sha256sum | awk '{print $1}')

if [ -n "${NUTTX_TOOLCHAIN_BIN:-}" ]; then
  export PATH="$NUTTX_TOOLCHAIN_BIN:$PATH"
elif ! command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 &&
     ! command -v riscv-none-elf-gcc >/dev/null 2>&1; then
  echo "No RISC-V NuttX toolchain found." >&2
  echo "Set NUTTX_TOOLCHAIN_BIN to the directory containing the toolchain." >&2
  exit 1
fi

if ! command -v kconfig-tweak >/dev/null 2>&1; then
  echo "kconfig-tweak is required (install kconfig-frontends or kconfiglib)." >&2
  exit 1
fi

if ! command -v esptool.py >/dev/null 2>&1; then
  echo "esptool.py is required: python3 -m pip install --user 'esptool>=4.8.1'" >&2
  exit 1
fi

"$root_dir/scripts/setup.sh"

cd "$nuttx_dir"

configured_hash=""
if [ -f "$config_stamp" ]; then
  configured_hash=$(cat "$config_stamp")
fi

if [ "${RECONFIGURE:-0}" = "1" ] || [ ! -f .config ] ||
   [ "$configured_hash" != "$defconfig_hash" ]; then
  echo "Reconfiguring NuttX from $defconfig"

  # "make distclean" removes the cloned Espressif HAL repository (~250 MB,
  # including the WiFi/PHY/Coex/BT binary submodules).  Re-cloning it on
  # every defconfig change is painful on slow networks, so park it outside
  # the build tree and put it back once the build tree has been recreated.
  # Delete .cache/esp-hal-3rdparty manually after changing
  # ESP_HAL_3RDPARTY_VERSION in nuttx.
  hal_dir="$nuttx_dir/arch/risc-v/src/esp32c3/esp-hal-3rdparty"
  hal_cache="$root_dir/.cache/esp-hal-3rdparty"

  if [ -d "$hal_dir" ] && [ ! -e "$hal_cache" ]; then
    install -d "$(dirname "$hal_cache")"
    mv "$hal_dir" "$hal_cache"
  fi

  if [ -f Make.defs ] || [ -f .config ]; then
    make distclean
  fi

  if [ ! -e "$hal_dir" ] && [ -d "$hal_cache" ]; then
    mv "$hal_cache" "$hal_dir"
  fi

  ./tools/configure.sh -a ../nuttx-apps esp32c3-supermini:clawdmochi
  printf '%s\n' "$defconfig_hash" > "$config_stamp"
fi

make -j"$jobs"

install -d "$root_dir/artifacts"
install -m 0644 nuttx.bin "$root_dir/artifacts/nuttx.bin"
install -m 0644 "${BOOTLOADER_BIN:-$root_dir/prebuilt/bootloader-esp32c3.bin}" \
  "$root_dir/artifacts/bootloader-esp32c3.bin"
python3 "$root_dir/scripts/gen_partition.py" "$root_dir/partitions.csv" \
  "$root_dir/artifacts/partition-table-esp32c3.bin"
"$root_dir/scripts/size-check.sh" "$root_dir/artifacts/nuttx.bin"
(
  cd "$root_dir/artifacts"
  sha256sum bootloader-esp32c3.bin partition-table-esp32c3.bin nuttx.bin \
    > SHA256SUMS
)

printf "nuttx.bin: "
stat -c '%s bytes' nuttx.bin
