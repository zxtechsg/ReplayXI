#!/usr/bin/env python3
"""Build offline, 1 m Tripo FBX LOD GLBs from the verified skinned blend.

Blender --factory-startup --background --python build_tripo_fbx_lods.py --
  --input-blend .../fbx-player-v2/ReplayXITripoFBXCandidate.blend
  --output-dir .../.codex-derived/replayxi-tripo164/fbx-lods-v1
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy

REPO = Path(__file__).resolve().parents[2]
EXPECTED_SOURCE_SHA = "a43e38d51b0878c96819abd4d85f956315f01928f35d446be65ab82a5e94c2e4"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def glb_json(path):
    with path.open("rb") as file:
        header = file.read(20)
        magic, version, _, length, chunk_type = struct.unpack("<4sIIII", header)
        if magic != b"glTF" or version != 2 or chunk_type != 0x4E4F534A:
            raise ValueError("Invalid GLB JSON chunk")
        return json.loads(file.read(length))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-blend", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source, output = args.input_blend.resolve(), args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated factory-startup background Blender")
    if not source.is_file() or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Input must exist and output must be a new .codex-derived directory")
    source_sha = digest(source)
    if EXPECTED_SOURCE_SHA and source_sha != EXPECTED_SOURCE_SHA:
        raise ValueError("Frozen v2 input SHA changed")
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False)
    mesh = bpy.data.objects.get("ReplayXI_Tripo_FBX_Candidate")
    if mesh is None or mesh.type != "MESH":
        raise ValueError("Frozen FBX mesh missing")
    arms = [modifier.object for modifier in mesh.modifiers if modifier.type == "ARMATURE"]
    if len(arms) != 1 or len(arms[0].data.bones) != 65:
        raise ValueError("Expected 65-bone source rig")
    rig = arms[0]
    rig.data.pose_position = "REST"
    bpy.context.scene.frame_set(1)
    if len(mesh.vertex_groups) != 52 or len(mesh.data.vertices) != 8820:
        raise ValueError("Unexpected source mesh skin")
    if len(mesh.data.materials) != 1 or len(mesh.data.uv_layers) != 1:
        raise ValueError("Expected one textured UV atlas")
    for vertex in mesh.data.vertices:
        weights = [group.weight for group in vertex.groups if group.weight > 0]
        if not weights or len(weights) > 4 or abs(sum(weights) - 1) > 1e-5:
            raise ValueError("Source weights fail four-influence gate")
    output.mkdir(parents=True)
    results = {}
    for label, ratio, limit in (("near", .45, 8200), ("low", .115, 2200)):
        lod = mesh.copy()
        lod.data = mesh.data.copy()
        bpy.context.scene.collection.objects.link(lod)
        lod.name = "ReplayXI_Tripo_FBX_" + label.title()
        for modifier in list(lod.modifiers):
            lod.modifiers.remove(modifier)
        decimate = lod.modifiers.new("Offline_LOD_Decimate", "DECIMATE")
        decimate.decimate_type = "COLLAPSE"
        decimate.ratio = ratio
        decimate.use_collapse_triangulate = True
        bpy.ops.object.select_all(action="DESELECT")
        lod.hide_set(False)
        lod.select_set(True)
        bpy.context.view_layer.objects.active = lod
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        arm = lod.modifiers.new("Native_FBX_Skin", "ARMATURE")
        arm.object = rig
        # Edge collapses interpolate all donor vertex groups, so trim again.
        for vertex in lod.data.vertices:
            weights = sorted(((group.group, group.weight) for group in vertex.groups if group.weight > 0),
                             key=lambda entry: -entry[1])
            total = sum(value for _, value in weights[:4])
            if total <= 0:
                raise ValueError(f"{label} has an unweighted vertex")
            for group, _ in weights[4:]:
                lod.vertex_groups[group].remove([vertex.index])
            for group, value in weights[:4]:
                lod.vertex_groups[group].add([vertex.index], value / total, "REPLACE")
        lod.data.calc_loop_triangles()
        triangles = len(lod.data.loop_triangles)
        if triangles > limit or triangles < limit * .65:
            raise ValueError(f"{label} triangle target missed: {triangles} / {limit}")
        max_influences = 0
        max_sum_error = 0.0
        for vertex in lod.data.vertices:
            weights = [group.weight for group in vertex.groups if group.weight > 0]
            if not weights or any(not math.isfinite(value) for value in weights):
                raise ValueError(f"{label} has missing/nonfinite weights")
            max_influences = max(max_influences, len(weights))
            max_sum_error = max(max_sum_error, abs(sum(weights) - 1))
        if max_influences > 4 or max_sum_error > 1e-4:
            raise ValueError(f"{label} weights are not four-normalized: {max_influences}, {max_sum_error}")
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = lod.evaluated_get(depsgraph)
        rest_error = max((evaluated.matrix_world @ v.co - lod.matrix_world @ lod.data.vertices[i].co).length
                         for i, v in enumerate(evaluated.data.vertices))
        if rest_error > 1e-5:
            raise ValueError(f"{label} rest deformation: {rest_error}")
        glb = output / f"ReplayXITripoFBX_{label.title()}_1m.glb"
        bpy.ops.object.select_all(action="DESELECT")
        rig.hide_set(False)
        for obj in (rig, lod):
            obj.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                                  export_skins=True, export_animations=False, export_def_bones=True,
                                  export_yup=True, export_cameras=False, export_lights=False,
                                  export_apply=False, export_all_influences=False)
        asset = glb_json(glb)
        if len(asset.get("skins", [])) != 1 or len(asset["skins"][0]["joints"]) != 52:
            raise ValueError(f"{label} GLB lost 52-joint skin")
        if len(asset.get("meshes", [])) != 1 or len(asset["meshes"][0]["primitives"]) != 1:
            raise ValueError(f"{label} GLB expected one mesh primitive")
        primitive = asset["meshes"][0]["primitives"][0]
        glb_triangles = asset["accessors"][primitive["indices"]]["count"] // 3
        if glb_triangles != triangles:
            raise ValueError(f"{label} export triangle mismatch: {triangles} vs {glb_triangles}")
        if len(asset.get("materials", [])) != 1 or len(asset.get("textures", [])) != 1:
            raise ValueError(f"{label} GLB texture/material lost")
        if asset.get("animations"):
            raise ValueError(f"{label} GLB must use full-res motion GLB")
        results[label] = {"glb": str(glb), "sha256": digest(glb), "verticesBlender": len(lod.data.vertices),
                          "trianglesBlender": triangles, "trianglesGLB": glb_triangles, "skinJointsGLB": 52,
                          "maxInfluences": max_influences, "maxWeightSumError": max_sum_error,
                          "maxRestErrorMetres": rest_error}
        lod.hide_set(True)
        lod.hide_render = True
    if digest(source) != source_sha:
        raise ValueError("Frozen input blend changed")
    report = {"sourceBlend": str(source), "sourceSHA256": source_sha,
              "scale": "1 m FBX local. Native conversion scales mesh/rest/clip translations once to 1.821917 m.",
              "lods": results, "candidateOnly": True}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_FBX_LODS " + json.dumps(report))


if __name__ == "__main__":
    main()
