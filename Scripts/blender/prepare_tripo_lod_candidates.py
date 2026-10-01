#!/usr/bin/env python3
"""Create offline near/far LOD GLBs from a skinned Tripo GLB.

The source is imported into a factory Blender process and never saved. Output
must be a new directory under .codex-derived. The builder preserves the source
rig, material, and UV layers; only mesh topology and weight sparsity change.
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
from mathutils.bvhtree import BVHTree

REPO = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = REPO / ".codex-derived/replayxi-tripo163/autorig-bind-repair/ReplayXI_Footballer_P2_Rigged_BindRepaired.glb"
DEFAULT_SHA256 = "8495584c9ffd93268e8882ccb2f08ca839b382555604712e001f80cf0fb65302"
# This is a topology/export consistency check in Blender REST mode. It does
# not prove anatomical joint placement or deformation quality during motion.
REST_BIND_TOLERANCE_M = 0.000001
TARGETS = {"near": 8200, "far": 2200}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def skin_meshes(objects):
    return [obj for obj in objects if obj.type == "MESH" and any(
        modifier.type == "ARMATURE" and modifier.object is not None for modifier in obj.modifiers)]


def check_weights(obj):
    max_influences = 0
    max_sum_error = 0.0
    for vertex in obj.data.vertices:
        active = [(item.group, item.weight) for item in vertex.groups if item.weight > 0]
        if not active or any(not math.isfinite(weight) for _, weight in active):
            raise ValueError(f"{obj.name}: missing/nonfinite skin weights")
        max_influences = max(max_influences, len(active))
        max_sum_error = max(max_sum_error, abs(sum(weight for _, weight in active) - 1.0))
    if max_influences > 4 or max_sum_error > 1e-6:
        raise ValueError(f"{obj.name}: weights violate 4 normalized influence limit")
    return {"maximumInfluences": max_influences, "maximumWeightSumError": max_sum_error}


def normalize_weights(obj):
    truncated_vertices = 0
    max_discarded = 0.0
    for vertex in obj.data.vertices:
        active = sorted(((item.group, item.weight) for item in vertex.groups if item.weight > 0),
                        key=lambda item: (-item[1], item[0]))
        kept = active[:4]
        if len(active) > 4:
            truncated_vertices += 1
            max_discarded = max(max_discarded, sum(weight for _, weight in active[4:]))
        total = sum(weight for _, weight in kept)
        if not math.isfinite(total) or total <= 0:
            raise ValueError(f"{obj.name}: decimation removed a vertex binding")
        for group, _ in active:
            obj.vertex_groups[group].remove([vertex.index])
        for group, weight in kept:
            obj.vertex_groups[group].add([vertex.index], weight / total, "REPLACE")
    stats = check_weights(obj)
    stats.update({"truncatedVertices": truncated_vertices, "maximumDiscardedWeight": max_discarded})
    return stats


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def rest_error(meshes):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    values = []
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            if len(mesh.vertices) != len(obj.data.vertices):
                raise ValueError(f"{obj.name}: armature changed rest vertex count")
            for source, result in zip(obj.data.vertices, mesh.vertices):
                raw_world = obj.matrix_world @ source.co
                skinned_world = evaluated.matrix_world @ result.co
                values.append((skinned_world - raw_world).length)
        finally:
            evaluated.to_mesh_clear()
    if not values or any(not math.isfinite(value) for value in values):
        raise ValueError("Missing or nonfinite rest deformation samples")
    values.sort()
    return {"maximumMetres": values[-1], "p95Metres": values[int((len(values) - 1) * .95)]}


def bounds(meshes):
    points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    return [[min(point[axis] for point in points), max(point[axis] for point in points)]
            for axis in range(3)]


def surface_distance(source_meshes, target_meshes):
    target_points, target_faces = [], []
    for obj in target_meshes:
        base = len(target_points)
        target_points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        obj.data.calc_loop_triangles()
        target_faces.extend(tuple(base + index for index in triangle.vertices)
                            for triangle in obj.data.loop_triangles)
    tree = BVHTree.FromPolygons(target_points, target_faces, all_triangles=True)
    values = []
    for obj in source_meshes:
        for vertex in obj.data.vertices:
            hit = tree.find_nearest(obj.matrix_world @ vertex.co)
            if hit[0] is None or not math.isfinite(hit[3]):
                raise ValueError("LOD surface comparison returned no finite match")
            values.append(hit[3])
    values.sort()
    return {"meanMetres": sum(values) / len(values),
            "p95Metres": values[int((len(values) - 1) * .95)],
            "maximumMetres": values[-1]}


def make_lod(source_meshes, collection, rig, label, target):
    source_triangles = sum(triangles(obj) for obj in source_meshes)
    ratio = min(1.0, target / source_triangles * 0.97)
    result, details = [], []
    # Decimate each source mesh by a common ratio so all sections retain their
    # original material/UV boundaries and the combined triangle budget holds.
    for source in source_meshes:
        obj = source.copy()
        obj.data = source.data.copy()
        obj.name = f"ReplayXI_Tripo_{label.title()}_{source.name}"
        collection.objects.link(obj)
        obj["candidate_only"] = True
        decimate = obj.modifiers.new(f"ReplayXI_{label.title()}_RestDecimate", "DECIMATE")
        decimate.decimate_type = "COLLAPSE"
        decimate.ratio = ratio
        decimate.use_collapse_triangulate = True
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        while obj.modifiers.find(decimate.name) > 0:
            bpy.ops.object.modifier_move_up(modifier=decimate.name)
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        obj.select_set(False)
        weight_stats = normalize_weights(obj)
        result.append(obj)
        details.append({"source": source.name, "candidate": obj.name,
                        "triangles": triangles(obj), "vertices": len(obj.data.vertices),
                        "uvLayers": [layer.name for layer in obj.data.uv_layers],
                        "materialSlots": len(obj.data.materials), "weights": weight_stats})
    total = sum(triangles(obj) for obj in result)
    if total > target:
        raise ValueError(f"{label} LOD has {total} triangles, over target {target}")
    return result, {"targetTriangles": target, "collapseRatio": ratio,
                    "triangles": total, "sections": details}


def decode_accessor(gltf, binary, accessor_index):
    accessor = gltf["accessors"][accessor_index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    formats = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4),
               5126: ("f", 4)}
    code, size = formats[accessor["componentType"]]
    stride = view.get("byteStride", components * size)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    rows = []
    for index in range(accessor["count"]):
        values = struct.unpack_from("<" + code * components, binary, start + index * stride)
        if accessor.get("normalized") and accessor["componentType"] != 5126:
            maximum = 255 if accessor["componentType"] == 5121 else 65535
            values = tuple(value / maximum for value in values)
        rows.append(values)
    return rows


def inspect_glb(path, bone_names):
    payload = path.read_bytes()
    magic, version, size, json_size, json_type = struct.unpack_from("<IIIII", payload)
    if (magic, version, size, json_type) != (0x46546C67, 2, len(payload), 0x4E4F534A):
        raise ValueError(f"{path.name}: invalid GLB header")
    manifest = json.loads(payload[20:20 + json_size])
    binary_size, binary_type = struct.unpack_from("<II", payload, 20 + json_size)
    if binary_type != 0x004E4942:
        raise ValueError(f"{path.name}: missing GLB binary buffer")
    binary = payload[28 + json_size:28 + json_size + binary_size]
    skins = manifest.get("skins", [])
    if len(skins) != 1:
        raise ValueError(f"{path.name}: expected one exported skin")
    exported_bones = [manifest["nodes"][index].get("name", "") for index in skins[0]["joints"]]
    if len(exported_bones) != len(bone_names) or set(exported_bones) != set(bone_names):
        raise ValueError(f"{path.name}: exported bone set differs from source")
    primitives = [primitive for mesh in manifest.get("meshes", []) for primitive in mesh["primitives"]]
    tri_count = 0
    max_sum_error = 0.0
    materials = set()
    for primitive in primitives:
        attrs = primitive["attributes"]
        for semantic in ("POSITION", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"):
            if semantic not in attrs:
                raise ValueError(f"{path.name}: missing {semantic}")
        positions = decode_accessor(manifest, binary, attrs["POSITION"])
        uvs = decode_accessor(manifest, binary, attrs["TEXCOORD_0"])
        joints = decode_accessor(manifest, binary, attrs["JOINTS_0"])
        weights = decode_accessor(manifest, binary, attrs["WEIGHTS_0"])
        if not (len(positions) == len(uvs) == len(joints) == len(weights)):
            raise ValueError(f"{path.name}: mismatched exported vertex attributes")
        if "JOINTS_1" in attrs or "WEIGHTS_1" in attrs:
            raise ValueError(f"{path.name}: exported more than four influences")
        for joint_row, weight_row in zip(joints, weights):
            if any(not 0 <= int(index) < len(bone_names) for index in joint_row):
                raise ValueError(f"{path.name}: invalid joint index")
            error = abs(sum(weight_row) - 1.0)
            if any(not math.isfinite(weight) or weight < 0 for weight in weight_row):
                raise ValueError(f"{path.name}: invalid exported weights")
            max_sum_error = max(max_sum_error, error)
        if primitive.get("material") is not None:
            materials.add(primitive["material"])
        indices = decode_accessor(manifest, binary, primitive["indices"])
        tri_count += len(indices) // 3
    if not primitives or len(materials) != 1 or max_sum_error > 1e-5:
        raise ValueError(f"{path.name}: expected one material and normalized skin weights")
    return {"sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload),
            "meshCount": len(manifest.get("meshes", [])), "primitiveCount": len(primitives),
            "materialCount": len(manifest.get("materials", [])), "triangles": tri_count,
            "boneCount": len(exported_bones), "boneNames": exported_bones,
            "uvAccessors": len(primitives), "maximumWeightSumError": max_sum_error}


def validate_export_reimport(path, expected_rest, target):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = set(bpy.data.objects) - before
    imported_rigs = [obj for obj in imported if obj.type == "ARMATURE"]
    if len(imported_rigs) != 1:
        raise ValueError(f"{path.name}: reimport did not produce one armature")
    imported_rig = imported_rigs[0]
    imported_rig.data.pose_position = "REST"
    imported_meshes = [obj for obj in imported if obj.type == "MESH" and any(
        modifier.type == "ARMATURE" and modifier.object == imported_rig
        for modifier in obj.modifiers)]
    if not imported_meshes:
        raise ValueError(f"{path.name}: reimport has no skinned mesh")
    expected = {name: (parent, matrix) for name, parent, matrix in expected_rest}
    actual = {bone.name: (bone.parent.name if bone.parent else None,
                          tuple(tuple(row) for row in bone.matrix_local))
              for bone in imported_rig.data.bones}
    if set(expected) != set(actual) or any(expected[name][0] != actual[name][0] for name in expected):
        raise ValueError(f"{path.name}: reimport bone hierarchy differs")
    matrix_delta = max(abs(expected[name][1][row][column] - actual[name][1][row][column])
                       for name in expected for row in range(4) for column in range(4))
    if matrix_delta > 0.00005:
        raise ValueError(f"{path.name}: reimport rest matrices changed ({matrix_delta:.8f})")
    bpy.context.view_layer.update()
    deformation = rest_error(imported_meshes)
    if deformation["maximumMetres"] > REST_BIND_TOLERANCE_M:
        raise ValueError(f"{path.name}: reimport REST deformation exceeds bind tolerance")
    material_ids = {mat.as_pointer() for obj in imported_meshes for mat in obj.data.materials if mat}
    if len(material_ids) != 1 or any(not obj.data.uv_layers for obj in imported_meshes):
        raise ValueError(f"{path.name}: reimport lost single material or UVs")
    weight_stats = [check_weights(obj) for obj in imported_meshes]
    uv_layers = [len(obj.data.uv_layers) for obj in imported_meshes]
    tri_count = sum(triangles(obj) for obj in imported_meshes)
    if tri_count > target:
        raise ValueError(f"{path.name}: reimport exceeds triangle budget")
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)
    return {"restDeformation": deformation, "maximumRestMatrixDelta": matrix_delta,
            "boneCount": len(actual), "meshCount": len(imported_meshes),
            "triangles": tri_count, "materialCount": len(material_ids),
            "uvLayers": uv_layers,
            "weights": weight_stats}


def export_glb(path, rig, meshes, ancestors):
    bpy.ops.object.select_all(action="DESELECT")
    selected = list(dict.fromkeys([*ancestors, rig, *meshes]))
    for obj in selected:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
        export_animations=False, export_skins=True, export_yup=True,
        export_cameras=False, export_lights=False, export_apply=False,
        export_all_influences=False)
    for obj in selected:
        obj.select_set(False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--expected-input-sha256", default=DEFAULT_SHA256)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source = args.input.resolve()
    output = args.output_dir.resolve()
    derived = (REPO / ".codex-derived").resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Run isolated Blender with --factory-startup --background")
    if not source.is_file() or source.suffix.lower() != ".glb":
        raise ValueError("Input must be an existing GLB")
    input_digest = sha256(source)
    if args.expected_input_sha256 and input_digest != args.expected_input_sha256:
        raise ValueError("Input GLB hash does not match expected source")
    if output.exists() or not output.is_relative_to(derived):
        raise ValueError("Output must be a new directory under .codex-derived")

    bpy.ops.import_scene.gltf(filepath=str(source))
    scene_objects = list(bpy.context.scene.objects)
    meshes = skin_meshes(scene_objects)
    armatures = {modifier.object for obj in meshes for modifier in obj.modifiers
                 if modifier.type == "ARMATURE" and modifier.object is not None}
    if not meshes or len(armatures) != 1:
        raise ValueError("Expected one or more skinned meshes bound to one armature")
    rig = next(iter(armatures))
    bone_names = [bone.name for bone in rig.data.bones]
    if not bone_names or len(set(bone_names)) != len(bone_names):
        raise ValueError("Source rig has no bones or duplicate bone names")
    material_ids = {material.as_pointer() for obj in meshes for material in obj.data.materials if material}
    if len(material_ids) != 1 or any(len(obj.data.uv_layers) < 1 for obj in meshes):
        raise ValueError("Source must have one shared material and UVs on every skinned mesh")
    for obj in meshes:
        check_weights(obj)
    rest_snapshot = [(bone.name, bone.parent.name if bone.parent else None,
                      tuple(tuple(row) for row in bone.matrix_local)) for bone in rig.data.bones]
    rig.data.pose_position = "REST"
    source_rest = rest_error(meshes)
    if source_rest["maximumMetres"] > REST_BIND_TOLERANCE_M:
        raise ValueError(f"Source REST deformation {source_rest['maximumMetres']:.6f}m exceeds "
                         f"{REST_BIND_TOLERANCE_M:.4f}m gate")
    source_bounds = bounds(meshes)
    source_triangles = sum(triangles(obj) for obj in meshes)
    if source_triangles <= TARGETS["near"]:
        raise ValueError("Source is already below near LOD budget")
    ancestors = []
    parent = rig.parent
    while parent:
        ancestors.append(parent)
        parent = parent.parent
    ancestors.reverse()
    collection = bpy.context.scene.collection
    lods, lod_stats = {}, {}
    for label, target in TARGETS.items():
        candidate, stats = make_lod(meshes, collection, rig, label, target)
        candidate_rest = rest_error(candidate)
        if candidate_rest["maximumMetres"] > REST_BIND_TOLERANCE_M:
            raise ValueError(f"{label} LOD REST deformation exceeds bind tolerance")
        lods[label] = candidate
        lod_stats[label] = stats | {"restDeformation": candidate_rest,
                                    "bounds": bounds(candidate),
                                    "sourceToCandidateSurfaceDistance": surface_distance(meshes, candidate),
                                    "candidateToSourceSurfaceDistance": surface_distance(candidate, meshes)}

    if rest_snapshot != [(bone.name, bone.parent.name if bone.parent else None,
                          tuple(tuple(row) for row in bone.matrix_local)) for bone in rig.data.bones]:
        raise ValueError("LOD creation changed source bone hierarchy or rest matrices")
    output.mkdir(parents=True)
    exports = {}
    for label, candidate in lods.items():
        path = output / f"ReplayXITripo_{label.title()}_Candidate.glb"
        export_glb(path, rig, candidate, ancestors)
        exports[label] = inspect_glb(path, bone_names)
        exports[label]["reimportValidation"] = validate_export_reimport(path, rest_snapshot, TARGETS[label])
        if exports[label]["triangles"] > TARGETS[label]:
            raise ValueError(f"{label} export exceeds its triangle budget")

    # Retain a reviewable Blender file with the source rig and both LODs.
    rig.data.pose_position = "REST"
    for obj in meshes:
        obj.hide_set(True)
        obj.hide_render = True
    for obj in lods["far"]:
        obj.hide_set(True)
        obj.hide_render = True
    for obj in lods["near"]:
        obj.hide_set(False)
        obj.hide_render = False
    blend_path = output / "ReplayXITripoLOD_Candidates.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), compress=True)
    report = {"schemaVersion": 1, "candidateOnly": True,
              "source": str(source), "sourceSHA256": input_digest,
              "sourceMeshNames": [obj.name for obj in meshes], "sourceTriangles": source_triangles,
              "sourceBounds": source_bounds, "sourceRestDeformation": source_rest,
              "boneCount": len(bone_names), "boneNames": bone_names,
              "materialCount": 1, "uvLayers": {obj.name: [layer.name for layer in obj.data.uv_layers]
                                                     for obj in meshes},
              "lods": lod_stats, "exports": exports,
              "skeletonHierarchyAndRestUnchanged": True,
              "outputs": {"blend": blend_path.name,
                          **{label: f"ReplayXITripo_{label.title()}_Candidate.glb" for label in lods}},
              "limitations": ["Offline topology candidates only; not runtime admitted",
                              "Near/far visual silhouette still needs review",
                              "Input rig has not passed animation QA; REST parity is not proof of good rigging"]}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_LOD_CANDIDATES " + json.dumps(report))


if __name__ == "__main__":
    main()
