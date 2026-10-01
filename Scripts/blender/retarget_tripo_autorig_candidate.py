#!/usr/bin/env python3
"""Align the repaired 52-joint Tripo skin and retarget Replay XI idle/run offline.

REJECTED v4: rendered idle/run show collapsed arms and sleeve gaps. Retained
only to reproduce the failed study; do not treat its finite bounds as motion QA.
This is a candidate study, not a runtime USDZ builder. Input GLBs remain intact.
Run in isolated Blender with --input repaired.glb --output-dir NEW_DERIVED_DIR.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_football_player import create_actions  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / ".codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayerHome.glb"
MOTION = REPO / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"
SOURCE_SHA = "3c7f948ee3701d1837356390e4af0d09c39de4cc9356f3f09d8970266d183787"
MOTION_SHA = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"

MAP = {
    "Hips": "Pelvis", "Spine": "Spine", "Spine1": "Spine1", "Spine2": "Spine2",
    "Neck": "Neck", "Head": "Head",
    "LeftUpLeg": "L Thigh", "LeftLeg": "L Calf", "LeftFoot": "L Foot", "LeftToeBase": "L Toe0",
    "RightUpLeg": "R Thigh", "RightLeg": "R Calf", "RightFoot": "R Foot", "RightToeBase": "R Toe0",
    "LeftShoulder": "L Clavicle", "LeftArm": "L UpperArm", "LeftForeArm": "L Forearm", "LeftHand": "L Hand",
    "RightShoulder": "R Clavicle", "RightArm": "R UpperArm", "RightForeArm": "R Forearm", "RightHand": "R Hand",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_bounds(mesh):
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    vertices = [evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices]
    if not vertices or any(not math.isfinite(value) for point in vertices for value in point):
        raise ValueError("Nonfinite evaluated skin")
    return [[min(point[axis] for point in vertices), max(point[axis] for point in vertices)]
            for axis in range(3)]


def retarget_frame(source, target, rest_source, rest_target, order, height_ratio):
    desired = {}
    for bone in order:
        name = bone.name
        semantic = name.removeprefix("mixamorig:")
        rest = rest_target[name]
        parent = bone.parent.name if bone.parent else None
        if semantic in MAP:
            source_name = "Bip01 " + MAP[semantic]
            pose = source.pose.bones[source_name].matrix.copy()
            source_rest = rest_source[source_name]
            delta = pose.to_quaternion() @ source_rest.to_quaternion().inverted()
            rotation = delta @ rest.to_quaternion()
        elif parent:
            rotation = (desired[parent] @ rest_target[parent].inverted() @ rest).to_quaternion()
        else:
            rotation = rest.to_quaternion()
        if parent:
            head = desired[parent] @ rest_target[parent].inverted() @ rest.translation
        else:
            source_pose = source.pose.bones["Bip01 Pelvis"].matrix.translation
            shift = (source_pose - rest_source["Bip01 Pelvis"].translation) * height_ratio
            head = rest.translation + shift
        desired[name] = Matrix.LocRotScale(head, rotation, Vector((1, 1, 1)))
    for bone in order:
        parent = bone.parent.name if bone.parent else None
        rest_local = rest_target[parent].inverted() @ rest_target[bone.name] if parent else rest_target[bone.name]
        pose_local = desired[parent].inverted() @ desired[bone.name] if parent else desired[bone.name]
        target.pose.bones[bone.name].matrix_basis = rest_local.inverted() @ pose_local
    bpy.context.view_layer.update()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    input_path, output = args.input.resolve(), args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use factory-startup background Blender")
    if not input_path.is_file() or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Input must exist; output must be a NEW derived directory")
    before = {"input": sha(input_path), "canonicalHome": sha(SOURCE), "motion": sha(MOTION)}
    if before["canonicalHome"] != SOURCE_SHA or before["motion"] != MOTION_SHA:
        raise ValueError("Canonical source hash changed")
    motion = json.loads(MOTION.read_text())
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source_objects = list(bpy.context.selected_objects)
    source = next(obj for obj in source_objects if obj.type == "ARMATURE")
    source_meshes = [obj for obj in source_objects if obj.type == "MESH"]
    actions_source = create_actions(source, motion)
    bpy.ops.import_scene.gltf(filepath=str(input_path))
    imported = list(bpy.context.selected_objects)
    target = next(obj for obj in imported if obj.type == "ARMATURE")
    mesh = next(obj for obj in imported if obj.type == "MESH")
    if len(target.data.bones) != 52 or len(mesh.data.vertices) != 16702 or len(mesh.data.uv_layers) != 1:
        raise ValueError("Unexpected Tripo skin geometry")
    if not all("mixamorig:" + name in target.data.bones for name in MAP):
        raise ValueError("Missing required Mixamo joint")
    source.data.pose_position = "REST"
    target.data.pose_position = "REST"
    pre_bounds = image_bounds(mesh)
    # The service bind rig is sideways and centred on the hips, while its mesh
    # stands Z-up from 0..1m. Rotate its left/up/front axes onto mesh X/Z/-Y,
    # scale the short template bones, and place the hips at ~0.55m.
    align = Matrix(((0, 0, 1.2, 0), (-1.2, 0, 0, 0), (0, -1.2, 0, .55), (0, 0, 0, 1)))
    bpy.context.view_layer.objects.active = target
    target.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in target.data.edit_bones:
        bone.transform(align, scale=True, roll=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    post_bounds = image_bounds(mesh)
    if max(abs(pre_bounds[axis][edge] - post_bounds[axis][edge]) for axis in range(3) for edge in range(2)) > .001:
        raise ValueError("Rest alignment changed visible mesh bounds")
    target.data.pose_position = "POSE"
    source.data.pose_position = "POSE"
    rest_source = {bone.name: bone.matrix_local.copy() for bone in source.data.bones}
    rest_target = {bone.name: bone.matrix_local.copy() for bone in target.data.bones}
    order = sorted(target.data.bones, key=lambda bone: len(bone.parent_recursive))
    for bone in target.pose.bones:
        bone.rotation_mode = "QUATERNION"
    target_height = post_bounds[2][1] - post_bounds[2][0]
    source_height = max((obj.matrix_world @ vertex.co).z for obj in source_meshes
                        for vertex in obj.data.vertices) - min((obj.matrix_world @ vertex.co).z
                        for obj in source_meshes for vertex in obj.data.vertices)
    height_ratio = target_height / source_height
    results = []
    target.animation_data_create()
    for clip in motion["clips"]:
        name = clip["id"]
        source.animation_data.action = actions_source[name]
        action = bpy.data.actions.new("ReplayXI_Tripo_AutoRig_" + name.title())
        action.use_fake_user = True
        target.animation_data.action = action
        for frame in clip["frames"]:
            number = 1 + frame["time"] * clip["fps"]
            bpy.context.scene.frame_set(round(number))
            if name == "run" and round(number) in (1, 5, 10, 14):
                print("RETARGET_ROOT", round(number),
                      tuple(source.pose.bones["Bip01 Pelvis"].matrix.translation),
                      tuple(rest_source["Bip01 Pelvis"].translation), height_ratio,
                      (source.pose.bones["Bip01 L Thigh"].matrix.to_quaternion() @
                       rest_source["Bip01 L Thigh"].to_quaternion().inverted()).angle)
            retarget_frame(source, target, rest_source, rest_target, order, height_ratio)
            for bone in order:
                pose_bone = target.pose.bones[bone.name]
                for channel in ("location", "rotation_quaternion", "scale"):
                    pose_bone.keyframe_insert(channel, frame=number, group=bone.name)
        for sample in (1, 5, 10, 14) if name == "run" else (1,):
            bpy.context.scene.frame_set(sample)
            result = image_bounds(mesh)
            if max(abs(value) for row in result for value in row) > 3:
                bad = sorted(((bone.name, tuple(bone.matrix.translation),
                               (bone.matrix.translation - rest_target[bone.name].translation).length)
                              for bone in target.pose.bones), key=lambda row: -row[2])[:5]
                raise ValueError(f"Retargeted skin exceeded bounded extent: {name} {sample} {result} bones={bad}")
            results.append({"clip": name, "frame": sample, "bounds": result})
    target.animation_data.action = bpy.data.actions["ReplayXI_Tripo_AutoRig_Idle"]
    bpy.context.scene.frame_set(1)
    for obj in source_objects:
        obj.hide_render = True
        obj.hide_set(True)
    mesh.name = "ReplayXI_Tripo_AutoRig_Candidate"
    output.mkdir(parents=True)
    blend = output / "ReplayXITripoAutoRigCandidate.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    after = {"input": sha(input_path), "canonicalHome": sha(SOURCE), "motion": sha(MOTION)}
    if before != after:
        raise ValueError("Read-only source changed")
    report = {"candidateOnly": True,
              "visualQAStatus": "REJECTED: collapsed arms and sleeve gaps in v4 renders",
              "sourceHashes": before,
              "targetJointCount": len(target.data.bones), "targetVertexCount": len(mesh.data.vertices),
              "restBoundsBefore": pre_bounds, "restBoundsAfter": post_bounds,
              "anatomicalAlignment": "short template rig rotated to mesh axes, scaled 1.2, hips at Z0.55m",
              "sourceToTargetHeightRatio": height_ratio, "mappedJoints": len(MAP),
              "unmappedFingerJoints": len(target.data.bones) - len(MAP),
              "poseSamples": results, "blend": str(blend), "blendSHA256": sha(blend),
              "limitations": "Offline retarget study; source locomotion is generic; native USDZ admission untested."}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_AUTORIG " + json.dumps(report))


if __name__ == "__main__":
    main()
