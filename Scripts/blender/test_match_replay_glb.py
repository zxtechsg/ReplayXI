"""Headless-only GLB reimport checks for camera, pitch and optional ball/POV."""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--synthetic-test", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if not bpy.app.background:
        raise RuntimeError("Run this QA only in isolated background Blender")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(args.glb.resolve()))
    bpy.context.view_layer.update()
    imported = set(bpy.data.objects) - before
    def named(prefix):
        values = [obj for obj in imported if obj.name.split(".")[0] == prefix]
        assert len(values) == 1, (prefix, [obj.name for obj in values])
        return values[0]
    tactical = named("Tactical")
    actual = tuple(tactical.matrix_world.translation)
    expected = (0, -135, 125)
    assert math.dist(actual, expected) < 0.001, ("camera transform collapsed", actual, expected)
    assert named("EvidenceStatus").type == "MESH"
    if args.synthetic_test:
        ball = next(obj for obj in imported if obj.name.startswith("Ball_0.22m"))
        assert math.dist(tuple(ball.matrix_world.translation), (2, -8, 0.11)) < 0.001
        pov = named("POV_home-6")
        assert math.dist(tuple(pov.matrix_world.translation), (2, -8, 1.68)) < 0.001
        assert any(obj.name.startswith("Mark_qa-pass") for obj in imported)
    else:
        assert not any(obj.name.startswith("Ball_0.22m") for obj in imported), "Untracked ball leaked into pending preview"
    print(json.dumps({"passed": True, "artifact": str(args.glb),
                      "cameraPosition": actual, "objectCount": len(imported),
                      "staticSnapshot": True, "syntheticTestOnly": args.synthetic_test}))


main()
