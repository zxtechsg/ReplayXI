#!/usr/bin/env python3
"""Headless post-publication test of the player .blend and all three GLBs.

Blender --factory-startup --background --python-exit-code 1 --python this.py
  -- --library-dir .codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def assign(rig, action):
    rig.animation_data_create()
    rig.animation_data.action = action
    if hasattr(action, "slots") and action.slots:
        rig.animation_data.action_slot = action.slots[0]


def sampled_world_points(body):
    bpy.context.view_layer.update()
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        return [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices
                if vertex.index % 37 == 0]
    finally:
        evaluated.to_mesh_clear()


def check_motion(rig, body, actions):
    assign(rig, actions["run"])
    bpy.context.scene.frame_set(1)
    first = sampled_world_points(body)
    bpy.context.scene.frame_set(7)
    second = sampled_world_points(body)
    displacement = max((one - two).length for one, two in zip(first, second))
    if displacement < 0.15 or displacement > 2:
        raise AssertionError(f"Run deformation missing or unstable: {displacement}")
    if not all(math.isfinite(value) for point in second for value in point):
        raise AssertionError("Deformed body is non-finite")
    assign(rig, actions["idle"])
    bpy.context.scene.frame_set(1)
    points = sampled_world_points(body)
    height = max(point.z for point in points) - min(point.z for point in points)
    if not 1.3 < height < 1.9:  # Body mesh excludes the separate head.
        raise AssertionError(f"Body scale/axis changed: height={height}")
    return displacement


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--library-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if bpy.data.filepath:
        raise RuntimeError("Tests require a factory-startup background process")
    directory = args.library_dir.resolve()
    bpy.context.scene.render.fps = 30
    report = json.loads((directory / "ReplayXIFootballPlayers.json").read_text())
    clear_scene()
    with bpy.data.libraries.load(str(directory / "ReplayXIFootballPlayers.blend"), link=False) as (source, target):
        target.collections = list(report["collections"].values())
        target.actions = [value["name"] for value in report["actions"].values()]
    for collection in target.collections:
        bpy.context.scene.collection.children.link(collection)
    actions = {key: bpy.data.actions[value["name"]] for key, value in report["actions"].items()}
    kit_bodies, fonts = [], []
    tests = []
    for collection in target.collections:
        objects = list(collection.objects)
        rig = next(obj for obj in objects if obj.type == "ARMATURE")
        root = next(obj for obj in objects if obj.get("replayxi_kind") == "player_root")
        body = next(obj for obj in objects if obj.get("replayxi_kind") == "body")
        numbers = [obj for obj in objects if obj.type == "FONT"]
        if len(rig.data.bones) != 80 or len(numbers) != 2:
            raise AssertionError("Library lost bones or editable jersey numbers")
        if body.parent != rig or body.modifiers[0].object != rig:
            raise AssertionError("Body is attached to the wrong rig")
        if not all(number.parent == rig and number.parent_bone == "Bip01 Spine2" for number in numbers):
            raise AssertionError("Number is not chest-parented")
        kit_bodies.append(body)
        fonts.extend(number.data for number in numbers)
        tests.append({"libraryKit": collection.name, "runDisplacement": check_motion(rig, body, actions)})
        # Reposition/rotate a template as the 22-player assembler will do.
        root.location.x, root.location.y = 12, -8
        root.rotation_euler.z = 1.1
        assign(rig, actions["run"])
        bpy.context.scene.frame_set(7)
        bpy.context.view_layer.update()
        for number in numbers:
            expected = rig.matrix_world @ rig.pose.bones["Bip01 Spine2"].matrix @ Vector((*number["replayxi_chest_anchor"], 1))
            if (number.matrix_world.translation - expected.to_3d()).length > 0.0005:
                raise AssertionError(f"Rotated/moved player lost jersey anchor: {number.name}, actual={tuple(number.matrix_world.translation)}, expected={tuple(expected)}")
    if len({body.data.as_pointer() for body in kit_bodies}) != 1:
        raise AssertionError("Team templates no longer share immutable body geometry")
    if len({body.material_slots[0].material.as_pointer() for body in kit_bodies}) != 3:
        raise AssertionError("Team colours contaminated each other through shared data")
    if len({font.as_pointer() for font in fonts}) != 6:
        raise AssertionError("Jersey digits are shared between templates")
    for kit, artifact in report["glbPreviews"].items():
        clear_scene()
        before_actions = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=artifact["path"])
        objects = list(bpy.context.scene.objects)
        rigs = [obj for obj in objects if obj.type == "ARMATURE"]
        if len(rigs) != 1 or len(rigs[0].data.bones) != 80:
            raise AssertionError("GLB roundtrip lost skeleton")
        body = next(obj for obj in objects if obj.get("replayxi_kind") == "body")
        imported_actions = list(set(bpy.data.actions) - before_actions)
        clips = {key: next(action for action in imported_actions if action.name.startswith(value["name"]))
                 for key, value in report["actions"].items()}
        tests.append({"roundtripGLB": kit, "runDisplacement": check_motion(rigs[0], body, clips)})
    print("REPLAYXI_PLAYER_TESTS " + json.dumps({"passed": len(tests), "checks": tests}))


if __name__ == "__main__":
    main()
