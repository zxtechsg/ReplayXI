#!/usr/bin/env python3
"""Fetch the pinned Microsoft Rocketbox football-player pilot inputs.

The downloaded files are build inputs, not application resources. Every file
is pinned to one upstream commit and admitted only after byte-count and SHA-256
verification. The script never replaces an existing invalid file.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile
from typing import Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


ROCKETBOX_REPOSITORY = "https://github.com/microsoft/Microsoft-Rocketbox"
ROCKETBOX_COMMIT = "0943055db6ec570bcef9f2c8b41c9e5467c808f9"
RAW_BASE_URL = (
    "https://raw.githubusercontent.com/microsoft/Microsoft-Rocketbox/"
    f"{ROCKETBOX_COMMIT}/"
)


@dataclass(frozen=True)
class AssetRecord:
    path: str
    byte_count: int
    sha256: str
    purpose: str


# Audited from the raw files at ROCKETBOX_COMMIT on 2026-09-03. Sports_Male_02
# is the cleanest football-shaped source mesh in the library: it has no alpha
# hair material and imports as two skinned primitives on one 80-joint skeleton.
PILOT_ASSETS: tuple[AssetRecord, ...] = (
    AssetRecord(
        "LICENSE.md",
        1_066,
        "17474e386e0b9e1a700cc3d06b2b0882a2c376d9c6b49c7f8274409b8f8d2352",
        "required MIT notice",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Export/Sports_Male_02.fbx",
        538_656,
        "eb8e93c524cb7e741f87eac164ed58b05179e460458415bf0fbb9efaa4374665",
        "football-kit character and 80-joint skin",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Sports_Male_02.png",
        410_182,
        "f9eaaaf87d108837c50e36f0f95b61430a5fcdfa644de6d392c84624f44a0aae",
        "upstream visual reference",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Textures/m301_body_color.tga",
        12_582_956,
        "30c476ad54d334e54cdc976e818de9d44c5a6dc7a8d542011a9da301a2fde45c",
        "body and kit base colour",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Textures/m301_body_normal.tga",
        12_582_956,
        "cade8db63791243aae802012edd2c46ab2486899a9173a9497a6d1acd3ab3399",
        "body and kit tangent-space normal",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Textures/m301_body_specular.tga",
        12_582_956,
        "4571014cd35eab46ef5d15b7ad046043c6d1ee8d5e7039fe22bf70b413bb0812",
        "source specular map for offline roughness conversion",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Textures/m301_head_color.tga",
        12_582_956,
        "85d9282454b3f9ed510a2664d3f851c24d4962c5b4af5942bb5413c6685047a3",
        "head base colour",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Textures/m301_head_normal.tga",
        12_582_956,
        "9df640cc33a98815fa19b32b93055cf864edb6c2753a2a6968f099704873e7fb",
        "head tangent-space normal",
    ),
    AssetRecord(
        "Assets/Avatars/Professions/Sports_Male_02/Textures/m301_head_specular.tga",
        12_582_956,
        "15fc06f0e38084355ce26446349319067ddc3a17a3934c9b4a8d9fe982f254a0",
        "source head specular map for offline roughness conversion",
    ),
    AssetRecord(
        "Assets/Animations/all_animations_max_motextr_static/m_idle_breathe_01.max.fbx",
        1_397_280,
        "281735704260d96e882d13e3c77d0ede00ed5d2e40805cd305000b3e5cbb1090",
        "neutral standing motion",
    ),
    AssetRecord(
        "Assets/Animations/all_animations_max_motextr_xy/m_run_fast_01.max.fbx",
        833_040,
        "81d096f62465ae038149e7726485133264e4a47d105d236370b00dc18c650526",
        "fast locomotion motion",
    ),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validated_target(root: Path, relative_path: str) -> Path:
    relative = PurePosixPath(relative_path)
    if relative.is_absolute() or not relative.parts or any(
        part in ("", ".", "..") for part in relative.parts
    ):
        raise ValueError(f"unsafe asset path: {relative_path!r}")

    resolved_root = root.resolve()
    target = resolved_root.joinpath(*relative.parts)
    # Existing symlinked parents must not redirect writes outside the selected
    # acquisition root.
    resolved_parent = target.parent.resolve()
    if resolved_parent != resolved_root and resolved_root not in resolved_parent.parents:
        raise ValueError(f"asset path escapes destination: {relative_path!r}")
    return target


def validation_error(path: Path, record: AssetRecord) -> str | None:
    if not path.is_file():
        return "missing"
    byte_count = path.stat().st_size
    if byte_count != record.byte_count:
        return f"size {byte_count}, expected {record.byte_count}"
    actual_hash = sha256_file(path)
    if actual_hash != record.sha256:
        return f"SHA-256 {actual_hash}, expected {record.sha256}"
    return None


def audit_directory(
    root: Path,
    records: Iterable[AssetRecord] = PILOT_ASSETS,
) -> list[str]:
    errors: list[str] = []
    for record in records:
        target = validated_target(root, record.path)
        problem = validation_error(target, record)
        if problem:
            errors.append(f"{record.path}: {problem}")
    return errors


def source_url(record: AssetRecord) -> str:
    return RAW_BASE_URL + "/".join(quote(part) for part in PurePosixPath(record.path).parts)


def fetch_record(root: Path, record: AssetRecord, timeout: float) -> str:
    target = validated_target(root, record.path)
    if target.exists():
        problem = validation_error(target, record)
        if problem:
            raise RuntimeError(
                f"refusing to replace invalid existing file {target}: {problem}"
            )
        return "verified"

    target.parent.mkdir(parents=True, exist_ok=True)
    request = Request(
        source_url(record),
        headers={"User-Agent": "ReplayXI-asset-audit/1.0"},
    )
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=target.parent,
            prefix=f".{target.name}.",
            suffix=".partial",
            delete=False,
        ) as temporary:
            temporary_name = temporary.name
            with urlopen(request, timeout=timeout) as response:
                while block := response.read(1024 * 1024):
                    temporary.write(block)
            temporary.flush()
            os.fsync(temporary.fileno())

        temporary_path = Path(temporary_name)
        problem = validation_error(temporary_path, record)
        if problem:
            raise RuntimeError(f"download validation failed for {record.path}: {problem}")
        os.replace(temporary_path, target)
        temporary_name = None
        return "downloaded"
    finally:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="validate an existing acquisition without network access",
    )
    parser.add_argument("--timeout", type=float, default=90.0)
    arguments = parser.parse_args(argv)

    if arguments.timeout <= 0:
        parser.error("--timeout must be positive")

    if arguments.verify_only:
        errors = audit_directory(arguments.destination)
        if errors:
            for error in errors:
                print(f"error: {error}", file=sys.stderr)
            return 1
        print(f"verified {len(PILOT_ASSETS)} Rocketbox pilot inputs")
        return 0

    try:
        arguments.destination.mkdir(parents=True, exist_ok=True)
        for record in PILOT_ASSETS:
            result = fetch_record(arguments.destination, record, arguments.timeout)
            print(f"{result}: {record.path}")
    except (HTTPError, URLError, OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    errors = audit_directory(arguments.destination)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"ready: {len(PILOT_ASSETS)} pinned inputs from {ROCKETBOX_COMMIT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
