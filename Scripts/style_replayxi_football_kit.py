#!/usr/bin/env python3
"""Build an opaque, skinned Replay XI football kit around the CC0 rig fixture.

The source character remains a technical retargeting fixture. This pass creates
four slightly expanded skinned shells (jersey, shorts, socks, boots) from its
existing weighted topology, so skin and anatomy textures cannot read as the
player's clothing in the app. The shells keep the source skeleton bindings and
therefore follow the authored sprint animation without a second rig.
"""

from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade

from replayxi_usdz_archive import normalize_usdz_timestamps, validated_archive_names


BODY_PRIM_SUFFIX = "/SuperHero_Male_67/skeleton_root/primitive_0"


def face_centroid(points, indices):
    count = float(len(indices))
    return tuple(sum(points[index][axis] for index in indices) / count for axis in range(3))


def build_material(stage: Usd.Stage, name: str, color: tuple[float, float, float], roughness: float):
    material = UsdShade.Material.Define(stage, f"/root/Materials/{name}")
    shader = UsdShade.Shader.Define(stage, f"/root/Materials/{name}/PreviewSurface")
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*color))
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(roughness)
    shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
    material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
    return material


def expanded_points(points, normals, amount: float):
    result = []
    for point, normal in zip(points, normals):
        length = math.sqrt(sum(float(value) * float(value) for value in normal))
        if length < 1e-8:
            result.append(point)
            continue
        result.append(
            Gf.Vec3f(
                float(point[0]) + (float(normal[0]) / length * amount),
                float(point[1]) + (float(normal[1]) / length * amount),
                float(point[2]) + (float(normal[2]) / length * amount),
            )
        )
    return result


def copy_shell(
    stage: Usd.Stage,
    body: UsdGeom.Mesh,
    name: str,
    selected_faces: list[int],
    material: UsdShade.Material,
    expansion: float,
):
    source_path = body.GetPath()
    target_path = source_path.GetParentPath().AppendChild(name)
    layer = stage.GetRootLayer()
    if layer.GetPrimAtPath(target_path):
        layer.RemovePrim(target_path)
    if not Sdf.CopySpec(layer, source_path, layer, target_path):
        raise RuntimeError(f"Could not clone body mesh for {name}")

    shell = UsdGeom.Mesh(stage.GetPrimAtPath(target_path))
    points = body.GetPointsAttr().Get()
    normals = body.GetNormalsAttr().Get()
    counts = body.GetFaceVertexCountsAttr().Get()
    indices = body.GetFaceVertexIndicesAttr().Get()

    offsets = []
    cursor = 0
    for count in counts:
        offsets.append((cursor, int(count)))
        cursor += int(count)

    shell_counts = []
    shell_indices = []
    for face_index in selected_faces:
        start, count = offsets[face_index]
        shell_counts.append(count)
        shell_indices.extend(indices[start : start + count])

    # Compact every shell to just the vertices its selected faces reference.
    # Besides reducing the asset, this keeps vertex primvar cardinality valid
    # for both Hydra and RealityKit's skinner.
    used_vertices = sorted(set(int(index) for index in shell_indices))
    remap = {old: new for new, old in enumerate(used_vertices)}
    shell_indices = [remap[int(index)] for index in shell_indices]
    expanded = expanded_points(points, normals, expansion)

    shell.GetFaceVertexCountsAttr().Set(shell_counts)
    shell.GetFaceVertexIndicesAttr().Set(shell_indices)
    shell.GetPointsAttr().Set([expanded[index] for index in used_vertices])
    shell.GetNormalsAttr().Set([normals[index] for index in used_vertices])

    for primvar in UsdGeom.PrimvarsAPI(shell).GetPrimvars():
        if primvar.GetInterpolation() not in (UsdGeom.Tokens.vertex, UsdGeom.Tokens.varying):
            continue
        values = primvar.Get()
        if values is None:
            continue
        element_size = max(int(primvar.GetElementSize()), 1)
        if len(values) == len(points):
            primvar.Set([values[index] for index in used_vertices])
        elif len(values) == len(points) * element_size:
            compacted = []
            for index in used_vertices:
                start = index * element_size
                compacted.extend(values[start : start + element_size])
            primvar.Set(compacted)

    shell.GetExtentAttr().Set(UsdGeom.PointBased(shell).ComputeExtent(shell.GetPointsAttr().Get()))
    shell.GetPrim().SetMetadata("comment", "Replay XI original football-kit shell; derived from CC0 weighted topology")
    UsdShade.MaterialBindingAPI.Apply(shell.GetPrim()).Bind(material)


def classify_faces(body: UsdGeom.Mesh):
    points = body.GetPointsAttr().Get()
    counts = body.GetFaceVertexCountsAttr().Get()
    indices = body.GetFaceVertexIndicesAttr().Get()
    groups = {"ReplayXI_Jersey": [], "ReplayXI_Shorts": [], "ReplayXI_Socks": [], "ReplayXI_Boots": [], "ReplayXI_Trim": []}

    cursor = 0
    for face_index, count in enumerate(counts):
        count = int(count)
        face = indices[cursor : cursor + count]
        cursor += count
        x, y, _ = face_centroid(points, face)
        ax = abs(x)

        # The source is in a T-pose. These bands form a conventional short-
        # sleeve football kit while leaving head, neck, forearms and thighs as
        # skin. Boundary faces intentionally overlap the trim shell so there
        # are no anatomy-coloured gaps during deformation.
        if y <= 0.145 and ax < 0.34:
            groups["ReplayXI_Boots"].append(face_index)
        elif 0.115 < y <= 0.54 and ax < 0.31:
            groups["ReplayXI_Socks"].append(face_index)
        elif 0.69 < y <= 0.99 and ax < 0.41:
            groups["ReplayXI_Shorts"].append(face_index)
        elif (0.96 < y <= 1.50 and ax < 0.39) or (1.24 < y <= 1.50 and 0.39 <= ax < 0.54):
            groups["ReplayXI_Jersey"].append(face_index)

        if (0.92 < y < 1.01 and ax < 0.42) or (1.27 < y < 1.48 and 0.43 < ax < 0.55):
            groups["ReplayXI_Trim"].append(face_index)

    return groups


def build(input_usdz: Path, output_usdz: Path):
    if not input_usdz.is_file():
        raise FileNotFoundError(input_usdz)
    output_usdz.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="replayxi-kit-") as temporary:
        work = Path(temporary)
        with zipfile.ZipFile(input_usdz) as archive:
            validated_archive_names(archive.infolist())
            archive.extractall(work)
        layers = sorted(work.glob("*.usd*"))
        if len(layers) != 1:
            raise RuntimeError(f"Expected one root USD layer, found {len(layers)}")

        stage = Usd.Stage.Open(str(layers[0]))
        body_prim = next(
            (prim for prim in stage.Traverse() if prim.GetPath().pathString.endswith(BODY_PRIM_SUFFIX)),
            None,
        )
        if body_prim is None or not body_prim.IsA(UsdGeom.Mesh):
            raise RuntimeError("Could not locate the weighted source body mesh")
        body = UsdGeom.Mesh(body_prim)
        groups = classify_faces(body)
        if any(not faces for faces in groups.values()):
            raise RuntimeError(f"One or more kit shells are empty: {groups}")

        materials = {
            "ReplayXI_Jersey": build_material(stage, "ReplayXI_Home_Jersey", (0.90, 0.94, 0.98), 0.78),
            "ReplayXI_Shorts": build_material(stage, "ReplayXI_Home_Shorts", (0.025, 0.055, 0.13), 0.82),
            "ReplayXI_Socks": build_material(stage, "ReplayXI_Home_Socks", (0.92, 0.95, 0.98), 0.86),
            "ReplayXI_Boots": build_material(stage, "ReplayXI_Boots", (0.012, 0.016, 0.022), 0.48),
            "ReplayXI_Trim": build_material(stage, "ReplayXI_Home_Trim", (0.64, 0.88, 0.12), 0.70),
        }
        expansions = {
            "ReplayXI_Jersey": 0.016,
            "ReplayXI_Shorts": 0.020,
            "ReplayXI_Socks": 0.011,
            "ReplayXI_Boots": 0.014,
            "ReplayXI_Trim": 0.024,
        }
        for name, faces in groups.items():
            copy_shell(stage, body, name, faces, materials[name], expansions[name])

        stage.SetMetadata("comment", "Replay XI licensed CC0 skinned player with original opaque football-kit shells")
        stage.GetRootLayer().Save()

        temporary_output = work / "ReplayXIPlayerKit.usdz"
        subprocess.run(
            ["/usr/bin/usdzip", "--arkitAsset", layers[0].name, temporary_output.name],
            cwd=work,
            check=True,
        )
        normalize_usdz_timestamps(temporary_output)
        subprocess.run(
            ["/usr/bin/usdchecker", "--arkit", "-t", temporary_output.name],
            cwd=work,
            check=True,
        )
        audit_script = Path(__file__).with_name("audit_replayxi_player_usdz.py")
        subprocess.run([sys.executable, str(audit_script), str(temporary_output)], check=True)
        shutil.copy2(temporary_output, output_usdz)

        print("Built", output_usdz)
        print("Shell face counts:", {name: len(faces) for name, faces in groups.items()})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_usdz", type=Path)
    parser.add_argument("output_usdz", type=Path)
    arguments = parser.parse_args()
    build(arguments.input_usdz, arguments.output_usdz)


if __name__ == "__main__":
    main()
