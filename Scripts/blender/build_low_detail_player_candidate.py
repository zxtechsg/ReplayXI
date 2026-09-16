#!/usr/bin/env python3
"""Loop102: isolated MIT Rocketbox low-detail feasibility, never runtime admission.

Append the audited library, decimate separate copied meshes in rest space, retain
the complete source skeleton, and compare identical native pose samples. The
source .blend and bundled USDZ/motion/contact files are hash-checked, never saved.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_football_player import USD_TO_BLENDER, flat_material, link_object, matrix, read_accessor
from render_runtime_player_poses import read_samples

REPOSITORY = Path(__file__).resolve().parents[2]
EXPECTED = {
    ".codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayers.blend":
        "58bfaa3086b64f6d0ddfea251241c0cb0f83631455ffead079d6e7be2f85de01",
    ".codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayerHome.glb":
        "3c7f948ee3701d1837356390e4af0d09c39de4cc9356f3f09d8970266d183787",
    "ReplayXI/Resources/Players/ReplayXIRocketboxAthlete.usdz":
        "7cfb694888f111928643e8aca7041d21925f5d55f3f5adbd353a972ca255e772",
    "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json":
        "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4",
    "ReplayXI/Resources/Players/ReplayXIRocketboxContactSurface.json":
        "71eb134afa27eac0c23500afbd038dd11594a2b5ad30a5a178b303305a49c3ca",
}


def checked_sources():
    result = {}
    for relative, expected in EXPECTED.items():
        digest = hashlib.sha256((REPOSITORY / relative).read_bytes()).hexdigest()
        if digest != expected:
            raise ValueError(f"Protected source hash changed: {relative}")
        result[relative] = digest
    return result


def mesh_info(obj):
    obj.data.calc_loop_triangles()
    maximum_influences = 0
    maximum_sum_error = 0.0
    used_groups = set()
    for vertex in obj.data.vertices:
        weights = [group for group in vertex.groups if group.weight > 0]
        if not weights or any(not math.isfinite(group.weight) for group in weights):
            raise ValueError("Missing/nonfinite candidate skin weights")
        maximum_influences = max(maximum_influences, len(weights))
        maximum_sum_error = max(maximum_sum_error, abs(sum(group.weight for group in weights) - 1))
        used_groups.update(obj.vertex_groups[group.group].name for group in weights)
    return {
        "vertices": len(obj.data.vertices), "triangles": len(obj.data.loop_triangles),
        "materials": len(obj.data.materials), "uvLayers": len(obj.data.uv_layers),
        "maximumInfluences": maximum_influences, "maximumWeightSumError": maximum_sum_error,
        "usedBoneCount": len(used_groups),
    }


def uv_per_vertex(obj):
    result = defaultdict(set)
    for loop in obj.data.loops:
        result[loop.vertex_index].add(tuple(obj.data.uv_layers.active.data[loop.index].uv))
    return result


def seam_signature(obj, indices):
    uvs = uv_per_vertex(obj)
    result = Counter()
    for index in indices:
        vertex = obj.data.vertices[index]
        weights = tuple(sorted((obj.vertex_groups[group.group].name, group.weight)
                               for group in vertex.groups if group.weight > 0))
        result[(tuple(vertex.co), tuple(sorted(uvs[index])), weights)] += 1
    return result


def reduce_mesh(source, collection):
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = source.name.replace("Home", "Low102")
    collection.objects.link(obj)
    obj["replayxi_candidate_only"] = True
    is_body = source.name.endswith("Body")
    coincident = defaultdict(list)
    for vertex in source.data.vertices:
        coincident[tuple(vertex.co)].append(vertex.index)
    uvs = uv_per_vertex(source)
    split = {point: indices for point, indices in coincident.items()
             if len(indices) > 1 and len(set().union(*(uvs[index] for index in indices))) > 1}
    # Pin only observed coincident garment seams at the crotch/shoulders.
    # These are already distinct UV islands; never weld them or their weights.
    protected = {index for point, indices in split.items()
                 if is_body and ((abs(point[0]) < 0.035 and 0.64 < point[2] < 1.02)
                                 or (0.15 < abs(point[0]) < 0.35 and 1.35 < point[2] < 1.60))
                 for index in indices}
    protected_points = {tuple(source.data.vertices[index].co) for index in protected}
    expected_seams = seam_signature(source, protected)
    group_name = None
    if protected:
        group = obj.vertex_groups.new(name="Loop102_DecimationAllowed")
        group_name = group.name
        group.add([index for index in range(len(obj.data.vertices)) if index not in protected], 1, "REPLACE")
    # Evaluate only the rest-space modifier; the source armature remains live.
    modifier = obj.modifiers.new("Loop102_RestSpace_Decimate", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = 0.30 if is_body else 0.20
    modifier.use_collapse_triangulate = True
    if group_name is not None:
        modifier.vertex_group = group_name
        modifier.vertex_group_factor = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    while obj.modifiers.find(modifier.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    if group_name is not None:
        obj.vertex_groups.remove(obj.vertex_groups[group_name])
    truncated = 0
    discarded = 0.0
    for vertex in obj.data.vertices:
        if tuple(vertex.co) in protected_points:
            continue  # Retain original bit-exact source weights at pinned seams.
        groups = sorted([(group.group, group.weight) for group in vertex.groups if group.weight > 0],
                        key=lambda pair: (-pair[1], pair[0]))
        kept = groups[:4]
        if len(groups) > 4:
            truncated += 1
            discarded = max(discarded, sum(weight for _, weight in groups[4:]))
        total = sum(weight for _, weight in kept)
        if total <= 0 or not math.isfinite(total):
            raise ValueError("Decimation lost a skin binding")
        for group, _ in groups:
            obj.vertex_groups[group].remove([vertex.index])
        for group, weight in kept:
            obj.vertex_groups[group].add([vertex.index], weight / total, "REPLACE")
    stats = mesh_info(obj)
    if stats["maximumInfluences"] > 4 or stats["maximumWeightSumError"] > 0.000001:
        raise ValueError("Candidate skin weights failed bounded admission")
    retained_indices = [vertex.index for vertex in obj.data.vertices if tuple(vertex.co) in protected_points]
    actual_seams = seam_signature(obj, retained_indices)
    if expected_seams - actual_seams:
        raise ValueError("Selected garment seam positions/UVs/weights did not survive exactly")
    stats.update({"weightTruncatedVertices": truncated, "maximumDiscardedWeight": discarded,
                  "collapseRatio": 0.30 if is_body else 0.20,
                  "sourceUVSplitGroups": len(split), "protectedSeamVertices": len(protected),
                  "protectedSeamPositions": len(protected_points),
                  "protectedSeamPositionUVAndWeightsExact": True})
    return obj, stats


def apply_pose(rig, root, motion, rest_local, sample):
    root.location.z = sample["groundOffset"]
    for index, joint in enumerate(motion["joints"]):
        target = matrix(sample["translations"][index], sample["rotations"][index], sample["scales"][index])
        if joint["parentIndex"] < 0:
            target = USD_TO_BLENDER @ target
        bone = rig.pose.bones[joint["sourceName"]]
        bone.rotation_mode = "QUATERNION"
        bone.matrix_basis = rest_local[index].inverted() @ target
    bpy.context.view_layer.update()


def evaluated_geometry(obj):
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        mesh.calc_loop_triangles()
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        triangles = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
        if any(not math.isfinite(value) for point in points for value in point):
            raise ValueError("Deformed candidate contains a nonfinite point")
        return points, triangles
    finally:
        evaluated.to_mesh_clear()


def distances(points, target_points, target_triangles):
    tree = BVHTree.FromPolygons(target_points, target_triangles, all_triangles=True)
    values = sorted(tree.find_nearest(point)[3] for point in points)
    return {"mean": sum(values) / len(values), "p95": values[int((len(values) - 1) * 0.95)],
            "maximum": values[-1]}


def export_glb(path, rig, root, candidate):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root, rig, *candidate]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, use_active_scene=True,
        export_animations=False, export_skins=True, export_yup=True,
        export_extras=True, export_cameras=False, export_lights=False,
        export_apply=False, export_all_influences=False)
    payload = path.read_bytes()
    magic, version, length, json_length, kind = struct.unpack_from("<IIIII", payload)
    if (magic, version, length, kind) != (0x46546C67, 2, len(payload), 0x4E4F534A):
        raise ValueError("Invalid generated GLB")
    manifest = json.loads(payload[20:20 + json_length])
    binary_length, binary_type = struct.unpack_from("<II", payload, 20 + json_length)
    if binary_type != 0x004E4942:
        raise ValueError("Candidate GLB has no binary buffer")
    binary = payload[28 + json_length:28 + json_length + binary_length]
    primitives = [primitive for mesh in manifest["meshes"] for primitive in mesh["primitives"]]
    vertices = sum(manifest["accessors"][p["attributes"]["POSITION"]]["count"] for p in primitives)
    triangles = sum(manifest["accessors"][p["indices"]]["count"] // 3 for p in primitives)
    skin = manifest["skins"]
    if len(skin) != 1 or len(skin[0]["joints"]) != 80 or len(primitives) != 2:
        raise ValueError("Candidate export lost its single complete skeleton/two sections")
    maximum_weight_error = 0.0
    for primitive in primitives:
        attrs = primitive["attributes"]
        for semantic in ("POSITION", "NORMAL", "TEXCOORD_0", "WEIGHTS_0"):
            values = read_accessor(manifest, binary, attrs[semantic])
            if any(not math.isfinite(value) for row in values for value in row):
                raise ValueError("Candidate export contains nonfinite geometry or skin data")
        for joints, weights in zip(read_accessor(manifest, binary, attrs["JOINTS_0"]),
                                   read_accessor(manifest, binary, attrs["WEIGHTS_0"])):
            if len(weights) != 4 or any(not 0 <= joint < 80 for joint in joints) or any(weight < 0 for weight in weights):
                raise ValueError("Candidate export has invalid joint indices/influences")
            maximum_weight_error = max(maximum_weight_error, abs(sum(weights) - 1))
    if maximum_weight_error > 0.000001:
        raise ValueError("Exported weights are not normalised")
    source_glb = REPOSITORY / ".codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayerHome.glb"
    source_payload = source_glb.read_bytes()
    source_json_length = struct.unpack_from("<I", source_payload, 12)[0]
    source_manifest = json.loads(source_payload[20:20 + source_json_length])
    source_names = [source_manifest["nodes"][index]["name"] for index in source_manifest["skins"][0]["joints"]]
    names = [manifest["nodes"][index]["name"] for index in skin[0]["joints"]]
    return {"vertices": vertices, "triangles": triangles, "meshCount": len(manifest["meshes"]),
            "materialCount": len(manifest["materials"]), "boneCount": len(skin[0]["joints"]),
            "boneNames": names, "jointOrderMatchesSourceGLB": names == source_names,
            "maximumExportedWeightSumError": maximum_weight_error,
            "skinAttributes": [sorted(p["attributes"]) for p in primitives],
            "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest(),
            "fitsInitialGeometryTarget": vertices <= 1400 and triangles <= 1800,
            "fitsExistingFarCeilings": vertices <= 1800 and triangles <= 2500}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--poses", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated --factory-startup --background Blender")
    if not output.is_relative_to((REPOSITORY / ".codex-derived").resolve()) or output.exists():
        raise ValueError("Use a NEW derived directory")
    protected_before = checked_sources()
    motion = json.loads((REPOSITORY / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json").read_text())
    samples = read_samples(args.poses, 80)
    selected = [next(sample for sample in samples if sample["name"] == name)
                for name in ("run", "cut-right", "pass-contact")]
    idle = dict(next(clip for clip in motion["clips"] if clip["id"] == "idle")["frames"][0])
    idle.update({"name": "source-idle", "groundOffset": -motion["geometry"]["restMinY"]})
    selected.insert(0, idle)
    library = REPOSITORY / next(iter(EXPECTED))
    with bpy.data.libraries.load(str(library), link=False) as (data_from, data_to):
        if "ReplayXI_Home" not in data_from.collections:
            raise ValueError("Audited Home collection missing")
        data_to.collections = ["ReplayXI_Home"]
    collection = data_to.collections[0]
    scene = bpy.data.scenes.new("ReplayXI_Low102_Feasibility")
    bpy.context.window.scene = scene
    scene.collection.children.link(collection)
    root = next(obj for obj in collection.objects if obj.name == "ReplayXI_Home_Root")
    rig = next(obj for obj in collection.objects if obj.name == "ReplayXI_Home_Rig")
    rig.animation_data_clear()
    for obj in collection.objects:
        if obj.type == "FONT":
            obj.hide_render = True
            obj.hide_set(True)
    original = [bpy.data.objects[f"ReplayXI_Home_{section}"] for section in ("Body", "Head")]
    source_stats = {section: mesh_info(obj) for section, obj in zip(("Body", "Head"), original)}
    rest_snapshot = [(bone.name, bone.parent.name if bone.parent else None,
                      [list(row) for row in bone.matrix_local]) for bone in rig.data.bones]
    # Blender's stored bone iteration order differs from the motion sidecar.
    # Preserve that source order, but resolve every pose explicitly by name.
    if len(rig.data.bones) != 80 or set(rig.data.bones.keys()) != {joint["sourceName"] for joint in motion["joints"]}:
        raise ValueError("Library joint names no longer match admitted motion")
    rest_local = []
    for joint in motion["joints"]:
        bone = rig.data.bones[joint["sourceName"]]
        expected_parent = motion["joints"][joint["parentIndex"]]["sourceName"] if joint["parentIndex"] >= 0 else None
        if (bone.parent.name if bone.parent else None) != expected_parent:
            raise ValueError("Library joint hierarchy no longer matches admitted motion")
        rest_local.append(bone.parent.matrix_local.inverted() @ bone.matrix_local
                          if bone.parent else bone.matrix_local.copy())
    rig.data.pose_position = "REST"
    candidate, candidate_stats = [], {}
    for section, source in zip(("Body", "Head"), original):
        obj, stats = reduce_mesh(source, collection)
        candidate.append(obj)
        candidate_stats[section] = stats
    rig.data.pose_position = "POSE"
    if rest_snapshot != [(bone.name, bone.parent.name if bone.parent else None,
                          [list(row) for row in bone.matrix_local]) for bone in rig.data.bones]:
        raise ValueError("Candidate changed source skeleton/rest transforms")
    output.mkdir(parents=True)
    notice = (REPOSITORY / "ReplayXI/Resources/Players/LICENSE-ROCKETBOX-MIT.txt").read_text()
    (output / "LICENSE-ROCKETBOX-MIT.txt").write_text(notice)
    bpy.data.texts.new("LOOP102-LICENSE-ROCKETBOX-MIT.txt").write(notice)
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    exported = export_glb(output / "ReplayXILow102Home.glb", rig, root, candidate)
    if exported["boneNames"] != [joint["sourceName"] for joint in motion["joints"]]:
        exported["motionOrderPreservedInGLB"] = False
    else:
        exported["motionOrderPreservedInGLB"] = True
    # Save only this new derivative. The original library path is never opened/saved.
    for obj in original:
        obj.hide_render = True
        obj.hide_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "ReplayXILow102Candidate.blend"), compress=True)
    for obj in original:
        obj.hide_set(False)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 640, 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world = bpy.data.worlds.new("Low102_World")
    scene.world.color = (0.16, 0.16, 0.16)
    scene.view_settings.view_transform = "AgX"
    qa = bpy.data.collections.new("Low102_QA")
    scene.collection.children.link(qa)
    camera = link_object(qa, "Low102_Camera", bpy.data.cameras.new("Low102_Camera"))
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
        light.data.energy, light.data.size, light.data.shape = energy, size, "DISK"
    floor = bpy.data.meshes.new("Low102_Floor")
    floor.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    floor.materials.append(flat_material("Low102_Grass", (0.035, 0.11, 0.065, 1)))
    link_object(qa, "Low102_Floor", floor)
    comparisons = []
    for sample in selected:
        apply_pose(rig, root, motion, rest_local, sample)
        row = {"name": sample["name"], "poseSource": "source idle clip" if sample["name"] == "source-idle" else "native Swift export", "sections": {}}
        for section, full, low in zip(("Body", "Head"), original, candidate):
            source_points, source_triangles = evaluated_geometry(full)
            points, triangles = evaluated_geometry(low)
            row["sections"][section] = {
                "sourceMinimumZ": min(point.z for point in source_points),
                "candidateMinimumZ": min(point.z for point in points),
                "candidateMaximumZ": max(point.z for point in points),
                "sourceToCandidateMetres": distances(source_points, points, triangles),
                "candidateToSourceMetres": distances(points, source_points, source_triangles),
            }
        if args.render:
            for label, visible, hidden in [("source", original, candidate), ("candidate", candidate, original)]:
                for obj in visible: obj.hide_render = False
                for obj in hidden: obj.hide_render = True
                scene.render.filepath = str(output / f"{sample['name']}-{label}.png")
                bpy.ops.render.render(write_still=True)
        comparisons.append(row)
    # Exact pose replay, measured on the candidate geometry, without contact repair.
    repeat = selected[1]
    apply_pose(rig, root, motion, rest_local, repeat)
    before = [[tuple(point) for point in evaluated_geometry(obj)[0]] for obj in candidate]
    for sample in reversed(selected): apply_pose(rig, root, motion, rest_local, sample)
    apply_pose(rig, root, motion, rest_local, repeat)
    after = [[tuple(point) for point in evaluated_geometry(obj)[0]] for obj in candidate]
    protected_after = checked_sources()
    report = {
        "candidateOnly": True, "blenderVersion": bpy.app.version_string,
        "license": "MIT Microsoft Rocketbox; original Replay XI neutral kit",
        "sourceHashesBefore": protected_before, "sourceHashesAfter": protected_after,
        "nativePoseAttachment": str(args.poses.resolve()),
        "poseAttachmentSHA256": hashlib.sha256(args.poses.read_bytes()).hexdigest(),
        "original": source_stats, "candidate": candidate_stats, "export": exported,
        "skeletonRestOrderAndMatricesUnchanged": True,
        "exactRepeatedPoseGeometry": before == after, "comparisons": comparisons,
        "limitations": ["Not imported or admitted by RealityKit", "80-bone CPU cost unchanged",
                        "Old contact surface is not calibrated for this mesh", "No hardware frame-time claim",
                        "Existing body/head textures and normal maps retained", "Only one body and home palette"]
    }
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_LOW102 " + json.dumps(report))


if __name__ == "__main__":
    main()
