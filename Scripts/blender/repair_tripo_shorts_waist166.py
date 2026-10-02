#!/usr/bin/env python3
"""REJECTED / NOT RECOMMENDED offline shorts-waist study.

Only weights on the isolated 502-face shorts shell change. Geometry, UVs,
materials, rig rest/bind, and idle/run bone curves remain untouched.
The high-knee renders worsen the white slash; do not use for native admission.
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
from audit_tripo_hem166 import components  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
APPROVED_SHA = "3b3aa3c6541510e477f767f2f232b81b53c9919cdfb1cca877108adf2809ff2f"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def layout_hash(mesh):
    data = []
    for vertex in mesh.data.vertices:
        data.append(tuple(vertex.co))
    for polygon in mesh.data.polygons:
        data.append(tuple(polygon.vertices))
    for layer in mesh.data.uv_layers:
        for loop in layer.data:
            data.append(tuple(loop.uv))
    return hashlib.sha256(repr(data).encode()).hexdigest()


def bounds(mesh):
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points = [evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices]
    return [[min(point[axis] for point in points), max(point[axis] for point in points)] for axis in range(3)]


def repair(mesh, shorts_faces):
    names = {group.index: group.name for group in mesh.vertex_groups}
    groups = {group.name: group for group in mesh.vertex_groups}
    vertices = sorted({index for face in shorts_faces for index in mesh.data.polygons[face].vertices})
    changed = []
    for index in vertices:
        vertex = mesh.data.vertices[index]
        z = vertex.co.z
        if z <= .45:
            continue
        t = max(0.0, min(1.0, (z - .45) / .065))
        fade = t * t * (3 - 2 * t)
        weights = {names[item.group]: item.weight for item in vertex.groups if item.weight > 0}
        thigh_names = [name for name in weights if name.endswith("UpLeg")]
        thigh = sum(weights[name] for name in thigh_names)
        if thigh <= .001 or fade <= 0:
            continue
        moved = thigh * fade
        for name in thigh_names:
            weights[name] *= 1 - fade
        weights["mixamorig:Hips"] = weights.get("mixamorig:Hips", 0) + moved
        retained = sorted(((name, value) for name, value in weights.items() if value > 1e-8),
                          key=lambda item: -item[1])[:4]
        total = sum(value for _, value in retained)
        if total <= 0:
            raise ValueError("Waistband vertex lost skin weights")
        old_group_ids = [item.group for item in vertex.groups]
        for group_id in old_group_ids:
            mesh.vertex_groups[group_id].remove([index])
        for name, value in retained:
            groups[name].add([index], value / total, "REPLACE")
        changed.append({"index": index, "restZ": z, "movedThighWeight": moved,
                        "newHipsWeight": next((value / total for name, value in retained if name == "mixamorig:Hips"), 0)})
    if not 40 <= len(changed) <= 400:
        raise ValueError(f"Unexpected shorts-band selection: {len(changed)}")
    max_influences = 0
    max_sum_error = 0.0
    worst = None
    for vertex in mesh.data.vertices:
        weights = [item.weight for item in vertex.groups if item.weight > 0]
        if not weights or any(not math.isfinite(value) for value in weights):
            raise ValueError("Invalid repaired skin")
        max_influences = max(max_influences, len(weights))
        error = abs(sum(weights) - 1)
        if error > max_sum_error:
            max_sum_error = error
            worst = (vertex.index, [(item.group, item.weight) for item in vertex.groups])
    if max_influences > 4 or max_sum_error > 1e-5:
        raise ValueError(f"Skin contract failed: {max_influences}, {max_sum_error}, {worst}")
    return {"changedVertices": len(changed), "maxMovedThighWeight": max(row["movedThighWeight"] for row in changed),
            "maxInfluences": max_influences, "maxWeightSumError": max_sum_error,
            "changedIndexMinMax": [min(row["index"] for row in changed), max(row["index"] for row in changed)],
            "rule": "Only 502-face shorts shell; smoothstep thigh→hips on original Z .45–.515 m"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-blend", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source, output = args.input_blend.resolve(), args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated factory-startup background Blender")
    if not source.is_file() or sha(source) != APPROVED_SHA or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Expected approved v9 motion blend and new derived output")
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False)
    mesh = bpy.data.objects["ReplayXI_Tripo_FBX_Candidate"]
    rig = next(modifier.object for modifier in mesh.modifiers if modifier.type == "ARMATURE")
    if len(mesh.data.vertices) != 8820 or len(rig.data.bones) != 65:
        raise ValueError("Unexpected approved skin/rig")
    grouped = components(mesh)
    if len(grouped) < 4 or len(grouped[3]) != 502:
        raise ValueError("Shorts shell topology changed")
    before_layout = layout_hash(mesh)
    rig.data.pose_position = "REST"
    rest_before = bounds(mesh)
    fixed = repair(mesh, grouped[3])
    if layout_hash(mesh) != before_layout:
        raise ValueError("Repair changed geometry or UVs")
    rest_after = bounds(mesh)
    rest_bound_error = max(abs(rest_before[axis][edge] - rest_after[axis][edge])
                           for axis in range(3) for edge in range(2))
    if rest_bound_error > 1e-5:
        raise ValueError(f"Repair changed rest skin bounds: {rest_bound_error}")
    rig.data.pose_position = "POSE"
    pose_samples = []
    for clip, frames in (("idle", (1,)), ("run", (1, 4, 5, 10, 14, 19))):
        rig.animation_data.action = bpy.data.actions["ReplayXI_Tripo_FBX_" + clip.title()]
        for frame in frames:
            bpy.context.scene.frame_set(frame)
            pose_samples.append({"clip": clip, "frame": frame, "bounds": bounds(mesh)})
    rig.animation_data.action = bpy.data.actions["ReplayXI_Tripo_FBX_Idle"]
    bpy.context.scene.frame_set(1)
    output.mkdir(parents=True)
    blend = output / "ReplayXITripoShortsWaistCandidate.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    rig.animation_data.action = None
    for clip in ("Idle", "Run"):
        action = bpy.data.actions["ReplayXI_Tripo_FBX_" + clip]
        track = rig.animation_data.nla_tracks.new()
        track.name = "ReplayXI_" + clip
        track.strips.new(track.name, 1, action)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig, mesh):
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    glb = output / "ReplayXITripoShortsWaistCandidate_1m.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_nla_strips=True,
                              export_def_bones=True, export_yup=True,
                              export_cameras=False, export_lights=False,
                              export_apply=False, export_all_influences=False)
    if sha(source) != APPROVED_SHA:
        raise ValueError("Approved source changed")
    report = {"candidateOnly": True, "source": str(source), "sourceSHA256": APPROVED_SHA,
              "layoutHashUnchanged": before_layout, "weightRepair": fixed,
              "restBoundsErrorMetres": rest_bound_error, "poseSamples": pose_samples,
              "outputs": {"blend": str(blend), "blendSHA256": sha(blend),
                          "motionGLB": str(glb), "motionGLBSHA256": sha(glb)},
              "status": "REJECTED: wider white/grey seam in high-knee renders; do not admit"}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("TRIPO_SHORTS_WAIST_CANDIDATE " + json.dumps({key: value for key, value in report.items() if key != "poseSamples"}))


if __name__ == "__main__":
    main()
