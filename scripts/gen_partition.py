#!/usr/bin/env python3

"""Generate an ESP-IDF partition-table binary from partitions.csv."""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

TABLE_SIZE = 0xC00

TYPE_IDS = {
    "app": 0x00,
    "data": 0x01,
}

SUBTYPE_IDS = {
    ("app", "factory"): 0x00,
    ("data", "phy"): 0x01,
    ("data", "nvs"): 0x02,
    ("data", "spiffs"): 0x82,
}


def parse_int(value: str) -> int:
    return int(value, 0)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    entries = []
    next_offset = 0x9000

    for line_number, raw_line in enumerate(
        args.input.read_text(encoding="utf-8-sig").splitlines(), start=1
    ):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue

        fields = [field.strip() for field in line.split(",")]
        if len(fields) < 5:
            raise ValueError(f"{args.input}:{line_number}: expected five fields")

        name, part_type, subtype = fields[:3]
        offset = parse_int(fields[3])
        size = parse_int(fields[4])
        flags = parse_int(fields[5]) if len(fields) > 5 and fields[5] else 0

        if len(name.encode("ascii")) > 16:
            raise ValueError(f"{args.input}:{line_number}: partition name too long")
        if part_type not in TYPE_IDS:
            raise ValueError(f"{args.input}:{line_number}: unknown type {part_type}")
        if (part_type, subtype) not in SUBTYPE_IDS:
            raise ValueError(f"{args.input}:{line_number}: unknown subtype {subtype}")
        if offset < next_offset:
            raise ValueError(f"{args.input}:{line_number}: overlapping partition")
        if size <= 0 or offset + size > 0x400000:
            raise ValueError(f"{args.input}:{line_number}: invalid partition range")

        entries.append((name, part_type, subtype, offset, size, flags))
        next_offset = offset + size

    table = bytearray(b"\xff" * TABLE_SIZE)
    position = 0

    for name, part_type, subtype, offset, size, flags in entries:
        entry = struct.pack(
            "<HBBII16sI",
            0x50AA,
            TYPE_IDS[part_type],
            SUBTYPE_IDS[(part_type, subtype)],
            offset,
            size,
            name.encode("ascii"),
            flags,
        )
        table[position : position + len(entry)] = entry
        position += len(entry)

    checksum_record = bytearray(b"\xff" * 32)
    checksum_record[:2] = struct.pack("<H", 0xEBEB)
    checksum_record[16:32] = hashlib.md5(table[:position]).digest()
    table[position : position + len(checksum_record)] = checksum_record

    args.output.write_bytes(table)


if __name__ == "__main__":
    main()
