#!/usr/bin/env python3
"""Rig Player A in source T rest; bake existing 52-bone motions to new rest."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import diversity172_rig_common as base


def arm_descendant(name):
    return any(name.startswith(f"mixamorig:{side}{part}")
               for side in ("Left", "Right") for part in ("Arm", "ForeArm", "Hand"))


def arm_rotation(name, rig):
    side = "Left" if name.startswith("mixamorig:Left") else "Right"
    upper = rig.data.bones[f"mixamorig:{side}Arm"]
    pivot = upper.head_local.copy()
    angle = -1.0995574288 if side == "Left" else 1.0995574288  # 63 degrees
    return Matrix.Translation(pivot) @ Matrix.Rotation(angle, 4, "Y") @ Matrix.Translation(-pivot)


def record_actions(rig):
    actions = {"idle": bpy.data.actions["ReplayXI_Tripo_FBX_Idle"],
               "run": bpy.data.actions["ReplayXI_Tripo_FBX_Run"]}
    samples = {}
    for label, action in actions.items():
        rig.animation_data.action = action
        first, last = map(round, action.frame_range)
        samples[label] = []
        for frame in range(first, last + 1):
            bpy.context.scene.frame_set(frame)
            samples[label].append((frame, {bone.name: bone.matrix.copy() for bone in rig.pose.bones}))
    rig.animation_data.action = None
    return samples


def pose_old_mesh_to_t(rig, old):
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    bpy.context.view_layer.update()
    # Set each arm chain in hierarchy order. The shoulder remains a body pivot.
    order = sorted((bone for bone in rig.data.bones if arm_descendant(bone.name)),
                   key=lambda bone: len(bone.parent_recursive))
    transforms = {side: arm_rotation(f"mixamorig:{side}Arm", rig) for side in ("Left", "Right")}
    for bone in order:
        side = "Left" if bone.name.startswith("mixamorig:Left") else "Right"
        rig.pose.bones[bone.name].matrix = transforms[side] @ bone.matrix_local
        bpy.context.view_layer.update()
    evaluated = old.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()
    if len(points) != len(old.data.vertices):
        raise ValueError("Old posed reference changed topology")
    return points


def make_t_rest(rig):
    transforms = {side: arm_rotation(f"mixamorig:{side}Arm", rig) for side in ("Left", "Right")}
    originals = {bone.name: (bone.head_local.copy(), bone.tail_local.copy(),
                             bone.matrix_local.to_3x3().col[2].copy())
                 for bone in rig.data.bones if arm_descendant(bone.name)}
    rig.data.pose_position = "REST"
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    connected = {bone.name: bone.use_connect for bone in rig.data.edit_bones if arm_descendant(bone.name)}
    for bone in rig.data.edit_bones:
        if arm_descendant(bone.name):
            bone.use_connect = False
    for bone in rig.data.edit_bones:
        if arm_descendant(bone.name):
            side = "Left" if bone.name.startswith("mixamorig:Left") else "Right"
            head, tail, up = originals[bone.name]
            bone.head = transforms[side] @ head
            bone.tail = transforms[side] @ tail
            bone.align_roll(transforms[side].to_3x3() @ up)
    for bone in rig.data.edit_bones:
        if arm_descendant(bone.name):
            bone.use_connect = connected[bone.name]
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
        bone.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()


def bake_actions(rig, samples):
    actions = {}
    order = sorted(rig.data.bones, key=lambda bone: len(bone.parent_recursive))
    for label, frames in samples.items():
        action = bpy.data.actions.new(f"PlayerA_{label.title()}")
        action.use_fake_user = True
        rig.animation_data.action = action
        for frame, poses in frames:
            bpy.context.scene.frame_set(frame)
            for bone in order:
                parent = bone.parent.name if bone.parent else None
                rest_local = (rig.data.bones[parent].matrix_local.inverted() @ bone.matrix_local
                              if parent else bone.matrix_local)
                pose_local = poses[parent].inverted() @ poses[bone.name] if parent else poses[bone.name]
                rig.pose.bones[bone.name].matrix_basis = rest_local.inverted() @ pose_local
            bpy.context.view_layer.update()
            for bone in order:
                pb = rig.pose.bones[bone.name]
                for channel in ("location", "rotation_quaternion", "scale"):
                    pb.keyframe_insert(data_path=channel, frame=frame, group=bone.name)
        actions[label] = action
    rig.animation_data.action = None
    return actions


def stabilize_hands(mesh):
    """Keep confident finger weights; bind ambiguous hand transfers to the palm."""
    affected = 0
    articulated = 0
    chains = ("Index", "Middle", "Ring", "Pinky", "Thumb")
    groups = {group.index: group.name for group in mesh.vertex_groups}
    for vertex in mesh.data.vertices:
        x, _, z = vertex.co
        if abs(x) <= .36 or z <= .68:
            continue
        side = "Left" if x >= 0 else "Right"
        hand = mesh.vertex_groups[f"mixamorig:{side}Hand"].index
        t = max(0.0, min(1.0, (abs(x) - .36) / .06))
        blend = t * t * (3 - 2 * t)
        existing = {item.group: item.weight for item in vertex.groups if item.weight > 0}
        finger_groups = {chain: {group: weight for group, weight in existing.items()
                                 if groups[group].startswith(f"mixamorig:{side}Hand{chain}")}
                         for chain in chains}
        dominant = max(chains, key=lambda chain: sum(finger_groups[chain].values()))
        if sum(finger_groups[dominant].values()) >= .45:
            # The transfer's clear finger chain should still bend at its real
            # phalanges. Discard competing chains that made fingers intersect.
            # The transfer is coarse near these narrow fingers. Limit its
            # influence so authored bends cannot fold the mesh through itself.
            mixed = {group: weight * (1 - min(blend, .12)) * .35
                     for group, weight in finger_groups[dominant].items()}
            mixed[hand] = 1 - sum(mixed.values())
            articulated += 1
        else:
            mixed = {group: weight * (1 - blend) for group, weight in existing.items()}
            mixed[hand] = mixed.get(hand, 0) + blend
        for group in existing:
            mesh.vertex_groups[group].remove([vertex.index])
        for group, weight in mixed.items():
            if weight > 0:
                mesh.vertex_groups[group].add([vertex.index], weight, "REPLACE")
        affected += 1
    return {"vertices": affected, "articulatedFingerVertices": articulated,
            "startXMetres": .36, "fullXMetres": .42,
            "fingerTransferThreshold": .45, "fingerInfluenceScale": .35,
            "maximumFingerPalmBlend": .12}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath or output.exists() or not output.is_relative_to((base.REPO / ".codex-derived").resolve()):
        raise ValueError("Use factory Blender and new derived output")
    before = {"source": base.sha(base.SOURCE), "motionBlend": base.sha(base.MOTION)}
    if before["source"] != base.SOURCE_SHA:
        raise ValueError("Source hash changed")
    bpy.ops.wm.open_mainfile(filepath=str(base.MOTION), load_ui=False)
    rig = bpy.data.objects["Armature"]
    old = bpy.data.objects["ReplayXI_Tripo_FBX_Candidate"]
    for obj in tuple(bpy.data.objects):
        if obj not in (rig, old):
            bpy.data.objects.remove(obj, do_unlink=True)
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    rig.data.pose_position = "POSE"
    samples = record_actions(rig)
    posed_old_points = pose_old_mesh_to_t(rig, old)
    make_t_rest(rig)
    old.hide_render = True
    old.hide_set(True)
    bpy.ops.import_scene.gltf(filepath=str(base.SOURCE))
    near = next(obj for obj in bpy.context.selected_objects if obj.type == "MESH")
    near.name = "PlayerA_Near"
    if len(near.data.materials) != 1 or len(near.data.uv_layers) != 1:
        raise ValueError("Unexpected source material/UV")
    near_decimation = base.decimate(near, 10500)
    transfer = base.transfer_weights(old, near, posed_old_points)
    hand_stabilization = stabilize_hands(near)
    near.parent = rig
    near.matrix_parent_inverse = rig.matrix_world.inverted()
    near.modifiers.new("PlayerA_52JointSkin", "ARMATURE").object = rig
    near_weights = base.weights_stats(near)
    if near_weights["missingVertices"] or near_weights["maxWeightSumError"] > 1e-4:
        raise ValueError(f"Near weights invalid: {near_weights}")
    near_rest = base.bounds(near, evaluated=True)
    low = near.copy()
    low.data = near.data.copy()
    bpy.context.scene.collection.objects.link(low)
    low.name = "PlayerA_Low"
    low_decimation = base.decimate(low, 2800)
    low_weights = base.weights_stats(low)
    if low_weights["missingVertices"] or low_weights["maxWeightSumError"] > 1e-4:
        raise ValueError(f"Low weights invalid: {low_weights}")
    low_rest = base.bounds(low, evaluated=True)
    rig.data.pose_position = "POSE"
    actions = bake_actions(rig, samples)
    for label, action in actions.items():
        track = rig.animation_data.nla_tracks.new()
        track.name = label
        track.strips.new(label, 1, action)
    rig.animation_data.action = None
    output.mkdir(parents=True)
    near_glb, low_glb, motion_glb = (output / name for name in
                                     ("PlayerA-Near.glb", "PlayerA-Low.glb", "PlayerA-Motion.glb"))
    base.export(near_glb, rig, near)
    base.export(low_glb, rig, low)
    base.export(motion_glb, rig, near, with_motion=True)
    low.hide_render = True
    rig.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(1)
    blend = output / "PlayerA-Rig.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    after = {"source": base.sha(base.SOURCE), "motionBlend": base.sha(base.MOTION)}
    if after != before:
        raise ValueError("Read-only input changed")
    report = {"candidateOnly": True, "sourceHashes": before, "sceneFPS": bpy.context.scene.render.fps,
              "near": {"decimation": near_decimation, "transfer": transfer,
                       "handStabilization": hand_stabilization, "weights": near_weights,
                       "restBounds": near_rest, "glb": str(near_glb), "sha256": base.sha(near_glb)},
              "low": {"decimation": low_decimation, "weights": low_weights,
                      "restBounds": low_rest, "glb": str(low_glb), "sha256": base.sha(low_glb)},
              "motion": {"glb": str(motion_glb), "sha256": base.sha(motion_glb),
                         "clips": {k: len(v) for k, v in samples.items()}},
              "blend": str(blend), "blendSHA256": base.sha(blend),
              "jointCount": len(rig.data.bones),
              "restBones": {b.name: {"parent": b.parent.name if b.parent else None,
                                      "matrix": [list(row) for row in b.matrix_local]}
                            for b in rig.data.bones},
              "limit": "Same-family surface weight transfer; visual pose QA required."}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("DIVERSITY172_TREST", json.dumps({k: v for k, v in report.items() if k != "restBones"}))


if __name__ == "__main__":
    main()
