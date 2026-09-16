#!/usr/bin/env python3
"""Loop102 full-mesh contact feasibility, not a bundled/runtime contact profile.

Every weighted canonical vertex is retained. Bone-local influence points are
prepared with the exact packaged inverse binds, without baking presentation
height. Run with Blender's bundled Python; output must be a new derived folder.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from build_replayxi_low_detail_candidate_usdz import pose_matrices

REPOSITORY = Path(__file__).resolve().parents[1]
CANONICAL = REPOSITORY / ".codex-derived/ReplayXI-Low102-Canonical-03"
ASSET_HASH = "cd8a496a1f89166cf819177c8b959246d130f64ea5dfbd86910488b1dbe849ac"
FIXTURE_HASH = "9cd03e16888fe635bc1e4d417d48895da33dd98b7be7dbf744e262f1177dd5fd"
MOTION_HASH = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(REPOSITORY / ".codex-derived"):
        raise ValueError("Choose a NEW derived output directory")
    fixture_path = CANONICAL / "native-admission-fixture.json"
    asset_path = CANONICAL / "ReplayXILow102Canonical.usdz"
    motion_path = REPOSITORY / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"
    inputs = {fixture_path: FIXTURE_HASH, asset_path: ASSET_HASH, motion_path: MOTION_HASH}
    if any(sha(path) != expected for path, expected in inputs.items()):
        raise ValueError("A frozen canonical input changed")
    fixture = json.loads(fixture_path.read_text())
    canonical_report = json.loads((CANONICAL / "report.json").read_text())
    motion = json.loads(motion_path.read_text())
    joints = fixture["skeleton"]["jointNames"]
    if len(joints) != 80 or len(set(joints)) != 80 or fixture["geometry"]["vertices"] != 1707:
        raise ValueError("Unexpected canonical mesh/skeleton")
    inverse_bind = np.asarray(fixture["skeleton"]["inverseBindMatricesColumnMajor"]).reshape(80, 4, 4).transpose(0, 2, 1)
    if not np.isfinite(inverse_bind).all():
        raise ValueError("Invalid canonical inverse binds")
    # Store actual Float32 values for the proposed native profile. Measure this
    # one-time quantisation separately from later Float32 arithmetic/SDK import.
    inverse_bind_float32 = inverse_bind.astype(np.float32)
    inverse_quantisation = float(np.max(abs(inverse_bind - inverse_bind_float32)))
    inverse_bind = inverse_bind_float32.astype(float)
    vertices, prepared, ranges = [], [], []
    for part in fixture["parts"]:
        for index, (point, indices, weights) in enumerate(zip(part["positions"], part["jointIndices"], part["jointWeights"])):
            influences = [(int(joint), float(weight)) for joint, weight in zip(indices, weights) if weight > 0]
            if (len(point) != 3 or not np.isfinite(point).all() or max(abs(value) for value in point) > 3
                    or not 1 <= len(influences) <= 4 or len({joint for joint, _ in influences}) != len(influences)
                    or any(not 0 <= joint < 80 or not np.isfinite(weight) or not 0 < weight <= 1 for joint, weight in influences)
                    or abs(sum(weight for _, weight in influences) - 1) > 0.000001):
                raise ValueError("Invalid candidate contact vertex")
            start = len(prepared)
            for joint, weight in influences:
                local = inverse_bind[joint] @ [*point, 1]
                prepared.append((joint, local, weight))
            ranges.append((start, len(prepared)))
            vertices.append({"id": f"{part['name']}:{index}", "position": point,
                             "joints": [joint for joint, _ in influences], "weights": [weight for _, weight in influences]})
    if len(vertices) != 1707 or len(prepared) != 2823:
        raise ValueError("Full-mesh coverage changed")
    profile = {"schemaVersion": 2, "candidateOnly": True, "profileKind": "full-low-mesh",
        "assetSHA256": ASSET_HASH, "motionSHA256": MOTION_HASH, "sourceVertexCount": 1707,
        "jointCount": 80, "jointNames": joints,
        "inverseBindMatricesColumnMajor": inverse_bind.transpose(0, 2, 1).reshape(80, 16).tolist(),
        "rootBaseLift": fixture["coordinates"]["rootBaseLift"], "rootLiftBakedIntoPoints": False,
        "paddingMetres": 0.006, "vertices": vertices}
    # This profile deliberately needs a separate admission path. It must not be
    # fed to the existing 5012-source /512-support-vertex near-skin decoder.
    comparisons = []
    for sample in fixture["poses"]:
        world = pose_matrices(sample, fixture["skeleton"]["parentIndices"])
        heights = []
        for start, end in ranges:
            heights.append(sum((world[joint] @ point)[1] * weight for joint, point, weight in prepared[start:end]))
        expected = [point[1] - sample["groundOffset"] for part in fixture["parts"]
                    for point in sample["expectedPositionsWithRootOffset"][part["name"]]]
        maximum_error = float(np.max(abs(np.asarray(heights) - expected)))
        minimum_error = abs(min(heights) - min(expected))
        if maximum_error > 0.000001 or minimum_error > 0.000001:
            raise ValueError("Full-vertex profile differs from packaged OpenUSD skinning")
        blender_pose = next(row for row in canonical_report["poses"] if row["name"] == sample["name"])
        blender_minimum = min(row["blenderMinimumY"] for row in blender_pose["sections"].values())
        comparisons.append({"name": sample["name"], "rootGroundOffset": sample["groundOffset"],
            "maximumVertexHeightDifferenceMetres": maximum_error,
            "profileMinimumWithoutRootOffset": min(heights),
            "packagedMinimumWithoutRootOffset": min(expected),
            "minimumDifferenceMetres": minimum_error,
            "presentedMinimumY": min(heights) + sample["groundOffset"],
            "blenderPresentedMinimumY": blender_minimum,
            "minimumDifferenceFromBlenderMetres": abs(min(heights) + sample["groundOffset"] - blender_minimum)})
    rest_sample = {"translations": [joint["translation"] for joint in motion["joints"]],
                   "rotations": [joint["rotation"] for joint in motion["joints"]],
                   "scales": [joint["scale"] for joint in motion["joints"]]}
    rest_inverse = np.linalg.inv(pose_matrices(rest_sample, fixture["skeleton"]["parentIndices"]))
    if any(sha(path) != expected for path, expected in inputs.items()):
        raise ValueError("Read-only canonical input changed")
    output.mkdir(parents=True)
    profile_path = output / "ReplayXILow102FullContactCandidate.json"
    profile_path.write_text(json.dumps(profile, separators=(",", ":"), allow_nan=False) + "\n")
    licence = CANONICAL / "LICENSE-ROCKETBOX-MIT.txt"
    (output / licence.name).write_bytes(licence.read_bytes())
    report = {"candidateOnly": True, "profileSHA256": sha(profile_path), "profileBytes": profile_path.stat().st_size,
        "vertices": len(vertices), "positiveInfluences": len(prepared), "maximumInfluencesPerVertex": 4,
        "matchesAllCanonicalVertices": True, "assetSHA256": ASSET_HASH, "motionSHA256": MOTION_HASH,
        "usesActualPackagedInverseBindMatrices": True, "rootLiftBakedIntoPoints": False,
        "maximumInverseBindFloat32Quantisation": inverse_quantisation,
        "maximumInverseBindDifferenceFromMotionRestDoubleComposition": float(np.max(abs(inverse_bind - rest_inverse))),
        "maximumInverseBindDifferenceFromMotionRestAfterFloat32Cast": float(np.max(abs(inverse_bind_float32 - rest_inverse.astype(np.float32)))),
        "currentNearMaximumVerticesUnchanged": 512, "currentNearMaximumPayloadBytesUnchanged": 262144,
        "poses": comparisons,
        "limits": ["Derived-only; current runtime rejects this profile", "No native-contact CPU measurement yet",
                   "Full coverage is exact only for the admitted linear skin and unchanged mesh/weights",
                   "Four reference poses; no headset/GPU deformation claim", "Padding is explicit and applied by caller, not baked",
                   "Motion-rest comparison uses offline double composition plus Float32 cast, not native Swift hierarchy arithmetic"]}
    (output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print("LOW102_CONTACT", str(profile_path), "bytes", report["profileBytes"], "influences", len(prepared),
          "maximumMinimumErrorMetres", max(row["minimumDifferenceMetres"] for row in comparisons))


if __name__ == "__main__":
    main()
