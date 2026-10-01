#!/usr/bin/env python3
"""Fit one textured GLB to the fixed Replay XI skeleton; offline candidate only.

Run: blender --factory-startup --background --python this_file -- \
    --input player.glb --output-dir .codex-derived/Tripo-Candidate-01 [--yaw 0]
The output directory must be new. This does not replace a bundled player.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_football_player import create_actions  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / ".codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayerHome.glb"
MOTION = REPO / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"
SOURCE_SHA256 = "3c7f948ee3701d1837356390e4af0d09c39de4cc9356f3f09d8970266d183787"
MOTION_SHA256 = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mesh_objects(objects):
    return [obj for obj in objects if obj.type == "MESH" and len(obj.data.vertices)]


def points_in_rig(meshes, rig):
    inverse = rig.matrix_world.inverted()
    return [inverse @ obj.matrix_world @ vertex.co
            for obj in meshes for vertex in obj.data.vertices]


def bounds(points):
    return [[min(point[axis] for point in points), max(point[axis] for point in points)]
            for axis in range(3)]


def triangle_weights(point, vertices):
    a, b, c = vertices
    v0, v1, v2 = b - a, c - a, point - a
    d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
    denominator = d00 * d11 - d01 * d01
    if denominator <= 1e-20:
        return (1.0, 0.0, 0.0)
    d20, d21 = v2.dot(v0), v2.dot(v1)
    v = (d11 * d20 - d01 * d21) / denominator
    w = (d00 * d21 - d01 * d20) / denominator
    u = 1.0 - v - w
    values = [max(0.0, value) for value in (u, v, w)]
    total = sum(values)
    return tuple(value / total for value in values) if total else (1.0, 0.0, 0.0)


def arm_weights(point):
    """Constrain A-pose arms to their own chain; hand stays rigid at the wrist.

    These landmarks are candidate-specific Blender Z-up metres, not a general
    auto-rig. A narrow blend at the torso boundary avoids an abrupt sleeve seam.
    """
    x, z = abs(point.x), point.z
    if not .72 <= z <= 1.58:
        return {}, 0.0, None
    boundary = max(.19, .18 + (1.45 - z) * .30)
    blend = min(1.0, max(0.0, (x - boundary) / .045))
    # Keep the shirt/sleeve root tied partly to the original torso weights.
    # Full limb ownership starts below the upper-arm cuff.
    blend *= min(1.0, max(0.0, (1.50 - z) / .25))
    if blend <= 0:
        return {}, 0.0, None
    side = "L" if point.x >= 0 else "R"
    upper, forearm, hand = (f"Bip01 {side} {bone}" for bone in ("UpperArm", "Forearm", "Hand"))
    if z >= 1.30:
        result, zone = {upper: 1.0}, "upper"
    elif z >= 1.20:
        u = (z - 1.20) / .10
        result, zone = {upper: u, forearm: 1 - u}, "elbow"
    elif z >= 1.08:
        result, zone = {forearm: 1.0}, "forearm"
    elif z >= .98:
        f = (z - .98) / .10
        result, zone = {forearm: f, hand: 1 - f}, "wrist"
    else:
        result, zone = {hand: 1.0}, "hand"
    return result, blend, zone


def source_surface(meshes, rig, names):
    points, triangles, sections, weights = [], [], [], []
    inverse = rig.matrix_world.inverted()
    for obj in meshes:
        base = len(points)
        points.extend(inverse @ obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        for vertex in obj.data.vertices:
            row = {}
            for group in vertex.groups:
                name = obj.vertex_groups[group.group].name
                if group.weight > 0 and name in names:
                    row[name] = row.get(name, 0.0) + group.weight
            if not row:
                raise ValueError("Canonical source has an unweighted vertex")
            weights.append(row)
        obj.data.calc_loop_triangles()
        for face in obj.data.loop_triangles:
            triangles.append(tuple(base + index for index in face.vertices))
            sections.append("Head" if "Head" in obj.name else "Body")
    if not triangles:
        raise ValueError("Canonical source has no triangles")
    return points, triangles, sections, weights, BVHTree.FromPolygons(points, triangles, all_triangles=True)


def transfer(candidate, surface, rig, names):
    source_points, faces, sections, source_weights, tree = surface
    distances, risks, section_counts, arm_zones = [], Counter(), Counter(), Counter()
    for obj in candidate:
        for name in names:
            obj.vertex_groups.new(name=name)
        for vertex in obj.data.vertices:
            hit, _, face_index, distance = tree.find_nearest(vertex.co)
            if hit is None or face_index is None or not math.isfinite(distance):
                raise ValueError("No finite canonical surface match")
            face = faces[face_index]
            bary = triangle_weights(hit, [source_points[index] for index in face])
            row = Counter()
            for vertex_index, coefficient in zip(face, bary):
                for name, value in source_weights[vertex_index].items():
                    row[name] += coefficient * value
            constrained, blend, zone = arm_weights(vertex.co)
            if zone:
                arm_zones[zone] += 1
                for name in set(row) | set(constrained):
                    row[name] = (1 - blend) * row.get(name, 0.0) + blend * constrained.get(name, 0.0)
            strongest = sorted(row.items(), key=lambda item: (-item[1], item[0]))[:4]
            total = sum(weight for _, weight in strongest)
            if not math.isfinite(total) or total <= 0:
                raise ValueError("Weight transfer produced an empty row")
            for name, weight in strongest:
                if weight > 0:
                    obj.vertex_groups[name].add([vertex.index], weight / total, "REPLACE")
            distances.append(distance)
            section_counts[sections[face_index]] += 1
            if distance > 0.08:
                risks["over_8cm"] += 1
            if abs(vertex.co.x) > 0.08 and abs(hit.x) > 0.08 and vertex.co.x * hit.x < 0:
                risks["opposite_side"] += 1
            if vertex.co.z < 0.70 and sections[face_index] == "Head":
                risks["lower_body_to_head"] += 1
        obj.parent = rig
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Identity(4)
        modifier = obj.modifiers.new("ReplayXI_Candidate_Skin", "ARMATURE")
        modifier.object = rig
        modifier.use_deform_preserve_volume = False
    distances.sort()
    return {"nearestSurfaceMetres": {"median": distances[len(distances) // 2],
                "p95": distances[int((len(distances) - 1) * .95)], "max": distances[-1]},
            "matchedSections": dict(section_counts), "riskCounts": dict(risks),
            "armConstraintZones": dict(arm_zones)}


def audit_candidate(meshes, rig, actions):
    vertices = triangles = max_influences = 0
    max_sum_error = 0.0
    rest_points = []
    for obj in meshes:
        obj.data.calc_loop_triangles()
        vertices += len(obj.data.vertices)
        triangles += len(obj.data.loop_triangles)
        for vertex in obj.data.vertices:
            rest_points.append(vertex.co.copy())
            active = [group for group in vertex.groups if group.weight > 0]
            if not active or any(not math.isfinite(group.weight) for group in active):
                raise ValueError("Missing or nonfinite skin weight")
            max_influences = max(max_influences, len(active))
            max_sum_error = max(max_sum_error, abs(sum(group.weight for group in active) - 1))
    if max_influences > 4 or max_sum_error > 1e-5:
        raise ValueError("Candidate exceeds four normalized influences")
    if any(not math.isfinite(value) for point in rest_points for value in point):
        raise ValueError("Nonfinite rest geometry")
    samples = []
    for label, action, frame in (("idle_start", actions["idle"], 1),
                                 ("idle_end", actions["idle"], 83),
                                 ("run_start", actions["run"], 1),
                                 ("run_mid", actions["run"], 10),
                                 ("run_end", actions["run"], 19)):
        rig.animation_data.action = action
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        z_values = []
        for obj in meshes:
            evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            deformed = evaluated.to_mesh()
            try:
                positions = [evaluated.matrix_world @ point.co for point in deformed.vertices]
                if len(positions) != len(obj.data.vertices) or any(
                        not math.isfinite(value) for point in positions for value in point):
                    raise ValueError("Nonfinite or changed evaluated geometry")
                z_values.extend(point.z for point in positions)
            finally:
                evaluated.to_mesh_clear()
        samples.append({"pose": label, "frame": frame, "minimumZ": min(z_values),
                        "maximumZ": max(z_values)})
    rig.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(1)
    return {"vertices": vertices, "triangles": triangles,
            "maximumInfluences": max_influences, "maximumWeightSumError": max_sum_error,
            "restBoundsRigLocal": bounds(rest_points), "deformationSamples": samples}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--yaw", type=float, default=0.0, help="Explicit yaw in degrees around Blender +Z")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output_dir.resolve()
    input_path = args.input.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated --factory-startup --background Blender")
    if output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Output must be a NEW directory under .codex-derived")
    if input_path.suffix.lower() != ".glb" or not input_path.is_file():
        raise ValueError("Input must be an existing GLB")
    if not math.isfinite(args.yaw):
        raise ValueError("Yaw must be finite")
    before = {"input": digest(input_path), "canonicalHomeGLB": digest(SOURCE),
              "canonicalMotion": digest(MOTION)}
    if before["canonicalHomeGLB"] != SOURCE_SHA256 or before["canonicalMotion"] != MOTION_SHA256:
        raise ValueError("Canonical source hash changed")
    motion = json.loads(MOTION.read_text())
    if len(motion["joints"]) != 80:
        raise ValueError("Expected 80 canonical joints")
    names = [joint["sourceName"] for joint in motion["joints"]]
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source_objects = list(bpy.context.selected_objects)
    rig = next((obj for obj in source_objects if obj.type == "ARMATURE"), None)
    source_meshes = [obj for obj in mesh_objects(source_objects)
                     if obj.name.startswith("ReplayXI_Home_") and
                     obj.name.rsplit("_", 1)[-1] in ("Body", "Head")]
    if rig is None or len(rig.data.bones) != 80 or set(rig.data.bones.keys()) != set(names) or not source_meshes:
        raise ValueError("Canonical GLB import lost its rig or meshes")
    parent_names = {bone.name: bone.parent.name if bone.parent else None for bone in rig.data.bones}
    for joint in motion["joints"]:
        expected = names[joint["parentIndex"]] if joint["parentIndex"] >= 0 else None
        if parent_names[joint["sourceName"]] != expected:
            raise ValueError("Canonical GLB hierarchy differs from motion")
    rest_snapshot = {bone.name: tuple(tuple(row) for row in bone.matrix_local)
                     for bone in rig.data.bones}
    source = source_surface(source_meshes, rig, set(names))
    source_bounds = bounds(source[0])
    source_height = source_bounds[2][1] - source_bounds[2][0]
    if not 1.4 <= source_height <= 2.1:
        raise ValueError("Canonical source has unexpected height")
    prior = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(input_path))
    imported = mesh_objects(set(bpy.data.objects) - prior)
    if not imported:
        raise ValueError("Input GLB has no mesh")
    candidate = []
    for index, obj in enumerate(imported):
        clone = obj.copy()
        clone.data = obj.data.copy()
        bpy.context.scene.collection.objects.link(clone)
        clone.name = f"ReplayXI_Tripo_Candidate_{index:02d}"
        clone.parent = None
        for modifier in list(clone.modifiers):
            clone.modifiers.remove(modifier)
        for group in list(clone.vertex_groups):
            clone.vertex_groups.remove(group)
        clone.data.transform(obj.matrix_world)
        candidate.append(clone)
        obj.hide_set(True)
        obj.hide_render = True
    yaw = Matrix.Rotation(math.radians(args.yaw), 4, "Z")
    raw = [yaw @ vertex.co for obj in candidate for vertex in obj.data.vertices]
    raw_bounds = bounds(raw)
    height = raw_bounds[2][1] - raw_bounds[2][0]
    if not 0.2 <= height <= 100 or any(not math.isfinite(value) for row in raw_bounds for value in row):
        raise ValueError("Input has invalid human-scale bounds")
    scale = source_height / height
    source_centre = [(row[0] + row[1]) / 2 for row in source_bounds[:2]]
    raw_centre = [(row[0] + row[1]) / 2 for row in raw_bounds[:2]]
    for obj in candidate:
        for vertex in obj.data.vertices:
            point = yaw @ vertex.co
            vertex.co = Vector(((point.x - raw_centre[0]) * scale + source_centre[0],
                                (point.y - raw_centre[1]) * scale + source_centre[1],
                                (point.z - raw_bounds[2][0]) * scale + source_bounds[2][0]))
        obj.data.update()
    transfer_report = transfer(candidate, source, rig, names)
    # Existing source rest is authoritative; actions address its bones by name.
    actions = create_actions(rig, motion)
    audit = audit_candidate(candidate, rig, actions)
    if rest_snapshot != {bone.name: tuple(tuple(row) for row in bone.matrix_local)
                         for bone in rig.data.bones}:
        raise ValueError("Candidate work changed canonical rest bones")
    output.mkdir(parents=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig, *candidate]:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    glb = output / "ReplayXITripoCandidate.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                              export_animations=False, export_skins=True, export_yup=True,
                              export_cameras=False, export_lights=False, export_apply=False,
                              export_all_influences=False)
    blend = output / "ReplayXITripoCandidate.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    after = {"input": digest(input_path), "canonicalHomeGLB": digest(SOURCE),
             "canonicalMotion": digest(MOTION)}
    if before != after:
        raise ValueError("Input or canonical source changed during the build")
    report = {"schemaVersion": 1, "candidateOnly": True,
              "input": str(input_path), "inputSHA256": before["input"],
              "canonicalHomeGLBSHA256": before["canonicalHomeGLB"],
              "canonicalMotionSHA256": before["canonicalMotion"],
              "yawDegrees": args.yaw, "scaleToCanonicalHeight": scale,
              "originalBounds": raw_bounds, "canonicalBoundsRigLocal": source_bounds,
              "meshObjects": len(candidate), "materialSlots": sum(len(obj.data.materials) for obj in candidate),
              "uvLayers": [len(obj.data.uv_layers) for obj in candidate],
              "rigJointCount": len(rig.data.bones), "rigRestUnchanged": True,
              "actionsInBlend": {key: action.name for key, action in actions.items()},
              "transfer": transfer_report, "audit": audit,
              "outputs": {"blend": blend.name, "glb": glb.name,
                          "blendSHA256": digest(blend), "glbSHA256": digest(glb)},
              "limits": "Nearest-surface weights are an offline candidate; inspect joints, seams, pose and texture before USDZ or runtime admission."}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_CANDIDATE " + json.dumps(report))


if __name__ == "__main__":
    main()
