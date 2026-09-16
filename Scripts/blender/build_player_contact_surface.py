#!/usr/bin/env python3
"""Bake a small, weighted skin-contact surface from the audited Blender player.

Run with --factory-startup --background --python-exit-code 1. The source library is read-only;
the profile and calibration receipt go into a new .codex-derived directory.
Contact samples retain their real skin weights, not enlarged collision spheres.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_football_player import USD_TO_BLENDER, matrix, rest_matrices
from render_runtime_player_poses import read_samples

REPOSITORY = Path(__file__).resolve().parents[2]
PLAYERS = REPOSITORY / "ReplayXI/Resources/Players"
MAXIMUM_VERTICES = 512
AUDITED_LIBRARY_SHA256 = "58bfaa3086b64f6d0ddfea251241c0cb0f83631455ffead079d6e7be2f85de01"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--poses", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use an isolated factory-startup background Blender")
    output = args.output.resolve()
    if not output.is_relative_to((REPOSITORY / ".codex-derived").resolve()) or output.exists():
        raise ValueError("Choose a new directory under .codex-derived")
    if digest(args.library) != AUDITED_LIBRARY_SHA256:
        raise ValueError("The Blender library has changed; audit its skin against the shipped asset first")
    motion_path = PLAYERS / "ReplayXIRocketboxMotion.json"
    model_path = PLAYERS / "ReplayXIRocketboxAthlete.usdz"
    motion = json.loads(motion_path.read_text())
    if len(motion["joints"]) != 80:
        raise ValueError("Expected the audited 80-joint skeleton")
    _, world_rest = rest_matrices(motion["joints"])
    inverse_rest = [transform.inverted() for transform in world_rest]
    source_indices = {joint["sourceName"]: index for index, joint in enumerate(motion["joints"])}
    path_indices = {joint["name"]: index for index, joint in enumerate(motion["joints"])}
    group_indices = {path_indices[path] for name, path in motion["semanticJoints"].items()
                     if not name.endswith("Toe")}
    samples = [sample for path in args.poses for sample in read_samples(path, len(world_rest))]
    if not 1 <= len(samples) <= 128:
        raise ValueError("Expected 1-128 checked poses")
    for clip in motion["clips"]:
        for index, frame in enumerate(clip["frames"]):
            samples.append({**frame, "name": f"source-{clip['id']}-{index}"})
    bpy.ops.wm.open_mainfile(filepath=str(args.library.resolve()), load_ui=False)
    rig = bpy.data.objects["ReplayXI_Home_Rig"]
    rig.animation_data_clear()
    blender_to_usd = USD_TO_BLENDER.inverted()
    vertices = []
    grouped = {}
    for section in ["Body", "Head"]:
        obj = bpy.data.objects[f"ReplayXI_Home_{section}"]
        relative = rig.matrix_world.inverted() @ obj.matrix_world
        for vertex in obj.data.vertices:
            position = blender_to_usd @ relative @ vertex.co
            weights = [(source_indices[obj.vertex_groups[group.group].name], group.weight)
                       for group in vertex.groups if group.weight > 0.000001]
            total = sum(weight for _, weight in weights)
            if not 1 <= len(weights) <= 4 or not math.isfinite(total) or abs(total - 1) > 0.001:
                raise ValueError(f"Invalid weights on {section}:{vertex.index}")
            weights = sorted((joint, weight / total) for joint, weight in weights)
            group = max(weights, key=lambda item: item[1])[0]
            while group not in group_indices:
                group = motion["joints"][group]["parentIndex"]
                if group < 0:
                    raise ValueError("A weighted joint has no body semantic")
            index = len(vertices)
            local_points = [(joint, weight, inverse_rest[joint] @ position) for joint, weight in weights]
            vertices.append({"id": f"{section}:{vertex.index}", "point": position,
                             "weights": weights, "localPoints": local_points})
            grouped.setdefault(group, []).append((index, inverse_rest[group] @ position))
    if len(vertices) != 5012:
        raise ValueError("The library no longer matches the shipped body/head")
    selected = set()
    directions = [Vector(direction) for direction in itertools.product([-1, 0, 1], repeat=3)
                  if direction != (0, 0, 0)]
    for group in sorted(grouped):
        for direction in directions:
            selected.add(max(grouped[group], key=lambda item: item[1].dot(direction))[0])
    if not 1 <= len(selected) <= MAXIMUM_VERTICES:
        raise ValueError(f"Contact profile exceeds the {MAXIMUM_VERTICES}-vertex budget: {len(selected)}")
    rest_local = []
    for joint in motion["joints"]:
        bone = rig.data.bones[joint["sourceName"]]
        rest_local.append(bone.parent.matrix_local.inverted() @ bone.matrix_local
                          if bone.parent else bone.matrix_local.copy())
    calibration = []
    sampled_heights = []
    for sample in samples:
        transforms = []
        for index, joint in enumerate(motion["joints"]):
            local = matrix(sample["translations"][index], sample["rotations"][index], sample["scales"][index])
            parent = joint["parentIndex"]
            transforms.append(transforms[parent] @ local if parent >= 0 else local)
            bone = rig.pose.bones[joint["sourceName"]]
            bone.rotation_mode = "QUATERNION"
            target = local if parent >= 0 else USD_TO_BLENDER @ local
            bone.matrix_basis = rest_local[index].inverted() @ target
        heights = [sum((transforms[joint] @ point).y * weight for joint, weight, point in vertex["localPoints"])
                   for vertex in vertices]
        exact_min = min(heights)
        bpy.context.view_layer.update()
        graph = bpy.context.evaluated_depsgraph_get()
        actual_min = math.inf
        for section in ["Body", "Head"]:
            obj = bpy.data.objects[f"ReplayXI_Home_{section}"].evaluated_get(graph)
            relative = blender_to_usd @ rig.matrix_world.inverted() @ obj.matrix_world
            actual_min = min(actual_min, min((relative @ vertex.co).y for vertex in obj.data.vertices))
        error = abs(exact_min - actual_min)
        if error > 0.0005:
            raise ValueError(f"Contact skin differs from Blender by {error:.6f} m at {sample['name']}")
        sampled_heights.append(heights)
        calibration.append({"name": sample["name"], "fullMeshMinimumY": exact_min,
                            "blenderMinimumY": actual_min, "skinAgreementErrorMetres": error})
    # Weighted skin can expose an interior rest-pose vertex when a joint folds.
    # Add the actual low vertex from the worst uncovered calibration pose until
    # the contact hull is within 3 mm across all supplied poses and source clips.
    while True:
        errors = [min(heights[index] for index in selected) - record["fullMeshMinimumY"]
                  for heights, record in zip(sampled_heights, calibration)]
        worst = max(range(len(errors)), key=errors.__getitem__)
        if errors[worst] <= 0.003:
            break
        heights = sampled_heights[worst]
        selected.add(min(range(len(vertices)), key=heights.__getitem__))
        if len(selected) > MAXIMUM_VERTICES:
            raise ValueError("Articulated contact calibration exceeds the vertex budget")
    chosen = sorted(selected)
    for heights, record in zip(sampled_heights, calibration):
        sampled_min = min(heights[index] for index in chosen)
        record.update(sampleMinimumY=sampled_min, omissionErrorMetres=sampled_min - record["fullMeshMinimumY"])
    maximum_error = max(item["omissionErrorMetres"] for item in calibration)
    padding = max(0.006, math.ceil((maximum_error + 0.003) * 1000) / 1000)
    if padding > 0.02:
        raise ValueError(f"Sparse contact omission {maximum_error:.4f} m needs denser selection")
    document = {"schemaVersion": 1, "assetSHA256": digest(model_path), "motionSHA256": digest(motion_path),
                "sourceVertexCount": len(vertices), "jointCount": len(world_rest), "paddingMetres": padding,
                "vertices": [{"id": vertices[index]["id"],
                              "position": [round(value, 7) for value in vertices[index]["point"]],
                              "joints": [joint for joint, _ in vertices[index]["weights"]],
                              "weights": [round(weight, 7) for _, weight in vertices[index]["weights"]]}
                             for index in chosen]}
    output.mkdir(parents=True)
    profile = output / "ReplayXIRocketboxContactSurface.json"
    profile.write_text(json.dumps(document, separators=(",", ":"), sort_keys=True) + "\n")
    report = {"profile": str(profile), "sha256": digest(profile), "vertices": len(chosen),
              "sourceVertices": len(vertices), "influences": sum(len(vertices[index]["weights"]) for index in chosen),
              "paddingMetres": padding, "maximumOmissionErrorMetres": maximum_error,
              "librarySHA256": digest(args.library), "calibration": calibration}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_CONTACT_SURFACE " + json.dumps(report))


if __name__ == "__main__":
    main()
