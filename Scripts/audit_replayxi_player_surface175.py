#!/usr/bin/env python3
"""Read-only rigged Player A/B GLB seam audit. Run with Blender's bundled Python.

Player A's source GLB is unrigged. Use the derived rigged near/low GLBs in
.codex-derived/replayxi-diversity172/rig-trest-v4/ (see its report.json).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

import build_replayxi_tripo_athlete as core


def components(vertex_count: int, faces: np.ndarray) -> list[int]:
    parent = np.arange(vertex_count, dtype=np.int32)

    def root(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for a, b, c in faces:
        lead = root(int(a))
        parent[root(int(b))] = lead
        parent[root(int(c))] = lead
    labels = np.fromiter((root(i) for i in range(vertex_count)), dtype=np.int32,
                         count=vertex_count)
    return sorted((int(n) for n in np.unique(labels, return_counts=True)[1]), reverse=True)


def weighted_joint_samples(body: dict, skin: dict, document: dict, name: str,
                           minimum: float) -> np.ndarray:
    nodes = [node for node in skin["weighted"]
             if document["nodes"][node].get("name") == name]
    if len(nodes) != 1:
        raise ValueError(f"Expected one {name} joint")
    joint = skin["index"][nodes[0]]
    share = np.where(body["joints"] == joint, body["weights"], 0).sum(axis=1)
    return np.flatnonzero(share > minimum)


def inspect(path: Path) -> dict:
    document, binary = core.glb(path)
    skins = document.get("skins")
    if not skins:
        raise ValueError(f"{path}: unrigged GLB (no skin); use rig-trest-v4/PlayerA-Near.glb for Player A")
    meshes = document.get("meshes", [])
    if len(skins) != 1 or len(meshes) != 1 or len(meshes[0].get("primitives", [])) != 1:
        raise ValueError(f"{path}: expected one rigged body mesh and primitive")
    weighted = skins[0].get("joints", [])
    if len(weighted) != 52:
        raise ValueError(f"{path}: expected a 52-joint Mixamo skin")
    mesh_nodes = [i for i, node in enumerate(document["nodes"]) if node.get("mesh") == 0]
    if len(mesh_nodes) != 1:
        raise ValueError(f"{path}: expected one body mesh node")
    skin = {"weighted": weighted, "index": {node: i for i, node in enumerate(weighted)},
            "primitive": meshes[0]["primitives"][0],
            "world": core.global_matrices(document), "meshNode": mesh_nodes[0]}
    body = core.mesh_data(document, binary, skin, 1)
    points = body["points"]
    faces = body["indices"].reshape(-1, 3)
    height = float(np.ptp(points[:, 1]))
    lower = float(points[:, 1].min())
    head_ids = weighted_joint_samples(body, skin, document, "mixamorig:Head", .65)
    neck_ids = weighted_joint_samples(body, skin, document, "mixamorig:Neck", .5)
    head = points[head_ids]
    neck = points[neck_ids]
    head = head[(head[:, 1] > lower + .83 * height) &
                (head[:, 1] < lower + .89 * height)]
    neck = neck[(neck[:, 1] > lower + .80 * height) &
                (neck[:, 1] < lower + .88 * height)]
    if not len(head) or not len(neck):
        raise ValueError("Head/neck overlap band has no weighted surface samples")
    # Only hundreds of points meet both the joint and neck-band filters.
    distances = np.linalg.norm(head[:, None, :] - neck[None, :, :], axis=2).min(axis=1)
    distances *= 1.82 / height
    all_edges = np.concatenate((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]))
    _, edge_counts = np.unique(np.sort(all_edges, axis=1), axis=0, return_counts=True)
    sizes = components(len(points), faces)
    return {
        "file": str(path),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "vertices": len(points),
        "triangles": len(faces),
        "indexedComponents": len(sizes),
        "largestIndexedComponents": sizes[:8],
        "indexedBoundaryEdges": int(np.count_nonzero(edge_counts == 1)),
        "headSamples": len(head),
        "neckSamples": len(neck),
        "headToNeckNearestMetres": {
            "minimum": float(distances.min()),
            "median": float(np.median(distances)),
            "p90": float(np.quantile(distances, .9)),
            "maximum": float(distances.max()),
        },
        "caution": "Indexed components include UV/material seams. Weighted point distance is not a surface gap; neither measure proves a visual hole.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glb", nargs="+", type=Path, help="Rigged 52-joint GLBs to compare")
    args = parser.parse_args()
    try:
        results = [inspect(path.resolve()) for path in args.glb]
    except (OSError, ValueError, KeyError, IndexError) as error:
        parser.error(str(error))
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
