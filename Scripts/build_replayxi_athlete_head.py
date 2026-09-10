#!/usr/bin/env python3
"""Extract the MIT Rocketbox head for Replay XI's articulated near athlete.

The body continues to use Replay XI's deterministic football rig. This static
mesh includes facial anatomy, ears and short hair, with a shared 512px normal
map and five skin palettes. It contains no source kit artwork or animation.
Requires Pillow, numpy, usd-core and Assimp 6.0; inputs come from the existing
hash-pinned fetch_replayxi_rocketbox_pilot.py acquisition.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from build_replayxi_rocketbox_pilot import (
    EXPECTED_ASSIMP_EXPORTS,
    MODEL_RELATIVE,
    TEXTURE_ROOT_RELATIVE,
    read_accessor,
    sha256_file,
)
from fetch_replayxi_rocketbox_pilot import PILOT_ASSETS, ROCKETBOX_COMMIT, audit_directory
from replayxi_usdz_archive import normalize_usdz_timestamps

SKIN_PALETTES = [
    (0.91, 0.70, 0.54),
    (0.74, 0.49, 0.32),
    (0.52, 0.31, 0.20),
    (0.34, 0.195, 0.145),
    (0.82, 0.59, 0.41),
]


def head_geometry(document: dict, binary: bytes) -> tuple[list, list, list, list]:
    """Convert the locked Z-up centimetre mesh into a head-local Y-up mesh."""
    primitive = document["meshes"][0]["primitives"][1]
    if primitive.get("material") != 1 or primitive.get("mode") != 4:
        raise RuntimeError("head primitive identity changed")
    attributes = primitive["attributes"]
    source = read_accessor(document, binary, attributes["POSITION"])
    normals = read_accessor(document, binary, attributes["NORMAL"])
    source_uv = read_accessor(document, binary, attributes["TEXCOORD_0"])
    # Assimp's glTF export addresses the top-origin PNG. USD's texture reader
    # samples from the bottom, so retain the horizontal and invert vertical UV.
    uv = [(u, 1 - v) for u, v in source_uv]
    indices = [int(item[0]) for item in read_accessor(document, binary, primitive["indices"])]
    if len(source) != 1_724 or len(indices) != 9_384:
        raise RuntimeError("head topology changed")
    # Rotate Z-up to Y-up. The head origin matches Replay XI's gaze pivot;
    # the authored neck replaces the procedural shell at the shirt collar.
    points = [(x / 100, (z - 164.5) / 100, -y / 100 - 0.025) for x, y, z in source]
    normals = [(x, z, -y) for x, y, z in normals]
    return points, normals, uv, indices


def make_skin_palette(image, colour: tuple[float, float, float]):
    """Retain face detail and dark hair while matching the existing rig's skin."""
    import numpy as np
    from PIL import Image

    rgb = np.asarray(image.convert("RGB"), dtype=np.float32) / 255
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # Authored atlas chroma separates skin from eye whites, blue irises and hair.
    chroma = np.clip((red - blue - 0.025) / 0.09, 0, 1)
    brightness = np.clip((red - 0.12) / 0.16, 0, 1)
    warmth = np.clip((red - green + 0.005) / 0.045, 0, 1)
    weight = (chroma * brightness * warmth)[..., None]
    reference = np.array([0.78, 0.58, 0.44], dtype=np.float32)
    target = np.asarray(colour, dtype=np.float32)
    recoloured = rgb * target / reference
    result = rgb * (1 - weight) + recoloured * weight
    return Image.fromarray(np.uint8(np.clip(result * 255, 0, 255)))


def build(source_root: Path, output: Path) -> dict:
    from PIL import Image
    from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, Vt

    errors = audit_directory(source_root, PILOT_ASSETS)
    if errors:
        raise RuntimeError("Rocketbox source verification failed: " + "; ".join(errors))
    output.mkdir(parents=True, exist_ok=True)
    resource_names = ["ReplayXIAthleteHead.usdz", "LICENSE-ROCKETBOX-MIT.txt"]
    resource_names += [f"ReplayXIAthleteSkin{index}.png" for index in range(5)]
    if any((output / name).exists() for name in resource_names):
        raise RuntimeError("output already contains head resources; choose an empty output directory")

    with tempfile.TemporaryDirectory(prefix="replayxi-head-") as temporary:
        work = Path(temporary)
        subprocess.run([
            "assimp", "export", str(source_root / MODEL_RELATIVE),
            str(work / "model.gltf"), "-fgltf2",
        ], check=True, capture_output=True)
        if sha256_file(work / "model.gltf") != EXPECTED_ASSIMP_EXPORTS["model.gltf"]:
            raise RuntimeError("Assimp document layout changed")
        document = json.loads((work / "model.gltf").read_text())
        points, normals, uv, indices = head_geometry(document, (work / "model.bin").read_bytes())
        # Assimp can vary unused skin-buffer padding between invocations. Lock
        # every actual value consumed by this static export independently.
        geometry_hash = hashlib.sha256(json.dumps(
            (points, normals, uv, indices), separators=(",", ":"), allow_nan=False,
        ).encode()).hexdigest()
        if geometry_hash != "31a6bbca3b396e201ceb7a112c823fb2292d5784f505e7d6c5c58c0792eda15d":
            raise RuntimeError("head geometry, normals or UVs changed")
        textures = source_root / TEXTURE_ROOT_RELATIVE
        diffuse = Image.open(textures / "m301_head_color.tga").convert("RGB").resize(
            (512, 512), Image.Resampling.LANCZOS,
        )
        normal = Image.open(textures / "m301_head_normal.tga").convert("RGB").resize(
            (512, 512), Image.Resampling.LANCZOS,
        )
        palette_images = [make_skin_palette(diffuse, colour) for colour in SKIN_PALETTES]
        palette_images[0].save(work / "head_colour.png", optimize=True)
        normal.save(work / "head_normal.png", optimize=True)

        stage = Usd.Stage.CreateNew(str(work / "head.usdc"))
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1)
        root = UsdGeom.Xform.Define(stage, "/ReplayXIAthleteHead")
        stage.SetDefaultPrim(root.GetPrim())
        root.GetPrim().SetCustomDataByKey("sourceCommit", ROCKETBOX_COMMIT)
        root.GetPrim().SetCustomDataByKey("license", (source_root / "LICENSE.md").read_text())
        mesh = UsdGeom.Mesh.Define(stage, "/ReplayXIAthleteHead/Face")
        mesh.CreatePointsAttr(Vt.Vec3fArray(points))
        mesh.CreateFaceVertexCountsAttr([3] * (len(indices) // 3))
        mesh.CreateFaceVertexIndicesAttr(indices)
        mesh.CreateNormalsAttr(Vt.Vec3fArray(normals))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateExtentAttr(UsdGeom.PointBased(mesh).ComputeExtent(Vt.Vec3fArray(points)))
        UsdGeom.PrimvarsAPI(mesh).CreatePrimvar(
            "st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex,
        ).Set(Vt.Vec2fArray(uv))

        material = UsdShade.Material.Define(stage, "/ReplayXIAthleteHead/Material")
        shader = UsdShade.Shader.Define(stage, "/ReplayXIAthleteHead/Material/Surface")
        shader.CreateIdAttr("UsdPreviewSurface")
        shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.73)
        shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0)
        st = UsdShade.Shader.Define(stage, "/ReplayXIAthleteHead/Material/ST")
        st.CreateIdAttr("UsdPrimvarReader_float2")
        st.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
        for name, filename, input_name, value_type, colour_space in [
            ("Colour", "head_colour.png", "diffuseColor", Sdf.ValueTypeNames.Color3f, "sRGB"),
            ("Normal", "head_normal.png", "normal", Sdf.ValueTypeNames.Normal3f, "raw"),
        ]:
            texture = UsdShade.Shader.Define(stage, f"/ReplayXIAthleteHead/Material/{name}")
            texture.CreateIdAttr("UsdUVTexture")
            texture.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath(filename))
            texture.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set(colour_space)
            texture.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(st.ConnectableAPI(), "result")
            if name == "Normal":
                texture.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2, 2, 2, 1))
                texture.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1, -1, -1, 0))
            shader.CreateInput(input_name, value_type).ConnectToSource(texture.ConnectableAPI(), "rgb")
        material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material)
        stage.GetRootLayer().Save()
        package = work / "ReplayXIAthleteHead.usdz"
        subprocess.run([
            "usdzip", "--arkitAsset", str(work / "head.usdc"), str(package),
        ], check=True, capture_output=True)
        normalize_usdz_timestamps(package)
        subprocess.run(["usdchecker", "--arkit", str(package)], check=True)
        (output / resource_names[0]).write_bytes(package.read_bytes())
        (output / resource_names[1]).write_bytes((source_root / "LICENSE.md").read_bytes())
        for index, image in enumerate(palette_images):
            image.save(output / f"ReplayXIAthleteSkin{index}.png", optimize=True)

    return {
        "sourceCommit": ROCKETBOX_COMMIT,
        "vertices": len(points), "triangles": len(indices) // 3,
        "bounds": [[min(p[i] for p in points), max(p[i] for p in points)] for i in range(3)],
        "textureSize": 512,
        "files": {name: {"sha256": sha256_file(output / name), "bytes": (output / name).stat().st_size}
                  for name in resource_names},
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.output), indent=2, sort_keys=True))
