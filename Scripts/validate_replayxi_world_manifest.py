#!/usr/bin/env python3
"""Validate a rights-safe Replay XI reconstructed-world handoff.

The app never treats a generated video stream as tactical ground truth. This
manifest keeps the original/cleared source, navigable-video generation and 3D
reconstruction artifacts distinct, hash locked and auditable before anything
is admitted to the Xcode bundle.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import struct
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlsplit


SCHEMA_VERSION = 1
RUNTIME_WORLD_ID = "right-wing-overlap"
RUNTIME_DISPLAY_NAME = "Real World Match Replay"
WORLD_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_COMMIT_SHA = re.compile(r"^[0-9a-f]{40}$")
ALLOWED_SOURCE_KINDS = {
    "original-synthetic",
    "club-owned-capture",
    "licensed-capture",
    "open-data-reconstruction",
}
ALLOWED_ARTIFACT_ROLES = {
    "source-video",
    "reference-image",
    "navigable-video",
    "reconstruction-point-cloud",
    "gaussian-splat",
    "tracking-data",
    "rights-record",
    "realitykit-world",
}
REQUIRED_ARTIFACT_ROLES = {
    "source-video",
    "reference-image",
    "navigable-video",
    "reconstruction-point-cloud",
    "realitykit-world",
}
ARTIFACT_SUFFIXES = {
    "source-video": {".mp4", ".mov"},
    "reference-image": {".png", ".jpg", ".jpeg", ".heic"},
    "navigable-video": {".mp4", ".mov"},
    "reconstruction-point-cloud": {".ply", ".las", ".laz", ".glb"},
    "gaussian-splat": {".ply", ".splat", ".spz"},
    "tracking-data": {".json", ".csv", ".parquet"},
    "rights-record": {".json", ".md", ".pdf", ".txt"},
    "realitykit-world": {".reality", ".usdz"},
}
FORBIDDEN_REMOTE_HOSTS = {
    "youtube.com",
    "www.youtube.com",
    "youtu.be",
}


class ManifestError(ValueError):
    pass


def _require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ManifestError(f"{field} must be an object")
    return value


def _require_text(value: Any, field: str, maximum: int = 2_000) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(f"{field} must be non-empty text")
    if len(value) > maximum:
        raise ManifestError(f"{field} exceeds {maximum} characters")
    return value.strip()


def _local_artifact_path(manifest_dir: Path, raw_path: Any, field: str) -> Path:
    text = _require_text(raw_path, field, maximum=512)
    logical = PurePosixPath(text)
    if logical.is_absolute() or ".." in logical.parts or "\\" in text:
        raise ManifestError(f"{field} must be a safe relative POSIX path")
    candidate = manifest_dir.joinpath(*logical.parts)
    if candidate.is_symlink():
        raise ManifestError(f"{field} must not be a symlink")
    try:
        candidate.resolve().relative_to(manifest_dir.resolve())
    except ValueError as error:
        raise ManifestError(f"{field} escapes the manifest directory") from error
    return candidate


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fail_format(role: str, detail: str) -> None:
    raise ManifestError(f"artifact format mismatch for {role}: {detail}")


def _iso_bmff_box_types(path: Path, role: str) -> tuple[list[bytes], set[bytes]]:
    """Read ISO-BMFF top-level box headers without loading media payloads."""

    file_size = path.stat().st_size
    box_types: list[bytes] = []
    brands: set[bytes] = set()
    offset = 0
    with path.open("rb") as handle:
        while offset < file_size:
            if file_size - offset < 8:
                _fail_format(role, "truncated ISO-BMFF box header")
            handle.seek(offset)
            header = handle.read(8)
            box_size = int.from_bytes(header[:4], "big")
            box_type = header[4:8]
            header_size = 8
            if box_size == 1:
                extended = handle.read(8)
                if len(extended) != 8:
                    _fail_format(role, "truncated ISO-BMFF extended size")
                box_size = int.from_bytes(extended, "big")
                header_size = 16
            elif box_size == 0:
                box_size = file_size - offset
            if box_size < header_size or offset + box_size > file_size:
                _fail_format(role, "invalid ISO-BMFF box size")
            if not box_types and box_type != b"ftyp":
                _fail_format(role, "ISO-BMFF must begin with an ftyp box")
            if box_type == b"ftyp":
                payload_size = box_size - header_size
                if payload_size < 8:
                    _fail_format(role, "ftyp box is too short")
                payload = handle.read(payload_size)
                if len(payload) != payload_size:
                    _fail_format(role, "truncated ftyp box")
                brands.add(payload[:4])
                brands.update(
                    payload[index : index + 4]
                    for index in range(8, len(payload) - 3, 4)
                )
            box_types.append(box_type)
            offset += box_size
    return box_types, brands


def _validate_iso_bmff_video(path: Path, role: str) -> None:
    box_types, _ = _iso_bmff_box_types(path, role)
    missing = {b"moov", b"mdat"} - set(box_types)
    if missing:
        names = ", ".join(sorted(box.decode("ascii") for box in missing))
        _fail_format(role, f"ISO-BMFF video is missing top-level box(es): {names}")


def _validate_heif(path: Path, role: str) -> None:
    box_types, brands = _iso_bmff_box_types(path, role)
    heif_brands = {b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1"}
    if b"meta" not in box_types or not brands.intersection(heif_brands):
        _fail_format(role, "HEIF image requires a compatible ftyp brand and meta box")


def _validate_png(path: Path, role: str) -> None:
    file_size = path.stat().st_size
    with path.open("rb") as handle:
        if handle.read(8) != b"\x89PNG\r\n\x1a\n":
            _fail_format(role, "invalid PNG signature")
        saw_header = False
        saw_image_data = False
        while handle.tell() < file_size:
            header = handle.read(8)
            if len(header) != 8:
                _fail_format(role, "truncated PNG chunk header")
            length, chunk_type = struct.unpack(">I4s", header)
            if length > file_size - handle.tell() - 4:
                _fail_format(role, "truncated PNG chunk")
            if not saw_header and chunk_type != b"IHDR":
                _fail_format(role, "PNG IHDR must be the first chunk")
            if chunk_type == b"IHDR":
                if saw_header or length != 13:
                    _fail_format(role, "invalid PNG IHDR")
                payload = handle.read(length)
                width, height = struct.unpack(">II", payload[:8])
                if width <= 0 or height <= 0:
                    _fail_format(role, "PNG dimensions must be positive")
                saw_header = True
            else:
                handle.seek(length, 1)
            if len(handle.read(4)) != 4:
                _fail_format(role, "truncated PNG chunk checksum")
            if chunk_type == b"IDAT":
                saw_image_data = True
            if chunk_type == b"IEND":
                if length != 0 or handle.tell() != file_size:
                    _fail_format(role, "invalid PNG IEND")
                if not saw_header or not saw_image_data:
                    _fail_format(role, "PNG requires IHDR and IDAT chunks")
                return
    _fail_format(role, "PNG is missing IEND")


def _validate_jpeg(path: Path, role: str) -> None:
    sof_markers = {
        0xC0,
        0xC1,
        0xC2,
        0xC3,
        0xC5,
        0xC6,
        0xC7,
        0xC9,
        0xCA,
        0xCB,
        0xCD,
        0xCE,
        0xCF,
    }
    saw_frame = False
    saw_scan = False
    with path.open("rb") as handle:
        if handle.read(2) != b"\xff\xd8":
            _fail_format(role, "invalid JPEG start marker")
        while not saw_scan:
            prefix = handle.read(1)
            while prefix and prefix != b"\xff":
                prefix = handle.read(1)
            if not prefix:
                _fail_format(role, "truncated JPEG marker stream")
            marker = handle.read(1)
            while marker == b"\xff":
                marker = handle.read(1)
            if not marker:
                _fail_format(role, "truncated JPEG marker")
            marker_value = marker[0]
            if marker_value == 0xD9:
                break
            if marker_value in {0x01, *range(0xD0, 0xD8)}:
                continue
            raw_length = handle.read(2)
            if len(raw_length) != 2:
                _fail_format(role, "truncated JPEG segment")
            segment_length = int.from_bytes(raw_length, "big")
            if segment_length < 2:
                _fail_format(role, "invalid JPEG segment length")
            payload_length = segment_length - 2
            if marker_value in sof_markers:
                payload = handle.read(payload_length)
                if len(payload) != payload_length or payload_length < 6:
                    _fail_format(role, "truncated JPEG frame header")
                height = int.from_bytes(payload[1:3], "big")
                width = int.from_bytes(payload[3:5], "big")
                if width <= 0 or height <= 0:
                    _fail_format(role, "JPEG dimensions must be positive")
                saw_frame = True
            elif marker_value == 0xDA:
                if len(handle.read(payload_length)) != payload_length:
                    _fail_format(role, "truncated JPEG scan header")
                saw_scan = True
            else:
                handle.seek(payload_length, 1)
        if not saw_frame or not saw_scan:
            _fail_format(role, "JPEG requires frame and scan headers")
        handle.seek(-2, 2)
        if handle.read(2) != b"\xff\xd9":
            _fail_format(role, "JPEG is missing its end marker")


def _validate_ply(path: Path, role: str) -> None:
    maximum_header_size = 1_048_576
    with path.open("rb") as handle:
        prefix = handle.read(maximum_header_size + 1)
    header_ends = []
    for marker in (b"end_header\n", b"end_header\r\n"):
        marker_offset = prefix.find(marker)
        if marker_offset >= 0:
            header_ends.append(marker_offset + len(marker))
    if not header_ends:
        if len(prefix) > maximum_header_size:
            _fail_format(role, "PLY header exceeds 1 MiB")
        _fail_format(role, "PLY is missing end_header")
    encoded_header_size = min(header_ends)
    prefix = prefix[:encoded_header_size]
    lines = prefix.splitlines(keepends=True)
    header_lines: list[str] = []
    header_size = 0
    for raw_line in lines:
        header_size += len(raw_line)
        try:
            line = raw_line.decode("ascii").strip()
        except UnicodeDecodeError as error:
            raise ManifestError(
                f"artifact format mismatch for {role}: PLY header is not ASCII"
            ) from error
        header_lines.append(line)
        if line == "end_header":
            break
    else:
        _fail_format(role, "PLY is missing end_header")
    if not header_lines or header_lines[0] != "ply":
        _fail_format(role, "invalid PLY signature")

    encoding: str | None = None
    vertex_count: int | None = None
    vertex_properties: list[tuple[str, str]] = []
    current_element: str | None = None
    for line in header_lines[1:-1]:
        fields = line.split()
        if not fields or fields[0] in {"comment", "obj_info"}:
            continue
        if fields[0] == "format" and len(fields) == 3 and fields[2] == "1.0":
            encoding = fields[1]
        elif fields[0] == "element" and len(fields) == 3:
            current_element = fields[1]
            if current_element == "vertex":
                try:
                    vertex_count = int(fields[2])
                except ValueError:
                    _fail_format(role, "PLY vertex count is invalid")
        elif fields[0] == "property" and current_element == "vertex":
            if len(fields) != 3 or fields[1] == "list":
                _fail_format(role, "PLY vertex properties must be scalar")
            vertex_properties.append((fields[1], fields[2]))

    allowed_encodings = {"ascii", "binary_little_endian", "binary_big_endian"}
    if encoding not in allowed_encodings:
        _fail_format(role, "PLY format must be version 1.0 ASCII or binary")
    if vertex_count is None or vertex_count <= 0:
        _fail_format(role, "PLY must declare at least one vertex")
    property_names = {name for _, name in vertex_properties}
    if not {"x", "y", "z"}.issubset(property_names):
        _fail_format(role, "PLY vertices require x, y and z properties")
    if len(property_names) != len(vertex_properties):
        _fail_format(role, "PLY vertex property names must be unique")
    gaussian_properties = {
        "f_dc_0",
        "f_dc_1",
        "f_dc_2",
        "opacity",
        "scale_0",
        "scale_1",
        "scale_2",
        "rot_0",
        "rot_1",
        "rot_2",
        "rot_3",
    }
    if role == "gaussian-splat":
        missing_gaussian_properties = gaussian_properties - property_names
        if missing_gaussian_properties:
            _fail_format(
                role,
                "Gaussian PLY is missing Inria properties: "
                f"{sorted(missing_gaussian_properties)}",
            )
        property_types = {name: data_type for data_type, name in vertex_properties}
        float_properties = {"float", "float32", "double", "float64"}
        if any(
            property_types[name] not in float_properties
            for name in {"x", "y", "z", *gaussian_properties}
        ):
            _fail_format(role, "Gaussian PLY core properties must use floating-point scalars")

    payload_size = path.stat().st_size - header_size
    if payload_size <= 0:
        _fail_format(role, "PLY has no vertex payload")
    if encoding == "ascii":
        with path.open("rb") as handle:
            handle.seek(header_size)
            raw_vertex = handle.readline(64 * 1024)
        try:
            first_vertex = raw_vertex.decode("ascii", errors="strict").split()
        except UnicodeDecodeError as error:
            raise ManifestError(
                f"artifact format mismatch for {role}: PLY vertex payload is not ASCII"
            ) from error
        if len(first_vertex) < len(vertex_properties):
            _fail_format(role, "PLY vertex payload is truncated")
        values_by_name: dict[str, float] = {}
        try:
            for (_, name), raw_value in zip(vertex_properties, first_vertex):
                values_by_name[name] = float(raw_value)
        except ValueError:
            _fail_format(role, "PLY vertex payload is not numeric")
        if not all(math.isfinite(values_by_name[axis]) for axis in ("x", "y", "z")):
            _fail_format(role, "PLY coordinates must be finite")
        if role == "gaussian-splat" and not all(
            math.isfinite(values_by_name[name]) for name in gaussian_properties
        ):
            _fail_format(role, "Gaussian PLY core values must be finite")
        return

    scalar_widths = {
        "char": 1,
        "int8": 1,
        "uchar": 1,
        "uint8": 1,
        "short": 2,
        "int16": 2,
        "ushort": 2,
        "uint16": 2,
        "int": 4,
        "int32": 4,
        "uint": 4,
        "uint32": 4,
        "float": 4,
        "float32": 4,
        "double": 8,
        "float64": 8,
    }
    try:
        vertex_stride = sum(scalar_widths[data_type] for data_type, _ in vertex_properties)
    except KeyError:
        _fail_format(role, "PLY uses an unsupported vertex scalar type")
    if payload_size < vertex_stride * vertex_count:
        _fail_format(role, "PLY binary vertex payload is truncated")


def _validate_interleaved_splat(path: Path, role: str) -> None:
    """Smoke-check the documented 32-byte little-endian legacy splat layout."""

    record = struct.Struct("<6f8B")
    file_size = path.stat().st_size
    if file_size == 0 or file_size % record.size != 0:
        _fail_format(role, "SPLAT must contain complete 32-byte Gaussian records")
    record_count = file_size // record.size
    sampled_indices = list(range(min(record_count, 64)))
    if record_count > 64:
        sampled_indices.append(record_count - 1)
    with path.open("rb") as handle:
        for index in sampled_indices:
            handle.seek(index * record.size)
            payload = handle.read(record.size)
            if len(payload) != record.size:
                _fail_format(role, "SPLAT record payload is truncated")
            unpacked = record.unpack(payload)
            position_and_scale = unpacked[:6]
            if not all(math.isfinite(value) for value in position_and_scale):
                _fail_format(role, "SPLAT positions and scales must be finite")
            if any(scale <= 0 for scale in position_and_scale[3:6]):
                _fail_format(role, "SPLAT scales must be positive")


def _validate_spz_v4(path: Path, role: str) -> None:
    """Boundedly inspect the current plaintext-header NGSP v4 container."""

    file_size = path.stat().st_size
    if file_size < 32:
        _fail_format(role, "SPZ is too short for an NGSP v4 header")
    with path.open("rb") as handle:
        header = handle.read(32)
        if header.startswith(b"\x1f\x8b"):
            _fail_format(
                role,
                "legacy gzip SPZ versions require official decoder qualification; "
                "repack as NGSP v4",
            )
        (
            magic,
            version,
            point_count,
            sh_degree,
            fractional_bits,
            flags,
            stream_count,
            toc_offset,
            reserved,
        ) = struct.unpack("<4sIIBBBBI12s", header)
        if magic != b"NGSP" or version != 4:
            _fail_format(role, "SPZ must use the current NGSP v4 container")
        if point_count <= 0:
            _fail_format(role, "SPZ must declare at least one Gaussian")
        if sh_degree > 4:
            _fail_format(role, "SPZ spherical-harmonic degree must be between 0 and 4")
        if fractional_bits > 24:
            _fail_format(role, "SPZ coordinate fractional bits exceed 24-bit positions")
        if flags & ~0x03:
            _fail_format(role, "SPZ header contains unsupported flag bits")
        if reserved != b"\x00" * 12:
            _fail_format(role, "SPZ reserved header bytes must be zero")
        if stream_count == 0:
            _fail_format(role, "SPZ must declare at least one attribute stream")
        if toc_offset < 32 or toc_offset > file_size:
            _fail_format(role, "SPZ table-of-contents offset is out of bounds")

        has_extensions = bool(flags & 0x02)
        if has_extensions != (toc_offset > 32):
            _fail_format(role, "SPZ extension flag does not match its header zone")
        if has_extensions:
            cursor = 32
            handle.seek(cursor)
            while cursor < toc_offset:
                if toc_offset - cursor < 8:
                    _fail_format(role, "SPZ extension record header is truncated")
                extension_header = handle.read(8)
                _, extension_size = struct.unpack("<II", extension_header)
                cursor += 8
                if extension_size > toc_offset - cursor:
                    _fail_format(role, "SPZ extension record exceeds its header zone")
                handle.seek(extension_size, 1)
                cursor += extension_size

        toc_size = stream_count * 16
        stream_offset = toc_offset + toc_size
        if stream_offset > file_size:
            _fail_format(role, "SPZ table of contents is truncated")
        handle.seek(toc_offset)
        stream_entries: list[tuple[int, int]] = []
        for _ in range(stream_count):
            raw_entry = handle.read(16)
            if len(raw_entry) != 16:
                _fail_format(role, "SPZ table-of-contents entry is truncated")
            compressed_size, uncompressed_size = struct.unpack("<QQ", raw_entry)
            if compressed_size < 4:
                _fail_format(role, "SPZ compressed stream is too short")
            stream_entries.append((compressed_size, uncompressed_size))
        if not any(uncompressed_size > 0 for _, uncompressed_size in stream_entries):
            _fail_format(role, "SPZ attribute streams have no decoded payload")
        encoded_stream_size = sum(
            compressed_size for compressed_size, _ in stream_entries
        )
        if encoded_stream_size != file_size - stream_offset:
            _fail_format(role, "SPZ compressed stream sizes do not match the file")

        for compressed_size, _ in stream_entries:
            handle.seek(stream_offset)
            if handle.read(4) != b"\x28\xb5\x2f\xfd":
                _fail_format(role, "SPZ attribute stream has no Zstandard frame signature")
            stream_offset += compressed_size


def _validate_glb_points(path: Path, role: str) -> None:
    file_size = path.stat().st_size
    with path.open("rb") as handle:
        header = handle.read(12)
        if len(header) != 12:
            _fail_format(role, "truncated GLB header")
        magic, version, declared_size = struct.unpack("<4sII", header)
        if magic != b"glTF" or version != 2 or declared_size != file_size:
            _fail_format(role, "GLB must have a valid v2 header and exact byte length")

        json_payload: bytes | None = None
        binary_chunk_length: int | None = None
        offset = 12
        while offset < file_size:
            chunk_header = handle.read(8)
            if len(chunk_header) != 8:
                _fail_format(role, "truncated GLB chunk header")
            chunk_length, chunk_type = struct.unpack("<I4s", chunk_header)
            offset += 8
            if chunk_length % 4 != 0 or offset + chunk_length > file_size:
                _fail_format(role, "invalid GLB chunk length")
            if json_payload is None:
                if chunk_type != b"JSON":
                    _fail_format(role, "GLB JSON must be the first chunk")
                if chunk_length > 16 * 1024 * 1024:
                    _fail_format(role, "GLB JSON chunk exceeds 16 MiB")
                json_payload = handle.read(chunk_length)
            else:
                if chunk_type == b"BIN\x00":
                    if binary_chunk_length is not None:
                        _fail_format(role, "GLB must not contain multiple BIN chunks")
                    binary_chunk_length = chunk_length
                handle.seek(chunk_length, 1)
            offset += chunk_length
        if offset != file_size or json_payload is None:
            _fail_format(role, "GLB is missing its JSON chunk")

    try:
        document = json.loads(json_payload.rstrip(b" \t\r\n\x00").decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(
            f"artifact format mismatch for {role}: GLB JSON is invalid"
        ) from error
    asset = document.get("asset") if isinstance(document, dict) else None
    if not isinstance(asset, dict) or asset.get("version") != "2.0":
        _fail_format(role, "GLB JSON must declare glTF asset version 2.0")

    buffers = document.get("buffers")
    if not isinstance(buffers, list) or not buffers:
        _fail_format(role, "GLB POINTS data requires an embedded buffer")
    buffer_views = document.get("bufferViews")
    if not isinstance(buffer_views, list):
        _fail_format(role, "GLB POINTS data requires a bufferView table")
    accessors = document.get("accessors")
    if not isinstance(accessors, list):
        _fail_format(role, "GLB POINTS data requires an accessor table")
    meshes = document.get("meshes")
    if not isinstance(meshes, list):
        _fail_format(role, "GLB POINTS data requires a mesh table")

    def json_integer(value: Any) -> bool:
        return isinstance(value, int) and not isinstance(value, bool)

    found_points = False
    for mesh in meshes:
        if not isinstance(mesh, dict):
            continue
        primitives = mesh.get("primitives")
        if not isinstance(primitives, list):
            continue
        for primitive in primitives:
            if not isinstance(primitive, dict) or primitive.get("mode") != 0:
                continue
            found_points = True
            attributes = primitive.get("attributes")
            position_index = attributes.get("POSITION") if isinstance(attributes, dict) else None
            if not json_integer(position_index) or not 0 <= position_index < len(accessors):
                _fail_format(role, "GLB POINTS POSITION accessor index is invalid")
            accessor = accessors[position_index]
            if not isinstance(accessor, dict):
                _fail_format(role, "GLB POINTS POSITION accessor must be an object")
            count = accessor.get("count")
            if accessor.get("type") != "VEC3" or not json_integer(count) or count <= 0:
                _fail_format(
                    role,
                    "GLB requires a POINTS primitive with a non-empty VEC3 POSITION accessor",
                )
            if accessor.get("componentType") != 5126:
                _fail_format(role, "GLB POINTS POSITION accessor must use float components")
            if accessor.get("normalized", False) is not False:
                _fail_format(role, "GLB POINTS POSITION accessor must not be normalized")

            buffer_view_index = accessor.get("bufferView")
            if (
                not json_integer(buffer_view_index)
                or not 0 <= buffer_view_index < len(buffer_views)
            ):
                _fail_format(role, "GLB POINTS POSITION accessor requires a valid bufferView")
            buffer_view = buffer_views[buffer_view_index]
            if not isinstance(buffer_view, dict):
                _fail_format(role, "GLB POINTS POSITION bufferView must be an object")

            buffer_index = buffer_view.get("buffer")
            if not json_integer(buffer_index) or not 0 <= buffer_index < len(buffers):
                _fail_format(role, "GLB POINTS POSITION buffer index is invalid")
            if buffer_index != 0:
                _fail_format(role, "GLB POINTS POSITION must use the embedded GLB buffer")
            buffer = buffers[buffer_index]
            if not isinstance(buffer, dict) or "uri" in buffer:
                _fail_format(role, "GLB POINTS buffer must be embedded without a URI")
            buffer_byte_length = buffer.get("byteLength")
            if not json_integer(buffer_byte_length) or buffer_byte_length <= 0:
                _fail_format(role, "GLB POINTS buffer byteLength is invalid")
            if binary_chunk_length is None:
                _fail_format(role, "GLB POINTS data requires a BIN chunk")
            if not buffer_byte_length <= binary_chunk_length <= buffer_byte_length + 3:
                _fail_format(role, "GLB BIN chunk length does not match its buffer")

            view_byte_offset = buffer_view.get("byteOffset", 0)
            view_byte_length = buffer_view.get("byteLength")
            if (
                not json_integer(view_byte_offset)
                or view_byte_offset < 0
                or not json_integer(view_byte_length)
                or view_byte_length <= 0
                or view_byte_offset + view_byte_length > buffer_byte_length
            ):
                _fail_format(role, "GLB POINTS bufferView exceeds its embedded buffer")

            accessor_byte_offset = accessor.get("byteOffset", 0)
            if (
                not json_integer(accessor_byte_offset)
                or accessor_byte_offset < 0
                or (view_byte_offset + accessor_byte_offset) % 4 != 0
            ):
                _fail_format(role, "GLB POINTS POSITION byteOffset is invalid")
            element_byte_length = 3 * 4
            byte_stride = buffer_view.get("byteStride", element_byte_length)
            if (
                not json_integer(byte_stride)
                or byte_stride < element_byte_length
                or byte_stride > 252
                or byte_stride % 4 != 0
            ):
                _fail_format(role, "GLB POINTS POSITION byteStride is invalid")
            required_view_bytes = (
                accessor_byte_offset
                + ((count - 1) * byte_stride)
                + element_byte_length
            )
            if required_view_bytes > view_byte_length:
                _fail_format(role, "GLB POINTS POSITION accessor exceeds its bufferView")

    if not found_points:
        _fail_format(role, "GLB requires a POINTS primitive with a POSITION accessor")


def _validate_usdz(path: Path, role: str) -> None:
    if not zipfile.is_zipfile(path):
        _fail_format(role, "USDZ must be a ZIP archive")
    try:
        with zipfile.ZipFile(path) as archive:
            members = archive.infolist()
            if not members:
                _fail_format(role, "USDZ archive is empty")
            for member in members:
                logical = PurePosixPath(member.filename)
                if logical.is_absolute() or ".." in logical.parts or "\\" in member.filename:
                    _fail_format(role, "USDZ contains an unsafe member path")
                if member.compress_type != zipfile.ZIP_STORED:
                    _fail_format(role, "USDZ members must be stored without compression")
                if member.flag_bits & 0x1:
                    _fail_format(role, "USDZ members must not be encrypted")
            root = members[0]
            suffix = PurePosixPath(root.filename).suffix.lower()
            if suffix not in {".usd", ".usda", ".usdc"}:
                _fail_format(role, "USDZ first member must be a USD root layer")
            with archive.open(root) as root_file:
                signature = root_file.read(16)
            if not (signature.startswith(b"#usda") or signature.startswith(b"PXR-USDC")):
                _fail_format(role, "USDZ root layer has no USDA or USDC signature")
    except (OSError, zipfile.BadZipFile) as error:
        raise ManifestError(
            f"artifact format mismatch for {role}: invalid USDZ archive"
        ) from error


def _validate_artifact_format(path: Path, role: str) -> None:
    suffix = path.suffix.lower()
    if role in {"source-video", "navigable-video"}:
        _validate_iso_bmff_video(path, role)
    elif role == "reference-image" and suffix == ".png":
        _validate_png(path, role)
    elif role == "reference-image" and suffix in {".jpg", ".jpeg"}:
        _validate_jpeg(path, role)
    elif role == "reference-image" and suffix == ".heic":
        _validate_heif(path, role)
    elif suffix == ".ply" and role in {"reconstruction-point-cloud", "gaussian-splat"}:
        _validate_ply(path, role)
    elif suffix == ".splat" and role == "gaussian-splat":
        _validate_interleaved_splat(path, role)
    elif suffix == ".spz" and role == "gaussian-splat":
        _validate_spz_v4(path, role)
    elif suffix == ".glb" and role == "reconstruction-point-cloud":
        _validate_glb_points(path, role)
    elif suffix in {".las", ".laz"} and role == "reconstruction-point-cloud":
        with path.open("rb") as handle:
            if handle.read(4) != b"LASF":
                _fail_format(role, "LAS/LAZ requires an LASF signature")
    elif suffix == ".usdz" and role == "realitykit-world":
        _validate_usdz(path, role)


def _validate_remote_url(raw_url: Any) -> None:
    url = _require_text(raw_url, "source.remoteURL", maximum=1_000)
    parsed = urlsplit(url)
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        raise ManifestError("source.remoteURL must be an absolute HTTPS URL")
    host = parsed.hostname.lower().rstrip(".")
    if any(host == denied or host.endswith(f".{denied}") for denied in FORBIDDEN_REMOTE_HOSTS):
        raise ManifestError("YouTube/broadcast URLs are not admitted as reconstruction inputs")


def _require_stage_order(stage_names: list[str], before: str, after: str) -> None:
    if before in stage_names and after in stage_names:
        if stage_names.index(before) >= stage_names.index(after):
            raise ManifestError(f"pipeline stage {before} must precede {after}")


def _admission_receipt(path: Path, report: dict[str, Any]) -> dict[str, Any]:
    runtime = next(
        artifact for artifact in report["artifacts"] if artifact["role"] == "realitykit-world"
    )
    rights = next(
        (
            artifact
            for artifact in report["artifacts"]
            if artifact["role"] == "rights-record"
        ),
        None,
    )
    receipt: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "admissionVersion": 1,
        "manifestSHA256": _sha256(path),
        "worldID": report["worldID"],
        "displayName": report["displayName"],
        "source": report["source"],
        "coordinates": report["coordinates"],
        "tacticalTruth": report["tacticalTruth"],
        "runtimeAsset": {
            "resourceName": Path(runtime["path"]).name,
            "sha256": runtime["sha256"],
            "byteCount": runtime["byteCount"],
        },
    }
    if rights is not None:
        receipt["rightsEvidenceSHA256"] = rights["sha256"]
    return receipt


def _receipt_output_path(
    raw_output: Path,
    manifest_path: Path,
    report: dict[str, Any],
) -> Path:
    """Resolve a receipt target without allowing it to alias validated input."""

    output = raw_output.expanduser().absolute()
    if output.is_symlink():
        raise ManifestError("admission receipt must not be a symlink")

    protected_paths = [
        ("manifest", manifest_path.resolve()),
        *(
            (artifact["role"], Path(artifact["path"]).resolve())
            for artifact in report["artifacts"]
        ),
    ]
    resolved_output = output.resolve()
    for label, protected_path in protected_paths:
        if resolved_output == protected_path:
            raise ManifestError(
                f"admission receipt must not alias validated input: {label}"
            )

    if output.exists():
        if not output.is_file():
            raise ManifestError("admission receipt must be a regular file")
        output_status = output.stat()
        output_identity = (output_status.st_dev, output_status.st_ino)
        for label, protected_path in protected_paths:
            protected_status = protected_path.stat()
            if output_identity == (protected_status.st_dev, protected_status.st_ino):
                raise ManifestError(
                    f"admission receipt must not hard-link validated input: {label}"
                )
    return output


def _write_admission_receipt(
    raw_output: Path,
    manifest_path: Path,
    report: dict[str, Any],
) -> Path:
    """Publish a receipt atomically so a target race cannot mutate another inode."""

    output = _receipt_output_path(raw_output, manifest_path, report)
    output.parent.mkdir(parents=True, exist_ok=True)
    encoded_receipt = (
        json.dumps(
            _admission_receipt(manifest_path, report),
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.",
        suffix=".tmp",
        dir=output.parent,
        text=True,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(encoded_receipt)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, output)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise
    return output


def validate_manifest(path: Path, *, verify_files: bool = True) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ManifestError(f"manifest is not a regular file: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"manifest is not valid UTF-8 JSON: {error}") from error
    root = _require_mapping(payload, "manifest")

    if root.get("schemaVersion") != SCHEMA_VERSION:
        raise ManifestError(f"schemaVersion must be {SCHEMA_VERSION}")
    world_id = _require_text(root.get("worldID"), "worldID", maximum=80)
    if not WORLD_ID.fullmatch(world_id):
        raise ManifestError("worldID must be a lowercase kebab-case identifier")
    if world_id != RUNTIME_WORLD_ID:
        raise ManifestError(f"worldID must match the runtime scenario: {RUNTIME_WORLD_ID}")
    display_name = _require_text(root.get("displayName"), "displayName", maximum=120)
    if display_name != RUNTIME_DISPLAY_NAME:
        raise ManifestError(
            f"displayName must match the runtime scenario: {RUNTIME_DISPLAY_NAME}"
        )

    source = _require_mapping(root.get("source"), "source")
    source_kind = _require_text(source.get("kind"), "source.kind", maximum=40)
    if source_kind not in ALLOWED_SOURCE_KINDS:
        raise ManifestError(f"source.kind is not admitted: {source_kind}")
    _require_text(source.get("owner"), "source.owner", maximum=160)
    _require_text(source.get("rightsBasis"), "source.rightsBasis", maximum=500)
    _require_text(source.get("promptOrCaptureNote"), "source.promptOrCaptureNote")
    likenesses = source.get("containsRealPlayerLikenesses")
    if not isinstance(likenesses, bool):
        raise ManifestError("source.containsRealPlayerLikenesses must be a boolean")
    if source_kind == "original-synthetic" and likenesses:
        raise ManifestError("original-synthetic worlds cannot contain real-player likenesses")
    if likenesses:
        _require_text(
            source.get("likenessRightsBasis"),
            "source.likenessRightsBasis",
            maximum=500,
        )
    remote_url = source.get("remoteURL")
    if remote_url is not None:
        _validate_remote_url(remote_url)

    coordinates = _require_mapping(root.get("coordinates"), "coordinates")
    if coordinates.get("upAxis") != "Y" or coordinates.get("metresPerUnit") != 1:
        raise ManifestError("coordinates must be Y-up with metresPerUnit=1")
    if coordinates.get("pitchLengthMetres") != 105 or coordinates.get("pitchWidthMetres") != 68:
        raise ManifestError("coordinates must use the canonical 105 x 68 metre pitch")
    if coordinates.get("origin") != "pitch-centre":
        raise ManifestError("coordinates.origin must be pitch-centre")
    if coordinates.get("positiveZ") != "home-attacking-direction":
        raise ManifestError("coordinates.positiveZ must be home-attacking-direction")
    if coordinates.get("positiveX") != "home-right":
        raise ManifestError("coordinates.positiveX must be home-right")

    truth = _require_mapping(root.get("tacticalTruth"), "tacticalTruth")
    if truth.get("generatedPixelsAreAuthoritative") is not False:
        raise ManifestError("generatedPixelsAreAuthoritative must be false")
    _require_text(truth.get("trackingAuthority"), "tacticalTruth.trackingAuthority", maximum=160)

    stages = root.get("pipeline")
    if not isinstance(stages, list) or not stages:
        raise ManifestError("pipeline must be a non-empty array")
    stage_names: list[str] = []
    for index, raw_stage in enumerate(stages):
        stage = _require_mapping(raw_stage, f"pipeline[{index}]")
        name = _require_text(stage.get("name"), f"pipeline[{index}].name", maximum=80)
        provider = _require_text(
            stage.get("provider"), f"pipeline[{index}].provider", maximum=160
        )
        model_or_version = _require_text(
            stage.get("modelOrVersion"), f"pipeline[{index}].modelOrVersion", 160
        )
        if name in stage_names:
            raise ManifestError(f"duplicate pipeline stage: {name}")
        stage_names.append(name)
        if name == "reconstruct-3d":
            if "lingbot-map" not in provider.lower():
                raise ManifestError("reconstruct-3d must identify LingBot-Map as the provider")
            if not GIT_COMMIT_SHA.fullmatch(stage["modelOrVersion"]):
                raise ManifestError(
                    "reconstruct-3d modelOrVersion must be an exact 40-character "
                    "lowercase LingBot-Map git SHA"
                )
        if name == "generate-navigable-video":
            implementation = f"{provider} {model_or_version}".lower()
            if "lingbot world 2" not in implementation:
                raise ManifestError(
                    "generate-navigable-video must identify LingBot World 2"
                )
    required_stage_names = {
        "generate-navigable-video",
        "reconstruct-3d",
        "prepare-realitykit",
    }
    missing_stage_names = required_stage_names - set(stage_names)
    if missing_stage_names:
        raise ManifestError(
            f"pipeline is missing required stages: {sorted(missing_stage_names)}"
        )
    if source_kind == "original-synthetic" and "generate-video" not in stage_names:
        raise ManifestError("original-synthetic sources require a generate-video stage")
    _require_stage_order(stage_names, "generate-video", "generate-navigable-video")
    _require_stage_order(stage_names, "generate-video", "reconstruct-3d")
    _require_stage_order(stage_names, "generate-navigable-video", "reconstruct-3d")
    _require_stage_order(stage_names, "reconstruct-3d", "optimize-gaussian")
    _require_stage_order(stage_names, "reconstruct-3d", "prepare-realitykit")
    _require_stage_order(stage_names, "optimize-gaussian", "prepare-realitykit")

    artifacts = root.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ManifestError("artifacts must be a non-empty array")
    roles: set[str] = set()
    resolved_paths: dict[Path, str] = {}
    file_identities: dict[tuple[int, int], str] = {}
    verified_artifacts: list[dict[str, Any]] = []
    for index, raw_artifact in enumerate(artifacts):
        artifact = _require_mapping(raw_artifact, f"artifacts[{index}]")
        role = _require_text(artifact.get("role"), f"artifacts[{index}].role", maximum=64)
        if role not in ALLOWED_ARTIFACT_ROLES:
            raise ManifestError(f"unsupported artifact role: {role}")
        if role in roles:
            raise ManifestError(f"duplicate artifact role: {role}")
        roles.add(role)
        local_path = _local_artifact_path(
            path.parent, artifact.get("path"), f"artifacts[{index}].path"
        )
        resolved_path = local_path.resolve()
        if previous_role := resolved_paths.get(resolved_path):
            raise ManifestError(
                f"artifact roles {previous_role} and {role} resolve to the same file"
            )
        resolved_paths[resolved_path] = role
        expected_hash = _require_text(
            artifact.get("sha256"), f"artifacts[{index}].sha256", maximum=64
        )
        if not SHA256.fullmatch(expected_hash):
            raise ManifestError(f"artifacts[{index}].sha256 must be lowercase SHA-256")
        allowed_suffixes = ARTIFACT_SUFFIXES[role]
        if local_path.suffix.lower() not in allowed_suffixes:
            raise ManifestError(
                f"artifacts[{index}].path must use one of {sorted(allowed_suffixes)} for {role}"
            )
        byte_count: int | None = None
        if verify_files:
            if not local_path.is_file() or local_path.is_symlink():
                raise ManifestError(f"artifact is not a regular file: {local_path}")
            file_status = local_path.stat()
            identity = (file_status.st_dev, file_status.st_ino)
            if previous_role := file_identities.get(identity):
                raise ManifestError(
                    f"artifact roles {previous_role} and {role} resolve to the same file"
                )
            file_identities[identity] = role
            byte_count = file_status.st_size
            if byte_count <= 0:
                raise ManifestError(f"artifact is empty: {local_path}")
            actual_hash = _sha256(local_path)
            if actual_hash != expected_hash:
                raise ManifestError(
                    f"artifact hash mismatch for {role}: expected {expected_hash}, got {actual_hash}"
                )
            _validate_artifact_format(local_path, role)
        verified_artifacts.append(
            {
                "role": role,
                "path": str(resolved_path),
                "sha256": expected_hash,
                "byteCount": byte_count,
            }
        )

    missing_roles = REQUIRED_ARTIFACT_ROLES - roles
    if missing_roles:
        raise ManifestError(f"missing required artifact roles: {sorted(missing_roles)}")
    if source_kind != "original-synthetic" and "rights-record" not in roles:
        raise ManifestError("captured/licensed sources require a hash-locked rights-record")
    if likenesses and "rights-record" not in roles:
        raise ManifestError("real-player likenesses require a hash-locked rights-record")
    if "navigable-video" in roles and "generate-navigable-video" not in stage_names:
        raise ManifestError("navigable-video requires a generate-navigable-video stage")
    if "generate-navigable-video" in stage_names:
        missing_lingbot_artifacts = {"reference-image", "navigable-video"} - roles
        if missing_lingbot_artifacts:
            raise ManifestError(
                "generate-navigable-video requires hash-locked reference-image "
                f"and navigable-video artifacts; missing: {sorted(missing_lingbot_artifacts)}"
            )
    if "gaussian-splat" in roles and "optimize-gaussian" not in stage_names:
        raise ManifestError("gaussian-splat requires an optimize-gaussian stage")
    if "optimize-gaussian" in stage_names and "gaussian-splat" not in roles:
        raise ManifestError("optimize-gaussian requires a hash-locked gaussian-splat artifact")

    return {
        "passed": True,
        "schemaVersion": SCHEMA_VERSION,
        "worldID": world_id,
        "displayName": display_name,
        "sourceKind": source_kind,
        "source": {
            "kind": source_kind,
            "owner": source["owner"].strip(),
            "rightsBasis": source["rightsBasis"].strip(),
            "containsRealPlayerLikenesses": likenesses,
        },
        "coordinates": {
            "upAxis": "Y",
            "metresPerUnit": 1,
            "pitchLengthMetres": 105,
            "pitchWidthMetres": 68,
            "origin": "pitch-centre",
            "positiveZ": "home-attacking-direction",
            "positiveX": "home-right",
        },
        "tacticalTruth": {
            "generatedPixelsAreAuthoritative": False,
            "trackingAuthority": truth["trackingAuthority"].strip(),
        },
        "pipelineStages": stage_names,
        "artifacts": verified_artifacts,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--schema-only",
        action="store_true",
        help="validate structure and paths without requiring artifact files",
    )
    parser.add_argument(
        "--write-admission-receipt",
        type=Path,
        help="after full validation, write the hash-checked runtime admission receipt",
    )
    arguments = parser.parse_args()
    if arguments.schema_only and arguments.write_admission_receipt is not None:
        parser.error("--write-admission-receipt cannot be combined with --schema-only")
    manifest_path = arguments.manifest.resolve()
    try:
        report = validate_manifest(
            manifest_path, verify_files=not arguments.schema_only
        )
        if arguments.write_admission_receipt is not None:
            output = _write_admission_receipt(
                arguments.write_admission_receipt,
                manifest_path,
                report,
            )
            report["admissionReceipt"] = str(output)
    except (ManifestError, OSError) as error:
        print(json.dumps({"passed": False, "error": str(error)}, indent=2))
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
