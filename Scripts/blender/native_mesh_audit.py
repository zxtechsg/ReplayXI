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
        if abs(minimum - sample["minimumY"]) > 0.00001:
            raise ValueError("Native mesh minimum does not match its measurement")
    return samples


def read_samples(path: Path):
    if path.stat().st_size > MAX_BYTES:
        raise ValueError("Mesh attachment exceeds 2 MB")
    return validate_samples(json.loads(path.read_text()))
