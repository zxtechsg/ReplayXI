#!/usr/bin/env python3
"""Build the MIT Rocketbox football body and deterministic idle/run pose data.

Uses the inputs fetched by fetch_replayxi_rocketbox_pilot.py. Requires Assimp,
numpy, Pillow, usd-core and Apple's usdzip/usdchecker. The USD has one clean
80-joint skeleton and two meshes; runtime local TRS arrays use its exact order.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, Vt

from build_replayxi_athlete_head import SKIN_PALETTES, make_skin_palette
from build_replayxi_rocketbox_pilot import (
    MODEL_RELATIVE, RUN_RELATIVE, TEXTURE_ROOT_RELATIVE,
    audit_usd_skinning, neutralize_body_texture_arrays, read_accessor, sha256_file,
    snapshot_verified_files,
)
from fetch_replayxi_rocketbox_pilot import PILOT_ASSETS, ROCKETBOX_COMMIT
from replayxi_usdz_archive import normalize_usdz_timestamps

IDLE_RELATIVE = "Assets/Animations/all_animations_max_motextr_static/m_idle_breathe_01.max.fbx"
ROOT_PATH = "/ReplayXIRocketbox"
SEMANTIC_SOURCE = {
    "hips": "Bip01 Pelvis", "spine": "Bip01 Spine", "chest": "Bip01 Spine2",
    "neck": "Bip01 Neck", "head": "Bip01 Head",
    "leftHip": "Bip01 L Thigh", "rightHip": "Bip01 R Thigh",
    "leftKnee": "Bip01 L Calf", "rightKnee": "Bip01 R Calf",
    "leftAnkle": "Bip01 L Foot", "rightAnkle": "Bip01 R Foot",
    "leftToe": "Bip01 L Toe0", "rightToe": "Bip01 R Toe0",
    "leftShoulder": "Bip01 L UpperArm", "rightShoulder": "Bip01 R UpperArm",
    "leftElbow": "Bip01 L Forearm", "rightElbow": "Bip01 R Forearm",
    "leftWrist": "Bip01 L Hand", "rightWrist": "Bip01 R Hand",
}


def rounded(values, places=7):
    return [round(float(value), places) for value in values]


def local_matrix(node):
    if "matrix" in node:
        return np.asarray(node["matrix"], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rotation = np.asarray(Gf.Matrix4d().SetRotate(Gf.Quatd(w, x, y, z))).T
    rotation[:3, :3] = rotation[:3, :3] @ np.diag(node.get("scale", [1, 1, 1]))
    rotation[:3, 3] = node.get("translation", [0, 0, 0])
    return rotation


def global_matrices(document, overrides=None):
    overrides = overrides or {}
    parents = {child: index for index, node in enumerate(document["nodes"])
               for child in node.get("children", [])}
    cache = {}

    def resolve(index):
        if index not in cache:
            node = dict(document["nodes"][index])
            node.update(overrides.get(node["name"], {}))
            parent = resolve(parents[index]) if index in parents else np.eye(4)
            cache[index] = parent @ local_matrix(node)
        return cache[index]

    return [resolve(index) for index in range(len(document["nodes"]))]


def metres(matrix):
    result = matrix.copy()
    result[:3, 3] /= 100
    return result


def usd_matrix(matrix):
    return Gf.Matrix4d(*matrix.T.reshape(-1).tolist())


def decompose(matrix):
    transform = Gf.Transform(usd_matrix(matrix))
    quaternion = transform.GetRotation().GetQuat()
    return (
        rounded(transform.GetTranslation()),
        rounded([*quaternion.GetImaginary(), quaternion.GetReal()]),
        rounded(transform.GetScale()),
    )


def skeleton_contract(model, binary):
    weighted = model["skins"][0]["joints"]
    if len(weighted) != 80 or len(set(weighted)) != 80:
        raise RuntimeError("expected the original 80 weighted joints")
    node_parents = {child: index for index, node in enumerate(model["nodes"])
                    for child in node.get("children", [])}
    weighted_set = set(weighted)
    parents = {}
    for index in weighted:
        parent = node_parents.get(index)
        while parent is not None and parent not in weighted_set:
            parent = node_parents.get(parent)
        parents[index] = parent
    paths = {}

    def path(index):
        if index not in paths:
            source = model["nodes"][index]["name"].removeprefix("Bip01 ")
            identifier = re.sub(r"[^A-Za-z0-9_]", "_", source)
            paths[index] = (path(parents[index]) + "/" if parents[index] is not None else "") + identifier
        return paths[index]

    order = sorted(weighted, key=lambda index: (path(index).count("/"), weighted.index(index)))
    indices = {node: index for index, node in enumerate(order)}
    world = global_matrices(model)
    mesh_node = next(index for index, node in enumerate(model["nodes"]) if node.get("mesh") == 0)
    inverse_bind = read_accessor(model, binary, model["skins"][0]["inverseBindMatrices"])
    bind_by_node = {node: metres(world[mesh_node] @ np.linalg.inv(np.array(inverse).reshape(4, 4).T))
                    for node, inverse in zip(weighted, inverse_bind)}
    rest_world = {node: metres(world[node]) for node in order}
    joints = []
    rest = []
    for node in order:
        parent = parents[node]
        local = np.linalg.inv(rest_world[parent]) @ rest_world[node] if parent is not None else rest_world[node]
        translation, rotation, scale = decompose(local)
        rest.append(local)
        orientation = bind_by_node[node][:3, :3]
        orientation = orientation / np.linalg.norm(orientation, axis=0)
        joints.append({
            "name": path(node), "sourceName": model["nodes"][node]["name"],
            "parentIndex": indices[parent] if parent is not None else -1,
            "translation": translation, "rotation": rotation, "scale": scale,
            "localRightAxis": rounded(orientation.T @ [1, 0, 0]),
            "localUpAxis": rounded(orientation.T @ [0, 1, 0]),
            "localForwardAxis": rounded(orientation.T @ [0, 0, 1]),
        })
    source_paths = {model["nodes"][node]["name"]: path(node) for node in order}
    return {
        "order": order, "indices": indices, "nodeParents": parents,
        "joints": joints, "paths": [path(node) for node in order],
        "bind": [bind_by_node[node] for node in order], "rest": rest,
        "world": rest_world, "meshWorld": world[mesh_node],
        "semanticJoints": {key: source_paths[name] for key, name in SEMANTIC_SOURCE.items()},
        "oldToNew": {old: indices[node] for old, node in enumerate(weighted)},
    }


def interpolate(times, values, time, rotation=False):
    if time <= times[0]:
        return values[0]
    if time >= times[-1]:
        return values[-1]
    high = int(np.searchsorted(times, time, side="right"))
    low = high - 1
    weight = (time - times[low]) / (times[high] - times[low])
    start, end = values[low], values[high]
    if not rotation:
        return start * (1 - weight) + end * weight
    cosine = float(np.dot(start, end))
    if cosine < 0:
        end = -end
        cosine = -cosine
    if cosine > 0.9995:
        value = start * (1 - weight) + end * weight
        return value / np.linalg.norm(value)
    angle = math.acos(min(max(cosine, -1), 1))
    return (start * math.sin((1 - weight) * angle) + end * math.sin(weight * angle)) / math.sin(angle)


def sample_clip(model, animation_document, binary, contract, clip_id):
    animation = animation_document["animations"][0]
    channels = []
    for channel in animation["channels"]:
        sampler = animation["samplers"][channel["sampler"]]
        name = animation_document["nodes"][channel["target"]["node"]]["name"]
        times = np.array(read_accessor(animation_document, binary, sampler["input"])).reshape(-1)
        values = np.array(read_accessor(animation_document, binary, sampler["output"]))
        channels.append((name, channel["target"]["path"], times, values))
    duration = float(max(channel[2][-1] for channel in channels))
    times = np.linspace(0, duration, round(duration * 30) + 1)
    frames = []
    for time in times:
        overrides = {}
        for name, target, key_times, values in channels:
            value = interpolate(key_times, values, time, rotation=target == "rotation").tolist()
            if name == "Bip01_$AssimpFbx$_Translation" and target == "translation":
                value[0] = 0
                value[2] = 0
            overrides.setdefault(name, {})[target] = value
        world = global_matrices(model, overrides)
        translations, rotations, scales = [], [], []
        for node in contract["order"]:
            parent = contract["nodeParents"][node]
            current = metres(world[node])
            local = np.linalg.inv(metres(world[parent])) @ current if parent is not None else current
            translation, rotation, scale = decompose(local)
            if frames:
                previous = frames[-1]["rotations"][len(rotations)]
                if np.dot(previous, rotation) < 0:
                    rotation = [-value for value in rotation]
            translations.append(translation)
            rotations.append(rotation)
            scales.append(scale)
        frames.append({"time": round(float(time), 8), "translations": translations,
                       "rotations": rotations, "scales": scales})
    return {"id": clip_id, "durationSeconds": duration, "fps": 30, "frames": frames}


def mesh_data(model, binary, contract):
    output = []
    for primitive in model["meshes"][0]["primitives"]:
        attributes = primitive["attributes"]
        source_positions = np.asarray(read_accessor(model, binary, attributes["POSITION"]))
        homogeneous = np.column_stack((source_positions, np.ones(len(source_positions))))
        # Explicit contraction avoids spurious Accelerate floating-point flags
        # on small, strided arrays. Check actual outputs instead of suppressing
        # warnings, since invalid geometry must never enter the USD.
        points = np.einsum("ij,nj->ni", contract["meshWorld"], homogeneous)[:, :3] / 100
        normals = np.einsum("ij,nj->ni", contract["meshWorld"][:3, :3],
                            np.asarray(read_accessor(model, binary, attributes["NORMAL"])))
        if not np.isfinite(points).all() or not np.isfinite(normals).all():
            raise RuntimeError("non-finite transformed mesh geometry")
        uv = np.asarray(read_accessor(model, binary, attributes["TEXCOORD_0"]))
        uv[:, 1] = 1 - uv[:, 1]
        weights = np.asarray(read_accessor(model, binary, attributes["WEIGHTS_0"]))
        weights /= weights.sum(axis=1)[:, None]
        source_joints = read_accessor(model, binary, attributes["JOINTS_0"])
        joints = [[contract["oldToNew"][int(index)] for index in row] for row in source_joints]
        indices = np.asarray(read_accessor(model, binary, primitive["indices"]), dtype=int).reshape(-1)
        output.append({"points": points, "normals": normals, "uv": uv,
                       "indices": indices, "joints": np.asarray(joints), "weights": weights})
    if [len(mesh["points"]) for mesh in output] != [3288, 1724]:
        raise RuntimeError("source mesh cardinality changed")
    return output


def make_textures(source, work, output, body_mesh):
    texture_root = source / TEXTURE_ROOT_RELATIVE
    body = np.asarray(Image.open(texture_root / "m301_body_color.tga").convert("RGB"))
    normal = np.asarray(Image.open(texture_root / "m301_body_normal.tga").convert("RGB"))
    _, clean_normal, skin = neutralize_body_texture_arrays(body, normal)
    # Classify the actual body UV triangles by pitch-space garment height.
    # This preserves shorts/socks/boots instead of repainting every garment
    # the same colour. Every non-skin source pixel is regenerated.
    regions = Image.new("L", (2048, 2048), 0)
    draw = ImageDraw.Draw(regions)
    for triangle in body_mesh["indices"].reshape(-1, 3):
        height = float(body_mesh["points"][triangle, 1].mean())
        region = 3 if height < 0.13 else 2 if height < 0.54 else 1 if height < 1.02 else 0
        uv = body_mesh["uv"][triangle]
        polygon = [(float(u * 2047), float((1 - v) * 2047)) for u, v in uv]
        draw.polygon(polygon, fill=region)
    region_pixels = np.asarray(regions)
    yy, xx = np.indices((2048, 2048), dtype=float)
    weave = 0.985 + 0.008 * np.sin(xx * math.pi / 4) * np.sin(yy * math.pi / 4)
    kits = {
        "Home": [(232, 242, 250), (7, 18, 41), (232, 242, 250), (7, 8, 10)],
        "Away": [(184, 12, 19), (19, 20, 24), (184, 12, 19), (7, 8, 10)],
        "Keeper": [(178, 240, 31), (20, 31, 15), (178, 240, 31), (7, 8, 10)],
    }
    names = []
    for kit, colours in kits.items():
        clean = (np.asarray(colours)[region_pixels] * weave[..., None]).clip(0, 255).astype(np.uint8)
        for index, colour in enumerate(SKIN_PALETTES):
            recoloured_skin = np.asarray(make_skin_palette(Image.fromarray(body), colour))
            final = clean.copy()
            final[skin] = recoloured_skin[skin]
            image = Image.fromarray(final).resize((512, 512), Image.Resampling.LANCZOS)
            filename = f"ReplayXIRocketbox{kit}Skin{index}.png"
            image.save(output / filename, optimize=True)
            names.append(filename)
            if kit == "Home" and index == 0:
                image.save(work / "body_colour.png", optimize=True)
    Image.fromarray(clean_normal).resize((1024, 1024), Image.Resampling.LANCZOS).save(work / "body_normal.png", optimize=True)
    head = Image.open(texture_root / "m301_head_color.tga").convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    make_skin_palette(head, SKIN_PALETTES[0]).save(work / "head_colour.png", optimize=True)
    Image.open(texture_root / "m301_head_normal.tga").convert("RGB").resize((512, 512), Image.Resampling.LANCZOS).save(work / "head_normal.png", optimize=True)
    return names


def material(stage, name, colour, normal, roughness):
    root = f"{ROOT_PATH}/{name}"
    value = UsdShade.Material.Define(stage, root)
    shader = UsdShade.Shader.Define(stage, root + "/Surface")
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(roughness)
    shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0)
    reader = UsdShade.Shader.Define(stage, root + "/ST")
    reader.CreateIdAttr("UsdPrimvarReader_float2")
    reader.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
    for suffix, filename, target, kind, colour_space in [
        ("Colour", colour, "diffuseColor", Sdf.ValueTypeNames.Color3f, "sRGB"),
        ("Normal", normal, "normal", Sdf.ValueTypeNames.Normal3f, "raw"),
    ]:
        texture = UsdShade.Shader.Define(stage, root + "/" + suffix)
        texture.CreateIdAttr("UsdUVTexture")
        texture.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath(filename))
        texture.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set(colour_space)
        texture.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), "result")
        if target == "normal":
            texture.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2, 2, 2, 1))
            texture.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1, -1, -1, 0))
        shader.CreateInput(target, kind).ConnectToSource(texture.ConnectableAPI(), "rgb")
    value.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
    return value


def write_usd(path, contract, meshes, clips, notice):
    stage = Usd.Stage.CreateNew(str(path))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1)
    stage.SetTimeCodesPerSecond(30)
    stage.SetFramesPerSecond(30)
    stage.SetStartTimeCode(0)
    stage.SetEndTimeCode(82)
    root = UsdSkel.Root.Define(stage, ROOT_PATH)
    stage.SetDefaultPrim(root.GetPrim())
    stage.GetRootLayer().customLayerData = {
        "replayxi_license_notice": notice, "sourceCommit": ROCKETBOX_COMMIT,
        "runtimeMotion": "ReplayXIRocketboxMotion.json; local TRS by exact joint name",
    }
    skeleton = UsdSkel.Skeleton.Define(stage, ROOT_PATH + "/Skeleton")
    skeleton.CreateJointsAttr(contract["paths"])
    skeleton.CreateBindTransformsAttr(Vt.Matrix4dArray([usd_matrix(matrix) for matrix in contract["bind"]]))
    skeleton.CreateRestTransformsAttr(Vt.Matrix4dArray([usd_matrix(matrix) for matrix in contract["rest"]]))
    materials = [material(stage, "BodyMaterial", "body_colour.png", "body_normal.png", 0.80),
                 material(stage, "HeadMaterial", "head_colour.png", "head_normal.png", 0.73)]
    for name, data, shade in zip(["Body", "Head"], meshes, materials):
        mesh = UsdGeom.Mesh.Define(stage, ROOT_PATH + "/" + name)
        mesh.CreatePointsAttr(Vt.Vec3fArray(data["points"].tolist()))
        mesh.CreateFaceVertexCountsAttr([3] * (len(data["indices"]) // 3))
        mesh.CreateFaceVertexIndicesAttr(data["indices"].tolist())
        mesh.CreateNormalsAttr(Vt.Vec3fArray(data["normals"].tolist()))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateExtentAttr(Vt.Vec3fArray([data["points"].min(axis=0).tolist(), data["points"].max(axis=0).tolist()]))
        UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex).Set(Vt.Vec2fArray(data["uv"].tolist()))
        binding = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
        binding.CreateSkeletonRel().SetTargets([skeleton.GetPath()])
        binding.CreateGeomBindTransformAttr(Gf.Matrix4d(1))
        binding.CreateJointIndicesPrimvar(False, 4).Set(data["joints"].reshape(-1).tolist())
        binding.CreateJointWeightsPrimvar(False, 4).Set(data["weights"].reshape(-1).tolist())
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(shade)
    for clip in clips:
        animation = UsdSkel.Animation.Define(stage, ROOT_PATH + "/" + clip["id"].title())
        animation.CreateJointsAttr(contract["paths"])
        for frame in clip["frames"]:
            time = frame["time"] * 30
            animation.CreateTranslationsAttr().Set(Vt.Vec3fArray(frame["translations"]), time)
            animation.CreateRotationsAttr().Set(Vt.QuatfArray([
                Gf.Quatf(q[3], Gf.Vec3f(*q[:3])) for q in frame["rotations"]
            ]), time)
            animation.CreateScalesAttr().Set(Vt.Vec3hArray(frame["scales"]), time)
    UsdSkel.BindingAPI.Apply(skeleton.GetPrim()).CreateAnimationSourceRel().SetTargets([Sdf.Path(ROOT_PATH + "/Idle")])
    stage.GetRootLayer().Save()


def local_anchor(contract, semantic, world_point):
    path = contract["semanticJoints"][semantic]
    index = contract["paths"].index(path)
    point = np.linalg.inv(contract["bind"][index]) @ [*world_point, 1]
    return rounded(point[:3])


def shirt_surface_point(mesh, x, y, front):
    """Ray-cast the bind-pose shirt so a jersey digit sits on its surface."""
    intersections = []
    for triangle in mesh["indices"].reshape(-1, 3):
        points = mesh["points"][triangle]
        plane = np.column_stack((points[1, :2] - points[0, :2], points[2, :2] - points[0, :2]))
        if abs(float(np.linalg.det(plane))) < 1e-10:
            continue
        u, v = np.linalg.solve(plane, np.array([x, y]) - points[0, :2])
        if u >= -1e-6 and v >= -1e-6 and u + v <= 1.000001:
            intersections.append(float(points[0, 2] * (1 - u - v) + points[1, 2] * u + points[2, 2] * v))
    if not intersections:
        raise RuntimeError("jersey anchor ray missed the body")
    z = max(intersections) + 0.004 if front else min(intersections) - 0.004
    return [x, y, z]


def build(source, output):
    output.mkdir(parents=True, exist_ok=True)
    if any(output.glob("ReplayXIRocketbox*")):
        raise RuntimeError("choose an output directory without prior Rocketbox outputs")
    with tempfile.TemporaryDirectory(prefix="replayxi-skinned-") as temporary:
        work = Path(temporary)
        verified = snapshot_verified_files(source, work / "inputs", PILOT_ASSETS)
        documents = {}
        binaries = {}
        for name, relative in [("model", MODEL_RELATIVE), ("idle", IDLE_RELATIVE), ("run", RUN_RELATIVE)]:
            subprocess.run(["assimp", "export", str(verified / relative), str(work / f"{name}.gltf"), "-fgltf2"], check=True, capture_output=True)
            documents[name] = json.loads((work / f"{name}.gltf").read_text())
            binaries[name] = (work / f"{name}.bin").read_bytes()
        model = documents["model"]
        contract = skeleton_contract(model, binaries["model"])
        meshes = mesh_data(model, binaries["model"], contract)
        clips = [sample_clip(model, documents[name], binaries[name], contract, name) for name in ["idle", "run"]]
        palette_names = make_textures(verified, work, output, meshes[0])
        notice = (verified / "LICENSE.md").read_text()
        layer = work / "athlete.usdc"
        write_usd(layer, contract, meshes, clips, notice)
        package = work / "ReplayXIRocketboxAthlete.usdz"
        subprocess.run(["usdzip", "--arkitAsset", str(layer), str(package)], check=True, capture_output=True)
        normalize_usdz_timestamps(package)
        subprocess.run(["usdchecker", "--arkit", str(package)], check=True)
        audit = audit_usd_skinning(package, notice)
        all_points = np.concatenate([mesh["points"] for mesh in meshes])
        minimum, maximum = all_points.min(axis=0), all_points.max(axis=0)
        body_points = meshes[0]["points"]
        contacts = {}
        for side, sign in [("left", 1), ("right", -1)]:
            sole = body_points[(body_points[:, 0] * sign > 0.03) & (body_points[:, 1] < minimum[1] + 0.025)]
            point = sole.mean(axis=0)
            point[1] = sole[:, 1].min()
            contacts[side] = {"footJoint": contract["semanticJoints"][side + "Ankle"],
                              "toeJoint": contract["semanticJoints"][side + "Toe"],
                              "solePoint": local_anchor(contract, side + "Ankle", point),
                              "restSoleWorld": rounded(point)}
        geometry = {"vertices": len(all_points), "triangles": sum(len(mesh["indices"]) // 3 for mesh in meshes),
                    "jointCount": 80, "materialCount": 2, "boundsMin": rounded(minimum), "boundsMax": rounded(maximum),
                    "nominalHeight": float(maximum[1] - minimum[1]), "restMinY": float(minimum[1]),
                    "pelvisRestHeight": float(contract["bind"][0][1, 3])}
        # The number positions follow the real shirt surface in the bind pose.
        # Runtime transforms these anchors with the sampled chest bone and
        # uses its localRight/Up/Forward axes to orient the glyph.
        anchors = {"joint": contract["semanticJoints"]["chest"],
                   "front": local_anchor(contract, "chest", shirt_surface_point(meshes[0], 0.055, 1.335, True)),
                   "back": local_anchor(contract, "chest", shirt_surface_point(meshes[0], 0, 1.335, False))}
        motion = {"schemaVersion": 1, "sourceCommit": ROCKETBOX_COMMIT,
                  "joints": contract["joints"], "semanticJoints": contract["semanticJoints"],
                  "clips": clips, "geometry": geometry, "footContacts": contacts,
                  "numberAnchors": anchors, "bodyMaterialSlot": 0, "headMaterialSlot": 1,
                  "rootMotion": "X/Z removed; source vertical motion retained; metres/Y-up/+Z forward"}
        (output / package.name).write_bytes(package.read_bytes())
        motion_path = output / "ReplayXIRocketboxMotion.json"
        motion_path.write_text(json.dumps(motion, separators=(",", ":"), allow_nan=False) + "\n")
        (output / "LICENSE-ROCKETBOX-MIT.txt").write_text(notice)
        names = [package.name, motion_path.name, *palette_names]
        report = {"sourceCommit": ROCKETBOX_COMMIT, "geometry": geometry, "skinning": audit,
                  "clips": [{"id": clip["id"], "durationSeconds": clip["durationSeconds"], "frames": len(clip["frames"])} for clip in clips],
                  "files": {name: {"bytes": (output / name).stat().st_size, "sha256": sha256_file(output / name)} for name in names}}
        (output / "ReplayXIRocketboxBuildReport.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.output), indent=2, sort_keys=True))
