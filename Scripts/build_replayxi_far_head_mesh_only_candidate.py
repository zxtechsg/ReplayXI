#!/usr/bin/env python3
"""Loop122 derived-only static head package: identical mesh, neutral material.

Run with the bundled Blender Python (OpenUSD required). The runtime may replace
this neutral PBR material with its prepared head palette, but this script does
not activate the candidate or establish native import/render/performance parity.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade

from replayxi_usdz_archive import normalize_usdz_timestamps, validated_archive_names


REPOSITORY = Path(__file__).resolve().parents[1]
SOURCE = REPOSITORY / ".codex-derived/ReplayXI-Far114-Head-02/ReplayXIFar114Head.usdz"
SOURCE_SHA = "0e8f602695ca0cca505a462db1e8f6a318b8aa72dcd914e0fcce2986bff3d1ce"
ROOT = "/ReplayXIAthleteHead"
MATERIAL = ROOT + "/Material"
FACE = ROOT + "/Face"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_hashes() -> dict[str, str]:
    return {str(path.relative_to(REPOSITORY)): sha(path)
            for path in sorted((REPOSITORY / "ReplayXI/Resources/Players").glob("*"))
            if path.is_file()}


def members(path: Path) -> list[dict]:
    with zipfile.ZipFile(path) as archive:
        validated_archive_names(archive.infolist())
        return [{"name": info.filename, "bytes": info.file_size,
                 "sha256": hashlib.sha256(archive.read(info.filename)).hexdigest()}
                for info in archive.infolist()]


def mesh_text(stage: Usd.Stage) -> str:
    return stage.GetPrimAtPath(FACE).GetPrimStack()[0].GetAsText()


def verify(source: Usd.Stage, candidate: Usd.Stage) -> dict:
    """Exact authored USD parity, not a tolerance-based geometric comparison."""
    if mesh_text(source) != mesh_text(candidate):
        raise ValueError("Face prim spec changed (geometry, normals, UV, binding or metadata)")
    if source.GetPseudoRoot().GetAllMetadata() != candidate.GetPseudoRoot().GetAllMetadata():
        raise ValueError("Stage metadata changed")
    for path in (ROOT, FACE):
        a, b = source.GetPrimAtPath(path), candidate.GetPrimAtPath(path)
        if a.GetAllMetadata() != b.GetAllMetadata():
            raise ValueError(f"Prim metadata changed: {path}")
        if UsdGeom.XformCache().GetLocalToWorldTransform(a) != UsdGeom.XformCache().GetLocalToWorldTransform(b):
            raise ValueError(f"Transform changed: {path}")
    meshes = [p for p in candidate.Traverse() if p.IsA(UsdGeom.Mesh)]
    materials = [p for p in candidate.Traverse() if p.IsA(UsdShade.Material)]
    if len(meshes) != 1 or len(materials) != 1:
        raise ValueError("Unexpected mesh/material count")
    if any(p.GetTypeName() in ("Skeleton", "SkelRoot") for p in candidate.Traverse()):
        raise ValueError("Static candidate has a skeleton")
    for prim in candidate.Traverse():
        for attr in prim.GetAttributes():
            if attr.GetTypeName() in (Sdf.ValueTypeNames.Asset, Sdf.ValueTypeNames.AssetArray):
                raise ValueError(f"Remaining external asset attribute: {attr.GetPath()}")
    material = UsdShade.Material(candidate.GetPrimAtPath(MATERIAL))
    surface, _, _ = material.ComputeSurfaceSource()
    if not surface or surface.GetIdAttr().Get() != "UsdPreviewSurface":
        raise ValueError("Expected the same Preview Surface PBR shader type")
    if surface.GetInput("diffuseColor").Get() != Gf.Vec3f(1):
        raise ValueError("Candidate material is not neutral white")
    mesh = UsdGeom.Mesh(meshes[0])
    points, counts = mesh.GetPointsAttr().Get(), mesh.GetFaceVertexCountsAttr().Get()
    if len(points) != 486 or len(counts) != 749 or any(v != 3 for v in counts):
        raise ValueError("Frozen114 topology changed")
    return {
        "vertices": len(points), "triangles": len(counts),
        "normals": len(mesh.GetNormalsAttr().Get()),
        "uvs": len(UsdGeom.PrimvarsAPI(mesh).GetPrimvar("st").Get()),
        "meshes": len(meshes), "materials": len(materials), "skeletons": 0,
        "bounds": [list(v) for v in mesh.GetExtentAttr().Get()],
        "exactFaceSpecSHA256": hashlib.sha256(mesh_text(candidate).encode()).hexdigest(),
        "exactFaceSpecEquality": True, "exactStageMetadataEquality": True,
        "exactRootAndFaceTransformEquality": True,
        "nativeImportParityVerified": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(REPOSITORY / ".codex-derived"):
        raise ValueError("Choose a NEW directory inside .codex-derived")
    if sha(SOURCE) != SOURCE_SHA:
        raise ValueError("Frozen114 source identity changed")
    protected_before = protected_hashes()
    source = Usd.Stage.Open(str(SOURCE))
    if not source:
        raise ValueError("Could not open the frozen source package")
    output.mkdir(parents=True)
    layer_path = output / "ReplayXIFar122Head.usdc"
    source.GetRootLayer().Export(str(layer_path))
    candidate = Usd.Stage.Open(str(layer_path))
    shader = UsdShade.Shader(candidate.GetPrimAtPath(MATERIAL + "/Surface"))
    colour = shader.GetInput("diffuseColor")
    colour.DisconnectSource()
    colour.Set(Gf.Vec3f(1))
    normal = shader.GetInput("normal")
    normal.DisconnectSource()
    shader.GetPrim().RemoveProperty("inputs:normal")
    for name in ("ST", "Colour", "Normal"):
        candidate.RemovePrim(MATERIAL + "/" + name)
    candidate.GetRootLayer().Save()
    verify(source, candidate)
    package = output / "ReplayXIFar122Head.usdz"
    packaged = subprocess.run(["/usr/bin/usdzip", "--arkitAsset", str(layer_path), str(package)],
                              capture_output=True, text=True, check=True)
    normalize_usdz_timestamps(package)
    package_stage = Usd.Stage.Open(str(package))
    geometry = verify(source, package_stage)
    candidate_members = members(package)
    if len(candidate_members) != 1 or not candidate_members[0]["name"].endswith(".usdc"):
        raise ValueError("Candidate package must contain only its stage")
    checker = subprocess.run(["/usr/bin/usdchecker", "--arkit", "-t", str(package)],
                             capture_output=True, text=True, check=True)
    licence = REPOSITORY / "ReplayXI/Resources/Players/LICENSE-ROCKETBOX-MIT.txt"
    shutil.copyfile(licence, output / licence.name)
    protected_after = protected_hashes()
    if protected_before != protected_after or sha(SOURCE) != SOURCE_SHA:
        raise ValueError("Protected source/resource identity changed")
    original_members = members(SOURCE)
    report = {
        "schemaVersion": 1, "purpose": "Derived-only mesh package feasibility; not active in app",
        "source": {"path": str(SOURCE), "sha256": SOURCE_SHA, "bytes": SOURCE.stat().st_size,
                   "members": original_members},
        "candidate": {"path": str(package), "sha256": sha(package), "bytes": package.stat().st_size,
                      "members": candidate_members},
        "geometry": geometry,
        "removedPNGBytes": sum(v["bytes"] for v in original_members if v["name"].endswith(".png")),
        "packageByteReduction": SOURCE.stat().st_size - package.stat().st_size,
        "licenceSHA256": sha(licence), "protectedShippingHashes": protected_after,
        "protectedShippingHashesUnchanged": True,
        "usdzipOutput": packaged.stdout + packaged.stderr,
        "usdcheckerOutput": checker.stdout + checker.stderr,
        "limits": ["No native import, tangent, image, cold-load time or memory parity measured",
                   "Native importer may derive tangent data differently without a normal map",
                   "Only redundant imported material textures are removed; shared runtime palette is unchanged"],
    }
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"candidate": report["candidate"], "geometry": geometry,
                      "removedPNGBytes": report["removedPNGBytes"],
                      "packageByteReduction": report["packageByteReduction"]}, indent=2))


if __name__ == "__main__":
    main()
