#!/usr/bin/env python3
"""Audit a Replay XI skinned USDZ without third-party Python packages.

Apple's usdchecker validates USD/USDZ conformance, but it intentionally does
not judge whether a skeleton's token paths describe the intended hierarchy.
That distinction matters here: the retired gltf2usd converter can turn
``root/pelvis/spine`` into ``root_pelvis_spine``.  The resulting package is
valid USD, yet every bone is interpreted as a root and animation deformation
is visibly wrong.

This preflight converts the root layer to USDA with Apple's ``usdcat`` and
checks the narrow structural contract used by Replay XI.  It has no Python
dependencies beyond the standard library, so it can run in CI before the
asset is admitted to the application bundle.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zipfile

from replayxi_usdz_archive import FIXED_ZIP_DATETIME, validated_archive_names


USDCAT = Path("/usr/bin/usdcat")
USDCHECKER = Path("/usr/bin/usdchecker")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _png_dimensions(payload: bytes) -> tuple[int, int] | None:
    if len(payload) < 24 or payload[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", payload[16:24])


def _joint_arrays(usda: str) -> list[list[str]]:
    arrays = re.findall(
        r"uniform\s+token\[\]\s+joints\s*=\s*\[(.*?)\]",
        usda,
        flags=re.DOTALL,
    )
    return [re.findall(r'"((?:[^"\\]|\\.)*)"', payload) for payload in arrays]


def _topology_errors(joints: list[str], label: str) -> list[str]:
    errors: list[str] = []
    if not joints:
        return [f"{label}: empty joint order"]
    if len(joints) != len(set(joints)):
        errors.append(f"{label}: joint paths are not unique")

    joint_set = set(joints)
    joint_positions = {joint: index for index, joint in enumerate(joints)}
    roots: list[str] = []
    for index, joint in enumerate(joints):
        if not joint or joint.startswith("/") or joint.endswith("/") or "//" in joint:
            errors.append(f"{label}: malformed relative joint path {joint!r}")
            continue
        parent = joint.rsplit("/", 1)[0] if "/" in joint else ""
        while parent and parent not in joint_set:
            parent = parent.rsplit("/", 1)[0] if "/" in parent else ""
        if not parent:
            roots.append(joint)
        elif joint_positions[parent] >= index:
            errors.append(f"{label}: parent {parent!r} must precede child {joint!r}")

    if len(joints) > 1 and all("/" not in joint for joint in joints):
        errors.append(
            f"{label}: all {len(joints)} joints are flat tokens; hierarchy separators were lost"
        )
    if len(roots) != 1:
        errors.append(
            f"{label}: expected one skeleton root, found {len(roots)} ({', '.join(roots[:4])})"
        )
    return errors


def audit(asset: Path) -> dict[str, object]:
    errors: list[str] = []
    warnings: list[str] = []
    if not asset.is_file():
        raise FileNotFoundError(asset)
    if asset.suffix.lower() != ".usdz":
        raise ValueError("asset must end in .usdz")
    if not USDCAT.is_file() or not USDCHECKER.is_file():
        raise RuntimeError("Apple usdcat and usdchecker are required in /usr/bin")

    texture_bytes = 0
    texture_count = 0
    archive_members: list[str] = []
    with zipfile.ZipFile(asset) as archive:
        infos = archive.infolist()
        try:
            archive_members = validated_archive_names(infos)
        except ValueError as error:
            errors.append(str(error))
            archive_members = [info.filename for info in infos]
        if not infos or not infos[0].filename.lower().endswith((".usd", ".usda", ".usdc")):
            errors.append("USDZ root layer is not the first archive member")
        compressed = [info.filename for info in infos if info.compress_type != zipfile.ZIP_STORED]
        if compressed:
            errors.append(f"USDZ members must be stored without compression: {compressed[:3]}")
        non_reproducible = [
            info.filename for info in infos if info.date_time != FIXED_ZIP_DATETIME
        ]
        if non_reproducible:
            errors.append(
                "USDZ member timestamps are not normalized for reproducible builds: "
                f"{non_reproducible[:3]}"
            )
        for info in infos:
            if not info.filename.lower().endswith(".png"):
                continue
            dimensions = _png_dimensions(archive.read(info))
            if dimensions:
                texture_count += 1
                texture_bytes += dimensions[0] * dimensions[1] * 4

    compliance = subprocess.run(
        [str(USDCHECKER), "--arkit", "-t", str(asset)],
        check=False,
        capture_output=True,
        text=True,
    )
    compliance_text = compliance.stdout + compliance.stderr
    if compliance.returncode != 0 or "Success!" not in compliance_text:
        errors.append("usdchecker --arkit -t rejected the package")

    with tempfile.TemporaryDirectory(prefix="replayxi-usdz-audit-") as temporary:
        usda = Path(temporary) / "asset.usda"
        converted = subprocess.run(
            [str(USDCAT), str(asset), "-o", str(usda)],
            check=False,
            capture_output=True,
            text=True,
        )
        if converted.returncode != 0 or not usda.is_file():
            errors.append(f"usdcat could not inspect the root layer: {converted.stderr.strip()}")
            text = ""
        else:
            text = usda.read_text()

    counts = {
        "meshes": len(re.findall(r'\bdef\s+Mesh\s+"', text)),
        "skeletons": len(re.findall(r'\bdef\s+Skeleton\s+"', text)),
        "skeletonRoots": len(re.findall(r'\bdef\s+SkelRoot\s+"', text)),
        "animations": len(re.findall(r'\bdef\s+SkelAnimation\s+"', text)),
        "legacyAnimatedXforms": len(
            re.findall(r"matrix4d\s+xformOp:transform:transform\.timeSamples", text)
        ),
    }
    if counts["meshes"] == 0:
        errors.append("asset contains no meshes")
    if counts["skeletons"] == 0 or counts["animations"] == 0:
        errors.append("asset contains no playable skeleton animation")
    if counts["skeletonRoots"] < counts["skeletons"]:
        errors.append("one or more skeletons are not encapsulated by a SkelRoot")
    if counts["legacyAnimatedXforms"]:
        errors.append(
            "asset still contains the converter's redundant animated Xform joint graph "
            f"({counts['legacyAnimatedXforms']} animated nodes)"
        )
    if not re.search(r"\bmetersPerUnit\s*=\s*1(?:\.0+)?\b", text):
        errors.append("stage is not authored in metres")
    if not re.search(r'\bupAxis\s*=\s*"Y"', text):
        errors.append("stage is not Y-up")

    arrays = _joint_arrays(text)
    if len(arrays) != counts["skeletons"] + counts["animations"]:
        errors.append(
            "every Skeleton and SkelAnimation must author an explicit joint order "
            f"(found {len(arrays)} arrays)"
        )
    for index, joints in enumerate(arrays):
        errors.extend(_topology_errors(joints, f"joint order {index + 1}"))

    # gltf2usd emits each Skeleton immediately followed by its SkelAnimation.
    # Replay XI keeps that narrow layout until the production DCC export path
    # consolidates the meshes under one shared skeleton.
    if len(arrays) % 2 == 0:
        for index in range(0, len(arrays), 2):
            if arrays[index] != arrays[index + 1]:
                errors.append(
                    f"skeleton/animation joint order mismatch in pair {(index // 2) + 1}"
                )
        roots = [arrays[index][0] for index in range(0, len(arrays), 2) if arrays[index]]
        if len(roots) != len(set(roots)):
            errors.append("separate skeletons reuse the same root joint namespace")

    if counts["skeletons"] > 1:
        warnings.append(
            f"asset contains {counts['skeletons']} skeleton copies; replace this technical "
            "fixture with one shared production skeleton before 22-player deployment"
        )
    if "extent" not in text:
        warnings.append("asset authors no extent; animated culling may be conservative")

    joint_count = len(arrays[0]) if arrays else 0
    return {
        "asset": str(asset.resolve()),
        "sha256": sha256(asset),
        "bytes": asset.stat().st_size,
        "archiveMembers": archive_members,
        "decodedTextureBytes": texture_bytes,
        "textures": texture_count,
        "joints": joint_count,
        **counts,
        "errors": errors,
        "warnings": warnings,
        "passed": not errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("assets", type=Path, nargs="+")
    parser.add_argument("--json", action="store_true", dest="as_json")
    arguments = parser.parse_args()
    reports = [audit(asset) for asset in arguments.assets]
    if arguments.as_json:
        payload = reports[0] if len(reports) == 1 else reports
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for report in reports:
            state = "PASS" if report["passed"] else "FAIL"
            print(
                f"{state}: {report['asset']} — {report['meshes']} meshes, "
                f"{report['skeletons']} skeletons, {report['joints']} joints"
            )
            for warning in report["warnings"]:
                print(f"warning: {warning}", file=sys.stderr)
            for error in report["errors"]:
                print(f"error: {error}", file=sys.stderr)
    return 0 if all(report["passed"] for report in reports) else 1


if __name__ == "__main__":
    raise SystemExit(main())
