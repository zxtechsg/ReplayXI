#!/usr/bin/env python3
"""Compare kit atlas texels reached by exposed head/neck/arm mesh UVs."""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
from pathlib import Path
import sys

import bpy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--near-glb", type=Path, required=True)
    parser.add_argument("--kits", type=Path, required=True)
    parser.add_argument("--output-report", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(args.near_glb))
    meshes = [obj for obj in bpy.context.scene.objects
              if obj.type == "MESH" and len(obj.data.materials) == 1]
    if len(meshes) != 1:
        raise ValueError("expected one near body mesh")
    mesh = meshes[0].data
    uv_layer = mesh.uv_layers.active
    if uv_layer is None:
        raise ValueError("missing UV atlas")
    zs = [vertex.co.z for vertex in mesh.vertices]
    low, height = min(zs), max(zs) - min(zs)
    regions = {name: set() for name in ("head", "chinNeck", "upperNeck", "forearms", "knees")}
    for loop in mesh.loops:
        point = mesh.vertices[loop.vertex_index].co
        h = (point.z - low) / height
        ax = abs(point.x)
        uv = uv_layer.data[loop.index].uv
        x = min(1023, max(0, int(uv.x * 1024)))
        y = min(1023, max(0, int(uv.y * 1024)))
        key = (x, y)
        if h >= .88:
            regions["head"].add(key)
        if .84 <= h < .88 and ax < .08:
            regions["chinNeck"].add(key)
        if .81 <= h < .84 and ax < .08:
            regions["upperNeck"].add(key)
        if .76 <= h < .84 and ax > .26:
            regions["forearms"].add(key)
        if .31 <= h < .35 and ax < .35:
            regions["knees"].add(key)
    images = {}
    for kit in ("Home", "Away", "Keeper"):
        path = args.kits / f"ReplayXITripoPlayerA{kit}.png"
        image = bpy.data.images.load(str(path), check_existing=False)
        if tuple(image.size) != (1024, 1024):
            raise ValueError("atlas size mismatch")
        pixels = array("f", [0.0]) * (1024 * 1024 * 4)
        image.pixels.foreach_get(pixels)
        images[kit] = pixels
    results = {}
    for region, samples in regions.items():
        if not samples:
            raise ValueError(f"no {region} samples")
        pairs = {}
        for left, right in (("Home", "Away"), ("Home", "Keeper")):
            maximum = 0.0
            changed = 0
            total = 0.0
            for x, y in samples:
                offset = (y * 1024 + x) * 4
                delta = max(abs(images[left][offset + channel] - images[right][offset + channel])
                            for channel in range(3))
                maximum = max(maximum, delta)
                total += delta
                changed += delta > 1 / 255
            pairs[left + "Vs" + right] = {"changedTexelsOver1of255": changed,
                                         "maximumChannelDifference": maximum,
                                         "meanMaximumChannelDifference": total / len(samples)}
        results[region] = {"sampledUVTexels": len(samples), "pairs": pairs}
    report = {"nearGLBSHA256": hashlib.sha256(args.near_glb.read_bytes()).hexdigest(),
              "kitFileSHA256": {kit: hashlib.sha256(
                  (args.kits / f"ReplayXITripoPlayerA{kit}.png").read_bytes()).hexdigest()
                  for kit in ("Home", "Away", "Keeper")},
              "regions": results}
    if args.output_report:
        if args.output_report.exists() or args.output_report.parent.resolve() != args.kits.resolve():
            raise ValueError("audit report must be a new file in kits directory")
        args.output_report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("REPLAYXI_PLAYER_A_SKIN_PIXELS " + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
