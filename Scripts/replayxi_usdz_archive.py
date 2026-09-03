#!/usr/bin/env python3
"""Small, dependency-free USDZ archive safety and reproducibility helpers."""

from __future__ import annotations

import os
from pathlib import Path, PurePosixPath
import stat
import struct
import zipfile


# ZIP's DOS timestamp cannot represent dates before 1980. A fixed 2000-01-01
# value makes identical USDZ inputs byte-for-byte reproducible without changing
# payloads, alignment padding, CRCs, or archive member offsets.
FIXED_ZIP_DATETIME = (2000, 1, 1, 0, 0, 0)
FIXED_DOS_TIME = 0
FIXED_DOS_DATE = ((FIXED_ZIP_DATETIME[0] - 1980) << 9) | (1 << 5) | 1


def validated_archive_names(infos: list[zipfile.ZipInfo]) -> list[str]:
    """Reject paths or entry types that are unsafe to extract."""

    names: list[str] = []
    for info in infos:
        member = PurePosixPath(info.filename)
        mode = info.external_attr >> 16
        if (
            member.is_absolute()
            or not member.parts
            or ".." in member.parts
            or "\\" in info.filename
        ):
            raise ValueError(f"unsafe USDZ archive member: {info.filename!r}")
        if stat.S_ISLNK(mode):
            raise ValueError(
                f"USDZ archive member must not be a symlink: {info.filename!r}"
            )
        names.append(info.filename)
    if len(names) != len(set(names)):
        raise ValueError("USDZ archive contains duplicate member names")
    return names


def normalize_usdz_timestamps(path: Path) -> None:
    """Normalize local and central ZIP timestamps without repacking the USDZ."""

    payload = bytearray(path.read_bytes())
    eocd = payload.rfind(b"PK\x05\x06", max(0, len(payload) - 65_557))
    if eocd < 0 or eocd + 22 > len(payload):
        raise ValueError(f"USDZ has no valid end-of-central-directory record: {path}")

    (
        disk_number,
        central_disk,
        entries_on_disk,
        entry_count,
        central_size,
        central_offset,
        comment_length,
    ) = struct.unpack_from("<4H2IH", payload, eocd + 4)
    if disk_number or central_disk or entries_on_disk != entry_count:
        raise ValueError("multi-disk USDZ archives are unsupported")
    if entry_count == 0xFFFF or central_size == 0xFFFFFFFF or central_offset == 0xFFFFFFFF:
        raise ValueError("ZIP64 USDZ archives are unsupported")
    if eocd + 22 + comment_length != len(payload):
        raise ValueError("malformed USDZ archive comment length")
    if central_offset + central_size != eocd:
        raise ValueError("malformed USDZ central-directory bounds")

    cursor = central_offset
    for _ in range(entry_count):
        if cursor + 46 > eocd or payload[cursor : cursor + 4] != b"PK\x01\x02":
            raise ValueError("malformed USDZ central-directory entry")
        filename_length, extra_length, member_comment_length = struct.unpack_from(
            "<3H", payload, cursor + 28
        )
        local_offset = struct.unpack_from("<I", payload, cursor + 42)[0]
        if (
            local_offset + 30 > central_offset
            or payload[local_offset : local_offset + 4] != b"PK\x03\x04"
        ):
            raise ValueError("malformed USDZ local-file header offset")
        struct.pack_into("<HH", payload, local_offset + 10, FIXED_DOS_TIME, FIXED_DOS_DATE)
        struct.pack_into("<HH", payload, cursor + 12, FIXED_DOS_TIME, FIXED_DOS_DATE)
        cursor += 46 + filename_length + extra_length + member_comment_length
    if cursor != eocd:
        raise ValueError("USDZ central-directory size does not match its entries")

    temporary = path.with_name(f".{path.name}.timestamp-normalized")
    temporary.write_bytes(payload)
    temporary.chmod(path.stat().st_mode)
    os.replace(temporary, path)
