#!/usr/bin/env python3
"""Read-only topology and run-pose audit for the Tripo jersey/shorts seam."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import statistics
import sys

import bpy
from mathutils.bvhtree import BVHTree

REPO = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def components(mesh):
    parent = list(range(len(mesh.data.vertices)))

    def root(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for polygon in mesh.data.polygons:
        first = polygon.vertices[0]
        for index in polygon.vertices[1:]:
            parent[root(index)] = root(first)
    groups = {}
    for polygon in mesh.data.polygons:
        groups.setdefault(root(polygon.vertices[0]), []).append(polygon.index)
    return sorted(groups.values(), key=len, reverse=True)


def component_report(mesh, face_ids):
    vertices = sorted({index for face in face_ids for index in mesh.data.polygons[face].vertices})
    coords = [mesh.data.vertices[index].co for index in vertices]
    bounds = [[min(point[axis] for point in coords), max(point[axis] for point in coords)] for axis in range(3)]
    image = bpy.data.images["tripo_image_e7d9fe2a_0"]
    uvs = mesh.data.uv_layers.active.data
    samples = []
    for face in face_ids[::max(1, len(face_ids) // 24)]:
        loop = mesh.data.polygons[face].loop_start
        coordinate = uvs[loop].uv
        x = min(image.size[0] - 1, max(0, round(coordinate.x * (image.size[0] - 1))))
        y = min(image.size[1] - 1, max(0, round(coordinate.y * (image.size[1] - 1))))
        pixel = (y * image.size[0] + x) * 4
        samples.append([round(image.pixels[pixel + channel], 3) for channel in range(3)])
    return {"faces": len(face_ids), "vertices": len(vertices), "boundsXYZ": bounds,
            "sampleRGB": samples[:24], "firstFace": face_ids[0], "firstVertex": vertices[0]}


def hem_vertices(mesh, torso_faces):
    edges = Counter()
    for face in torso_faces:
        polygon = mesh.data.polygons[face]
        indices = polygon.vertices
        for position in range(len(indices)):
            edges[tuple(sorted((indices[position], indices[(position + 1) % len(indices)])))] += 1
    boundary = {index for edge, count in edges.items() if count == 1 for index in edge}
    return sorted(index for index in boundary if mesh.data.vertices[index].co.z < .57)


def collision_frames(mesh, rig, torso_faces, shorts_faces, hem):
    actions = {"idle": bpy.data.actions["ReplayXI_Tripo_FBX_Idle"],
               "run": bpy.data.actions["ReplayXI_Tripo_FBX_Run"]}
    garment_faces = [face for face in torso_faces
                     if min(mesh.data.vertices[index].co.z for index in mesh.data.polygons[face].vertices) < .68]
    shorts_vertices = sorted({index for face in shorts_faces for index in mesh.data.polygons[face].vertices})
    waistband = [index for index in shorts_vertices if mesh.data.vertices[index].co.z > .515]
    names = {group.index: group.name for group in mesh.vertex_groups}
    waistband_weights = []
    for index in waistband:
        vertex = mesh.data.vertices[index]
        weights = {names[item.group]: item.weight for item in vertex.groups}
        waistband_weights.append({"index": index, "restXYZ": list(vertex.co),
                                  "thighWeight": sum(value for name, value in weights.items() if name.endswith("UpLeg")),
                                  "hipsWeight": weights.get("mixamorig:Hips", 0),
                                  "spineWeight": weights.get("mixamorig:Spine", 0)})
    data = []
    rig.data.pose_position = "POSE"
    for clip, frames in (("idle", (1,)), ("run", range(1, 20))):
        rig.animation_data.action = actions[clip]
        for frame in frames:
            bpy.context.scene.frame_set(frame)
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).data
            points = [vertex.co.copy() for vertex in evaluated.vertices]
            top = BVHTree.FromPolygons(points,
                                       [list(mesh.data.polygons[face].vertices) for face in garment_faces],
                                       all_triangles=False, epsilon=0)
            bottom = BVHTree.FromPolygons(points,
                                          [list(mesh.data.polygons[face].vertices) for face in shorts_faces],
                                          all_triangles=False, epsilon=0)
            overlaps = top.overlap(bottom)
            front_overlaps = 0
            side_overlaps = [0, 0]
            for local_face, _ in overlaps:
                polygon = mesh.data.polygons[garment_faces[local_face]]
                center = sum((points[index] for index in polygon.vertices), points[polygon.vertices[0]] * 0) / len(polygon.vertices)
                if center.y < 0:
                    front_overlaps += 1
                side_overlaps[0 if center.x < 0 else 1] += 1
            distances = []
            for index in hem:
                point = points[index]
                nearest, normal, _, distance = bottom.find_nearest(point)
                if nearest is None:
                    continue
                signed = (point - nearest).dot(normal)
                distances.append((index, signed, distance, point.x, point.y, point.z))
            front = [row for row in distances if row[4] < 0]
            front_sorted = sorted(front, key=lambda row: row[1])
            waist_pose = []
            for side in (-1, 1):
                side_front = [points[index] for index in waistband
                              if mesh.data.vertices[index].co.x * side > 0
                              and mesh.data.vertices[index].co.y < 0]
                waist_pose.append({"side": "leftX" if side < 0 else "rightX",
                                   "count": len(side_front),
                                   "minZ": min(point.z for point in side_front) if side_front else None,
                                   "maxZ": max(point.z for point in side_front) if side_front else None,
                                   "medianZ": statistics.median(point.z for point in side_front) if side_front else None,
                                   "minY": min(point.y for point in side_front) if side_front else None})
            data.append({"clip": clip, "frame": frame, "shirtShortsIntersectingFacePairs": len(overlaps),
                         "frontIntersectingPairs": front_overlaps,
                         "leftRightIntersectingPairs": side_overlaps,
                         "hemBoundaryVertices": len(distances), "frontHemVertices": len(front),
                         "frontHemNegativeSignedDistances": sum(row[1] < 0 for row in front),
                         "frontHemMinSignedDistance": front_sorted[0][1] if front_sorted else None,
                         "frontHemMedianSignedDistance": statistics.median(row[1] for row in front) if front else None,
                         "waistbandFrontPose": waist_pose,
                         "worstFrontHemVertices": [dict(index=row[0], signedDistance=row[1],
                                                         unsignedDistance=row[2], posedXYZ=row[3:])
                                                   for row in front_sorted[:8]]})
    return {"torsoGarmentFaces": len(garment_faces), "shortsFaces": len(shorts_faces),
            "hemBoundaryVertices": len(hem), "shortsWaistbandVertices": len(waistband),
            "shortsWaistbandThighWeightMedian": statistics.median(row["thighWeight"] for row in waistband_weights),
            "shortsWaistbandHipsWeightMedian": statistics.median(row["hipsWeight"] for row in waistband_weights),
            "shortsWaistbandWeights": waistband_weights, "frames": data}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-blend", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source, output = args.input_blend.resolve(), args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated factory-startup background Blender")
    if not source.is_file() or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Input must exist and output must be a new derived directory")
    before = sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False)
    mesh = bpy.data.objects["ReplayXI_Tripo_FBX_Candidate"]
    rig = next(modifier.object for modifier in mesh.modifiers if modifier.type == "ARMATURE")
    if len(mesh.data.vertices) != 8820 or len(rig.data.bones) != 65:
        raise ValueError("Unexpected approved player geometry or rig")
    grouped = components(mesh)
    summary = [component_report(mesh, faces) for faces in grouped]
    if len(grouped) < 4 or len(grouped[0]) != 4928 or len(grouped[3]) != 502:
        raise ValueError("Torso/shorts topology changed")
    hem = hem_vertices(mesh, grouped[0])
    collision = collision_frames(mesh, rig, grouped[0], grouped[3], hem)
    if before != sha(source):
        raise ValueError("Input changed during audit")
    output.mkdir(parents=True)
    report = {"input": str(source), "inputSHA256": before,
              "components": summary, "componentCount": len(summary),
              "collision": collision}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("TRIPO_HEM_AUDIT " + json.dumps({"count": len(summary),
                                         "top": [{"faces": item["faces"], "boundsXYZ": item["boundsXYZ"]}
                                                 for item in summary[:4]],
                                         "collision": [{"clip": row["clip"], "frame": row["frame"],
                                                        "intersections": row["shirtShortsIntersectingFacePairs"],
                                                        "front": row["frontIntersectingPairs"],
                                                        "frontHemNegative": row["frontHemNegativeSignedDistances"],
                                                        "frontHemMin": row["frontHemMinSignedDistance"]}
                                                       for row in collision["frames"]]}))


if __name__ == "__main__":
    main()
