#!/usr/bin/env python3
"""Render only the rigged Tripo candidate from front and side, read-only input.

Run with Blender --factory-startup --background --python this_file --
--candidate candidate.blend --output-dir NEW_DIRECTORY_UNDER_.codex-derived
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

REPO = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source, output = args.candidate.resolve(), args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated factory-startup background Blender")
    if not source.is_file() or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Input must exist; output must be a NEW derived directory")
    before = digest(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False)
    candidate = [obj for obj in bpy.data.objects if obj.type == "MESH" and
                 obj.name.startswith(("ReplayXI_Tripo_Candidate_", "ReplayXI_Tripo_AutoRig_Candidate"))]
    rigs = {modifier.object for obj in candidate for modifier in obj.modifiers
            if modifier.type == "ARMATURE" and modifier.object is not None}
    if not candidate or len(rigs) != 1:
        raise ValueError("Expected one armature bound to the candidate meshes")
    rig = next(iter(rigs))
    if len(rig.data.bones) not in (52, 80) or not rig.animation_data:
        raise ValueError("Candidate mesh or rig actions missing")
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.hide_render = obj not in candidate
    for obj in candidate:
        obj.hide_set(False)
        obj.hide_render = False
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 12
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("Tripo_QA_World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.27, .27, .27, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .7
    scene.world = world
    camera_data = bpy.data.cameras.new("Tripo_QA_Camera")
    camera = bpy.data.objects.new("Tripo_QA_Camera", camera_data)
    scene.collection.objects.link(camera)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.18
    scene.camera = camera
    for name, location, energy in (("Key", (-3, -3, 5), 500), ("Fill", (3, -2, 3), 250),
                                   ("Rim", (1, 3, 4), 350)):
        lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        scene.collection.objects.link(lamp)
        lamp.location = location
        lamp.rotation_euler = (Vector((0, 0, .9)) - lamp.location).to_track_quat("-Z", "Y").to_euler()
        lamp.data.energy = energy
        lamp.data.shape = "DISK"
        lamp.data.size = 3
    actions = {}
    names = ("ReplayXI_Tripo_AutoRig_Idle", "ReplayXI_Tripo_AutoRig_Run") if len(rig.data.bones) == 52 else (
        "ReplayXI_Idle.001", "ReplayXI_Run_InPlace.001")
    for name in names:
        action = bpy.data.actions.get(name)
        if action is None:
            raise ValueError(f"Missing candidate action: {name}")
        actions["idle" if "Idle" in name else "run"] = action
    output.mkdir(parents=True)
    images = []
    for clip, frame in (("rest", 1), ("idle", 1), ("run", 1),
                        ("run", 5), ("run", 10), ("run", 14)):
        rig.data.pose_position = "REST" if clip == "rest" else "POSE"
        if clip != "rest":
            rig.animation_data.action = actions[clip]
        scene.frame_set(frame)
        for view, position in (("front", (0, -4.4, 1.0)), ("side", (4.4, 0, 1.0))):
            camera.location = position
            camera.rotation_euler = (Vector((0, 0, .90)) - camera.location).to_track_quat("-Z", "Y").to_euler()
            filename = f"{clip}-{frame:02d}-{view}.png"
            scene.render.filepath = str(output / filename)
            bpy.ops.render.render(write_still=True)
            images.append(filename)
    after = digest(source)
    if after != before:
        raise ValueError("Candidate blend changed during read-only render")
    report = {"candidate": str(source), "candidateSHA256": before,
              "renderedMeshNames": [obj.name for obj in candidate], "images": images,
              "sourceUnchanged": True}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_PREVIEWS " + json.dumps(report))


if __name__ == "__main__":
    main()
