#!/usr/bin/env python3
"""Canonicalise the original Blender-MCP124 meshes without changing their shape.

The live Blender file intentionally uses the app's Y-up local coordinates.
Only stage metadata and hierarchy are canonicalised; points are not rotated.
Output is derived-only until native mesh, skin, budget and render tests pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, Vt

from replayxi_usdz_archive import normalize_usdz_timestamps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / ".codex-derived/ReplayXI-Players124-Anatomy-01/ReplayXIFarAnatomy.usdc"


def hash_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def flattened(primvar):
    return primvar.ComputeFlattened()


def compact(mesh):
    """Keep split attributes, weights and winding; merge only exact tuples."""
    points = mesh.GetPointsAttr().Get()
    indices = mesh.GetFaceVertexIndicesAttr().Get()
    counts = mesh.GetFaceVertexCountsAttr().Get()
    if any(value != 3 for value in counts):
        raise ValueError("Expected explicitly triangulated Blender source")
    normals = mesh.GetNormalsAttr().Get()
    uv = UsdGeom.PrimvarsAPI(mesh).GetPrimvar("st")
    texcoords = flattened(uv)
    binding = UsdSkel.BindingAPI(mesh.GetPrim())
    joint_indices = binding.GetJointIndicesPrimvar()
    joint_weights = binding.GetJointWeightsPrimvar()
    width = joint_weights.GetElementSize() if joint_weights else 0
    source_joints = flattened(joint_indices) if joint_indices else []
    source_weights = flattened(joint_weights) if joint_weights else []
    out = {"positions": [], "normals": [], "uvs": [], "indices": [], "weights": []}
    table = {}
    for corner, index in enumerate(indices):
        normal = normals[corner if mesh.GetNormalsInterpolation() == "faceVarying" else index]
        coord = texcoords[corner if uv.GetInterpolation() == "faceVarying" else index]
        weights = [0.0, 0.0, 0.0]
        if width:
            for slot in range(width):
                offset = index * width + slot
                weights[int(source_joints[offset])] += float(source_weights[offset])
            if abs(sum(weights) - 1) > 1e-6:
                raise ValueError("Invalid three-joint source weights")
        key = tuple(points[index]), tuple(normal), tuple(coord), tuple(weights)
        if key not in table:
            table[key] = len(out["positions"])
            out["positions"].append(key[0])
            out["normals"].append(key[1])
            out["uvs"].append(key[2])
            out["weights"].append(weights)
        out["indices"].append(table[key])
    return out, binding


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT / ".codex-derived"):
        raise ValueError("Choose a fresh derived output directory")
    output.mkdir(parents=True)
    source = Usd.Stage.Open(str(SOURCE))
    stage = Usd.Stage.CreateNew(str(output / "ReplayXIArticulatedFar.usdc"))
    root = UsdGeom.Xform.Define(stage, "/ReplayXIArticulatedFar")
    stage.SetDefaultPrim(root.GetPrim())
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1)
    root.GetPrim().SetCustomData({"creator": "Replay XI",
        "description": "Original Blender-MCP anatomical far meshes; no reference package geometry or texture copied",
        "sourceSHA256": hash_file(SOURCE)})
    material = UsdShade.Material.Define(stage, "/ReplayXIArticulatedFar/Material")
    shader = UsdShade.Shader.Define(stage, "/ReplayXIArticulatedFar/Material/Surface")
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(1))
    shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0)
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.8)
    material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
    parts = {}
    for prim in source.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        kind = next(name for name in ["Torso", "Shorts", "Arm", "Leg"] if "_" + name + "_Mesh" in prim.GetName())
        geometry, binding = compact(UsdGeom.Mesh(prim))
        transform = UsdGeom.XformCache().GetLocalToWorldTransform(prim)
        if transform != Gf.Matrix4d(1):
            raise ValueError("Source geometry must have identity object transforms")
        skeleton_paths = binding.GetSkeletonRel().GetTargets()
        if skeleton_paths:
            target_root = UsdSkel.Root.Define(stage, "/ReplayXIArticulatedFar/" + kind)
            skeleton = UsdSkel.Skeleton.Define(stage, str(target_root.GetPath()) + "/Skeleton")
            source_skeleton = UsdSkel.Skeleton(source.GetPrimAtPath(skeleton_paths[0]))
            names = source_skeleton.GetJointsAttr().Get()
            if list(names) != ["Root", "Root/Bend", "Root/Bend/Tip"]:
                raise ValueError("Three-joint limb names changed")
            skeleton.CreateJointsAttr().Set(names)
            skeleton.CreateRestTransformsAttr().Set(source_skeleton.GetRestTransformsAttr().Get())
            skeleton.CreateBindTransformsAttr().Set(source_skeleton.GetBindTransformsAttr().Get())
            mesh = UsdGeom.Mesh.Define(stage, str(target_root.GetPath()) + "/Mesh")
            skin = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
            skin.CreateSkeletonRel().SetTargets([skeleton.GetPath()])
            skin.CreateGeomBindTransformAttr().Set(Gf.Matrix4d(1))
            skin.CreateJointIndicesPrimvar(False, 3).Set(Vt.IntArray([value for _ in geometry["positions"] for value in (0, 1, 2)]))
            skin.CreateJointWeightsPrimvar(False, 3).Set(Vt.FloatArray([value for weights in geometry["weights"] for value in weights]))
        else:
            mesh = UsdGeom.Mesh.Define(stage, "/ReplayXIArticulatedFar/" + kind)
        mesh.CreatePointsAttr().Set(Vt.Vec3fArray(geometry["positions"]))
        mesh.CreateNormalsAttr().Set(Vt.Vec3fArray(geometry["normals"]))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateFaceVertexCountsAttr().Set(Vt.IntArray([3] * (len(geometry["indices"]) // 3)))
        mesh.CreateFaceVertexIndicesAttr().Set(Vt.IntArray(geometry["indices"]))
        mesh.CreateSubdivisionSchemeAttr().Set(UsdGeom.Tokens.none)
        mesh.CreateExtentAttr().Set(UsdGeom.PointBased(mesh).ComputeExtent(mesh.GetPointsAttr().Get()))
        UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray,
                                             UsdGeom.Tokens.vertex).Set(Vt.Vec2fArray(geometry["uvs"]))
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material)
        parts[kind] = {"vertices": len(geometry["positions"]), "triangles": len(geometry["indices"]) // 3,
                       "joints": 3 if skeleton_paths else 0, "geometry": geometry}
    if set(parts) != {"Torso", "Shorts", "Leg", "Arm"}:
        raise ValueError("Missing canonical part")
    count = {name: sum(parts[p][name] * (2 if p in ["Leg", "Arm"] else 1) for p in parts)
             for name in ["vertices", "triangles"]}
    count["vertices"] += 486
    count["triangles"] += 749
    if count["vertices"] > 1800 or count["triangles"] > 2500:
        raise ValueError(f"Far body with retained face exceeds unchanged budget: {count}")
    stage.GetRootLayer().Save()
    package = output / "ReplayXIArticulatedFar.usdz"
    subprocess.run(["/usr/bin/usdzip", "--arkitAsset", str(output / "ReplayXIArticulatedFar.usdc"), str(package)],
                   capture_output=True, check=True)
    normalize_usdz_timestamps(package)
    checker = subprocess.run(["/usr/bin/usdchecker", "--arkit", "-t", str(package)],
                             capture_output=True, text=True, check=True)
    report = {"schemaVersion": 1, "assetSHA256": hash_file(package), "assetBytes": package.stat().st_size,
              "sourceSHA256": hash_file(SOURCE), "source": str(SOURCE), "parts": parts,
              "completeFarBody": {**count, "models": 7, "limbJoints": 12, "licensedFaceSeparate": True},
              "usdChecker": checker.stdout + checker.stderr}
    (output / "manifest.json").write_text(json.dumps(report, separators=(",", ":")) + "\n")
    print(json.dumps({"assetSHA256": report["assetSHA256"], "assetBytes": report["assetBytes"],
                      "completeFarBody": report["completeFarBody"],
                      "parts": {name: {k: v for k, v in part.items() if k != "geometry"} for name, part in parts.items()}}, indent=2))


if __name__ == "__main__":
    main()
