# ClawdMochi NuttX ESP32-C3

This repository integrates NuttX with the ClawdMochi ESP32-C3 device. It
replaces the previous BOOT + A/B application layout with one NuttX image and a
NuttX-managed LittleFS data partition.

The design is documented in
[docs/dev-plan-nuttx-data-single-system.md](docs/dev-plan-nuttx-data-single-system.md).

## Status

The build, flash, and boot path is working on the target board: `scripts/build.sh`
produces the three images, the images flash without error, and the board starts
NuttX and reaches the NSH prompt, where commands can be entered. The later
phases of the plan (Wi-Fi/DHCP, `/data` persistence, ELF execution) are
validated incrementally on hardware.

## Working notes

- The build needs network access (submodules, Python packages, toolchain
  packages). This WSL distro reaches the network through the Windows host, so
  the Windows-side proxy must be configured and running before
  `git submodule update --init --recursive` or `scripts/build.sh` is run.
- AI assistants working in this repository only modify source code. Building
  and flashing the board are done by the developer: do not run
  `scripts/build.sh`, `make`, `esptool.py`, or `scripts/flash.sh`
  automatically.
- The board port is committed on branch `clawdmochi` in both submodule forks.
  Change the port there, push the branch, then record the new revision here
  with `git add nuttx nuttx-apps`. Do not commit in a detached submodule
  checkout: the recorded revision would only exist on the local machine.

## Layout

- `nuttx`: NuttX fork (`TTHHR/nuttx`, branch `clawdmochi`), based on the
  tested upstream revision plus the ESP32-C3 port.
- `nuttx-apps`: applications fork (`TTHHR/nuttx-apps`, branch `clawdmochi`),
  carrying `examples/clawdmochi_posix`.
- `apps/clawdmochi_posix`: POSIX validation application.
- `config`: board configuration, startup script, network defaults, and the
  application overlay copied into the source trees by `scripts/setup.sh`.
- `partitions.csv`: 4 MB ESP32-C3 flash layout.
- `scripts`: reproducible setup, build, size check, and flash helpers.
- `docs`: design plan and Wi-Fi bring-up notes
  ([wifi-bringup-notes.md](docs/wifi-bringup-notes.md)).

## First build

Make sure the Windows-side proxy is configured before this step, otherwise
submodule and package downloads will fail (see
[Working notes](#working-notes)).

Initialize the submodules. In WSL, install the Linux RISC-V bare-metal
toolchain, Kconfig frontend, and esptool:

```console
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf \
  picolibc-riscv64-unknown-elf kconfig-frontends
python3 -m pip install --user 'esptool>=4.8.1'
```

Then build:

```console
git submodule update --init --recursive
./scripts/build.sh
```

`build.sh` uses the Linux `riscv64-unknown-elf-` toolchain in `PATH`. It
generates the partition table from `partitions.csv`, uses the checked-in
ESP32-C3 ESP-IDF bootloader by default, and verifies that the NuttX image
fits the 1.25 MiB system partition.

The Windows-ready artifacts are copied to `artifacts/`:

- `artifacts/bootloader-esp32c3.bin`
- `artifacts/partition-table-esp32c3.bin`
- `artifacts/nuttx.bin`

From Windows, this WSL directory is available through the `\\wsl$` share. The
three files can be copied to Windows and flashed there.

Copy `artifacts/` to a local Windows directory, then run:

```console
esptool.py --chip esp32c3 --port COM5 erase_flash
esptool.py --chip esp32c3 --port COM5 -b 460800 write_flash ^
  "0x0 bootloader-esp32c3.bin" ^
  "0x8000 partition-table-esp32c3.bin" ^
  "0x10000 nuttx.bin"
```

In PowerShell, replace the `^` continuation characters with backticks or
put the three flash mappings on one line.

## Flash

Pass the WSL serial device explicitly:

If the serial port is passed through to WSL:

```console
./scripts/flash.sh /dev/ttyUSB0
```

The initial image must be written with the ESP-IDF second-stage bootloader,
custom partition table, and NuttX application image. After that, only
`nuttx.bin` normally needs replacement.

## Runtime

At boot NuttX mounts the `nuttxdata` region at `/data`, associates with the
configured access point, obtains an IPv4 address over DHCP, prints the
interface status over UART, and enters NSH. The default test AP is configured
in `config/clawdmochi/defconfig` and can be changed with `make menuconfig`.

Create an executable directory and a boot script from NSH:

```console
nsh> mkdir -p /data/bin /data/scripts
nsh> cat > /data/boot.nsh
echo ClawdMochi boot script
```

On the next boot, an existing `/data/boot.nsh` is sourced automatically.
NuttX ELF programs can be run by absolute path, for example:

```console
nsh> /data/bin/clawdmochi_posix
```

The built-in validation application can be run without a data-partition
upload:

```console
nsh> clawdmochi_posix
```

## Recovery

The ESP ROM serial download path remains available. If the NuttX image is
broken, hold the board in download mode and run the initial flash helper again:

```console
./scripts/flash.sh /dev/ttyUSB0 --erase
```

This deliberately does not implement remote self-update of the single NuttX
system partition.
