#!/usr/bin/env python3
"""Prepare the user-supplied Blender FBX skin with Replay XI idle/run clips.

Read-only source; output is a new .codex-derived directory. This keeps the
FBX's own anatomically aligned Mixamo rig and exports an offline GLB candidate.
It does not change runtime resources or declare native USDZ admission.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_football_player import create_actions  # noqa: E402
from retarget_tripo_autorig_candidate import MAP, image_bounds, retarget_frame  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / ".codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayerHome.glb"
MOTION = REPO / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"
SOURCE_SHA = "3c7f948ee3701d1837356390e4af0d09c39de4cc9356f3f09d8970266d183787"
MOTION_SHA = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def four_weights(mesh):
    changed = 0
    maximum_discarded = 0.0
    maximum_sum_error = 0.0
    for vertex in mesh.data.vertices:
        weighted = sorted(((group.group, group.weight) for group in vertex.groups if group.weight > 0),
                          key=lambda row: (-row[1], row[0]))
        if not weighted or any(not math.isfinite(value) or value < 0 for _, value in weighted):
            raise ValueError("Missing or invalid FBX weight")
        if len(weighted) > 4:
            changed += 1
            maximum_discarded = max(maximum_discarded, sum(weight for _, weight in weighted[4:]))
            for group, _ in weighted[4:]:
                mesh.vertex_groups[group].remove([vertex.index])
        selected = weighted[:4]
        total = sum(value for _, value in selected)
        if total <= 0:
            raise ValueError("Empty retained weight set")
        for group, value in selected:
            mesh.vertex_groups[group].add([vertex.index], value / total, "REPLACE")
        current = [group for group in mesh.data.vertices[vertex.index].groups if group.weight > 0]
        if len(current) > 4:
            raise ValueError("Four-weight reduction failed")
        maximum_sum_error = max(maximum_sum_error, abs(sum(group.weight for group in current) - 1))
    if maximum_sum_error > 1e-5:
        raise ValueError("Reduced weights are not normalized")
    return {"reducedVertices": changed, "maxDiscardedWeightBeforeRenormalization": maximum_discarded,
            "maxInfluences": 4, "maxWeightSumError": maximum_sum_error}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-fbx", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    input_path, output = args.input_fbx.resolve(), args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated factory-startup background Blender")
    if input_path.suffix.lower() != ".fbx" or not input_path.is_file() or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("FBX must exist; output must be a NEW derived directory")
    texture = input_path.with_suffix(".fbm") / "tripo_rgb_fc71fa8e-e587-43f5-9823-bc929ad4bac6.jpg"
    if not texture.is_file():
        raise ValueError("FBX texture companion is missing")
    before = {"fbx": sha(input_path), "texture": sha(texture), "canonicalHome": sha(SOURCE), "motion": sha(MOTION)}
    if before["canonicalHome"] != SOURCE_SHA or before["motion"] != MOTION_SHA:
        raise ValueError("Canonical source hash changed")
    motion = json.loads(MOTION.read_text())
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source_objects = list(set(bpy.data.objects) - existing)
    source = next(obj for obj in source_objects if obj.type == "ARMATURE")
    source_meshes = [obj for obj in source_objects if obj.type == "MESH" and obj.name.endswith(("Body", "Head"))]
    source_actions = create_actions(source, motion)
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(input_path))
    imported = list(set(bpy.data.objects) - existing)
    target = next(obj for obj in imported if obj.type == "ARMATURE")
    mesh = next(obj for obj in imported if obj.type == "MESH")
    if len(target.data.bones) != 65 or len(mesh.data.vertices) != 8820 or len(mesh.data.polygons) != 9388:
        raise ValueError("FBX rig or geometry changed")
    if len(mesh.data.materials) != 1 or len(mesh.data.uv_layers) != 1 or len(mesh.vertex_groups) != 52:
        raise ValueError("FBX texture/skin layout changed")
    if not all("mixamorig:" + name in target.data.bones for name in MAP):
        raise ValueError("FBX lacks mapped Mixamo bones")
    target.data.pose_position = "REST"
    rest_bounds = image_bounds(mesh)
    raw = [mesh.matrix_world @ vertex.co for vertex in mesh.data.vertices]
    rest_error = max((mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world @ vertex.co - raw[index]).length
                     for index, vertex in enumerate(mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices))
    if rest_error > 1e-5:
        raise ValueError("FBX skin does not preserve its rest mesh")
    reduction = four_weights(mesh)
    used_bones = {group.name for group in mesh.vertex_groups
                  if any(weight.group == group.index and weight.weight > 0
                         for vertex in mesh.data.vertices for weight in vertex.groups)}
    for bone in target.data.bones:
        bone.use_deform = bone.name in used_bones
    if len(used_bones) != 52 or sum(bone.use_deform for bone in target.data.bones) != 52:
        raise ValueError("Expected exactly 52 weighted deform bones")
    reduced_bounds = image_bounds(mesh)
    if max(abs(rest_bounds[axis][edge] - reduced_bounds[axis][edge])
           for axis in range(3) for edge in range(2)) > 1e-5:
        raise ValueError("Weight reduction changed rest bounds")
    source_height = max((obj.matrix_world @ vertex.co).z for obj in source_meshes
                        for vertex in obj.data.vertices) - min((obj.matrix_world @ vertex.co).z
                        for obj in source_meshes for vertex in obj.data.vertices)
    # Keep the FBX skin and native anatomical pivots at their verified 1 m
    # scale. The native converter scales mesh/rest/clip translations once.
    source_scale = 1.0
    scaled_bounds = rest_bounds
    for image in bpy.data.images:
        if image.filepath and Path(bpy.path.abspath(image.filepath)).resolve() == texture:
            image.pack()
    source.data.pose_position = "POSE"
    target.data.pose_position = "POSE"
    source_rest = {bone.name: bone.matrix_local.copy() for bone in source.data.bones}
    target_rest = {bone.name: bone.matrix_local.copy() for bone in target.data.bones}
    order = sorted(target.data.bones, key=lambda bone: len(bone.parent_recursive))
    for bone in target.pose.bones:
        bone.rotation_mode = "QUATERNION"
    target_height = scaled_bounds[2][1] - scaled_bounds[2][0]
    ratio = target_height / source_height
    target.animation_data_create()
    samples = []
    for clip in motion["clips"]:
        source.animation_data.action = source_actions[clip["id"]]
        action = bpy.data.actions.new("ReplayXI_Tripo_FBX_" + clip["id"].title())
        action.use_fake_user = True
        target.animation_data.action = action
        for frame in clip["frames"]:
            number = 1 + frame["time"] * clip["fps"]
            bpy.context.scene.frame_set(round(number))
            retarget_frame(source, target, source_rest, target_rest, order, ratio)
            for bone in order:
                pose_bone = target.pose.bones[bone.name]
                for channel in ("location", "rotation_quaternion", "scale"):
                    pose_bone.keyframe_insert(channel, frame=number, group=bone.name)
        for number in ((1, 5, 10, 14) if clip["id"] == "run" else (1,)):
            bpy.context.scene.frame_set(number)
            extent = image_bounds(mesh)
            if max(abs(value) for row in extent for value in row) > 3:
                raise ValueError(f"Retargeted FBX skin exceeds 3m local extent: {clip['id']} {number} {extent}")
            samples.append({"clip": clip["id"], "frame": number, "bounds": extent})
    target.animation_data.action = bpy.data.actions["ReplayXI_Tripo_FBX_Idle"]
    bpy.context.scene.frame_set(1)
    for obj in source_objects:
        obj.hide_set(True)
        obj.hide_render = True
    mesh.name = "ReplayXI_Tripo_FBX_Candidate"
    output.mkdir(parents=True)
    blend = output / "ReplayXITripoFBXCandidate.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    target.animation_data.action = None
    for clip_id in ("Idle", "Run"):
        action = bpy.data.actions["ReplayXI_Tripo_FBX_" + clip_id]
        track = target.animation_data.nla_tracks.new()
        track.name = "ReplayXI_" + clip_id
        track.strips.new(track.name, 1, action)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (target, mesh):
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    glb = output / "ReplayXITripoFBXCandidate.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_nla_strips=True,
                              export_def_bones=True,
                              export_yup=True, export_cameras=False, export_lights=False,
                              export_apply=False, export_all_influences=False)
    after = {"fbx": sha(input_path), "texture": sha(texture), "canonicalHome": sha(SOURCE), "motion": sha(MOTION)}
    if before != after:
        raise ValueError("Source files changed during candidate build")
    report = {"candidateOnly": True, "sourceHashes": before, "jointCountBlender": 65,
              "weightedGroups": len(mesh.vertex_groups), "verticesBlender": len(mesh.data.vertices),
              "trianglesBlender": len(mesh.data.polygons), "sourceScale": source_scale,
              "restBoundsBeforeScale": rest_bounds, "restBounds": scaled_bounds,
              "restMaximumVertexErrorMetres": rest_error, "weightReduction": reduction,
              "mappedMajorJoints": len(MAP), "targetToCanonicalHeightRatio": ratio,
              "poseSamples": samples, "outputs": {"blend": blend.name, "glb": glb.name,
                  "blendSHA256": sha(blend), "glbSHA256": sha(glb)},
              "limits": "Offline candidate; source motion is generic; runtime USDZ/provider admission still required."}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_FBX_CANDIDATE " + json.dumps(report))


if __name__ == "__main__":
    main()
