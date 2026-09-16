#!/usr/bin/env python3
"""Render actual Swift runtime pose attachments against the audited Blender skin.

Run in an isolated --factory-startup --background Blender. This reads an existing
player library without saving over it; PNGs and a report go to a new derived dir.
The input comes from ReplaySkinnedAthleteRuntimeTests, not a second animation rig.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_football_player import USD_TO_BLENDER, flat_material, link_object, matrix

REPOSITORY = Path(__file__).resolve().parents[2]


def read_samples(path: Path, joint_count: int):
    if path.stat().st_size > 2 * 1024 * 1024:
        raise ValueError("Pose attachment exceeds 2 MB")
    samples = json.loads(path.read_text())["samples"]
    if not 1 <= len(samples) <= 24:
        raise ValueError("Expected 1-24 runtime poses")
    names = set()
    for sample in samples:
        name = sample["name"]
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9-]{1,48}", name) or name in names:
            raise ValueError("Pose names must be unique safe filenames")
        names.add(name)
        for field, width in [("translations", 3), ("rotations", 4), ("scales", 3)]:
            values = sample[field]
            if len(values) != joint_count or any(len(value) != width for value in values):
                raise ValueError("Pose does not match the audited joint layout")
            if not all(isinstance(v, (int, float)) and math.isfinite(v) and abs(v) < 10
                       for row in values for v in row):
                raise ValueError("Pose contains an invalid transform")
        if not math.isfinite(sample["groundOffset"]) or abs(sample["groundOffset"]) > 0.5:
            raise ValueError("Invalid ground offset")
    return samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--poses", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frame-body", action="store_true", help="Frame the full body at each pose, including falls")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use an isolated factory-startup background process")
    output = args.output.resolve()
    if not output.is_relative_to((REPOSITORY / ".codex-derived").resolve()) or output.exists():
        raise ValueError("Choose a new directory under .codex-derived")
    motion = json.loads((REPOSITORY / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json").read_text())
    source_names = {joint["name"]: joint["sourceName"] for joint in motion["joints"]}
    samples = read_samples(args.poses, len(motion["joints"]))
    bpy.ops.wm.open_mainfile(filepath=str(args.library.resolve()), load_ui=False)
    rig = bpy.data.objects["ReplayXI_Home_Rig"]
    root = bpy.data.objects["ReplayXI_Home_Root"]
    rig.animation_data_clear()
    rest_local = []
    for joint in motion["joints"]:
        bone = rig.data.bones[joint["sourceName"]]
        rest_local.append(bone.parent.matrix_local.inverted() @ bone.matrix_local
                          if bone.parent else bone.matrix_local.copy())
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.16, 0.16, 0.16)
    scene.view_settings.view_transform = "AgX"
    qa = bpy.data.collections.new("ReplayXI_Runtime_QA")
    scene.collection.children.link(qa)
    camera = link_object(qa, "Runtime_Camera", bpy.data.cameras.new("Runtime_Camera"))
    camera.location = (2.4, -4.6, 1.9)
    camera.rotation_euler = (Vector((0, 0, 0.93)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 62
    scene.camera = camera
    for name, location, energy, size in [
        ("Key", (-3, -4, 5), 450, 4), ("Fill", (3, -1, 3), 220, 3), ("Rim", (1, 3, 4), 420, 3)
    ]:
        light = link_object(qa, name, bpy.data.lights.new(name, "AREA"))
        light.location = location
        light.rotation_euler = (Vector((0, 0, 1)) - light.location).to_track_quat("-Z", "Y").to_euler()
        light.data.energy, light.data.size = energy, size
        light.data.shape = "DISK"
    floor = bpy.data.meshes.new("Runtime_Floor")
    floor.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    floor.materials.append(flat_material("Runtime_Grass", (0.035, 0.11, 0.065, 1)))
    link_object(qa, "Runtime_Floor", floor)
    output.mkdir(parents=True)
    report = []
    for sample in samples:
        root.location.z = sample["groundOffset"]
        for index, joint in enumerate(motion["joints"]):
            target = matrix(sample["translations"][index], sample["rotations"][index], sample["scales"][index])
            if joint["parentIndex"] < 0:
                target = USD_TO_BLENDER @ target
            bone = rig.pose.bones[joint["sourceName"]]
            bone.rotation_mode = "QUATERNION"
            bone.matrix_basis = rest_local[index].inverted() @ target
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        points = []
        sections = {}
        for section in ["Body", "Head"]:
            mesh = bpy.data.objects[f"ReplayXI_Home_{section}"].evaluated_get(depsgraph)
            vertices = [mesh.matrix_world @ vertex.co for vertex in mesh.data.vertices]
            points.extend(vertices)
            sections[section] = {"minZ": min(p.z for p in vertices),
                                 "maxZ": max(p.z for p in vertices), "vertices": len(vertices)}
        if args.frame_body:
            lower = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
            upper = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
            centre = (lower + upper) * 0.5
            camera.location = centre + Vector((2.4, -4.6, 1.5))
            camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()
            camera.data.type = "ORTHO"
            camera.data.ortho_scale = max(2.2, (upper - lower).length * 1.4)
        scene.render.filepath = str(output / f"{sample['name']}.png")
        bpy.ops.render.render(write_still=True)
        joints = {semantic: list(rig.matrix_world @ rig.pose.bones[source_names[name]].head)
                  for semantic, name in motion["semanticJoints"].items()}
        report.append({"name": sample["name"], "minZ": min(p.z for p in points),
                       "maxZ": max(p.z for p in points), "vertices": len(points), "sections": sections, "joints": joints,
                       "image": scene.render.filepath})
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_RUNTIME_POSES " + json.dumps(report))


if __name__ == "__main__":
    main()
