#!/usr/bin/env python3
"""Measure Player A triangle orientation against its skinned smooth normals."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

import build_replayxi_tripo_athlete as core


def check(body, points, normals, include_indices):
    faces = body["indices"].reshape(-1, 3)
    geometry = np.cross(points[faces[:, 1]] - points[faces[:, 0]],
                        points[faces[:, 2]] - points[faces[:, 0]])
    lengths = np.linalg.norm(geometry, axis=1)
    smooth = normals[faces].mean(axis=1)
    smooth /= np.maximum(np.linalg.norm(smooth, axis=1)[:, None], 1e-20)
    agreement = np.einsum("ij,ij->i", geometry, smooth) / np.maximum(lengths, 1e-20)
    middle = points[faces].mean(axis=1)
    shirt = (middle[:, 1] >= 1.12) & (middle[:, 1] <= 1.62)
    inverted = agreement < 0
    shallow = agreement < .2
    result = {"triangles": len(faces), "degenerateUnder1e-10": int((lengths < 1e-10).sum()),
            "invertedVsSmoothNormals": int(inverted.sum()),
            "shirtInvertedVsSmoothNormals": int((inverted & shirt).sum()),
            "shallowVsSmoothNormals": int(shallow.sum()),
            "shirtShallowVsSmoothNormals": int((shallow & shirt).sum())}
    if include_indices:
        result["invertedFaceIndices"] = np.flatnonzero(inverted).tolist()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--near-glb", type=Path, required=True)
    parser.add_argument("--motion-glb", type=Path, required=True)
    parser.add_argument("--normal-mode", choices=("source", "area-weighted"), default="source")
    parser.add_argument("--include-indices", action="store_true")
    args = parser.parse_args()
    document, binary = core.glb(args.near_glb)
    skin = core.inspect_skin(document, binary)
    native = core.mesh_data(document, binary, skin, 1)
    scale = 1.82 / np.ptp(native["points"][:, 1])
    body = core.mesh_data(document, binary, skin, scale, args.normal_mode)
    joints, _, binds = core.skeleton(document, skin, scale)
    motion_document, motion_binary = core.glb(args.motion_glb)
    motion_skin = core.inspect_skin(motion_document, motion_binary)
    motion_skin["rootRestXZ"] = [0, 0]
    clips, _ = core.motion_clips(motion_document, motion_binary, motion_skin, scale)
    report = {"source": check(body, body["points"], body["normals"], args.include_indices), "poses": {}}
    for clip in clips:
        for frame_index in sorted({0, len(clip["frames"]) // 2, len(clip["frames"]) - 1}):
            posed, world = core.posed_vertices(body, joints, binds, clip["frames"][frame_index])
            transforms = np.asarray([matrix @ np.linalg.inv(bind)
                                     for matrix, bind in zip(world, binds)])
            joint_matrix = transforms[body["joints"], :3, :3]
            smooth = np.einsum("nkij,nj,nk->ni", joint_matrix, body["normals"], body["weights"])
            smooth /= np.maximum(np.linalg.norm(smooth, axis=1)[:, None], 1e-20)
            report["poses"][f"{clip['id']}:{frame_index}"] = check(body, posed, smooth, args.include_indices)
    print(json.dumps(report, separators=(",", ":")))


if __name__ == "__main__":
    main()
