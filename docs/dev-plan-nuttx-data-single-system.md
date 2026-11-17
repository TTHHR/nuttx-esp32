# ClawdMochi ESP32-C3: NuttX + NuttXData Development Plan

## 1. Purpose

This document records the development plan for replacing the current
`BOOT + A/B APP` layout with a single NuttX system plus a NuttX-managed
data partition.

Target device:

- ESP32-C3
- 4MB internal XMC flash
- Current serial recovery port: `COM5`
- Current test Wi-Fi: `invo-lan`

## 2. Baseline Decision

The previous BOOT application is considered removable for the current
development and validation phase because the developer has confirmed that
serial rescue via `COM` is acceptable.

Accepted rescue/update path for this phase:

- Broken NuttX image: reflash via `esptool.py` over `COM5`
- Broken data partition: recreate/mount from NuttX NSH or reflash if
  necessary

This plan does **not** try to implement safe remote self-update of the
running NuttX system partition in the first phase.

## 3. Target System Concept

New runtime model:

```text
ESP32-C3 ROM bootloader
  -> ESP-IDF second-stage bootloader
  -> NuttX main system image (nuttx partition)
       -> initialize flash
       -> connect Wi-Fi
       -> print/show IP
       -> mount nuttxdata as /data
       -> execute /data/boot.nsh if present
       -> enter NSH or run the built-in NuttX manager
```

The system is not split into BOOT and APP. NuttX is the main and only
application runtime.

## 4. Goals

### G1: Remove BOOT application

- Delete the old factory BOOT app from the product flow.
- Keep ESP-IDF second-stage bootloader and partition table only.
- NuttX becomes the bootable image at `0x10000`.

### G2: Use two main NuttX domains

- `nuttx`: NuttX system image.
- `nuttxdata`: NuttX-managed file system for scripts, data, and NuttX
  ELF/NXFLAT programs.

### G3: NuttX owns Wi-Fi

- NuttX connects to the configured AP after boot.
- NuttX obtains an IPv4 address.
- NuttX prints the IP over UART.
- Optional later step: display the IP on the existing ST7789 screen.

### G4: NuttX owns flash data

- NuttX exposes the `nuttxdata` region as flash storage.
- NuttX mounts `/data`.
- `/data` survives normal reboots.

### G5: Run programs from nuttxdata

- NSH scripts can be stored in `/data`.
- NuttX ELF/NXFLAT programs can be stored in `/data/bin` and executed from
  NSH.
- Arbitrary non-NuttX binaries are out of scope in this phase.

### G6: Slim down NuttX

- Disable example and test applications that are not needed.
- Keep the minimal feature set required by the new architecture.
- Keep source tree intact; use Kconfig/defconfig to exclude builds instead
  of deleting source files.

## 5. Proposed Partition Table

The following layout is the initial plan. Sizes are fixed until a build
shows that NuttX needs more room.

| Name      | Type | SubType | Offset   | Size     | Purpose                              |
|-----------|------|---------|----------|----------|--------------------------------------|
| nvs       | data | nvs     | 0x9000   | 0x4000   | Wi-Fi and NuttX config               |
| phy_init  | data | phy     | 0xf000   | 0x1000   | RF calibration                       |
| nuttx     | app  | factory | 0x10000  | 0x140000 | NuttX system image                  |
| nuttxdata | data | spiffs  | 0x150000 | 0x2B0000 | NuttX data filesystem               |

Notes:

- `nuttx` is provisionally sized at 1.25 MiB.
- `nuttxdata` is provisionally sized at 2.625 MiB.
- The `spiffs` subtype is a placeholder. The actual NuttX filesystem is
  selected in phase 3; the boot partition table subtype is not the NuttX
  filesystem driver.
- `phy_init` shall be kept unless testing proves it can be omitted.

## 6. NuttX Feature Budget

### Must keep

Core:

- NuttX kernel
- NSH
- POSIX spawn/path execution where needed
- ELF and/or NXFLAT binary loader support

Networking:

- TCP/IP stack
- UDP/TCP sockets
- Wi-Fi support
- DHCP client
- DNS client if hostname access is needed

Storage:

- Flash MTD
- `/data` filesystem
- Filesystem creation tool
- mount

Management:

- Serial console / NSH
- A small built-in Wi-Fi/device manager or equivalent init sequence
- File transfer path for later use: TFTP or FTP is preferred in phase 5

### Should disable

Typical examples:

- `CONFIG_EXAMPLES_HELLO=n`
- `CONFIG_EXAMPLES_HELLOXX=n`
- `CONFIG_TESTING_OSTEST=n`
- Unused sensor examples
- Unused graphics examples
- Unused network examples
- Unneeded interpreter examples, unless later required

The exact disable list will be finalized against the generated `.config`.

## 7. NuttX Source and Build Setup

Current repository is `D:\nuttx-esp32`. The plan assumes it will contain the
NuttX integration work.

Source prerequisites:

- `nuttx` source tree.
- `nuttx-apps` tree.

Existing reference trees used while planning:

- `D:\soft\claude\nuttx-apps`
- `D:\soft\claude\nxtmpdir\esp-hal-3rdparty`

Before development, the current `D:\nuttx-esp32` repository must be
populated or linked with the intended NuttX/nuttx-apps sources.

## 8. Development Phases

### Phase 0: Backup and repo preparation

Tasks:

1. Record current 4MB flash as a full backup.
2. Record current partition table.
3. Initialize `D:\nuttx-esp32` structure for NuttX integration.
4. Preserve the previous BOOT research under `D:\soft\claude`.

Example:

```powershell
esptool.py --port COM5 flash_id
esptool.py --port COM5 read_flash 0x0 0x400000 D:\soft\claude\clawdmochi-4MB-backup.bin
```

### Phase 1: NuttX board build and slimming

Tasks:

1. Build a baseline `esp32c3-devkit:nsh` or equivalent ESP32-C3 config.
2. Enable Wi-Fi and flash storage.
3. Enable NSH and file app execution.
4. Disable example/test apps.
5. Record image size and compare against the `nuttx` 1.25 MiB budget.

Acceptance:

- NuttX builds successfully.
- `nuttx.bin` is generated.
- Image size is compatible with the planned `nuttx` partition.

### Phase 2: Partition table and first flashing

Tasks:

1. Create the new partition CSV.
2. Flash ESP-IDF bootloader.
3. Flash partition table.
4. Flash NuttX system image at `0x10000`.

Acceptance:

- ESP-ROM starts.
- ESP-IDF second-stage bootloader recognizes the `nuttx` factory app.
- NuttX reaches NSH over serial.

### Phase 3: Data partition filesystem

Tasks:

1. Decide initial filesystem: NXFFS, SmartFS, or LittleFS.
2. Configure NuttX flash MTD to expose `nuttxdata`.
3. Add startup mount for `/data`.
4. Verify `/data` survives reboot.

Acceptance:

- `mount` shows `/data`.
- Files can be created, read, deleted, and kept across reboot.

### Phase 4: Wi-Fi startup and device manager

Tasks:

1. Add Wi-Fi network startup using the intended SSID/password.
2. Implement simple DHCP wait until an IP is acquired.
3. Print the IP to the serial console.
4. Optionally display the IP on the existing screen in a later step.

Acceptance:

- After boot, NuttX connects to `invo-lan`.
- Serial shows a valid IP.
- No BOOT app is needed to obtain an IP.

### Phase 5: Script and executable loading

Tasks:

1. Ensure NSH can execute script files from `/data`.
2. Build a small NuttX ELF or NXFLAT test program.
3. Copy it into `/data/bin`.
4. Execute it from NSH.

Acceptance:

- `nsh> /data/bin/test.elf` runs.
- A `/data/boot.nsh` with one command can run at startup or manually.

### Phase 6: Transfer path for uploaded files

Tasks:

1. Choose a first transfer method for `nuttxdata`: TFTP, FTP, or a later
   tiny web uploader inside NuttX.
2. Document how to put ELF/NXFLAT programs into `/data/bin`.

This phase can be iterative.

### Phase 7: Validation application

Tasks:

1. Rebuild/keep the existing `clawdmochi_posix` application as a first
   NuttX executable test.
2. Run it from `/data/bin` or as a built-in first.
3. Confirm POSIX threads, mutex, condition variable, semaphore, and timer
   API behavior.

Acceptance:

- `clawdmochi_posix` prints `PASS`.

## 9. Risks and Open Items

### R1: NuttX image size

If NuttX with Wi-Fi, network, NSH, file system, and ELF/NXFLAT loader
exceeds 1.25 MiB, adjust:

- Reduce unnecessary NuttX features.
- Increase `nuttx` partition size and reduce `nuttxdata`.

### R2: NuttX executable format

ELF and NXFLAT loading is required to execute uploaded programs. This must
be verified early. It affects whether uploaded programs are relocated into
RAM or executed from flash.

### R3: No safe remote self-update

This phase accepts serial recovery. Before production use, a separate
updater/recovery strategy is required.

### R4: NuttX flash subregion

NuttX must know the physical offset and size of `nuttxdata`. If NuttX does
not parse the ESP-IDF partition table in our board config, use a fixed NuttX
configuration for:

- data MTD offset
- data MTD size

### R5: Wi-Fi stability

NuttX ESP32-C3 Wi-Fi must be validated for DHCP, reconnect, and long-run
operation. The existing ESP-IDF BOOT behavior is the reference baseline.

### R6: Screen display

The old BOOT displayed IP on ST7789. The first NuttX phase can use serial
logging only. Screen display is an optional future milestone to avoid
blocking the filesystem and app execution path.

## 10. Acceptance Checklist

Phase 2 is done: the images flash and the board reaches NSH.

- [x] ESP32-C3 boots directly into NuttX without BOOT app.
- [x] Partition table has `nuttx` and `nuttxdata`.
- [x] NSH accepts commands after boot.
- [ ] NuttX connects to Wi-Fi and prints an IP.
- [ ] NuttX mounts `/data` from `nuttxdata`.
- [ ] NSH can read/write/delete files under `/data`.
- [ ] NSH can execute a NuttX ELF/NXFLAT program from `/data/bin`.
- [ ] Example and test apps no longer appear in the build where not needed.
- [ ] A broken NuttX image can be recovered by flashing over COM.
- [ ] Existing POSIX validation can run on the new system.

## 11. First Action Items

1. Populate or restore the NuttX main source tree into `D:\nuttx-esp32`.
2. Create the `esp32c3-devkit:nsh` base config.
3. Enable Wi-Fi, network, MTD, filesystem, NSH, and BINFMT.
4. Disable obvious example/testing applications.
5. Record the first `nuttx.bin` size.
6. Create and flash the new partition table.
