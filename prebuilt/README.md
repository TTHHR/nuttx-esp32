# Prebuilt ESP-IDF bootloader

`bootloader-esp32c3.bin` is the validated ESP32-C3 second-stage bootloader
from the existing ClawdMochi ESP-IDF product build. It starts the factory
application at `0x10000` and reads the partition table from `0x8000`.

SHA-256:

```text
2f44629a8dbbd20653b0a0237384745739192bb8f23ff5ade15cf856eeab0167
```

The checked-in bootloader avoids requiring a full ESP-IDF checkout just to
assemble the NuttX firmware. Override it with `BOOTLOADER_BIN` when using a
bootloader built from another ESP-IDF revision.
