"""Shared offline mesh/skin helpers for Player Diversity 172."""
from __future__ import annotations

import hashlib
import math
from pathlib import Path

import bpy
from mathutils.bvhtree import BVHTree

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "Assets/ReplayXI/PlayerDiversity171/Source/player-a-hd-source.glb"
MOTION = REPO / "Assets/ReplayXI/TripoFootballer/Blender/ReplayXITripoFootballMotion.blend"
SOURCE_SHA = "2b25690666877f3e090d5ce4e5d8e30702d6d02f497e5511de4ba9d3df1dcfc3"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def decimate(obj, target):
    current = triangles(obj)
    ratio = min(1.0, target / current * .98)
    modifier = obj.modifiers.new("Diversity172SurfaceLOD", "DECIMATE")
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    while obj.modifiers.find(modifier.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    return {"sourceTriangles": current, "ratio": ratio, "triangles": triangles(obj),
            "vertices": len(obj.data.vertices)}


def weights_stats(obj):
    maxima, missing, maximum_error, excess = 0, 0, 0.0, 0
    for vertex in obj.data.vertices:
        active = sorted(((g.group, g.weight) for g in vertex.groups if g.weight > 0),
                        key=lambda item: -item[1])
        if not active:
            missing += 1
            continue
        excess += len(active) > 4
        kept = active[:4]
        total = sum(weight for _, weight in kept)
        if not math.isfinite(total) or total <= 0:
            raise ValueError("Invalid skin weight")
        for index, _ in active:
            obj.vertex_groups[index].remove([vertex.index])
        for index, weight in kept:
            obj.vertex_groups[index].add([vertex.index], weight / total, "REPLACE")
        maxima = max(maxima, len(kept))
        maximum_error = max(maximum_error, abs(sum(weight / total for _, weight in kept) - 1))
    return {"maxInfluences": maxima, "missingVertices": missing,
            "truncatedVertices": excess, "maxWeightSumError": maximum_error}


def barycentric(point, a, b, c):
    v0, v1, v2 = b - a, c - a, point - a
    d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
    d20, d21 = v2.dot(v0), v2.dot(v1)
    denominator = d00 * d11 - d01 * d01
    if abs(denominator) < 1e-15:
        return (1.0, 0.0, 0.0)
    v = (d11 * d20 - d01 * d21) / denominator
    w = (d00 * d21 - d01 * d20) / denominator
    return (1 - v - w, v, w)


def transfer_weights(reference, target, posed_reference_points):
    reference.data.calc_loop_triangles()
    faces = [tuple(triangle.vertices) for triangle in reference.data.loop_triangles]
    tree = BVHTree.FromPolygons(posed_reference_points, faces, all_triangles=True)
    groups = {group.index: target.vertex_groups.new(name=group.name)
              for group in reference.vertex_groups}
    reference_weights = [{item.group: item.weight for item in vertex.groups}
                         for vertex in reference.data.vertices]
    distances = []
    for vertex in target.data.vertices:
        hit, _, face_index, distance = tree.find_nearest(target.matrix_world @ vertex.co)
        if hit is None:
            raise ValueError("No posed Tripo surface match")
        distances.append(distance)
        vertex_ids = faces[face_index]
        factors = barycentric(hit, *(posed_reference_points[i] for i in vertex_ids))
        combined = {}
        for vertex_id, factor in zip(vertex_ids, factors):
            for group, weight in reference_weights[vertex_id].items():
                combined[group] = combined.get(group, 0) + weight * factor
        kept = sorted(((group, weight) for group, weight in combined.items() if weight > 0),
                      key=lambda item: -item[1])[:4]
        total = sum(weight for _, weight in kept)
        if total <= 0:
            raise ValueError("Unweighted target vertex")
        for group, weight in kept:
            groups[group].add([vertex.index], weight / total, "REPLACE")
    distances.sort()
    return {"meanDistanceMetres": sum(distances) / len(distances),
            "p95DistanceMetres": distances[int(.95 * (len(distances) - 1))],
            "maxDistanceMetres": distances[-1]}


def bounds(obj, evaluated=False):
    if evaluated:
        active = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = active.to_mesh()
        points = [active.matrix_world @ vertex.co for vertex in mesh.vertices]
        active.to_mesh_clear()
    else:
        points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return [[min(point[i] for point in points), max(point[i] for point in points)] for i in range(3)]


def export(path, rig, mesh, with_motion=False):
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    mesh.hide_set(False)
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=with_motion,
                              export_animation_mode="NLA_TRACKS", export_nla_strips=True,
                              export_def_bones=True, export_yup=True, export_materials="EXPORT")
