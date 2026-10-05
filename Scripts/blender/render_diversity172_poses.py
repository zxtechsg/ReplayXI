#!/usr/bin/env python3
"""Render Player A rest, idle, running, head turn and arm raise for visual QA."""
from pathlib import Path
import argparse
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

parser = argparse.ArgumentParser()
parser.add_argument("--blend", type=Path, required=True)
parser.add_argument("--output-dir", type=Path, required=True)
parser.add_argument("--lod", choices=("near", "low"), default="near")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
bpy.ops.wm.open_mainfile(filepath=str(args.blend.resolve()), load_ui=False)
out = args.output_dir.resolve()
out.mkdir(parents=True, exist_ok=True)
rig = bpy.data.objects["Armature"]
mesh = bpy.data.objects["PlayerA_Near" if args.lod == "near" else "PlayerA_Low"]
for obj in bpy.data.objects:
    if obj.type == "MESH":
        obj.hide_render = obj != mesh
mesh.hide_set(False)
mesh.hide_render = False
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 8
scene.cycles.use_denoising = True
scene.render.resolution_x = 640
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"
world = bpy.data.worlds.new("Diversity172_QA_World")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (.28, .28, .28, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = .7
scene.world = world
camera = bpy.data.objects.new("Diversity172_QA_Camera", bpy.data.cameras.new("Diversity172_QA_Camera"))
scene.collection.objects.link(camera)
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.40
scene.camera = camera
for name, location, power in (("Key", (-2, -3, 4), 350), ("Fill", (2, -2, 3), 220), ("Rim", (1, 3, 3), 300)):
    lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
    scene.collection.objects.link(lamp)
    lamp.location = location
    lamp.rotation_euler = (Vector((0, 0, .50)) - lamp.location).to_track_quat("-Z", "Y").to_euler()
    lamp.data.energy = power
    lamp.data.shape = "DISK"
    lamp.data.size = 2
frames = [("rest", 1), ("idle", 1), ("run", 1), ("run", 5), ("run", 10),
          ("head-turn", 1), ("arm-raise", 1)]
images = []
for track in rig.animation_data.nla_tracks:
    track.mute = True
idle_name = "PlayerA_Idle" if bpy.data.actions.get("PlayerA_Idle") else "ReplayXI_Tripo_FBX_Idle"
run_name = "PlayerA_Run" if bpy.data.actions.get("PlayerA_Run") else "ReplayXI_Tripo_FBX_Run"
for label, frame in frames:
    rig.data.pose_position = "REST" if label == "rest" else "POSE"
    rig.animation_data.action = bpy.data.actions.get(run_name if label == "run" else idle_name)
    scene.frame_set(frame)
    if label in ("head-turn", "arm-raise"):
        bases = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
        rig.animation_data.action = None
        for bone in rig.pose.bones:
            bone.matrix_basis = bases[bone.name]
    head = rig.pose.bones["mixamorig:Head"]
    arm = rig.pose.bones["mixamorig:LeftArm"]
    orig_head = head.rotation_quaternion.copy()
    orig_arm = arm.rotation_quaternion.copy()
    if label == "head-turn":
        pivot = head.matrix.translation.copy()
        turn = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(38), 4, "Z") @ Matrix.Translation(-pivot)
        head.matrix = turn @ head.matrix
    if label == "arm-raise":
        pivot = arm.matrix.translation.copy()
        lift = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-45), 4, "Y") @ Matrix.Translation(-pivot)
        arm.matrix = lift @ arm.matrix
    bpy.context.view_layer.update()
    for view, position in (("front", (0, -3, .51)), ("side", (3, 0, .51))):
        camera.location = position
        camera.rotation_euler = (Vector((0, 0, .51)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        filename = f"{label}-{frame:02d}-{view}.png"
        scene.render.filepath = str(out / filename)
        bpy.ops.render.render(write_still=True)
        images.append(filename)
    head.rotation_quaternion = orig_head
    arm.rotation_quaternion = orig_arm
(out / "render-report.json").write_text(json.dumps({"images": images}, indent=2) + "\n")
print("DIVERSITY172_QA", images)
