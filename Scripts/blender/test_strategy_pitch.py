#!/usr/bin/env python3
"""Check a staged strategy-pitch build and its Blender authoring file."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy


def main(directory):
    if not bpy.app.background:
        raise RuntimeError("Use background Blender; this check opens the staged authoring file")
    directory = directory.resolve()
    report = json.loads((directory / "ReplayXIStrategyPitch.json").read_text())
    assert report["pitchDimensionsMetres"] == [68, 105]
    assert report["meshCount"] == 2 and report["materialCount"] == 4
    assert report["triangleCount"] < 8000
    assert report["assetBytes"] < 1_500_000
    assert report["textureCount"] == 2 and report["textureResolution"] == [512, 512]
    assert report["netCordSegments"] == 3 and report["netCordSides"] == 3

    bpy.ops.wm.open_mainfile(filepath=str(directory / "ReplayXIStrategyPitch.blend"))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert len(meshes) == 2
    assert {obj.name for obj in meshes} == {"field-surface", "pitch-markings-and-goals"}
    materials = {slot.material.name for obj in meshes for slot in obj.material_slots}
    assert len(materials) == 4
    triangles = sum(sum(max(0, len(face.vertices) - 2) for face in obj.data.polygons)
                    for obj in meshes)
    assert triangles == report["triangleCount"]
    assert "WovenGoalNet" in materials

    for name in ("TurfLight.png", "TurfDark.png"):
        image = bpy.data.images.load(str(directory / name), check_existing=False)
        assert tuple(image.size) == (512, 512)
        pixels = list(image.pixels)
        # Inspect one colour channel; alpha=1 must not make a flat tile pass.
        red = pixels[0::4]
        assert max(red) - min(red) > 0.001
    assert (directory / "overview.png").stat().st_size > 100_000
    assert (directory / "goal.png").stat().st_size > 100_000
    package = directory / "ReplayXIStrategyPitch.usdz"
    assert package.stat().st_size == report["assetBytes"]
    assert hashlib.sha256(package.read_bytes()).hexdigest() == report["sha256"]
    print("STRATEGY_PITCH_TESTS passed; " + json.dumps({
        "triangles": triangles, "materials": len(materials),
        "assetBytes": report["assetBytes"], "sha256": report["sha256"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    main(args.directory)
