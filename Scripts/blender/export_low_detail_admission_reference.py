#!/usr/bin/env python3
"""Export bounded Loop102 Blender deformation evidence, never change an asset.

Use factory-startup background Blender. The only output is a new JSON evidence
file under .codex-derived; the library, source mesh and candidate are read-only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_low_detail_player_candidate import checked_sources, apply_pose, evaluated_geometry, uv_per_vertex
from prepare_football_player import USD_TO_BLENDER
from render_runtime_player_poses import read_samples

REPOSITORY = Path(__file__).resolve().parents[2]
CANDIDATE = REPOSITORY / ".codex-derived/ReplayXI-Low102-Candidate-03/ReplayXILow102Candidate.blend"
CANDIDATE_HASH = "377cb76f8a45b57261f1febff1c4238ca5e6b08a1a46472280b911d71defa7e4"


def matrix_rows(value):
    return [[float(element) for element in row] for row in value]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--poses", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = args.output.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise ValueError("Use factory-startup background Blender")
    if output.exists() or not output.is_relative_to(REPOSITORY / ".codex-derived"):
        raise ValueError("Choose a new derived output file")
    before = checked_sources()
    if hashlib.sha256(CANDIDATE.read_bytes()).hexdigest() != CANDIDATE_HASH:
        raise ValueError("Refined candidate changed")
    motion = json.loads((REPOSITORY / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json").read_text())
    with bpy.data.libraries.load(str(CANDIDATE), link=False) as (source, target):
        if "ReplayXI_Home" not in source.collections:
            raise ValueError("Candidate collection missing")
        target.collections = ["ReplayXI_Home"]
    collection = target.collections[0]
    scene = bpy.data.scenes.new("Low102_Admission_Reference")
    bpy.context.window.scene = scene
    scene.collection.children.link(collection)
    root = next(obj for obj in collection.objects if obj.name == "ReplayXI_Home_Root")
    rig = next(obj for obj in collection.objects if obj.name == "ReplayXI_Home_Rig")
    meshes = {name: next(obj for obj in collection.objects if obj.name == f"ReplayXI_Low102_{name}")
              for name in ("Body", "Head")}
    rig.animation_data_clear()
    rig.data.pose_position = "POSE"
    inverse_axis = USD_TO_BLENDER.inverted()
    rest_local = []
    joints = []
    for joint in motion["joints"]:
        bone = rig.data.bones[joint["sourceName"]]
        parent = bone.parent
        rest = parent.matrix_local.inverted() @ bone.matrix_local if parent else bone.matrix_local.copy()
        rest_local.append(rest)
        joints.append({"name": joint["name"], "sourceName": bone.name,
                       "parentSourceName": parent.name if parent else None,
                       "bindMatrixYUp": matrix_rows(inverse_axis @ bone.matrix_local)})
        rig.pose.bones[bone.name].matrix_basis = Matrix.Identity(4)
    root.location.z = 0
    bpy.context.view_layer.update()
    bind_meshes = {}
    for name, obj in meshes.items():
        vertices, triangles = evaluated_geometry(obj)
        vertex_uvs = uv_per_vertex(obj)
        bind_meshes[name] = {
            "positions": [list(inverse_axis @ point) for point in vertices],
            "triangles": triangles,
            "uvsPerVertex": [sorted(vertex_uvs[index]) for index in range(len(vertices))],
            "weights": [sorted([[obj.vertex_groups[group.group].name, group.weight]
                                for group in vertex.groups if group.weight > 0])
                        for vertex in obj.data.vertices],
        }
    samples = read_samples(args.poses, 80)
    selected = [next(sample for sample in samples if sample["name"] == name)
                for name in ("run", "cut-right", "pass-contact")]
    idle = dict(next(clip for clip in motion["clips"] if clip["id"] == "idle")["frames"][0])
    idle.update({"name": "source-idle", "groundOffset": -motion["geometry"]["restMinY"]})
    selected.insert(0, idle)
    poses = []
    for sample in selected:
        apply_pose(rig, root, motion, rest_local, sample)
        positions = {name: [list(inverse_axis @ point) for point in evaluated_geometry(obj)[0]]
                     for name, obj in meshes.items()}
        actual_joint_world = [matrix_rows(inverse_axis @ rig.pose.bones[joint["sourceName"]].matrix)
                              for joint in motion["joints"]]
        poses.append({"sample": sample, "positions": positions,
                      "actualPoseMatricesYUpWithoutGroundOffset": actual_joint_world})
    if before != checked_sources() or hashlib.sha256(CANDIDATE.read_bytes()).hexdigest() != CANDIDATE_HASH:
        raise ValueError("Read-only input changed")
    report = {"candidateOnly": True, "blenderVersion": bpy.app.version_string,
              "candidateBlendSHA256": CANDIDATE_HASH,
              "motionSHA256": before["ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"],
              "rootOffsetAppliedOnce": True, "joints": joints,
              "bindMeshes": bind_meshes, "poses": poses, "protectedSourceHashes": before}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, separators=(",", ":"), allow_nan=False) + "\n")
    print("LOW102_REFERENCE", str(output), "poses", len(poses),
          "vertices", {name: len(value["positions"]) for name, value in bind_meshes.items()})


if __name__ == "__main__":
    main()
