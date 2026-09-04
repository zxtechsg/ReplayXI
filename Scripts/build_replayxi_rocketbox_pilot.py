#!/usr/bin/env python3
"""Build the audited Microsoft Rocketbox Replay XI player pilot.

This is deliberately a fail-closed, offline build step.  It accepts only the
pinned inputs acquired by ``fetch_replayxi_rocketbox_pilot.py`` and the pinned
gltf2usd source tree, joins animation to the mesh by unique node *names* (never
by exporter indices), removes locomotion root travel, and replaces the source
club artwork with a neutral Replay XI kit before packaging an ARKit USDZ.

The build requires Pillow, numpy and OpenUSD's Python bindings.  Example:

  PYTHONPATH=/private/tmp/replayxi-rocketbox-python \
    python3 Scripts/build_replayxi_rocketbox_pilot.py \
      /private/tmp/replayxi-rocketbox-pilot-check \
      /private/tmp/gltf2usd-c0752099313834a466acf04b89af33dfd5dc9a0b \
      /private/tmp/ReplayXIRocketboxPilot.usdz
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
from typing import Any, Iterable

from fetch_replayxi_rocketbox_pilot import AssetRecord, PILOT_ASSETS, audit_directory
from replayxi_usdz_archive import normalize_usdz_timestamps


BUILDER_VERSION = "2"
CLIP_NAME = "ReplayXI_RunFast_InPlace"
MODEL_RELATIVE = "Assets/Avatars/Professions/Sports_Male_02/Export/Sports_Male_02.fbx"
RUN_RELATIVE = "Assets/Animations/all_animations_max_motextr_xy/m_run_fast_01.max.fbx"
TEXTURE_ROOT_RELATIVE = "Assets/Avatars/Professions/Sports_Male_02/Textures"
ROOT_TRANSLATION_NODE = "Bip01_$AssimpFbx$_Translation"
PELVIS_NODE = "Bip01 Pelvis"
MOTION_EXTRACTION_NODES = frozenset(
    {
        "MotionExtractionHelper_$AssimpFbx$_Translation",
        "MotionExtractionHelper_$AssimpFbx$_Rotation",
    }
)
EXPECTED_ASSIMP_VERSION = "6.0"
EXPECTED_GLTF2USD_SOURCE_HASH = (
    "348287ce53f3eab1ec5ed0ccae060555e259ff955cf8475b26928999e5496f47"
)
EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH = (
    "ea03c0e62eb9cd338f4c42530790c45f2b9d8e53410e3b419c953e74516033ce"
)
EXPECTED_MICROSOFT_MIT_NOTICE_SHA256 = (
    "17474e386e0b9e1a700cc3d06b2b0882a2c376d9c6b49c7f8274409b8f8d2352"
)
MICROSOFT_MIT_NOTICE = """MIT License

Copyright (c) 2020 Microsoft

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
EXPECTED_ASSIMP_EXPORTS = {
    "model.gltf": "e41695b55f94e22199bf8e963596bd55c75c80a318bb2318dc6587778a4d3510",
    "model.bin": "5ddc0bb2d216e16a2e683a97916f11af5290f625fb6c0723720cbd00b253ba33",
    "run.gltf": "e2b8a1c822f65904ed6355c4e3a60a87ab7efe6f99ad66ec5756765e74ccdf17",
    "run.bin": "dd0aaa0e63a6c29ef4539d65f9bfbc701d27deb60bb0cd73fe85d8950d2869fc",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json(payload: object) -> bytes:
    return (json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n").encode()


def finite_positive_float(value: str) -> float:
    """argparse type for finite, strictly positive floating-point settings."""

    try:
        parsed = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"expected a number, got {value!r}") from error
    if not math.isfinite(parsed) or parsed <= 0.0:
        raise argparse.ArgumentTypeError(f"expected a finite positive number, got {value!r}")
    return parsed


def snapshot_verified_files(
    source_root: Path,
    destination_root: Path,
    records: Iterable[AssetRecord],
) -> Path:
    """Copy locked inputs once, then verify and consume only the private copy."""

    if destination_root.exists():
        raise RuntimeError(f"verified snapshot destination already exists: {destination_root}")
    locked_records = tuple(records)
    if not locked_records:
        raise RuntimeError("verified snapshot requires at least one locked input")
    destination_root.mkdir(parents=True)
    for record in locked_records:
        relative = Path(record.path)
        if relative.is_absolute() or not relative.parts or any(
            part in {"", ".", ".."} for part in relative.parts
        ):
            raise RuntimeError(f"unsafe snapshot input path: {record.path!r}")
        source = source_root.joinpath(*relative.parts)
        destination = destination_root.joinpath(*relative.parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        _snapshot_locked_record(source, destination, record)
    errors = audit_directory(destination_root, locked_records)
    if errors:
        raise RuntimeError(
            "private Rocketbox snapshot audit failed:\n" + "\n".join(errors)
        )
    return destination_root


def _snapshot_locked_record(
    source: Path, destination: Path, record: AssetRecord
) -> None:
    """Copy one regular file with a strict byte ceiling before atomic publication."""

    if not isinstance(record.byte_count, int) or record.byte_count < 0:
        raise RuntimeError(f"invalid locked byte count for {record.path!r}")
    flags = os.O_RDONLY
    for optional_flag in ("O_CLOEXEC", "O_NONBLOCK", "O_NOFOLLOW"):
        flags |= getattr(os, optional_flag, 0)
    descriptor: int | None = None
    temporary_path: Path | None = None
    try:
        try:
            descriptor = os.open(source, flags)
        except OSError as error:
            raise RuntimeError(
                f"could not safely open locked input {record.path}: {error}"
            ) from error
        source_stat = os.fstat(descriptor)
        if not stat.S_ISREG(source_stat.st_mode):
            raise RuntimeError(f"locked input is not a regular file: {record.path}")

        digest = hashlib.sha256()
        byte_count = 0
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".snapshot",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            # Reading at most expected+1 makes oversized regular files fail
            # without copying the remainder and makes unbounded devices harmless.
            limit = record.byte_count + 1
            while byte_count < limit:
                chunk = os.read(descriptor, min(1024 * 1024, limit - byte_count))
                if not chunk:
                    break
                byte_count += len(chunk)
                digest.update(chunk)
                temporary.write(chunk)
            temporary.flush()
            os.fsync(temporary.fileno())
            os.fchmod(temporary.fileno(), 0o644)

        if source_stat.st_size != record.byte_count or byte_count != record.byte_count:
            raise RuntimeError(
                f"locked input size changed for {record.path}: "
                f"read {byte_count}, expected {record.byte_count}"
            )
        actual_hash = digest.hexdigest()
        if actual_hash != record.sha256:
            raise RuntimeError(
                f"locked input SHA-256 changed for {record.path}: "
                f"{actual_hash}, expected {record.sha256}"
            )
        if destination.exists() or destination.is_symlink():
            raise RuntimeError(f"duplicate locked snapshot destination: {record.path}")
        os.replace(temporary_path, destination)
        temporary_path = None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def load_microsoft_mit_notice(input_root: Path) -> str:
    """Return the pinned notice only when it is the complete Microsoft MIT text."""

    notice_path = input_root / "LICENSE.md"
    payload = notice_path.read_bytes()
    actual_hash = hashlib.sha256(payload).hexdigest()
    if actual_hash != EXPECTED_MICROSOFT_MIT_NOTICE_SHA256:
        raise RuntimeError(
            f"Microsoft MIT notice hash changed: {actual_hash}; "
            f"expected {EXPECTED_MICROSOFT_MIT_NOTICE_SHA256}"
        )
    expected = MICROSOFT_MIT_NOTICE.encode("utf-8")
    if payload != expected:
        raise RuntimeError("Microsoft MIT notice does not match the exact audited text")
    return MICROSOFT_MIT_NOTICE


def _absolute_lexical_path(path: Path) -> Path:
    """Make a path absolute without following its final symlink."""

    return Path(os.path.abspath(os.fspath(path)))


def _validate_destination(path: Path, label: str) -> Path:
    destination = _absolute_lexical_path(path)
    if destination.is_symlink():
        raise RuntimeError(f"{label} destination must not be a symlink: {destination}")
    if destination.exists() and not destination.is_file():
        raise RuntimeError(f"{label} destination must be a regular file: {destination}")
    return destination


def validate_publication_paths(
    output: Path, report: Path | None
) -> tuple[Path, Path | None]:
    """Reject output/report aliases before any final artifact is published."""

    output_path = _validate_destination(output, "output")
    if report is None:
        return output_path, None
    report_path = _validate_destination(report, "report")
    if output_path == report_path:
        raise RuntimeError("report destination aliases the USDZ output")
    if output_path.resolve(strict=False) == report_path.resolve(strict=False):
        raise RuntimeError("report destination resolves to the USDZ output")
    if output_path.exists() and report_path.exists() and os.path.samefile(
        output_path, report_path
    ):
        raise RuntimeError("report destination is a hardlink to the USDZ output")
    return output_path, report_path


def _publish_exclusive(destination: Path, writer: Any) -> None:
    """Publish through an unpredictable O_EXCL file in the destination directory."""

    destination = _validate_destination(destination, "publication")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            writer(temporary)
            temporary.flush()
            os.fsync(temporary.fileno())
            os.fchmod(temporary.fileno(), 0o644)
        # A destination introduced as a symlink while the build was running is
        # refused, even though os.replace itself would replace rather than follow it.
        _validate_destination(destination, "publication")
        os.replace(temporary_path, destination)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def publish_file_exclusive(source: Path, destination: Path) -> None:
    def copy_to(temporary: Any) -> None:
        with source.open("rb") as source_handle:
            shutil.copyfileobj(source_handle, temporary, length=1024 * 1024)

    _publish_exclusive(destination, copy_to)


def publish_bytes_exclusive(payload: bytes, destination: Path) -> None:
    _publish_exclusive(destination, lambda temporary: temporary.write(payload))


def publish_asset_and_report(
    candidate: Path,
    output: Path,
    report: Path | None,
    rendered_report: bytes,
) -> None:
    """Publish safely, rechecking aliases once the output has an inode."""

    output_path, report_path = validate_publication_paths(output, report)
    publish_file_exclusive(candidate, output_path)
    if report_path is not None:
        # On a case-insensitive filesystem two differently-cased missing paths
        # may not compare equal. Once output exists, samefile/resolve can prove
        # the alias before the report's atomic replace could overwrite the USDZ.
        output_path, report_path = validate_publication_paths(output_path, report_path)
        publish_bytes_exclusive(rendered_report, report_path)


def unique_node_map(document: dict[str, Any], label: str) -> dict[str, int]:
    nodes = document.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise RuntimeError(f"{label} has no nodes")
    result: dict[str, int] = {}
    for index, node in enumerate(nodes):
        name = node.get("name") if isinstance(node, dict) else None
        if not isinstance(name, str) or not name:
            raise RuntimeError(f"{label} node {index} has no stable name")
        if name in result:
            raise RuntimeError(f"{label} has duplicate node name {name!r}")
        result[name] = index
    return result


def _single_buffer(document: dict[str, Any], directory: Path, label: str) -> bytearray:
    buffers = document.get("buffers")
    if not isinstance(buffers, list) or len(buffers) != 1:
        raise RuntimeError(f"{label} must contain exactly one external buffer")
    uri = buffers[0].get("uri")
    if not isinstance(uri, str) or Path(uri).name != uri or not uri.endswith(".bin"):
        raise RuntimeError(f"{label} buffer URI is unsafe or unexpected: {uri!r}")
    payload = bytearray((directory / uri).read_bytes())
    if len(payload) != buffers[0].get("byteLength"):
        raise RuntimeError(f"{label} buffer byte length does not match its manifest")
    return payload


def _accessor_layout(
    document: dict[str, Any], payload: bytes | bytearray, accessor_index: int
) -> tuple[dict[str, Any], dict[str, Any], int, int, str, int]:
    accessors = document.get("accessors", [])
    views = document.get("bufferViews", [])
    if not 0 <= accessor_index < len(accessors):
        raise RuntimeError(f"accessor index {accessor_index} is out of range")
    accessor = accessors[accessor_index]
    if "sparse" in accessor:
        raise RuntimeError("sparse accessors are outside the locked pilot topology")
    view_index = accessor.get("bufferView")
    if not isinstance(view_index, int) or not 0 <= view_index < len(views):
        raise RuntimeError(f"accessor {accessor_index} has an invalid bufferView")
    view = views[view_index]
    if view.get("buffer", 0) != 0:
        raise RuntimeError("pilot accessors must use buffer zero")
    component = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}.get(
        accessor.get("componentType")
    )
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}.get(
        accessor.get("type")
    )
    if component is None or width is None:
        raise RuntimeError(f"accessor {accessor_index} has an unsupported layout")
    code, byte_width = component
    packed = width * byte_width
    stride = view.get("byteStride", packed)
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    count = accessor.get("count")
    if not isinstance(count, int) or count <= 0 or stride < packed:
        raise RuntimeError(f"accessor {accessor_index} has invalid count or stride")
    if offset < 0 or offset + (count - 1) * stride + packed > len(payload):
        raise RuntimeError(f"accessor {accessor_index} escapes its buffer")
    return accessor, view, offset, stride, code, width


def read_accessor(
    document: dict[str, Any], payload: bytes | bytearray, accessor_index: int
) -> list[tuple[float | int, ...]]:
    accessor, _, offset, stride, code, width = _accessor_layout(
        document, payload, accessor_index
    )
    unpack = struct.Struct("<" + code * width).unpack_from
    return [unpack(payload, offset + row * stride) for row in range(accessor["count"])]


def _validate_assimp_documents(model: dict[str, Any], run: dict[str, Any]) -> None:
    expected_model_counts = {
        "nodes": 89,
        "meshes": 1,
        "skins": 1,
        "materials": 2,
        "images": 6,
        "textures": 6,
        "accessors": 37,
        "bufferViews": 37,
        "animations": 1,
    }
    expected_run_counts = {
        "nodes": 134,
        "accessors": 516,
        "bufferViews": 516,
        "animations": 1,
    }
    for key, expected in expected_model_counts.items():
        if len(model.get(key, [])) != expected:
            raise RuntimeError(f"model {key} changed: expected {expected}")
    for key, expected in expected_run_counts.items():
        if len(run.get(key, [])) != expected:
            raise RuntimeError(f"run {key} changed: expected {expected}")
    if run.get("meshes") or run.get("skins"):
        raise RuntimeError("run source unexpectedly contains geometry")
    primitives = model["meshes"][0].get("primitives", [])
    if len(primitives) != 2 or [item.get("material") for item in primitives] != [0, 1]:
        raise RuntimeError("expected body and head as two material-indexed primitives")
    vertex_counts = [model["accessors"][p["attributes"]["POSITION"]]["count"] for p in primitives]
    index_counts = [model["accessors"][p["indices"]]["count"] for p in primitives]
    if vertex_counts != [3288, 1724] or index_counts != [15054, 9384]:
        raise RuntimeError("Rocketbox pilot mesh topology changed")
    joints = model["skins"][0].get("joints", [])
    if len(joints) != 80 or len(set(joints)) != 80:
        raise RuntimeError("expected one unique 80-joint skin")
    unique_node_map(model, "model")
    unique_node_map(run, "run")


def merge_run_animation(
    model: dict[str, Any],
    model_binary: bytes | bytearray,
    run: dict[str, Any],
    run_binary: bytes | bytearray,
) -> tuple[dict[str, Any], bytes, dict[str, float | int]]:
    """Merge run onto model by stable names and make its locomotion root in-place."""

    output = copy.deepcopy(model)
    motion = copy.deepcopy(run)
    motion_bytes = bytearray(run_binary)
    model_names = unique_node_map(output, "model")
    run_names = unique_node_map(motion, "run")
    animations = motion.get("animations", [])
    if len(animations) != 1:
        raise RuntimeError("run source must contain exactly one animation")
    source_animation = animations[0]
    source_samplers = source_animation.get("samplers", [])
    channels = source_animation.get("channels", [])
    if len(channels) != 258 or len(source_samplers) != 258:
        raise RuntimeError("run animation channel topology changed")

    signatures: set[tuple[str, str]] = set()
    animated_paths: dict[str, set[str]] = {}
    root_output_accessor: int | None = None
    pelvis_output_accessor: int | None = None
    dropped_names: set[str] = set()
    kept: list[tuple[dict[str, Any], dict[str, Any], str]] = []
    used_sampler_indices: set[int] = set()
    for channel in channels:
        sampler_index = channel.get("sampler")
        if not isinstance(sampler_index, int) or not 0 <= sampler_index < len(source_samplers):
            raise RuntimeError("run animation contains an invalid sampler reference")
        if sampler_index in used_sampler_indices:
            raise RuntimeError("locked run topology expects one sampler per channel")
        used_sampler_indices.add(sampler_index)
        target = channel.get("target", {})
        node_index = target.get("node")
        path = target.get("path")
        if not isinstance(node_index, int) or not 0 <= node_index < len(motion["nodes"]):
            raise RuntimeError("run animation contains an invalid node target")
        name = motion["nodes"][node_index]["name"]
        if path not in {"translation", "rotation", "scale"}:
            raise RuntimeError(f"unsupported animation path {path!r}")
        signature = (name, path)
        if signature in signatures:
            raise RuntimeError(f"duplicate animation channel {signature!r}")
        signatures.add(signature)
        animated_paths.setdefault(name, set()).add(path)
        if name not in model_names:
            dropped_names.add(name)
            continue
        sampler = source_samplers[sampler_index]
        if name == ROOT_TRANSLATION_NODE and path == "translation":
            root_output_accessor = sampler["output"]
        if name == PELVIS_NODE and path == "translation":
            pelvis_output_accessor = sampler["output"]
        kept.append((channel, sampler, name))

    if dropped_names != set(MOTION_EXTRACTION_NODES):
        raise RuntimeError(f"unexpected unmatched animation nodes: {sorted(dropped_names)}")
    expected_paths = {"translation", "rotation", "scale"}
    if any(paths != expected_paths for paths in animated_paths.values()):
        raise RuntimeError("every animated Rocketbox node must provide complete TRS channels")
    weighted_names = {output["nodes"][index]["name"] for index in output["skins"][0]["joints"]}
    if any(animated_paths.get(name) != expected_paths for name in weighted_names):
        raise RuntimeError("one or more weighted joints lacks complete run animation")
    if len(kept) != 252 or root_output_accessor is None or pelvis_output_accessor is None:
        raise RuntimeError("stable-name animation merge cardinality changed")

    accessor, _, offset, stride, code, width = _accessor_layout(
        motion, motion_bytes, root_output_accessor
    )
    if code != "f" or width != 3 or accessor["count"] != 19:
        raise RuntimeError("root translation accessor topology changed")
    values = read_accessor(motion, motion_bytes, root_output_accessor)
    first = values[0]
    travel_x = float(values[-1][0] - first[0])
    travel_z = float(values[-1][2] - first[2])
    if abs(travel_x) > 0.01 or not 300.0 < abs(travel_z) < 400.0:
        raise RuntimeError(
            f"unexpected motion-extraction travel x={travel_x:.6f}, z={travel_z:.6f}"
        )
    for row, value in enumerate(values):
        struct.pack_into("<fff", motion_bytes, offset + row * stride, first[0], value[1], first[2])
    rewritten = read_accessor(motion, motion_bytes, root_output_accessor)
    accessor["min"] = [min(row[column] for row in rewritten) for column in range(3)]
    accessor["max"] = [max(row[column] for row in rewritten) for column in range(3)]

    # The motion wrapper is not a weighted joint and gltf2usd's redundant
    # transform graph is removed later. Bake its vertical cadence (but never
    # horizontal travel) into the weighted pelvis so the playable clip keeps
    # the athlete's airborne phase and landing compression.
    pelvis_accessor, _, pelvis_offset, pelvis_stride, pelvis_code, pelvis_width = _accessor_layout(
        motion, motion_bytes, pelvis_output_accessor
    )
    pelvis_values = read_accessor(motion, motion_bytes, pelvis_output_accessor)
    if (
        pelvis_code != "f"
        or pelvis_width != 3
        or pelvis_accessor["count"] != len(rewritten)
    ):
        raise RuntimeError("pelvis translation accessor topology changed")
    vertical_gait = [float(value[1] - first[1]) for value in rewritten]
    vertical_range = max(vertical_gait) - min(vertical_gait)
    if not 5.0 < vertical_range < 10.0:
        raise RuntimeError(f"unexpected vertical gait range: {vertical_range:.6f} cm")
    for row, (pelvis, vertical) in enumerate(zip(pelvis_values, vertical_gait)):
        struct.pack_into(
            "<fff",
            motion_bytes,
            pelvis_offset + row * pelvis_stride,
            pelvis[0],
            pelvis[1] + vertical,
            pelvis[2],
        )
    baked_pelvis = read_accessor(motion, motion_bytes, pelvis_output_accessor)
    pelvis_accessor["min"] = [min(row[column] for row in baked_pelvis) for column in range(3)]
    pelvis_accessor["max"] = [max(row[column] for row in baked_pelvis) for column in range(3)]

    merged_binary = bytearray(model_binary)
    imported_accessors: dict[int, int] = {}

    def import_accessor(old_index: int) -> int:
        existing = imported_accessors.get(old_index)
        if existing is not None:
            return existing
        old_accessor, old_view, _, _, _, _ = _accessor_layout(motion, motion_bytes, old_index)
        old_view_index = old_accessor["bufferView"]
        start = old_view.get("byteOffset", 0)
        end = start + old_view["byteLength"]
        if end > len(motion_bytes):
            raise RuntimeError(f"animation bufferView {old_view_index} escapes its buffer")
        while len(merged_binary) % 4:
            merged_binary.append(0)
        new_view = copy.deepcopy(old_view)
        new_view["buffer"] = 0
        new_view["byteOffset"] = len(merged_binary)
        merged_binary.extend(motion_bytes[start:end])
        new_view_index = len(output["bufferViews"])
        output["bufferViews"].append(new_view)
        new_accessor = copy.deepcopy(old_accessor)
        new_accessor["bufferView"] = new_view_index
        new_index = len(output["accessors"])
        output["accessors"].append(new_accessor)
        imported_accessors[old_index] = new_index
        return new_index

    output_channels: list[dict[str, Any]] = []
    output_samplers: list[dict[str, Any]] = []
    for channel, sampler, name in kept:
        new_sampler = copy.deepcopy(sampler)
        new_sampler["input"] = import_accessor(sampler["input"])
        new_sampler["output"] = import_accessor(sampler["output"])
        target = copy.deepcopy(channel["target"])
        target["node"] = model_names[name]
        output_channels.append({"sampler": len(output_samplers), "target": target})
        output_samplers.append(new_sampler)

    output["animations"] = [
        {"name": CLIP_NAME, "channels": output_channels, "samplers": output_samplers}
    ]
    output["buffers"] = [{"byteLength": len(merged_binary), "uri": "player.bin"}]
    for node in output["nodes"]:
        node.pop("extras", None)
    output["asset"] = {
        "version": "2.0",
        "generator": f"Replay XI Rocketbox Pilot Builder {BUILDER_VERSION}",
        "copyright": "Microsoft Rocketbox source under MIT; neutral Replay XI derivative",
    }
    output.pop("extensionsRequired", None)
    output.pop("extensionsUsed", None)
    return output, bytes(merged_binary), {
        "keptChannels": len(kept),
        "droppedMotionExtractionChannels": len(channels) - len(kept),
        "sourceTravelCentimetres": math.hypot(travel_x, travel_z),
        "residualHorizontalTravelCentimetres": 0.0,
        "verticalGaitRangeCentimetres": vertical_range,
    }


def canonicalize_materials(document: dict[str, Any]) -> None:
    if [material.get("name") for material in document.get("materials", [])] != [
        "m301_body",
        "m301_head",
    ]:
        raise RuntimeError("Rocketbox material identity changed")
    document["images"] = [
        {"name": "ReplayXI_NeutralKit_BaseColor", "uri": "replayxi_body_color.png"},
        {"name": "ReplayXI_NeutralKit_Normal", "uri": "replayxi_body_normal.png"},
        {"name": "ReplayXI_AthleteHead_BaseColor", "uri": "replayxi_head_color.png"},
        {"name": "ReplayXI_AthleteHead_Normal", "uri": "replayxi_head_normal.png"},
    ]
    document["samplers"] = [
        {"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}
    ]
    document["textures"] = [
        {"sampler": 0, "source": index} for index in range(len(document["images"]))
    ]
    document["materials"] = [
        {
            "name": "ReplayXI_NeutralKit",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.78,
            },
            "normalTexture": {"index": 1},
        },
        {
            "name": "ReplayXI_AthleteHead",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                "baseColorTexture": {"index": 2},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.72,
            },
            "normalTexture": {"index": 3},
        },
    ]


def is_skin_pixel(red: int, green: int, blue: int) -> bool:
    """Conservative colour gate; atlas-position gating is applied separately."""

    return (
        red >= 75
        and green >= 45
        and blue >= 28
        and red > green + 8
        and green > blue + 4
        and green * 100 >= red * 48
        and blue * 100 >= green * 45
        and red - green <= 105
        and green - blue <= 90
    )


def classify_skin_pixels(body: Any) -> Any:
    """Classify RGB texels through the single audited skin-colour predicate."""

    try:
        import numpy as np
    except ImportError as error:
        raise RuntimeError("numpy is required to classify Rocketbox textures") from error
    if body.ndim != 3 or body.shape[2] != 3:
        raise RuntimeError("body texture must be an RGB array")
    red = body[:, :, 0].astype(np.uint32)
    green = body[:, :, 1].astype(np.uint32)
    blue = body[:, :, 2].astype(np.uint32)
    packed = (red << 16) | (green << 8) | blue
    unique, inverse = np.unique(packed, return_inverse=True)
    classified = np.fromiter(
        (
            is_skin_pixel(
                int((value >> 16) & 255),
                int((value >> 8) & 255),
                int(value & 255),
            )
            for value in unique
        ),
        dtype=np.bool_,
        count=len(unique),
    )
    return classified[inverse].reshape(body.shape[:2])


def neutralize_body_texture_arrays(
    body: Any, normal: Any, atlas_skin_region: Any | None = None
) -> tuple[Any, Any, Any]:
    """Regenerate all kit pixels while retaining only gated skin atlas texels."""

    try:
        import numpy as np
    except ImportError as error:
        raise RuntimeError("numpy is required to build Rocketbox textures") from error
    if body.shape != normal.shape or body.ndim != 3 or body.shape[2] != 3:
        raise RuntimeError("body colour and normal textures must be matching RGB arrays")
    colour_skin = classify_skin_pixels(body)
    if atlas_skin_region is None:
        if body.shape[:2] != (2048, 2048):
            raise RuntimeError("Rocketbox body texture must be exactly 2048 square")
        atlas_skin_region = np.zeros(colour_skin.shape, dtype=bool)
        atlas_skin_region[400:680, :620] = True
        atlas_skin_region[400:680, 1428:] = True
        atlas_skin_region[1120:, :620] = True
        atlas_skin_region[1120:, 1428:] = True
    elif atlas_skin_region.shape != body.shape[:2]:
        raise RuntimeError("skin atlas mask dimensions do not match the body texture")
    skin = colour_skin & atlas_skin_region

    # All non-skin texels are regenerated, including unused black atlas space,
    # so no source number, sponsor, crest, or wordmark survives in the output.
    yy, xx = np.indices(colour_skin.shape, dtype=np.float32)
    shade = 0.985 + 0.008 * np.sin(xx * (math.pi / 4.0)) * np.sin(
        yy * (math.pi / 4.0)
    )
    styled = np.empty_like(body)
    for channel, base in enumerate((17, 43, 72)):
        styled[:, :, channel] = np.rint(base * shade).astype(np.uint8)
    styled[skin] = body[skin]

    # Regenerate cloth normals too: retaining the original normal would retain
    # embossed sponsor and crest silhouettes after the colour texture is clean.
    styled_normal = np.empty_like(normal)
    styled_normal[:, :, 0] = np.rint(
        128.0 + 2.0 * np.sin(yy * (math.pi / 4.0))
    ).astype(np.uint8)
    styled_normal[:, :, 1] = np.rint(
        128.0 + 2.0 * np.sin(xx * (math.pi / 4.0))
    ).astype(np.uint8)
    styled_normal[:, :, 2] = 255
    styled_normal[skin] = normal[skin]
    return styled, styled_normal, skin


def hierarchical_joint_order(joints: list[str]) -> list[int]:
    """Return a stable parent-before-child permutation for USD joint paths."""

    if not joints or len(joints) != len(set(joints)):
        raise RuntimeError("joint paths must be non-empty and unique")
    positions = {joint: index for index, joint in enumerate(joints)}
    parents: dict[str, str | None] = {}
    for joint in joints:
        if not joint or joint.startswith("/") or joint.endswith("/") or "//" in joint:
            raise RuntimeError(f"malformed joint path {joint!r}")
        candidate = joint.rsplit("/", 1)[0] if "/" in joint else ""
        while candidate and candidate not in positions:
            candidate = candidate.rsplit("/", 1)[0] if "/" in candidate else ""
        parents[joint] = candidate or None
    roots = [joint for joint, parent in parents.items() if parent is None]
    if len(roots) != 1:
        raise RuntimeError(f"expected one effective joint root, found {len(roots)}")
    ordered = sorted(range(len(joints)), key=lambda index: (joints[index].count("/"), index))
    output_position = {joints[old]: new for new, old in enumerate(ordered)}
    if any(
        parent is not None and output_position[parent] >= output_position[joint]
        for joint, parent in parents.items()
    ):
        raise RuntimeError("could not construct parent-before-child joint order")
    return ordered


def _save_png(image: Any, destination: Path) -> None:
    image.save(destination, format="PNG", optimize=False, compress_level=9)


def build_textures(
    input_root: Path,
    output_directory: Path,
    texture_size: int,
) -> dict[str, Any]:
    try:
        import numpy as np
        from PIL import Image
    except ImportError as error:
        raise RuntimeError("Pillow and numpy are required to build Rocketbox textures") from error

    if texture_size not in {512, 1024}:
        raise RuntimeError("texture size must be 512 or 1024")
    source_root = input_root / TEXTURE_ROOT_RELATIVE
    names = {
        "bodyColor": "m301_body_color.tga",
        "bodyNormal": "m301_body_normal.tga",
        "headColor": "m301_head_color.tga",
        "headNormal": "m301_head_normal.tga",
    }
    images = {key: Image.open(source_root / value).convert("RGB") for key, value in names.items()}
    if any(image.size != (2048, 2048) for image in images.values()):
        raise RuntimeError("Rocketbox pilot textures must be exactly 2048 square")

    body = np.asarray(images["bodyColor"], dtype=np.uint8)
    normal = np.asarray(images["bodyNormal"], dtype=np.uint8)
    styled, styled_normal, skin = neutralize_body_texture_arrays(body, normal)
    styled_image = Image.fromarray(styled)
    styled_normal_image = Image.fromarray(styled_normal)

    resampling = Image.Resampling.LANCZOS
    outputs = {
        "replayxi_body_color.png": styled_image.resize((texture_size, texture_size), resampling),
        "replayxi_body_normal.png": styled_normal_image.resize((texture_size, texture_size), resampling),
        "replayxi_head_color.png": images["headColor"].resize((texture_size, texture_size), resampling),
        "replayxi_head_normal.png": images["headNormal"].resize((texture_size, texture_size), resampling),
    }
    for filename, image in outputs.items():
        _save_png(image, output_directory / filename)
    skin_pixels = int(np.count_nonzero(skin))
    if not 500_000 < skin_pixels < 2_500_000:
        raise RuntimeError(f"skin-preservation mask changed unexpectedly: {skin_pixels} pixels")
    return {
        "sourceTextureSize": 2048,
        "outputTextureSize": texture_size,
        "skinPixelsPreservedBeforeDownsample": skin_pixels,
        "textureSHA256": {
            name: sha256_file(output_directory / name) for name in sorted(outputs)
        },
    }


def _converter_execution_files(root: Path) -> list[Path]:
    source = root / "Source"
    if not source.is_dir() or source.is_symlink():
        raise RuntimeError(f"gltf2usd Source must be a real directory: {source}")
    files: list[Path] = []
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if path.is_symlink():
            raise RuntimeError(f"gltf2usd execution tree contains a symlink: {relative}")
        if "__pycache__" in relative.parts or path.suffix.lower() in {".pyc", ".pyo"}:
            raise RuntimeError(f"gltf2usd execution tree contains bytecode/cache: {relative}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise RuntimeError(f"gltf2usd execution tree contains a non-file: {relative}")
        # Upstream tests and their binary fixtures are not part of the tool we
        # execute and are deliberately omitted from the isolated copy.
        if relative.parts and relative.parts[0] == "tests":
            continue
        if path.suffix != ".py":
            raise RuntimeError(f"unexpected executable-tree file: {relative}")
        files.append(path)
    if source / "gltf2usd.py" not in files:
        raise RuntimeError("gltf2usd execution tree has no Source/gltf2usd.py")
    return files


def gltf2usd_source_hash(root: Path) -> str:
    """Hash every byte that can be imported by the isolated converter."""

    files = _converter_execution_files(root)
    manifest = "".join(
        f"{path.relative_to(root).as_posix()}\0{path.stat().st_size}\0{sha256_file(path)}\n"
        for path in files
    )
    return hashlib.sha256(manifest.encode()).hexdigest()


def _replace_exact(path: Path, old: str, new: str, expected: int = 1) -> None:
    content = path.read_text()
    count = content.count(old)
    if count != expected:
        raise RuntimeError(
            f"converter patch no longer matches {path.name}: expected {expected}, found {count}: {old}"
        )
    path.write_text(content.replace(old, new))


def patch_converter(source_root: Path, destination_root: Path) -> Path:
    source_files = _converter_execution_files(source_root)
    destination_source = destination_root / "Source"
    if destination_root.exists():
        raise RuntimeError(f"isolated gltf2usd destination already exists: {destination_root}")
    destination_source.mkdir(parents=True)
    for source in source_files:
        relative = source.relative_to(source_root / "Source")
        destination = destination_source / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    # This private tree, not the mutable source tree, is the authority for all
    # subsequent patching and execution.
    actual_hash = gltf2usd_source_hash(destination_root)
    if actual_hash != EXPECTED_GLTF2USD_SOURCE_HASH:
        raise RuntimeError(
            f"private gltf2usd snapshot hash {actual_hash}; "
            f"expected {EXPECTED_GLTF2USD_SOURCE_HASH}"
        )
    main = destination_root / "Source/gltf2usd.py"
    replacements = {
        "skeleton.CreateJointsAttr().Set(usd_joint_names)": "skeleton.CreateJointsAttr().Set(Vt.TokenArray([str(path) for path in usd_joint_names]))",
        "skeleton.CreateBindTransformsAttr(gltf_bind_transforms)": "skeleton.CreateBindTransformsAttr().Set(Vt.Matrix4dArray(gltf_bind_transforms))",
        "skeleton.CreateRestTransformsAttr(gltf_rest_transforms)": "skeleton.CreateRestTransformsAttr().Set(Vt.Matrix4dArray(gltf_rest_transforms))",
        "skelAnim.CreateJointsAttr().Set(joint_names)": "skelAnim.CreateJointsAttr().Set(Vt.TokenArray([str(path) for path in joint_names]))",
        "translate_attr.Set(entries, Usd.TimeCode(input_key * self.fps))": "translate_attr.Set(Vt.Vec3fArray([Gf.Vec3f(*entry) for entry in entries]), Usd.TimeCode(input_key * self.fps))",
        "scale_attr.Set(entries, Usd.TimeCode(input_key * self.fps))": "scale_attr.Set(Vt.Vec3hArray([Gf.Vec3h(*entry) for entry in entries]), Usd.TimeCode(input_key * self.fps))",
        "return GLTF2USDUtils.convert_to_usd_friendly_node_name(self._joint_hierarchy_name_map[gltf_joint])": "return '/'.join(GLTF2USDUtils.convert_to_usd_friendly_node_name(segment) for segment in self._joint_hierarchy_name_map[gltf_joint].split('/'))",
        "return GLTF2USDUtils.convert_to_usd_friendly_node_name(joint_name)": "return '/'.join(GLTF2USDUtils.convert_to_usd_friendly_node_name(segment) for segment in joint_name.split('/'))",
    }
    for old, new in replacements.items():
        _replace_exact(main, old, new)
    _replace_exact(main, "len(indices)/3", "len(indices)//3")
    _replace_exact(
        main,
        "sampler.get_output_count() / sampler.get_input_count()",
        "sampler.get_output_count() // sampler.get_input_count()",
    )
    _replace_exact(main, "range(0, len(output_data)/2)", "range(0, len(output_data)//2)")

    gltf_types = destination_root / "Source/_gltf2usd/gltf2"
    _replace_exact(gltf_types / "Skin.py", "from sets import Set", "Set = set")
    for filename in ("Node.py", "GLTFImage.py"):
        path = gltf_types / filename
        path.write_text("unicode = str\n" + path.read_text())
    materials = destination_root / "Source/_gltf2usd/usd_material.py"
    content = materials.read_text()
    content, connections = re.subn(
        r"\.ConnectToSource\(texture_shader, '([^']+)'\)",
        r".ConnectToSource(texture_shader.GetOutput('\1'))",
        content,
    )
    if connections != 12 or content.count("AlphaMode(alpha_mode)") != 5:
        raise RuntimeError("converter material compatibility topology changed")
    materials.write_text(content.replace("AlphaMode(alpha_mode)", "alpha_mode"))
    patched_hash = gltf2usd_source_hash(destination_root)
    if patched_hash != EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH:
        raise RuntimeError(
            f"patched gltf2usd execution hash {patched_hash}; "
            f"expected {EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH}"
        )
    return main


def _run(command: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, check=True, text=True, **kwargs)
    except subprocess.CalledProcessError as error:
        details = "\n".join(
            value.strip()
            for value in (error.stdout, error.stderr)
            if isinstance(value, str) and value.strip()
        )
        suffix = f"\n{details}" if details else ""
        raise RuntimeError(
            f"command failed with status {error.returncode}: {' '.join(command)}{suffix}"
        ) from error


def export_assimp(input_root: Path, work: Path, assimp: Path) -> tuple[Path, Path]:
    version = _run([str(assimp), "version"], capture_output=True).stdout
    if f"Version {EXPECTED_ASSIMP_VERSION}" not in version:
        raise RuntimeError(f"expected Assimp {EXPECTED_ASSIMP_VERSION}, got: {version.strip()}")
    model_dir, run_dir = work / "assimp-model", work / "assimp-run"
    model_dir.mkdir()
    run_dir.mkdir()
    model_path, run_path = model_dir / "model.gltf", run_dir / "run.gltf"
    _run([str(assimp), "export", str(input_root / MODEL_RELATIVE), str(model_path), "-f", "gltf2"], capture_output=True)
    _run([str(assimp), "export", str(input_root / RUN_RELATIVE), str(run_path), "-f", "gltf2"], capture_output=True)
    for filename, expected in EXPECTED_ASSIMP_EXPORTS.items():
        path = (model_dir if filename.startswith("model") else run_dir) / filename
        actual = sha256_file(path)
        if actual != expected:
            raise RuntimeError(f"Assimp export {filename} changed: {actual}, expected {expected}")
    return model_path, run_path


def run_converter(converter_script: Path, gltf_path: Path, usdc_path: Path, fps: float) -> None:
    if not math.isfinite(fps) or fps <= 0.0:
        raise RuntimeError(f"converter fps must be finite and positive, got {fps!r}")
    source = converter_script.parent
    converter_root = source.parent
    expected_script = _absolute_lexical_path(converter_root / "Source/gltf2usd.py")
    if _absolute_lexical_path(converter_script) != expected_script:
        raise RuntimeError("converter entry point is outside its audited execution tree")
    actual_hash = gltf2usd_source_hash(converter_root)
    if actual_hash != EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH:
        raise RuntimeError(
            f"gltf2usd execution tree changed before launch: {actual_hash}; "
            f"expected {EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH}"
        )
    environment = dict(os.environ)
    paths = [str(source), str(source / "_gltf2usd"), str(source / "_gltf2usd/gltf2")]
    if environment.get("PYTHONPATH"):
        paths.append(environment["PYTHONPATH"])
    environment["PYTHONPATH"] = os.pathsep.join(paths)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    _run(
        [sys.executable, "-B", str(converter_script), "-g", str(gltf_path), "-o", str(usdc_path), "-s", "0.01", "--fps", str(fps)],
        env=environment,
        capture_output=True,
    )


def validate_skinning_arrays(
    *,
    label: str,
    point_count: int,
    joint_count: int,
    influences_per_point: int,
    indices: Any,
    weights: Any,
) -> dict[str, float | int]:
    """Validate one vertex-interpolated influence table without trusting USD."""

    if point_count <= 0 or joint_count <= 0 or influences_per_point <= 0:
        raise RuntimeError(f"{label} has invalid skinning dimensions")
    expected = point_count * influences_per_point
    if len(indices) != expected or len(weights) != expected:
        raise RuntimeError(
            f"{label} skinning cardinality changed: expected {expected}, "
            f"got {len(indices)} indices and {len(weights)} weights"
        )
    parsed_indices: list[int] = []
    parsed_weights: list[float] = []
    for position, value in enumerate(indices):
        try:
            parsed = int(value)
        except (OverflowError, TypeError, ValueError) as error:
            raise RuntimeError(
                f"{label} has invalid joint index {value!r} at {position}"
            ) from error
        if parsed != value or not 0 <= parsed < joint_count:
            raise RuntimeError(f"{label} has invalid joint index {value!r} at {position}")
        parsed_indices.append(parsed)
    for position, value in enumerate(weights):
        try:
            parsed = float(value)
        except (TypeError, ValueError) as error:
            raise RuntimeError(
                f"{label} has invalid joint weight {value!r} at {position}"
            ) from error
        if not math.isfinite(parsed) or parsed < 0.0:
            raise RuntimeError(f"{label} has invalid joint weight {value!r} at {position}")
        parsed_weights.append(parsed)
    maximum_sum_error = 0.0
    minimum_sum = math.inf
    maximum_sum = -math.inf
    for point in range(point_count):
        start = point * influences_per_point
        total = sum(parsed_weights[start : start + influences_per_point])
        minimum_sum = min(minimum_sum, total)
        maximum_sum = max(maximum_sum, total)
        maximum_sum_error = max(maximum_sum_error, abs(total - 1.0))
    if maximum_sum_error > 1e-4:
        raise RuntimeError(
            f"{label} joint weights are not normalized; maximum sum error "
            f"{maximum_sum_error:.9f}"
        )
    return {
        "points": point_count,
        "influencesPerPoint": influences_per_point,
        "jointIndices": len(parsed_indices),
        "minimumWeightSum": minimum_sum,
        "maximumWeightSum": maximum_sum,
        "maximumWeightSumError": maximum_sum_error,
    }


def audit_usd_skinning(
    asset_path: Path, expected_license_notice: str | None = None
) -> dict[str, Any]:
    """Prove all meshes are valid targets of the asset's sole skeleton."""

    try:
        from pxr import Usd, UsdGeom, UsdSkel
    except ImportError as error:
        raise RuntimeError("OpenUSD Python bindings are required") from error
    stage = Usd.Stage.Open(str(asset_path))
    if not stage:
        raise RuntimeError(f"OpenUSD could not open skinning audit input: {asset_path}")
    roots = [UsdSkel.Root(prim) for prim in stage.Traverse() if prim.IsA(UsdSkel.Root)]
    skeletons = [
        UsdSkel.Skeleton(prim) for prim in stage.Traverse() if prim.IsA(UsdSkel.Skeleton)
    ]
    meshes = [UsdGeom.Mesh(prim) for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
    if len(roots) != 1 or len(skeletons) != 1 or len(meshes) != 2:
        raise RuntimeError("expected one SkelRoot, one skeleton, and two skinned meshes")
    skeleton = skeletons[0]
    skeleton_path = skeleton.GetPath()
    joints = skeleton.GetJointsAttr().Get()
    if not joints or len(joints) != 80:
        raise RuntimeError("skinning audit expected the locked 80-joint skeleton")

    cache = UsdSkel.Cache()
    if not cache.Populate(roots[0], Usd.PrimDefaultPredicate):
        raise RuntimeError("UsdSkel cache could not populate the pilot SkelRoot")
    bindings = cache.ComputeSkelBindings(roots[0], Usd.PrimDefaultPredicate)
    if len(bindings) != 1 or bindings[0].GetSkeleton().GetPath() != skeleton_path:
        raise RuntimeError("meshes are not grouped under the sole pilot skeleton")
    expected_mesh_paths = {mesh.GetPath() for mesh in meshes}
    binding_mesh_paths = {
        query.GetPrim().GetPath() for query in bindings[0].GetSkinningTargets()
    }
    if binding_mesh_paths != expected_mesh_paths:
        raise RuntimeError("skeleton binding targets do not exactly match all pilot meshes")

    mesh_reports: dict[str, Any] = {}
    for mesh in meshes:
        prim = mesh.GetPrim()
        label = str(prim.GetPath())
        query = cache.GetSkinningQuery(prim)
        if not query or query.GetPrim() != prim or not query.HasJointInfluences():
            raise RuntimeError(f"{label} has no valid UsdSkel SkinningQuery")
        binding = UsdSkel.BindingAPI(prim)
        targets = binding.GetSkeletonRel().GetTargets()
        inherited = binding.GetInheritedSkeleton()
        direct = binding.GetSkeleton()
        if (
            targets != [skeleton_path]
            or not inherited
            or inherited.GetPath() != skeleton_path
            or not direct
            or direct.GetPath() != skeleton_path
        ):
            raise RuntimeError(f"{label} is not bound directly to the sole skeleton")
        indices_primvar = query.GetJointIndicesPrimvar()
        weights_primvar = query.GetJointWeightsPrimvar()
        if not indices_primvar or not weights_primvar:
            raise RuntimeError(f"{label} is missing joint influence primvars")
        interpolation = str(indices_primvar.GetInterpolation())
        influences = int(indices_primvar.GetElementSize())
        if (
            interpolation != "vertex"
            or str(weights_primvar.GetInterpolation()) != interpolation
            or int(weights_primvar.GetElementSize()) != influences
            or int(query.GetNumInfluencesPerComponent()) != influences
            or str(query.GetInterpolation()) != interpolation
        ):
            raise RuntimeError(f"{label} joint influence layout changed")
        indices = indices_primvar.ComputeFlattened()
        weights = weights_primvar.ComputeFlattened()
        valid_indices, reason = UsdSkel.BindingAPI.ValidateJointIndices(
            indices, len(joints)
        )
        if not valid_indices:
            raise RuntimeError(f"{label} has invalid UsdSkel joint indices: {reason}")
        points = mesh.GetPointsAttr().Get()
        report = validate_skinning_arrays(
            label=label,
            point_count=len(points),
            joint_count=len(joints),
            influences_per_point=influences,
            indices=indices,
            weights=weights,
        )
        transform = query.GetGeomBindTransform()
        if any(
            not math.isfinite(float(transform[row][column]))
            for row in range(4)
            for column in range(4)
        ):
            raise RuntimeError(f"{label} has a non-finite geometry bind transform")
        report["minimumJointIndex"] = min(int(value) for value in indices)
        report["maximumJointIndex"] = max(int(value) for value in indices)
        mesh_reports[label] = report

    metadata = dict(stage.GetRootLayer().customLayerData)
    if (
        expected_license_notice is not None
        and metadata.get("replayxi_license_notice") != expected_license_notice
    ):
        raise RuntimeError("derived package is missing the exact Microsoft MIT notice")
    return {
        "skeleton": str(skeleton_path),
        "joints": len(joints),
        "boundMeshes": len(mesh_reports),
        "meshes": mesh_reports,
    }


def postprocess_and_audit_usd(
    usdc_path: Path,
    source_hashes: dict[str, str],
    license_notice: str,
) -> dict[str, Any]:
    try:
        from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, Vt
    except ImportError as error:
        raise RuntimeError("OpenUSD Python bindings are required") from error

    stage = Usd.Stage.Open(str(usdc_path))
    if not stage:
        raise RuntimeError("OpenUSD could not open converter output")
    root = stage.GetPrimAtPath("/root")
    if not root:
        raise RuntimeError("converter output lost /root")
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    stage.SetDefaultPrim(root)
    redundant_path = Sdf.Path("/root/b_RootNode__0/b_Bip01__AssimpFbx__Translation__3")
    redundant = stage.GetPrimAtPath(redundant_path)
    if not redundant or not any(
        attribute.ValueMightBeTimeVarying()
        for prim in Usd.PrimRange(redundant)
        for attribute in prim.GetAttributes()
    ):
        raise RuntimeError("expected redundant animated joint graph was not found")
    stage.RemovePrim(redundant_path)

    skeletons = [UsdSkel.Skeleton(prim) for prim in stage.Traverse() if prim.IsA(UsdSkel.Skeleton)]
    animations = [UsdSkel.Animation(prim) for prim in stage.Traverse() if prim.IsA(UsdSkel.Animation)]
    meshes = [prim for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
    if len(skeletons) != 1 or len(animations) != 1 or len(meshes) != 2:
        raise RuntimeError("expected one skeleton, one animation, and two meshes")
    joints = [str(path) for path in skeletons[0].GetJointsAttr().Get()]
    animation_joints = [str(path) for path in animations[0].GetJointsAttr().Get()]
    if len(joints) != 80 or joints != animation_joints or len(joints) != len(set(joints)):
        raise RuntimeError("USD skeleton/animation joint contract changed")
    if len(joints) > 1 and all("/" not in joint for joint in joints):
        raise RuntimeError("gltf2usd flattened the skeleton hierarchy")

    # Rocketbox's FBX skin table is not topological (Spine precedes Pelvis).
    # UsdSkel requires parents before children, so reorder every joint-indexed
    # array and remap vertex influences as one atomic transformation.
    order = hierarchical_joint_order(joints)
    if order != list(range(len(joints))):
        old_to_new = {old: new for new, old in enumerate(order)}
        skeleton = skeletons[0]
        animation = animations[0]
        skeleton.GetJointsAttr().Set(Vt.TokenArray([joints[index] for index in order]))
        bind = skeleton.GetBindTransformsAttr().Get()
        rest = skeleton.GetRestTransformsAttr().Get()
        if len(bind) != len(joints) or len(rest) != len(joints):
            raise RuntimeError("skeleton transform cardinality changed")
        skeleton.GetBindTransformsAttr().Set(Vt.Matrix4dArray([bind[index] for index in order]))
        skeleton.GetRestTransformsAttr().Set(Vt.Matrix4dArray([rest[index] for index in order]))
        animation.GetJointsAttr().Set(Vt.TokenArray([joints[index] for index in order]))
        for attribute, array_type in (
            (animation.GetTranslationsAttr(), Vt.Vec3fArray),
            (animation.GetRotationsAttr(), Vt.QuatfArray),
            (animation.GetScalesAttr(), Vt.Vec3hArray),
        ):
            for sample in attribute.GetTimeSamples():
                values = attribute.Get(sample)
                if len(values) != len(joints):
                    raise RuntimeError("animation sample cardinality changed")
                attribute.Set(array_type([values[index] for index in order]), sample)
        for mesh_prim in meshes:
            indices = UsdSkel.BindingAPI(mesh_prim).GetJointIndicesPrimvar()
            flattened = indices.ComputeFlattened()
            if not flattened:
                raise RuntimeError(f"mesh {mesh_prim.GetPath()} has no joint indices")
            if any(int(value) not in old_to_new for value in flattened):
                raise RuntimeError(f"mesh {mesh_prim.GetPath()} has an invalid joint index")
            indices.Set(Vt.IntArray([old_to_new[int(value)] for value in flattened]))
        joints = [joints[index] for index in order]

    for prim in stage.Traverse():
        if prim.IsA(UsdSkel.Skeleton) or prim.IsA(UsdGeom.Mesh):
            UsdSkel.BindingAPI.Apply(prim)
        if prim.IsA(UsdGeom.Mesh):
            UsdShade.MaterialBindingAPI.Apply(prim)
            mesh = UsdGeom.Mesh(prim)
            points = mesh.GetPointsAttr().Get()
            if not points:
                raise RuntimeError(f"mesh {prim.GetPath()} has no points")
            minimum = Gf.Vec3f(*(min(float(point[axis]) for point in points) for axis in range(3)))
            maximum = Gf.Vec3f(*(max(float(point[axis]) for point in points) for axis in range(3)))
            mesh.CreateExtentAttr().Set([minimum, maximum])
        if prim.IsA(UsdShade.Shader):
            varname = prim.GetAttribute("inputs:varname")
            if varname and varname.GetTypeName() == Sdf.ValueTypeNames.Token:
                value = str(varname.Get())
                prim.RemoveProperty("inputs:varname")
                prim.CreateAttribute("inputs:varname", Sdf.ValueTypeNames.String).Set(value)
            if prim.GetName() == "normalTexture":
                shader = UsdShade.Shader(prim)
                shader.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set("raw")
                shader.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2, 2, 2, 1))
                shader.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1, -1, -1, 0))
            file_attribute = prim.GetAttribute("inputs:file")
            if file_attribute:
                asset = file_attribute.Get()
                asset_path = asset.path if asset else ""
                if not asset_path or Path(asset_path).name != asset_path:
                    raise RuntimeError(f"non-local texture path in USD: {asset_path!r}")

    metadata = dict(stage.GetRootLayer().customLayerData)
    metadata.update(
        {
            "replayxi_asset": "Rocketbox Sports_Male_02 neutral-kit pilot",
            "replayxi_builder_version": BUILDER_VERSION,
            "replayxi_clip": CLIP_NAME,
            "replayxi_license": "Microsoft Rocketbox MIT",
            "replayxi_license_notice": license_notice,
            "replayxi_license_notice_sha256": EXPECTED_MICROSOFT_MIT_NOTICE_SHA256,
            "replayxi_model_sha256": source_hashes["model"],
            "replayxi_run_sha256": source_hashes["run"],
            "replayxi_root_motion": "horizontal translation removed; vertical gait retained",
        }
    )
    stage.GetRootLayer().customLayerData = metadata
    animation_sample_count = len(animations[0].GetRotationsAttr().GetTimeSamples())
    stage.GetRootLayer().Save()

    stage = Usd.Stage.Open(str(usdc_path))
    if stage.GetRootLayer().customLayerData.get("replayxi_license_notice") != license_notice:
        raise RuntimeError("saved USD lost the exact Microsoft MIT notice")
    skinning_report = audit_usd_skinning(usdc_path, license_notice)
    skeleton = next(UsdSkel.Skeleton(p) for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton))
    skel_root = UsdSkel.Root(skeleton.GetPrim().GetParent())
    cache = UsdSkel.Cache()
    cache.Populate(skel_root, Usd.PrimDefaultPredicate)
    query = cache.GetSkelQuery(skeleton)
    if not query or not query.GetAnimQuery():
        raise RuntimeError("converted skeleton has no bound animation query")
    start = query.ComputeSkinningTransforms(Usd.TimeCode(stage.GetStartTimeCode()))
    midpoint = (stage.GetStartTimeCode() + stage.GetEndTimeCode()) / 2.0
    end = query.ComputeSkinningTransforms(Usd.TimeCode(midpoint))
    delta = max(
        abs(float(a[row][column] - b[row][column]))
        for a, b in zip(start, end)
        for row in range(4)
        for column in range(4)
    )
    if delta < 1e-4:
        raise RuntimeError("run clip does not deform the skeleton")
    bbox = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ["default", "render", "proxy"])
    visible_boxes = [
        bbox.ComputeWorldBound(prim).ComputeAlignedBox()
        for prim in stage.Traverse()
        if prim.IsA(UsdGeom.Mesh)
    ]
    minimum = [min(float(box.GetMin()[axis]) for box in visible_boxes) for axis in range(3)]
    maximum = [max(float(box.GetMax()[axis]) for box in visible_boxes) for axis in range(3)]
    extents = [maximum[axis] - minimum[axis] for axis in range(3)]
    if not (1.7 < extents[1] < 2.1 and 0.9 < extents[0] < 1.6 and 0.2 < extents[2] < 0.8):
        raise RuntimeError(f"visible bounds changed unexpectedly: {extents}")
    return {
        "meshes": len(meshes),
        "skeletons": len(skeletons),
        "animations": len(animations),
        "joints": len(joints),
        "animationSamples": animation_sample_count,
        "durationSeconds": (stage.GetEndTimeCode() - stage.GetStartTimeCode()) / stage.GetTimeCodesPerSecond(),
        "animatedDelta": delta,
        "skinning": skinning_report,
        "boundsMetres": {
            "min": minimum,
            "max": maximum,
            "extents": extents,
        },
    }


def package_and_check(
    usdc_path: Path, license_notice: str
) -> tuple[Path, dict[str, Any]]:
    candidate = usdc_path.parent / "ReplayXIRocketboxPilot.usdz"
    _run(["/usr/bin/usdzip", "--arkitAsset", usdc_path.name, str(candidate)], cwd=usdc_path.parent, capture_output=True)
    normalize_usdz_timestamps(candidate)
    checked = subprocess.run(
        ["/usr/bin/usdchecker", "--arkit", "-t", str(candidate)],
        check=False,
        capture_output=True,
        text=True,
    )
    if checked.returncode != 0 or "Success!" not in checked.stdout + checked.stderr:
        raise RuntimeError("usdchecker rejected pilot USDZ:\n" + checked.stdout + checked.stderr)
    return candidate, audit_usd_skinning(candidate, license_notice)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_root", type=Path)
    parser.add_argument("gltf2usd_root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--assimp", type=Path, default=Path("/opt/homebrew/bin/assimp"))
    parser.add_argument("--texture-size", type=int, default=1024, choices=(512, 1024))
    parser.add_argument("--fps", type=finite_positive_float, default=30.0)
    parser.add_argument("--report", type=Path)
    arguments = parser.parse_args(argv)
    if arguments.output.suffix.lower() != ".usdz":
        parser.error("output must end in .usdz")
    output_path, report_path = validate_publication_paths(
        arguments.output, arguments.report
    )
    with tempfile.TemporaryDirectory(prefix="replayxi-rocketbox-build-") as temporary:
        work = Path(temporary)
        input_snapshot = snapshot_verified_files(
            arguments.input_root, work / "verified-inputs", PILOT_ASSETS
        )
        license_notice = load_microsoft_mit_notice(input_snapshot)
        source_hashes = {
            "model": sha256_file(input_snapshot / MODEL_RELATIVE),
            "run": sha256_file(input_snapshot / RUN_RELATIVE),
        }
        model_path, run_path = export_assimp(input_snapshot, work, arguments.assimp)
        model = json.loads(model_path.read_text())
        run = json.loads(run_path.read_text())
        _validate_assimp_documents(model, run)
        model_binary = _single_buffer(model, model_path.parent, "model")
        run_binary = _single_buffer(run, run_path.parent, "run")
        merged, binary, merge_report = merge_run_animation(model, model_binary, run, run_binary)
        canonicalize_materials(merged)

        gltf_directory = work / "gltf"
        gltf_directory.mkdir()
        (gltf_directory / "player.bin").write_bytes(binary)
        (gltf_directory / "player.gltf").write_bytes(canonical_json(merged))
        texture_report = build_textures(
            input_snapshot, gltf_directory, arguments.texture_size
        )

        converter = patch_converter(arguments.gltf2usd_root, work / "gltf2usd")
        usd_directory = work / "usd"
        usd_directory.mkdir()
        usdc = usd_directory / "player.usdc"
        run_converter(converter, gltf_directory / "player.gltf", usdc, arguments.fps)
        usd_report = postprocess_and_audit_usd(usdc, source_hashes, license_notice)
        candidate, packaged_skinning = package_and_check(usdc, license_notice)

        report = {
            "asset": str(output_path),
            "builderVersion": BUILDER_VERSION,
            "bytes": candidate.stat().st_size,
            "sha256": sha256_file(candidate),
            "sourceSHA256": source_hashes,
            "converter": {
                "upstreamExecutionTreeSHA256": EXPECTED_GLTF2USD_SOURCE_HASH,
                "patchedExecutionTreeSHA256": gltf2usd_source_hash(converter.parent.parent),
            },
            "license": {
                "name": "MIT License",
                "copyright": "Copyright (c) 2020 Microsoft",
                "notice": license_notice,
                "noticeSHA256": EXPECTED_MICROSOFT_MIT_NOTICE_SHA256,
            },
            "merge": merge_report,
            "textures": texture_report,
            "usd": usd_report,
            "packagedSkinning": packaged_skinning,
        }
        rendered = json.dumps(report, indent=2, sort_keys=True)

        # Repeat the identity check at the publication boundary to catch paths
        # that changed while the expensive conversion was running.
        output_path, report_path = validate_publication_paths(output_path, report_path)
        publish_asset_and_report(
            candidate,
            output_path,
            report_path,
            (rendered + "\n").encode("utf-8"),
        )
    print(rendered)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
