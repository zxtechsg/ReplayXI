#!/usr/bin/env python3
"""Polish the valid 1 m FBX motion: relaxed idle arms and gently curled fingers.

Never edits the source blend or production assets. Outputs a new derived blend and
full-resolution motion GLB for native conversion; the 1 m LOD GLBs are separate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

REPO = Path(__file__).resolve().parents[2]
SOURCE_SHA = "a43e38d51b0878c96819abd4d85f956315f01928f35d446be65ab82a5e94c2e4"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(mesh):
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points = [evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices]
    if not points or any(not math.isfinite(value) for point in points for value in point):
        raise ValueError("Nonfinite posed FBX mesh")
    return [[min(point[axis] for point in points), max(point[axis] for point in points)] for axis in range(3)]


def finger_curl(rig):
    """Return rest-local bend axes, inferred from shaft toward palm/hand head."""
    curls = {}
    for side in ("Left", "Right"):
        hand = rig.data.bones[f"mixamorig:{side}Hand"].head_local
        for digit in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
            for segment in (1, 2, 3):
                name = f"mixamorig:{side}Hand{digit}{segment}"
                bone = rig.data.bones[name]
                shaft = (bone.tail_local - bone.head_local).normalized()
                inward = hand - bone.head_local
                axis = shaft.cross(inward)
                if axis.length < 1e-5:
                    raise ValueError(f"Cannot infer finger bend axis: {name}")
                axis.normalize()
                local = bone.matrix_local.to_quaternion().inverted() @ axis
                angle = (18, 22, 12)[segment - 1] if digit == "Thumb" else (42, 52, 32)[segment - 1]
                curls[name] = (local, math.radians(angle), tuple(axis))
    return curls


def point_bone(pose, direction):
    """Rotate a pose shaft to an armature-space direction without stretching."""
    bone = pose.bone
    original = (bone.tail_local - bone.head_local).normalized()
    desired = Vector(direction).normalized()
    rotation = original.rotation_difference(desired) @ bone.matrix_local.to_quaternion()
    pose.matrix = Matrix.LocRotScale(pose.head.copy(), rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def twist_wrist(rig, side, clip):
    """Aim rest-palm normal to inward/rear, by a bounded twist about forearm."""
    prefix = f"mixamorig:{side}Hand"
    hand = rig.pose.bones[prefix]
    forearm = rig.pose.bones[f"mixamorig:{side}ForeArm"]
    finger = rig.data.bones[prefix + "Middle1"]
    index = rig.data.bones[prefix + "Index1"]
    pinky = rig.data.bones[prefix + "Pinky1"]
    span = index.head_local - pinky.head_local
    reach = finger.head_local - hand.bone.head_local
    rest_normal = span.cross(reach).normalized()
    if rest_normal.y > 0:
        rest_normal.negate()
    current_normal = (hand.matrix @ hand.bone.matrix_local.inverted()).to_quaternion() @ rest_normal
    axis = (hand.head - forearm.head).normalized()
    sign = 1 if side == "Left" else -1
    target = Vector((-sign, .10 if clip == "idle" else .30, 0)).normalized()
    current_plane = (current_normal - axis * current_normal.dot(axis)).normalized()
    target_plane = (target - axis * target.dot(axis)).normalized()
    angle = math.atan2(axis.dot(current_plane.cross(target_plane)), current_plane.dot(target_plane))
    angle = max(-math.radians(75), min(math.radians(75), angle))
    hand.matrix = Matrix.LocRotScale(hand.head.copy(), Quaternion(axis, angle) @ hand.matrix.to_quaternion(),
                                     Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    return math.degrees(angle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-blend", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source, output = args.input_blend.resolve(), args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated factory-startup background Blender")
    if not source.is_file() or sha(source) != SOURCE_SHA or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Expected frozen v2 FBX source and new derived output")
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False)
    mesh = bpy.data.objects.get("ReplayXI_Tripo_FBX_Candidate")
    rig = next((modifier.object for modifier in mesh.modifiers if modifier.type == "ARMATURE"), None)
    if rig is None or len(rig.data.bones) != 65:
        raise ValueError("Expected valid FBX rig")
    curls = finger_curl(rig)
    actions = {"idle": bpy.data.actions["ReplayXI_Tripo_FBX_Idle"],
               "run": bpy.data.actions["ReplayXI_Tripo_FBX_Run"]}
    changed = {}
    for clip, action in actions.items():
        rig.animation_data.action = action
        first, last = map(round, action.frame_range)
        for frame in range(first, last + 1):
            bpy.context.scene.frame_set(frame)
            if clip == "idle":
                # Bring the FBX's wide A-pose arms down beside the thighs.
                for side, side_sign in (("Left", 1), ("Right", -1)):
                    shoulder = rig.pose.bones[f"mixamorig:{side}Shoulder"]
                    shoulder.rotation_quaternion = Quaternion((1, 0, 0, 0))
                    shoulder.keyframe_insert("rotation_quaternion", frame=frame, group=shoulder.name)
                    bpy.context.view_layer.update()
                    arm = rig.pose.bones[f"mixamorig:{side}Arm"]
                    point_bone(arm, (side_sign * .15, -.02, -.99))
                    forearm = rig.pose.bones[f"mixamorig:{side}ForeArm"]
                    point_bone(forearm, (side_sign * .08, -.08, -.99))
                    hand = rig.pose.bones[f"mixamorig:{side}Hand"]
                    hand.rotation_quaternion = Quaternion((1, 0, 0, 0))
                    for pose in (arm, forearm, hand):
                        for channel in ("location", "rotation_quaternion", "scale"):
                            pose.keyframe_insert(channel, frame=frame, group=pose.name)
            else:
                # Canonical source arms turn behind the torso on this different
                # A-pose. Drive native shafts directly with a restrained sprint
                # swing; keep inherited torso motion and native segment lengths.
                phase = math.cos(2 * math.pi * (frame - 5) / 18)
                for side, side_sign in (("Left", 1), ("Right", -1)):
                    swing = -phase * side_sign  # Right hand forward at frame 1.
                    shoulder = rig.pose.bones[f"mixamorig:{side}Shoulder"]
                    shoulder.rotation_quaternion = Quaternion((1, 0, 0, 0))
                    shoulder.keyframe_insert("rotation_quaternion", frame=frame, group=shoulder.name)
                    bpy.context.view_layer.update()
                    arm = rig.pose.bones[f"mixamorig:{side}Arm"]
                    point_bone(arm, (side_sign * .25, .12 - .22 * max(swing, 0) + .33 * max(-swing, 0), -.91))
                    forearm = rig.pose.bones[f"mixamorig:{side}ForeArm"]
                    front = max(swing, 0)
                    back = max(-swing, 0)
                    point_bone(forearm, (side_sign * .12,
                                         -.10 - .65 * front + .65 * back,
                                         -.95 + 1.60 * front + .20 * back))
                    hand = rig.pose.bones[f"mixamorig:{side}Hand"]
                    hand.rotation_quaternion = Quaternion((1, 0, 0, 0))
                    for pose in (arm, forearm, hand):
                        for channel in ("location", "rotation_quaternion", "scale"):
                            pose.keyframe_insert(channel, frame=frame, group=pose.name)
            for side in ("Left", "Right"):
                twist_wrist(rig, side, clip)
                hand = rig.pose.bones[f"mixamorig:{side}Hand"]
                hand.keyframe_insert("rotation_quaternion", frame=frame, group=hand.name)
            for name, (axis, angle, _) in curls.items():
                pose = rig.pose.bones[name]
                pose.rotation_mode = "QUATERNION"
                pose.rotation_quaternion = Quaternion(axis, angle)
                pose.keyframe_insert("rotation_quaternion", frame=frame, group=name)
        changed[clip] = {"frames": last - first + 1, "range": [first, last]}
    pose_samples = []
    rig.data.pose_position = "POSE"
    for clip, frames in (("idle", (1,)), ("run", (1, 5, 10, 14))):
        rig.animation_data.action = actions[clip]
        for frame in frames:
            bpy.context.scene.frame_set(frame)
            extent = bounds(mesh)
            if max(abs(value) for axis in extent for value in axis) > 2:
                raise ValueError(f"Motion bounds exceed expected 1 m scale: {clip} {frame}")
            pose_samples.append({"clip": clip, "frame": frame, "bounds": extent})
    rig.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(1)
    output.mkdir(parents=True)
    blend = output / "ReplayXITripoFBXMotionPolished.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    rig.animation_data.action = None
    for clip, action in actions.items():
        track = rig.animation_data.nla_tracks.new()
        track.name = "ReplayXI_" + clip.title()
        track.strips.new(track.name, 1, action)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig, mesh):
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    glb = output / "ReplayXITripoFBXMotionPolished_1m.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_nla_strips=True,
                              export_def_bones=True, export_yup=True,
                              export_cameras=False, export_lights=False,
                              export_apply=False, export_all_influences=False)
    if sha(source) != SOURCE_SHA:
        raise ValueError("Source blend changed")
    report = {"sourceBlendSHA256": SOURCE_SHA, "outputs": {"blend": str(blend), "blendSHA256": sha(blend),
              "motionGLB": str(glb), "motionGLBSHA256": sha(glb)}, "clips": changed,
              "idleArms": "Native shafts directed down/slightly outward; torso motion retained",
              "fingerCurlsDegrees": {"fingers": [42, 52, 32], "thumb": [18, 22, 12]},
              "fingerBendAxesWorld": {name: axis for name, (_, _, axis) in curls.items()},
              "hemWeightRepair": "Not applied: isolated weight edits worsened jersey/shorts intersection",
              "poseSamples": pose_samples,
              "status": "Offline motion polish; visual and native QA required"}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_FBX_POLISH " + json.dumps({key: value for key, value in report.items() if key != "fingerBendAxesWorld"}))


if __name__ == "__main__":
    main()
