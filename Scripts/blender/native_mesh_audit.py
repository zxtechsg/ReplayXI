"""Validate bounded native mesh QA attachments without requiring Blender."""
from __future__ import annotations

import json
import math
from pathlib import Path
import re

MAX_BYTES = 2 * 1024 * 1024
MAX_SAMPLES = 8
MAX_VERTICES = 8_000
MAX_INDICES = 48_000
MAX_TEXTURE_PIXELS = 4096
TEXTURE_FORMATS = {"rgba8Unorm_srgb": "Display P3", "bgra8Unorm_srgb": "Display P3",
                   "rgba8Unorm": "Linear DCI-P3 D65", "bgra8Unorm": "Linear DCI-P3 D65"}


def finite_number(value, limit):
    return type(value) in (int, float) and math.isfinite(value) and abs(value) <= limit


def validate_samples(document):
    if not isinstance(document, dict):
        raise ValueError("Expected a mesh audit object")
    samples = document.get("samples")
    if not isinstance(samples, list) or not 1 <= len(samples) <= MAX_SAMPLES:
        raise ValueError("Expected 1-8 native mesh samples")
    names = set()
    for sample in samples:
        if not isinstance(sample, dict):
            raise ValueError("Invalid sample")
        name = sample.get("name")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9-]{1,64}", name) or name in names:
            raise ValueError("Sample names must be unique safe filenames")
        names.add(name)
        if not finite_number(sample.get("minimumY"), 5) or not finite_number(sample.get("time"), 600):
            raise ValueError("Invalid sample measurement")
        meshes = sample.get("meshes")
        if not isinstance(meshes, list) or not 1 <= len(meshes) <= 32:
            raise ValueError("Expected 1-32 static meshes")
        vertices = indices_count = 0
        minimum = math.inf
        for mesh in meshes:
            if not isinstance(mesh, dict):
                raise ValueError("Invalid mesh")
            points, indices, tint = mesh.get("positions"), mesh.get("indices"), mesh.get("tint")
            if not isinstance(points, list) or not points:
                raise ValueError("Missing mesh vertices")
            vertices += len(points)
            if vertices > MAX_VERTICES:
                raise ValueError("Mesh vertex budget exceeded")
            for point in points:
                if not isinstance(point, list) or len(point) != 3 or not all(finite_number(v, 5) for v in point):
                    raise ValueError("Invalid player-local vertex")
                minimum = min(minimum, point[1])
            if not isinstance(indices, list) or not indices or len(indices) % 3:
                raise ValueError("Expected indexed triangles")
            indices_count += len(indices)
            if indices_count > MAX_INDICES or not all(type(i) is int and 0 <= i < len(points) for i in indices):
                raise ValueError("Invalid triangle index or budget")
            if not isinstance(tint, list) or len(tint) != 4 or not all(finite_number(v, 1) and v >= 0 for v in tint):
                raise ValueError("Invalid RGBA tint")
            if mesh.get("tintColourSpace") != "Linear Rec.709":
                raise ValueError("Native tint must explicitly use linear Rec.709 primaries")
            uvs, texture = mesh.get("uvs"), mesh.get("texture")
            if uvs is not None:
                if not isinstance(uvs, list) or len(uvs) != len(points) or not all(
                    isinstance(uv, list) and len(uv) == 2
                    and all(finite_number(v, 1) and v >= 0 for v in uv) for uv in uvs
                ):
                    raise ValueError("Invalid per-vertex UV coordinates")
            if texture is not None:
                if uvs is None:
                    raise ValueError("Textured meshes require UV coordinates")
                validate_texture(texture)
        if abs(minimum - sample["minimumY"]) > 0.00001:
            raise ValueError("Native mesh minimum does not match its measurement")
    return samples


def validate_texture(texture):
    if not isinstance(texture, dict):
        raise ValueError("Invalid native texture")
    width, height = texture.get("width"), texture.get("height")
    if not all(type(v) is int and 1 <= v <= 256 for v in (width, height)):
        raise ValueError("Invalid native texture dimensions")
    if width * height > MAX_TEXTURE_PIXELS:
        raise ValueError("Native texture pixel budget exceeded")
    pixel_format = texture.get("pixelFormat")
    expected_space = TEXTURE_FORMATS.get(pixel_format) if isinstance(pixel_format, str) else None
    if expected_space is None or texture.get("colourSpace") != expected_space:
        raise ValueError("Unsupported native texture colour format")
    if texture.get("origin") != "top-left":
        raise ValueError("Native texture origin must be explicit")
    pixels = texture.get("rgba8")
    if not isinstance(pixels, list) or len(pixels) != width * height * 4 or not all(
        type(v) is int and 0 <= v <= 255 for v in pixels
    ):
        raise ValueError("Invalid native RGBA8 pixels")
    if any(pixels[i] != 255 for i in range(3, len(pixels), 4)):
        raise ValueError("This audit supports opaque colour textures only")


def blender_texture_pixels(texture):
    """One row flip: Metal row 0 is top; Blender image storage is bottom-up.

    Native shader controls establish bottom-origin RealityKit mesh UVs, like
    Blender. Preserve those UVs; a second UV flip masks an upside-down app map.
    No PNG round-trip, colour-space guess or channel swap occurs here: the
    native exporter has already canonicalised RGBA versus BGRA bytes.
    """
    validate_texture(texture)
    row_bytes = texture["width"] * 4
    pixels = texture["rgba8"]
    return [channel / 255 for row in reversed(range(texture["height"]))
            for channel in pixels[row * row_bytes:(row + 1) * row_bytes]]


def blender_texture_coordinate(uv):
    """Keep the native mesh's bottom-origin UV after image storage is flipped."""
    if not isinstance(uv, (list, tuple)) or len(uv) != 2 or not all(
        finite_number(value, 1) and value >= 0 for value in uv
    ):
        raise ValueError("Invalid native UV coordinate")
    return tuple(uv)


def read_samples(path: Path):
    if path.stat().st_size > MAX_BYTES:
        raise ValueError("Mesh attachment exceeds 2 MB")
    return validate_samples(json.loads(path.read_text()))
