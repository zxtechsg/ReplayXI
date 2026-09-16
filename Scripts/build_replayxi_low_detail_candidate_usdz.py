#!/usr/bin/env python3
"""Loop102 canonical USDZ prototype; all output stays in a new derived folder.

Run with Blender's bundled Python (numpy/OpenUSD are already present). This is
not a runtime asset builder: no source replacement, contact sidecar or live cap
change. The admitted skeleton/animation/materials remain exact; only mesh arrays
are replaced after named skin remapping and bounded Blender parity checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile

import numpy as np
from pxr import Gf, Usd, UsdGeom, UsdSkel, Vt

from audit_replayxi_player_usdz import audit
from build_replayxi_rocketbox_pilot import audit_usd_skinning, read_accessor
from replayxi_usdz_archive import normalize_usdz_timestamps, validated_archive_names

REPOSITORY = Path(__file__).resolve().parents[1]
SOURCE = REPOSITORY / "ReplayXI/Resources/Players/ReplayXIRocketboxAthlete.usdz"
MOTION = REPOSITORY / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"
CANDIDATE = REPOSITORY / ".codex-derived/ReplayXI-Low102-Candidate-03/ReplayXILow102Home.glb"
EXPECTED = {
    SOURCE: "7cfb694888f111928643e8aca7041d21925f5d55f3f5adbd353a972ca255e772",
    MOTION: "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4",
    CANDIDATE: "48218ff9b1d8fdb53ec04a78c9c62caf5669cd063d97bb3d7921df2f661f1049",
}
ROOT = "/ReplayXIRocketbox"
# An offline Float32 transform/export budget, not a motion-quality threshold:
# 32 Float32 epsilons over a bounded 2 m player is under 8 micrometres.
POSE_ROUNDTRIP_BUDGET_METRES = 0.000008


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_sources():
    actual = {str(path.relative_to(REPOSITORY)): digest(path) for path in EXPECTED}
    if any(actual[str(path.relative_to(REPOSITORY))] != value for path, value in EXPECTED.items()):
        raise ValueError("A hash-locked input changed")
    return actual


def finite(value, shape=None):
    array = np.asarray(value)
    if not np.isfinite(array).all() or (shape is not None and array.shape != shape):
        raise ValueError("Invalid finite array/shape")
    return array


def load_glb():
    payload = CANDIDATE.read_bytes()
    magic, version, length, json_length, kind = struct.unpack_from("<IIIII", payload)
    if (magic, version, length, kind) != (0x46546C67, 2, len(payload), 0x4E4F534A):
        raise ValueError("Invalid bounded GLB")
    binary_length, binary_kind = struct.unpack_from("<II", payload, 20 + json_length)
    if binary_kind != 0x004E4942 or 28 + json_length + binary_length != len(payload):
        raise ValueError("Invalid GLB binary bounds")
    document = json.loads(payload[20:20 + json_length])
    if len(document["skins"]) != 1 or len(document["meshes"]) != 2:
        raise ValueError("Expected one skin/two mesh sections")
    return document, payload[28 + json_length:]


def attribute_snapshot(prim):
    return {str(attribute.GetName()): {
        "default": repr(attribute.Get()),
        "samples": [(time, repr(attribute.Get(time))) for time in attribute.GetTimeSamples()],
        "metadata": repr(attribute.GetAllMetadata()),
    } for attribute in prim.GetAttributes()}


def pose_matrices(sample, parents):
    result = []
    for index, (translation, quaternion, scale) in enumerate(zip(
            sample["translations"], sample["rotations"], sample["scales"])):
        x, y, z, w = quaternion
        rotation = Gf.Quatd(w, x, y, z)
        rotation.Normalize()
        matrix = np.asarray(Gf.Matrix4d().SetRotate(rotation)).T.copy()
        matrix[:3, :3] = matrix[:3, :3] @ np.diag(scale)
        matrix[:3, 3] = translation
        parent = parents[index]
        result.append(result[parent] @ matrix if parent >= 0 else matrix)
    return finite(result, (80, 4, 4))


def correspondence(points, joints, weights, uv, reference, names):
    reference_points = finite(reference["positions"])
    reference_weights = []
    for row in reference["weights"]:
        by_joint = np.zeros(80)
        for name, weight in row:
            by_joint[names.index(name)] = weight
        reference_weights.append(by_joint)
    reference_weights = np.asarray(reference_weights)
    result, restored_joints, restored_weights, represented = [], [], [], set()
    max_position, max_weight, max_uv, restored_vertices = 0.0, 0.0, 0.0, 0
    for point, vertex_joints, vertex_weights, vertex_uv in zip(points, joints, weights, uv):
        distances = np.linalg.norm(reference_points - point, axis=1)
        candidates = np.flatnonzero(distances <= 0.000001)
        dense_weights = np.zeros(80)
        np.add.at(dense_weights, vertex_joints, vertex_weights)
        admissible = []
        for candidate in candidates:
            # Blender 5.2's glTF primitive_extract.__get_bone_data drops
            # weights <= 0.0001, then normalises the survivors. Verify that
            # exact export policy before restoring the candidate's original
            # <=4 influences. Never silently relax a skin-weight comparison.
            filtered = reference_weights[candidate].copy()
            filtered[filtered <= 0.0001] = 0
            filtered /= filtered.sum()
            weight_error = float(np.max(abs(filtered - dense_weights)))
            uv_error = min(float(np.max(abs(np.asarray(value) - vertex_uv)))
                           for value in reference["uvsPerVertex"][candidate])
            if weight_error <= 0.000001 and uv_error <= 0.000001:
                admissible.append((float(distances[candidate]), int(candidate), weight_error, uv_error))
        if not admissible:
            nearest = int(np.argmin(distances))
            raise ValueError("A GLB vertex has no matching rest point + UV + named weights: "
                             f"distance={distances[nearest]}, uv={vertex_uv.tolist()}, "
                             f"referenceUV={reference['uvsPerVertex'][nearest]}, "
                             f"weightError={np.max(abs(reference_weights[nearest] - dense_weights))}")
        distance, candidate, weight_error, uv_error = min(admissible)
        if any(np.max(abs(reference_weights[other] - reference_weights[candidate])) > 0.00000001
               for _, other, _, _ in admissible):
            raise ValueError("Ambiguous coincident candidate weights; cannot restore safely")
        represented.update(other for _, other, _, _ in admissible)
        result.append(candidate)
        exact = reference_weights[candidate]
        nonzero = sorted(np.flatnonzero(exact), key=lambda index: (-exact[index], index))
        if not 1 <= len(nonzero) <= 4 or abs(exact.sum() - 1) > 0.000001:
            raise ValueError("Blender candidate exceeds the original four-influence contract")
        restored_vertices += int(np.max(abs(exact - dense_weights)) > 0.000001)
        restored_joints.append(nonzero + [0] * (4 - len(nonzero)))
        restored_weights.append([exact[index] for index in nonzero] + [0] * (4 - len(nonzero)))
        max_position, max_weight, max_uv = max(max_position, distance), max(max_weight, weight_error), max(max_uv, uv_error)
    if len(represented) != len(reference_points):
        raise ValueError("The conversion lost at least one Blender vertex")
    return np.asarray(result), np.asarray(restored_joints), np.asarray(restored_weights), {"maximumRestPositionDifferenceMetres": max_position,
                               "maximumNamedWeightDifference": max_weight,
                               "maximumUVDifference": max_uv,
                               "restoredTinyWeightVertices": restored_vertices,
                               "allBlenderVerticesRepresented": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(REPOSITORY / ".codex-derived"):
        raise ValueError("Choose a NEW .codex-derived folder")
    before = checked_sources()
    reference = json.loads(args.reference.read_text())
    if reference["motionSHA256"] != EXPECTED[MOTION] or len(reference["poses"]) != 4:
        raise ValueError("Unexpected bounded Blender reference")
    motion = json.loads(MOTION.read_text())
    canonical_names = [joint["sourceName"] for joint in motion["joints"]]
    paths = [joint["name"] for joint in motion["joints"]]
    parents = [joint["parentIndex"] for joint in motion["joints"]]
    document, binary = load_glb()
    skin = document["skins"][0]
    source_names = [document["nodes"][index]["name"] for index in skin["joints"]]
    if len(source_names) != 80 or set(source_names) != set(canonical_names):
        raise ValueError("Candidate skeleton identity changed")
    remap = np.asarray([canonical_names.index(name) for name in source_names])
    node_parents = {child: index for index, node in enumerate(document["nodes"])
                    for child in node.get("children", [])}
    weighted = set(skin["joints"])
    for old_index, node_index in enumerate(skin["joints"]):
        parent = node_parents.get(node_index)
        while parent is not None and parent not in weighted:
            parent = node_parents.get(parent)
        expected = parents[remap[old_index]]
        if (document["nodes"][parent]["name"] if parent is not None else None) != (
                canonical_names[expected] if expected >= 0 else None):
            raise ValueError("Candidate bone ancestry changed")
    root_node = next(node for node in document["nodes"] if node["name"] == "ReplayXI_Home_Root")
    if root_node.get("rotation", [0, 0, 0, 1]) != [0, 0, 0, 1] or root_node.get("scale", [1, 1, 1]) != [1, 1, 1]:
        raise ValueError("Unexpected candidate root rotation/scale")
    offset = finite(root_node["translation"], (3,))
    if abs(offset[1] + motion["geometry"]["restMinY"]) > 0.00000001 or offset[0] != 0 or offset[2] != 0:
        raise ValueError("Unexpected root ground offset")
    inverse_bind = finite(read_accessor(document, binary, skin["inverseBindMatrices"]), (80, 16)).reshape(80, 4, 4).transpose(0, 2, 1)
    bind_from_glb = np.linalg.inv(inverse_bind)
    bind_from_glb[:, :3, 3] -= offset
    blender_bind = finite([joint["bindMatrixYUp"] for joint in reference["joints"]], (80, 4, 4))
    bind_error = float(np.max(abs(bind_from_glb - blender_bind[remap])))
    if bind_error > 0.000001:
        raise ValueError("Candidate inverse binds do not match Blender rest matrices")
    output.mkdir(parents=True)
    staging = output / "stage"
    staging.mkdir()
    with zipfile.ZipFile(SOURCE) as archive:
        for member in validated_archive_names(archive.infolist()):
            destination = staging / member
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read(member))
    source_stage = Usd.Stage.Open(str(SOURCE))
    preserved_names = ("Skeleton", "Idle", "Run", "BodyMaterial", "HeadMaterial")
    preserved = {name: source_stage.GetPrimAtPath(ROOT + "/" + name).GetPrimStack()[0].GetAsText()
                 for name in preserved_names}
    source_layer = staging / "athlete.usdc"
    layer = staging / "candidate.usda"
    extracted_stage = Usd.Stage.Open(str(source_layer))
    extracted_stage.GetRootLayer().Export(str(layer))
    stage = Usd.Stage.Open(str(layer))
    skeleton = UsdSkel.Skeleton(stage.GetPrimAtPath(ROOT + "/Skeleton"))
    if list(skeleton.GetJointsAttr().Get()) != paths:
        raise ValueError("Source USD joint order differs from motion")
    canonical_bind = np.asarray(skeleton.GetBindTransformsAttr().Get()).transpose(0, 2, 1)
    meshes, mesh_reports = {}, {}
    for mesh_index, section in enumerate(("Body", "Head")):
        node = next(node for node in document["nodes"] if node.get("mesh") == mesh_index)
        if node["name"] != f"ReplayXI_Low102_{section}" or node.get("skin") != 0 or any(key in node for key in ("translation", "rotation", "scale", "matrix")):
            raise ValueError("Candidate mesh transform/section changed")
        primitives = document["meshes"][mesh_index]["primitives"]
        if len(primitives) != 1:
            raise ValueError("Candidate mesh split unexpectedly")
        primitive = primitives[0]
        attrs = primitive["attributes"]
        points = finite(read_accessor(document, binary, attrs["POSITION"])) - offset
        normals = finite(read_accessor(document, binary, attrs["NORMAL"]))
        uv = finite(read_accessor(document, binary, attrs["TEXCOORD_0"])).copy()
        uv[:, 1] = 1 - uv[:, 1]
        indices = finite(read_accessor(document, binary, primitive["indices"])).astype(int).reshape(-1)
        source_joints = finite(read_accessor(document, binary, attrs["JOINTS_0"])).astype(int)
        if source_joints.shape != (len(points), 4) or np.any(source_joints < 0) or np.any(source_joints >= 80):
            raise ValueError("Invalid candidate joint indices")
        joints = remap[source_joints]
        weights = finite(read_accessor(document, binary, attrs["WEIGHTS_0"]), (len(points), 4))
        if (np.any(weights < 0) or np.max(abs(weights.sum(axis=1) - 1)) > 0.000001
                or np.max(abs(np.linalg.norm(normals, axis=1) - 1)) > 0.000001
                or len(indices) % 3 or np.any(indices < 0) or np.any(indices >= len(points))):
            raise ValueError("Invalid geometry/weights")
        correspondence_indices, joints, weights, correspondence_report = correspondence(
            points, joints, weights, uv, reference["bindMeshes"][section], canonical_names)
        mesh = UsdGeom.Mesh(stage.GetPrimAtPath(ROOT + "/" + section))
        mesh.GetPointsAttr().Set(Vt.Vec3fArray(points.tolist()))
        mesh.GetNormalsAttr().Set(Vt.Vec3fArray(normals.tolist()))
        mesh.GetFaceVertexCountsAttr().Set([3] * (len(indices) // 3))
        mesh.GetFaceVertexIndicesAttr().Set(indices.tolist())
        mesh.GetExtentAttr().Set(Vt.Vec3fArray([points.min(axis=0).tolist(), points.max(axis=0).tolist()]))
        UsdGeom.PrimvarsAPI(mesh).GetPrimvar("st").Set(Vt.Vec2fArray(uv.tolist()))
        binding = UsdSkel.BindingAPI(mesh.GetPrim())
        binding.GetJointIndicesPrimvar().Set(joints.reshape(-1).tolist())
        binding.GetJointWeightsPrimvar().Set(weights.reshape(-1).tolist())
        meshes[section] = {"indices": correspondence_indices, "vertices": len(points), "triangles": len(indices) // 3}
        mesh_reports[section] = {**meshes[section], **correspondence_report}
        mesh_reports[section].pop("indices")
    metadata = dict(stage.GetRootLayer().customLayerData)
    metadata["replayxi_candidate_only"] = "Loop102 offline prototype; no runtime/contact admission"
    stage.GetRootLayer().customLayerData = metadata
    stage.GetRootLayer().Save()
    package = output / "ReplayXILow102Canonical.usdz"
    subprocess.run(["/usr/bin/usdzip", "--arkitAsset", str(layer), str(package)], check=True, capture_output=True)
    normalize_usdz_timestamps(package)
    reopened = Usd.Stage.Open(str(package))
    for name in preserved_names:
        if reopened.GetPrimAtPath(ROOT + "/" + name).GetPrimStack()[0].GetAsText() != preserved[name]:
            raise ValueError(f"Canonical {name} was not preserved exactly")
    notice = source_stage.GetRootLayer().customLayerData["replayxi_license_notice"]
    skin_audit = audit_usd_skinning(package, notice)
    archive_audit = audit(package)
    if archive_audit["errors"]:
        raise ValueError(f"USDZ preflight failed: {archive_audit['errors']}")
    packaged_skeleton = UsdSkel.Skeleton(reopened.GetPrimAtPath(ROOT + "/Skeleton"))
    fixture_parts = []
    for material_index, section in enumerate(("Body", "Head")):
        mesh = UsdGeom.Mesh(reopened.GetPrimAtPath(ROOT + "/" + section))
        binding = UsdSkel.BindingAPI(mesh.GetPrim())
        fixture_parts.append({
            "name": section, "materialIndex": material_index,
            "positions": np.asarray(mesh.GetPointsAttr().Get()).tolist(),
            "normals": np.asarray(mesh.GetNormalsAttr().Get()).tolist(),
            "uvs": np.asarray(UsdGeom.PrimvarsAPI(mesh).GetPrimvar("st").Get()).tolist(),
            "triangleIndices": list(mesh.GetFaceVertexIndicesAttr().Get()),
            "jointIndices": np.asarray(binding.GetJointIndicesPrimvar().Get()).reshape(-1, 4).tolist(),
            "jointWeights": np.asarray(binding.GetJointWeightsPrimvar().Get()).reshape(-1, 4).tolist(),
        })
    # USD matrices use row-vector convention. Flattening their stored rows is
    # the equivalent column-major list for native column-vector SIMD matrices.
    fixture = {"schemaVersion": 1, "candidateOnly": True,
        "asset": {"filename": package.name, "sha256": digest(package), "bytes": package.stat().st_size},
        "coordinates": {"upAxis": "Y", "metresPerUnit": 1, "forwardAxis": "+Z",
            "rootBaseLift": -motion["geometry"]["restMinY"], "rootLiftBakedIntoPoints": False},
        "skeleton": {"jointNames": paths, "sourceNames": canonical_names, "parentIndices": parents,
            "bindMatricesColumnMajor": np.asarray(packaged_skeleton.GetBindTransformsAttr().Get()).reshape(80, 16).tolist(),
            "inverseBindMatricesColumnMajor": np.linalg.inv(canonical_bind).transpose(0, 2, 1).reshape(80, 16).tolist(),
            "restLocalMatricesColumnMajor": np.asarray(packaged_skeleton.GetRestTransformsAttr().Get()).reshape(80, 16).tolist()},
        "parts": fixture_parts, "poses": [],
        "geometry": {"vertices": sum(value["vertices"] for value in meshes.values()),
                     "triangles": sum(value["triangles"] for value in meshes.values()),
                     "materials": 2, "meshSections": 2, "joints": 80, "maxInfluencesPerVertex": 4}}
    pose_reports = []
    inverse_canonical = np.linalg.inv(canonical_bind)
    for row in reference["poses"]:
        sample = row["sample"]
        world = pose_matrices(sample, parents)
        skinning = world @ inverse_canonical
        transforms = Vt.Matrix4dArray([Gf.Matrix4d(*value.T.reshape(-1).tolist()) for value in skinning])
        report = {"name": sample["name"], "groundOffset": sample["groundOffset"], "sections": {}}
        fixture_pose = {"name": sample["name"], "groundOffset": sample["groundOffset"],
                        "translations": sample["translations"], "rotations": sample["rotations"],
                        "scales": sample["scales"], "expectedPositionsWithRootOffset": {}}
        for section in ("Body", "Head"):
            mesh = UsdGeom.Mesh(reopened.GetPrimAtPath(ROOT + "/" + section))
            binding = UsdSkel.BindingAPI(mesh.GetPrim())
            points = Vt.Vec3fArray(mesh.GetPointsAttr().Get())
            if not UsdSkel.SkinPoints(UsdSkel.Tokens.classicLinear, binding.GetGeomBindTransformAttr().Get(),
                    transforms, binding.GetJointIndicesPrimvar().Get(), binding.GetJointWeightsPrimvar().Get(), 4, points):
                raise ValueError("OpenUSD could not evaluate the packaged skin")
            posed = np.asarray(points) + [0, sample["groundOffset"], 0]
            expected = np.asarray(row["positions"][section])[meshes[section]["indices"]]
            errors = np.linalg.norm(posed - expected, axis=1)
            if float(errors.max()) > POSE_ROUNDTRIP_BUDGET_METRES:
                raise ValueError(f"{sample['name']}/{section} lost weighted Blender pose parity")
            report["sections"][section] = {"maximumWeightedVertexDifferenceMetres": float(errors.max()),
                "p95WeightedVertexDifferenceMetres": float(np.percentile(errors, 95)),
                "blenderMinimumY": float(expected[:, 1].min()), "packagedMinimumY": float(posed[:, 1].min())}
            fixture_pose["expectedPositionsWithRootOffset"][section] = posed.tolist()
        pose_reports.append(report)
        fixture["poses"].append(fixture_pose)
    after = checked_sources()
    if after != before:
        raise ValueError("Protected input changed")
    licence = REPOSITORY / "ReplayXI/Resources/Players/LICENSE-ROCKETBOX-MIT.txt"
    (output / licence.name).write_bytes(licence.read_bytes())
    fixture_path = output / "native-admission-fixture.json"
    fixture_path.write_text(json.dumps(fixture, separators=(",", ":"), allow_nan=False) + "\n")
    report = {"candidateOnly": True, "usdVersion": list(Usd.GetVersion()),
              "sourceHashes": before, "packageSHA256": digest(package), "packageBytes": package.stat().st_size,
              "referenceSHA256": digest(args.reference), "canonicalJointCount": 80,
              "nativeAdmissionFixtureSHA256": digest(fixture_path),
              "sourceToCanonicalIndex": remap.tolist(), "originalOrderAlreadyCanonical": bool(np.array_equal(remap, np.arange(80))),
              "preservedExact": list(preserved_names), "glbBakedGroundOffsetRemoved": offset.tolist(),
              "maximumGLBBindVsBlenderDifference": bind_error,
              "maximumSourceBindVsBlenderDifference": float(np.max(abs(canonical_bind - blender_bind))),
              "posedRoundtripBudgetMetres": POSE_ROUNDTRIP_BUDGET_METRES,
              "meshes": mesh_reports, "poses": pose_reports, "skinAudit": skin_audit, "archiveAudit": archive_audit,
              "limits": ["No RealityKit import or live cap change", "No candidate contact-surface calibration",
                         "80-bone CPU pose cost remains", "Four poses only; not all joints/views",
                         "Root lift is applied once by presentation; it is not baked in canonical points"]}
    (output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print("LOW102_CANONICAL", str(package), "vertices", sum(value["vertices"] for value in mesh_reports.values()),
          "maximumPoseDifferenceMetres", max(section["maximumWeightedVertexDifferenceMetres"]
              for pose in pose_reports for section in pose["sections"].values()))


if __name__ == "__main__":
    main()
