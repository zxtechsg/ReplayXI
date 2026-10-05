#!/usr/bin/env python3
"""Build separate, audited Tripo USDZ/JSON assets from admitted skinned GLBs.

Use Blender's bundled Python (numpy and pxr) and Apple's usdzip/usdchecker.
Inputs are never changed. The target directory must not already exist.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, Vt

from build_replayxi_rocketbox_pilot import read_accessor
from replayxi_usdz_archive import normalize_usdz_timestamps

REPO = Path(__file__).resolve().parents[1]
ROOT = "/ReplayXITripo"
SEMANTICS = {
    "hips": "Hips", "spine": "Spine", "chest": "Spine2", "neck": "Neck", "head": "Head",
    "leftHip": "LeftUpLeg", "rightHip": "RightUpLeg", "leftKnee": "LeftLeg", "rightKnee": "RightLeg",
    "leftAnkle": "LeftFoot", "rightAnkle": "RightFoot", "leftToe": "LeftToeBase", "rightToe": "RightToeBase",
    "leftShoulder": "LeftArm", "rightShoulder": "RightArm", "leftElbow": "LeftForeArm", "rightElbow": "RightForeArm",
    "leftWrist": "LeftHand", "rightWrist": "RightHand",
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
    parents = ancestry(document)
    cache = {}
    def resolve(index):
        if index not in cache:
            node = dict(document["nodes"][index])
            node.update(overrides.get(index, {}))
            cache[index] = (resolve(parents[index]) if index in parents else np.eye(4)) @ local_matrix(node)
        return cache[index]
    return [resolve(index) for index in range(len(document["nodes"]))]


def usd_matrix(matrix):
    return Gf.Matrix4d(*matrix.T.reshape(-1).tolist())


def decompose(matrix):
    transform = Gf.Transform(usd_matrix(matrix))
    q = transform.GetRotation().GetQuat()
    return rounded(transform.GetTranslation()), rounded([*q.GetImaginary(), q.GetReal()]), rounded(transform.GetScale())


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
    if cosine > .9995:
        value = start * (1 - weight) + end * weight
        return value / np.linalg.norm(value)
    angle = math.acos(min(max(cosine, -1), 1))
    return (start * math.sin((1 - weight) * angle) + end * math.sin(weight * angle)) / math.sin(angle)


def local_anchor(contract, semantic, world_point):
    index = contract["paths"].index(contract["semanticJoints"][semantic])
    return rounded((np.linalg.inv(contract["bind"][index]) @ [*world_point, 1])[:3])


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def glb(path):
    raw = path.read_bytes()
    if len(raw) < 28 or struct.unpack_from("<III", raw) != (0x46546C67, 2, len(raw)):
        raise ValueError(f"invalid GLB: {path}")
    offset, document, binary = 12, None, None
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        data = raw[offset + 8:offset + 8 + size]
        if len(data) != size:
            raise ValueError("truncated GLB chunk")
        if kind == 0x4E4F534A:
            document = json.loads(data)
        elif kind == 0x004E4942:
            binary = data
        offset += size + 8
    if document is None or binary is None or offset != len(raw):
        raise ValueError("GLB lacks JSON or binary chunk")
    return document, binary


def atlas_bytes(document, binary):
    if len(document.get("images", [])) != 1:
        raise ValueError("expected exactly one source atlas image")
    image = document["images"][0]
    if image.get("mimeType") != "image/jpeg":
        raise ValueError("expected JPEG source atlas")
    view = document["bufferViews"][image["bufferView"]]
    offset = view.get("byteOffset", 0)
    return binary[offset:offset + view["byteLength"]]


def uv_position_map(document, binary):
    primitive = document["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    points = np.asarray(read_accessor(document, binary, attributes["POSITION"]), dtype=float)
    uvs = np.asarray(read_accessor(document, binary, attributes["TEXCOORD_0"]), dtype=float)
    if len(points) != len(uvs):
        raise ValueError("source UV count differs from positions")
    return {tuple(np.round(uv, 6)): point for point, uv in zip(points, uvs)}


def atlas_provenance(source_glb, source_jpeg, kits_report, motion_document, motion_binary,
                     lod_documents):
    original, original_binary = glb(source_glb)
    jpeg = source_jpeg.read_bytes()
    if atlas_bytes(original, original_binary) != jpeg:
        raise ValueError("original GLB atlas differs from FBX companion JPEG")
    for label, document, binary in [("motion", motion_document, motion_binary), *lod_documents]:
        if atlas_bytes(document, binary) != jpeg:
            raise ValueError(f"{label} GLB atlas differs from FBX companion JPEG")
    source_map = uv_position_map(original, original_binary)
    motion_map = uv_position_map(motion_document, motion_binary)
    if set(source_map) != set(motion_map):
        raise ValueError("FBX motion GLB changed source UV atlas coordinates")
    maximum_position_error = max(float(np.max(abs(source_map[uv] - motion_map[uv])))
                                 for uv in source_map)
    if maximum_position_error > 2e-6:
        raise ValueError("FBX motion GLB changed source UV-to-position mapping")
    kit_report = json.loads(kits_report.read_text())
    if kit_report.get("sourceSHA256") != sha(source_glb) or not kit_report.get("sameGeometryForBothTeams"):
        raise ValueError("kit report is not bound to original GLB atlas")
    kits = {}
    for row in kit_report["textures"]:
        path = kits_report.parent / row["texture"]
        payload = path.read_bytes()
        if (row["kit"] not in ("home", "away", "keeper") or row["size"] != [2048, 2048]
                or payload[:8] != b"\x89PNG\r\n\x1a\n"
                or struct.unpack_from(">II", payload, 16) != (2048, 2048)
                or sha(path) != row["sha256"]):
            raise ValueError("invalid source kit atlas or report hash")
        kits[row["kit"]] = {"file": path.name, "sha256": row["sha256"], "size": row["size"]}
    if set(kits) != {"home", "away", "keeper"}:
        raise ValueError("missing source kit atlas")
    return {"sourceGLBSHA256": sha(source_glb), "sourceJPEG_SHA256": sha(source_jpeg),
            "sourceJPEGByteIdenticalIn": ["original", "motion", "near", "low"],
            "matchedUniqueUVCoordinates": len(source_map),
            "maximumUVMatchedPositionErrorMetres": maximum_position_error,
            "bakedKits": kits}


def ancestry(document):
    return {child: index for index, node in enumerate(document["nodes"])
            for child in node.get("children", [])}


def inspect_skin(document, binary):
    if len(document.get("skins", [])) != 1 or len(document["skins"][0]["joints"]) != 52:
        raise ValueError("expected exactly one 52-joint Mixamo skin")
    weighted = document["skins"][0]["joints"]
    if len(set(weighted)) != 52:
        raise ValueError("duplicate weighted joint")
    names = [document["nodes"][node].get("name", "") for node in weighted]
    if len(set(names)) != 52 or not all(name.startswith("mixamorig:") for name in names):
        raise ValueError("invalid Mixamo joint identities")
    if len(document.get("meshes", [])) != 1 or len(document["meshes"][0]["primitives"]) != 1:
        raise ValueError("expected one body mesh and draw primitive")
    mesh_nodes = [i for i, node in enumerate(document["nodes"]) if node.get("mesh") == 0]
    if len(mesh_nodes) != 1 or document["nodes"][mesh_nodes[0]].get("skin") != 0:
        raise ValueError("body must bind directly to the single skin")
    primitive = document["meshes"][0]["primitives"][0]
    if len(document.get("materials", [])) != 1 or primitive.get("material") != 0:
        raise ValueError("expected exactly one PBR material")
    parent_map = ancestry(document)
    active = set(weighted)
    parent = {}
    for node in weighted:
        ancestor = parent_map.get(node)
        while ancestor is not None and ancestor not in active:
            ancestor = parent_map.get(ancestor)
        parent[node] = ancestor
    root = [node for node in weighted if parent[node] is None]
    if len(root) != 1 or document["nodes"][root[0]]["name"] != "mixamorig:Hips":
        raise ValueError("Hips must be the sole weighted root")
    order = []
    def visit(node):
        order.append(node)
        for child in weighted:
            if parent[child] == node:
                visit(child)
    visit(root[0])
    if len(order) != 52:
        raise ValueError("weighted rig is disconnected")
    index = {node: i for i, node in enumerate(order)}
    paths = {}
    for node in order:
        short = document["nodes"][node]["name"].removeprefix("mixamorig:")
        paths[node] = (paths[parent[node]] + "/" if parent[node] is not None else "") + short
    semantic = {}
    for role, short in SEMANTICS.items():
        matches = [paths[node] for node in order if document["nodes"][node]["name"] == "mixamorig:" + short]
        if len(matches) != 1:
            raise ValueError(f"missing semantic joint {role}")
        semantic[role] = matches[0]
    world = global_matrices(document)
    if not np.allclose(world[mesh_nodes[0]], np.eye(4), atol=1e-6):
        raise ValueError("skinned mesh must export with identity world transform")
    inverse = np.asarray(read_accessor(document, binary, document["skins"][0]["inverseBindMatrices"]), dtype=float)
    if inverse.shape != (52, 16):
        raise ValueError("inverse bind matrix shape changed")
    inverse = inverse.reshape(52, 4, 4).transpose(0, 2, 1)
    bind = {node: world[mesh_nodes[0]] @ np.linalg.inv(matrix)
            for node, matrix in zip(weighted, inverse)}
    if max(np.max(abs(bind[node] - world[node])) for node in weighted) > 2e-4:
        raise ValueError("inverse binds differ from skeleton rest world")
    return {"weighted": weighted, "order": order, "index": index, "paths": paths,
            "parent": parent, "world": world, "bind": bind, "semantic": semantic,
            "meshNode": mesh_nodes[0], "primitive": primitive}


def scale_world(matrix, scale):
    result = np.array(matrix, dtype=float, copy=True)
    result[:3, 3] *= scale
    return result


def skeleton(document, skin, scale):
    joints, rests, binds = [], [], []
    for node in skin["order"]:
        parent = skin["parent"][node]
        current = scale_world(skin["world"][node], scale)
        local = np.linalg.inv(scale_world(skin["world"][parent], scale)) @ current if parent is not None else current
        translation, rotation, sizes = decompose(local)
        bind = scale_world(skin["bind"][node], scale)
        left, _, right = np.linalg.svd(bind[:3, :3])
        orientation = left @ right
        joints.append({"name": skin["paths"][node], "sourceName": document["nodes"][node]["name"],
                       "parentIndex": skin["index"][parent] if parent is not None else -1,
                       "translation": translation, "rotation": rotation, "scale": sizes,
                       "localRightAxis": rounded(orientation.T @ [1, 0, 0]),
                       "localUpAxis": rounded(orientation.T @ [0, 1, 0]),
                       "localForwardAxis": rounded(orientation.T @ [0, 0, 1])})
        rests.append(local)
        binds.append(bind)
    return joints, rests, binds


def mesh_data(document, binary, skin, scale, normal_mode="source"):
    primitive = skin["primitive"]
    attrs = primitive["attributes"]
    required = {"POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"}
    if not required.issubset(attrs) or "JOINTS_1" in attrs or "WEIGHTS_1" in attrs:
        raise ValueError("body lacks a four-influence smooth textured skin")
    def get(key):
        return np.asarray(read_accessor(document, binary, attrs[key]))
    points = get("POSITION").astype(float)
    normals = get("NORMAL").astype(float)
    uvs = get("TEXCOORD_0").astype(float)
    old_joints = get("JOINTS_0").astype(int)
    weights = get("WEIGHTS_0").astype(float)
    indices = np.asarray(read_accessor(document, binary, primitive["indices"]), dtype=int).reshape(-1)
    if points.shape[1] != 3 or normals.shape != points.shape or uvs.shape != (len(points), 2):
        raise ValueError("invalid body attributes")
    if old_joints.shape != (len(points), 4) or weights.shape != old_joints.shape:
        raise ValueError("invalid joint/weight attributes")
    if len(indices) % 3 or np.any(indices < 0) or np.any(indices >= len(points)):
        raise ValueError("invalid triangle indices")
    if np.any(old_joints < 0) or np.any(old_joints >= 52) or np.any(weights < 0):
        raise ValueError("invalid skin influences")
    sums = weights.sum(axis=1)
    if np.any(abs(sums - 1) > 1e-4):
        raise ValueError("unnormalized skin weights")
    weights /= sums[:, None]
    transform = skin["world"][skin["meshNode"]]
    points = (np.column_stack((points, np.ones(len(points)))) @ transform.T)[:, :3] * scale
    normals = normals @ np.linalg.inv(transform[:3, :3])
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    if normal_mode == "area-weighted":
        faces = indices.reshape(-1, 3)
        area_normals = np.cross(points[faces[:, 1]] - points[faces[:, 0]],
                                points[faces[:, 2]] - points[faces[:, 0]])
        smoothed = np.zeros_like(points)
        for corner in range(3):
            np.add.at(smoothed, faces[:, corner], area_normals)
        # GLB duplicates vertices at UV seams. Weld normal values only; keep
        # topology, UVs, weights, and the one-draw triangle index buffer intact.
        groups = {}
        for index, point in enumerate(points):
            groups.setdefault(tuple(np.round(point, 6)), []).append(index)
        for members in groups.values():
            if len(members) > 1:
                smoothed[members] = smoothed[members].sum(axis=0)
        lengths = np.linalg.norm(smoothed, axis=1)
        valid = lengths > 1e-12
        smoothed[valid] /= lengths[valid, None]
        smoothed[~valid] = normals[~valid]
        normals = smoothed
    elif normal_mode != "source":
        raise ValueError("unsupported normal mode")
    uvs[:, 1] = 1 - uvs[:, 1]
    joints = np.vectorize(lambda value: skin["index"][skin["weighted"][value]])(old_joints)
    if not all(np.isfinite(array).all() for array in (points, normals, uvs, weights)):
        raise ValueError("nonfinite body geometry")
    return {"points": points, "normals": normals, "uv": uvs, "indices": indices,
            "joints": joints, "weights": weights,
            "triangles": len(indices) // 3, "vertices": len(points)}


def weld_body_uv_topology(body):
    """Weld exact position+skin duplicates while moving UVs to face corners.

    This changes only the authored USD point topology. Source body arrays remain
    untouched so contact sampling and motion geometry keep source vertex counts.
    """
    points = np.asarray(body["points"])
    normals = np.asarray(body["normals"])
    joints = np.asarray(body["joints"])
    weights = np.asarray(body["weights"])
    uvs = np.asarray(body["uv"])
    indices = np.asarray(body["indices"], dtype=np.int64)
    if (points.ndim != 2 or points.shape[1] != 3 or normals.shape != points.shape
            or joints.shape != weights.shape or len(points) != len(joints)
            or uvs.shape != (len(points), 2) or len(indices) % 3
            or np.any(indices < 0) or np.any(indices >= len(points))):
        raise ValueError("invalid source body arrays for USD topology weld")

    key_to_point = {}
    remap = np.empty(len(points), dtype=np.int32)
    representatives = []
    groups = []
    for source_index, (point, row, mass) in enumerate(zip(points, joints, weights)):
        # These values are authored as USD Vec3f/FloatArray. Key at that exact
        # storage precision, without a geometric epsilon or rounded tolerance.
        key = (tuple(float(value) for value in np.asarray(point, dtype=np.float32))
               + tuple(int(value) for value in row)
               + tuple(float(value) for value in np.asarray(mass, dtype=np.float32)))
        target = key_to_point.get(key)
        if target is None:
            target = len(representatives)
            key_to_point[key] = target
            representatives.append(source_index)
            groups.append([])
        remap[source_index] = target
        groups[target].append(source_index)

    for target, members in enumerate(groups):
        reference = np.asarray(normals[representatives[target]], dtype=np.float32)
        if any(not np.array_equal(np.asarray(normals[index], dtype=np.float32), reference)
               for index in members):
            raise ValueError("position+skin weld would merge divergent source normals")

    representatives = np.asarray(representatives, dtype=np.int64)
    mapped_indices = remap[indices]
    return {
        "points": points[representatives],
        "normals": normals[representatives],
        "uv": uvs[indices],
        "indices": mapped_indices,
        "joints": joints[representatives],
        "weights": weights[representatives],
        "triangles": int(body["triangles"]),
        "vertices": len(representatives),
        "sourceVertices": len(points),
        "uvInterpolation": "faceVarying",
        "sourceToUsdPoint": remap,
    }


def motion_clips(document, binary, skin, scale):
    animations = document.get("animations", [])
    clips = {}
    root_offsets = {}
    for clip_id in ("idle", "run"):
        matching = [entry for entry in animations if clip_id in entry.get("name", "").lower()]
        if len(matching) != 1:
            raise ValueError(f"expected one {clip_id} animation, found {len(matching)}")
        channels = []
        for channel in matching[0]["channels"]:
            target = channel["target"]
            if target["path"] not in ("translation", "rotation", "scale"):
                continue
            sampler = matching[0]["samplers"][channel["sampler"]]
            interpolation = sampler.get("interpolation", "LINEAR")
            if interpolation not in ("LINEAR", "STEP"):
                raise ValueError("animation must use linear or step glTF samples")
            times = np.asarray(read_accessor(document, binary, sampler["input"]), dtype=float).reshape(-1)
            values = np.asarray(read_accessor(document, binary, sampler["output"]), dtype=float)
            if not len(times) or np.any(np.diff(times) <= 0):
                raise ValueError("invalid clip key times")
            channels.append((target["node"], target["path"], times, values, interpolation))
        if not channels:
            raise ValueError(f"{clip_id} has no TRS channels")
        duration = max(float(times[-1]) for _, _, times, _, _ in channels)
        # Blender exported the source action at 24 FPS. Preserve its exact
        # keyed poses, including the frame-numbered independent pose report.
        fps = 24
        count = round(duration * fps) + 1
        if not 2 <= count <= 2401:
            raise ValueError("clip frame count outside runtime bounds")
        frames = []
        removed = []
        for seconds in np.arange(count, dtype=float) / fps:
            overrides = {}
            for node, component, times, values, interpolation in channels:
                if interpolation == "STEP":
                    value = values[max(0, int(np.searchsorted(times, seconds, side="right")) - 1)]
                else:
                    value = interpolate(times, values, seconds, component == "rotation")
                overrides.setdefault(node, {})[component] = value.tolist()
            world = global_matrices(document, overrides)
            translations, rotations, sizes = [], [], []
            for node in skin["order"]:
                parent = skin["parent"][node]
                current = scale_world(world[node], scale)
                local = np.linalg.inv(scale_world(world[parent], scale)) @ current if parent is not None else current
                trans, rotation, dimensions = decompose(local)
                if parent is None:
                    removed.append([trans[0], trans[2]])
                    trans[0], trans[2] = skin["rootRestXZ"]
                if frames and np.dot(rotation, frames[-1]["rotations"][len(rotations)]) < 0:
                    rotation = [-value for value in rotation]
                translations.append(trans); rotations.append(rotation); sizes.append(dimensions)
            frames.append({"time": round(float(seconds), 8), "translations": translations,
                           "rotations": rotations, "scales": sizes})
        clips[clip_id] = {"id": clip_id, "durationSeconds": duration, "fps": fps, "frames": frames}
        root_offsets[clip_id] = removed
    return [clips["idle"], clips["run"]], root_offsets


def material(stage):
    path = ROOT + "/BodyMaterial"
    result = UsdShade.Material.Define(stage, path)
    surface = UsdShade.Shader.Define(stage, path + "/Surface")
    surface.CreateIdAttr("UsdPreviewSurface")
    surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.78)
    surface.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0)
    surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(1, 1, 1))
    st = UsdShade.Shader.Define(stage, path + "/ST")
    st.CreateIdAttr("UsdPrimvarReader_float2")
    st.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
    result.CreateSurfaceOutput().ConnectToSource(surface.ConnectableAPI(), "surface")
    return result


def write_usd(path, joints, rests, binds, body, clips, source_hash, weld_uv_topology=False,
              source_prefix="tripo-fbx-", runtime_motion_name="ReplayXITripoMotion.json"):
    usd_body = weld_body_uv_topology(body) if weld_uv_topology else {
        **body, "uvInterpolation": "vertex", "sourceVertices": body["vertices"]}
    stage = Usd.Stage.CreateNew(str(path))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1)
    stage.SetTimeCodesPerSecond(30)
    stage.SetFramesPerSecond(30)
    stage.SetStartTimeCode(0)
    stage.SetEndTimeCode(max(len(clip["frames"]) - 1 for clip in clips))
    root = UsdSkel.Root.Define(stage, ROOT)
    stage.SetDefaultPrim(root.GetPrim())
    stage.GetRootLayer().customLayerData = {"sourceCommit": source_prefix + source_hash[:32],
                                           "runtimeMotion": runtime_motion_name + "; exact local TRS joint order"}
    skel = UsdSkel.Skeleton.Define(stage, ROOT + "/Skeleton")
    paths = [item["name"] for item in joints]
    skel.CreateJointsAttr(paths)
    skel.CreateBindTransformsAttr(Vt.Matrix4dArray([usd_matrix(value) for value in binds]))
    skel.CreateRestTransformsAttr(Vt.Matrix4dArray([usd_matrix(value) for value in rests]))
    mesh = UsdGeom.Mesh.Define(stage, ROOT + "/Body")
    mesh.CreatePointsAttr(Vt.Vec3fArray(usd_body["points"].tolist()))
    mesh.CreateFaceVertexCountsAttr([3] * usd_body["triangles"])
    mesh.CreateFaceVertexIndicesAttr(usd_body["indices"].tolist())
    mesh.CreateNormalsAttr(Vt.Vec3fArray(usd_body["normals"].tolist()))
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    mesh.CreateExtentAttr(Vt.Vec3fArray([usd_body["points"].min(axis=0).tolist(), usd_body["points"].max(axis=0).tolist()]))
    UsdGeom.PrimvarsAPI(mesh).CreatePrimvar(
        "st", Sdf.ValueTypeNames.TexCoord2fArray, usd_body["uvInterpolation"]
    ).Set(Vt.Vec2fArray(usd_body["uv"].tolist()))
    binding = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
    binding.CreateSkeletonRel().SetTargets([skel.GetPath()])
    binding.CreateGeomBindTransformAttr(Gf.Matrix4d(1))
    binding.CreateJointIndicesPrimvar(False, 4).Set(usd_body["joints"].reshape(-1).tolist())
    binding.CreateJointWeightsPrimvar(False, 4).Set(usd_body["weights"].reshape(-1).tolist())
    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material(stage))
    for clip in clips:
        anim = UsdSkel.Animation.Define(stage, ROOT + "/" + clip["id"].title())
        anim.CreateJointsAttr(paths)
        for frame in clip["frames"]:
            time = frame["time"] * 30
            anim.CreateTranslationsAttr().Set(Vt.Vec3fArray(frame["translations"]), time)
            anim.CreateRotationsAttr().Set(Vt.QuatfArray([Gf.Quatf(q[3], Gf.Vec3f(*q[:3])) for q in frame["rotations"]]), time)
            anim.CreateScalesAttr().Set(Vt.Vec3hArray(frame["scales"]), time)
    UsdSkel.BindingAPI.Apply(skel.GetPrim()).CreateAnimationSourceRel().SetTargets([Sdf.Path(ROOT + "/Idle")])
    stage.GetRootLayer().Save()


def anchors_and_contacts(body, joints, binds, semantics, minimum, maximum):
    paths = [entry["name"] for entry in joints]
    contract = {"paths": paths, "bind": binds, "semanticJoints": semantics}
    points = body["points"]
    center_y = minimum[1] + 0.77 * (maximum[1] - minimum[1])
    def shirt_point(front):
        sample = points[(abs(points[:, 0]) < .075) & (abs(points[:, 1] - center_y) < .045)]
        if len(sample) < 4:
            raise ValueError("cannot locate front/back shirt surface")
        z = np.max(sample[:, 2]) + .004 if front else np.min(sample[:, 2]) - .004
        return [0, center_y, z]
    number = {"joint": semantics["chest"],
              "front": local_anchor(contract, "chest", shirt_point(True)),
              "back": local_anchor(contract, "chest", shirt_point(False))}
    contacts = {}
    for side, sign in (("left", 1), ("right", -1)):
        candidates = points[(points[:, 0] * sign > .025) & (points[:, 1] < minimum[1] + .04)]
        if len(candidates) < 3:
            raise ValueError(f"cannot locate {side} boot sole")
        sole = candidates.mean(axis=0)
        sole[1] = candidates[:, 1].min()
        contacts[side] = {"footJoint": semantics[side + "Ankle"], "toeJoint": semantics[side + "Toe"],
                          "solePoint": local_anchor(contract, side + "Ankle", sole),
                          "restSoleWorld": rounded(sole)}
    return number, contacts


def contact_vertices(body, joint_paths, semantic, minimum, maximum, asset_hash, motion_hash,
                     runtime_head_floor):
    points, joints, weights = body["points"], body["joints"], body["weights"]
    head_path = semantic["head"]
    head_joints = {index for index, path in enumerate(joint_paths)
                   if path == head_path or path.startswith(head_path + "/")}
    skull = [i for i, (row, mass) in enumerate(zip(joints, weights))
             if points[i, 1] >= runtime_head_floor
             and sum(float(weight) for joint, weight in zip(row, mass) if int(joint) in head_joints) >= .8]
    if len(skull) < 6:
        raise ValueError("fewer than six weighted skull vertices for header probes")
    chosen = set()
    # The Tripo header guard deforms all four real influences. Reserve its
    # exact >=80% head-subtree source vertices before body/floor sampling.
    skull_limit = min(96, len(skull))
    if len(skull) <= skull_limit:
        chosen.update(skull)
    else:
        head_points = points[skull]
        seeds = set()
        for axis in range(3):
            seeds.add(skull[int(np.argmin(head_points[:, axis]))])
            seeds.add(skull[int(np.argmax(head_points[:, axis]))])
        chosen.update(seeds)
        while len(chosen) < skull_limit:
            selected = points[sorted(chosen)]
            remaining = [index for index in skull if index not in chosen]
            distances = np.sum((points[remaining, None, :] - selected[None, :, :]) ** 2, axis=2)
            nearest = distances.min(axis=1)
            chosen.add(remaining[int(np.argmax(nearest))])
    def add_extrema(indices):
        if not indices:
            return
        subset = points[indices]
        for axis in range(3):
            chosen.add(indices[int(np.argmin(subset[:, axis]))])
            chosen.add(indices[int(np.argmax(subset[:, axis]))])
    all_indices = list(range(len(points)))
    body_eligible = [index for index in all_indices if index not in skull or index in chosen]
    add_extrema(body_eligible)
    for side in (-1, 1):
        boot = [i for i in body_eligible if points[i, 0] * side > .025 and points[i, 1] < minimum[1] + .07]
        add_extrema(boot)
    for band in range(12):
        low = minimum[1] + band / 12 * (maximum[1] - minimum[1])
        high = minimum[1] + (band + 1) / 12 * (maximum[1] - minimum[1])
        add_extrema([i for i in body_eligible if low <= points[i, 1] <= high])
    # Deterministic spatial coverage: preserve all critical extrema, then
    # evenly sample remaining source vertices up to the hard 512-point budget.
    remaining = [i for i in body_eligible if i not in chosen]
    allowance = min(512 - len(chosen), len(remaining))
    if allowance < 0:
        raise ValueError("critical extrema exceed contact budget")
    chosen.update(remaining[round(i * (len(remaining) - 1) / max(allowance - 1, 1))] for i in range(allowance))
    vertices = []
    for i in sorted(chosen):
        active = [(int(j), float(w)) for j, w in zip(joints[i], weights[i]) if w > 1e-6]
        total = sum(w for _, w in active)
        vertices.append({"id": f"body-{i}", "position": rounded(points[i]),
                         "joints": [j for j, _ in active],
                         "weights": rounded([w / total for _, w in active], 9)})
    return {"schemaVersion": 1, "assetSHA256": asset_hash, "motionSHA256": motion_hash,
            "sourceVertexCount": len(points), "jointCount": len(joint_paths),
            "paddingMetres": .006, "vertices": vertices}


def posed_vertices(body, joints, binds, frame):
    world = []
    for joint, position, quaternion, scale in zip(joints, frame["translations"], frame["rotations"], frame["scales"]):
        local = local_matrix({"translation": position, "rotation": quaternion, "scale": scale})
        parent = joint["parentIndex"]
        world.append(world[parent] @ local if parent >= 0 else local)
    skin = np.asarray([matrix @ np.linalg.inv(bind) for matrix, bind in zip(world, binds)])
    point = np.column_stack((body["points"], np.ones(body["vertices"])))
    matrices = skin[body["joints"]]
    posed = np.einsum("nkij,nj->nki", matrices, point)[:, :, :3]
    posed = np.einsum("nki,nk->ni", posed, body["weights"])
    if not np.isfinite(posed).all():
        raise ValueError("posed skin contains nonfinite coordinates")
    return posed, world


def posed_bounds(body, joints, binds, frame):
    posed, _ = posed_vertices(body, joints, binds, frame)
    return posed.min(axis=0), posed.max(axis=0)


def clipped_panel_maximum(points, triangles, half_width, half_height):
    """Max cloth depth in a number panel's X/Y rectangle, including edge crossings."""
    def clip(poly, axis, bound, upper):
        if not poly:
            return poly
        out = []
        previous = poly[-1]
        previous_inside = previous[axis] <= bound if upper else previous[axis] >= bound
        for current in poly:
            inside = current[axis] <= bound if upper else current[axis] >= bound
            if inside != previous_inside:
                fraction = (bound - previous[axis]) / (current[axis] - previous[axis])
                out.append(previous + fraction * (current - previous))
            if inside:
                out.append(current)
            previous, previous_inside = current, inside
        return out
    maximum = -math.inf
    hits = 0
    for triangle in triangles:
        vertices = points[triangle]
        if (vertices[:, 0].max() < -half_width or vertices[:, 0].min() > half_width
                or vertices[:, 1].max() < -half_height or vertices[:, 1].min() > half_height):
            continue
        face = np.cross(vertices[1] - vertices[0], vertices[2] - vertices[0])
        if face[2] <= 1e-10:
            continue
        polygon = list(vertices)
        for axis, bound, upper in ((0, -half_width, False), (0, half_width, True),
                                   (1, -half_height, False), (1, half_height, True)):
            polygon = clip(polygon, axis, bound, upper)
            if not polygon:
                break
        if polygon:
            hits += 1
            maximum = max(maximum, max(float(vertex[2]) for vertex in polygon))
    if hits < 2:
        raise ValueError("number panel missed the rendered shirt surface")
    return maximum, hits


def number_panel_clearance(body, joints, binds, clips, anchors):
    """Measure both 2-digit number rectangles against the actual skinned shirt."""
    chest = [joint["name"] for joint in joints].index(anchors["joint"])
    rest_orientation = np.eye(4)
    rest_orientation[:3, :3] = np.linalg.inv(binds[chest][:3, :3])
    back_flip = np.diag([-1, 1, -1, 1])
    triangles = body["indices"].reshape(-1, 3)
    rest_points = body["points"]
    centroid = rest_points[triangles].mean(axis=1)
    shirt = triangles[(centroid[:, 1] > 1.12) & (centroid[:, 1] < 1.61)
                      & (abs(centroid[:, 0]) < .24)]
    audit = {}
    for side, width, height, flip in (("front", .075, .065, np.eye(4)),
                                      ("back", .15, .12, back_flip)):
        peak = -math.inf
        samples = []
        for clip in clips:
            frames = range(len(clip["frames"])) if clip["id"] == "run" else (0, 20, 40, 60, len(clip["frames"]) - 1)
            for frame_index in frames:
                posed, world = posed_vertices(body, joints, binds, clip["frames"][frame_index])
                translation = np.eye(4)
                translation[:3, 3] = anchors[side]
                panel = world[chest] @ translation @ rest_orientation @ flip
                panel_points = (np.column_stack((posed, np.ones(len(posed)))) @ np.linalg.inv(panel).T)[:, :3]
                depth, count = clipped_panel_maximum(panel_points, shirt, width, height)
                peak = max(peak, depth)
                samples.append({"clip": clip["id"], "frame": frame_index,
                                "maximumClothDepthMetres": depth, "shirtTriangles": count})
        audit[side] = {"halfWidthMetres": width, "halfHeightMetres": height,
                       "maximumClothDepthMetres": peak, "samples": samples}
    return audit


def lift_number_anchors(body, joints, binds, clips, anchors):
    before = number_panel_clearance(body, joints, binds, clips, anchors)
    chest = [joint["name"] for joint in joints].index(anchors["joint"])
    inverse_rotation = np.linalg.inv(binds[chest][:3, :3])
    target_clearance = .01
    offsets = {}
    for side, sign in (("front", 1), ("back", -1)):
        distance = max(0, before[side]["maximumClothDepthMetres"] + target_clearance)
        if distance > .04:
            raise ValueError(f"{side} number needs excessive shirt offset: {distance:.4f}m")
        outward_world = np.array([0., 0., sign * distance])
        anchors[side] = rounded(np.asarray(anchors[side]) + inverse_rotation @ outward_world)
        offsets[side] = distance
    after = number_panel_clearance(body, joints, binds, clips, anchors)
    if any(item["maximumClothDepthMetres"] > -target_clearance + 1e-5 for item in after.values()):
        raise ValueError("number glyph rectangle still intersects skinned shirt")
    return {"targetClearanceMetres": target_clearance, "outwardOffsetsMetres": offsets,
            "before": before, "after": after}


def validate_pose_reference(report_path, body, joints, binds, clips, root_offsets, scale):
    report = json.loads(report_path.read_text())
    expected = report.get("poseSamples", [])
    if not expected:
        raise ValueError("source Blender report lacks pose samples")
    clip_map = {clip["id"]: clip for clip in clips}
    audit = []
    for item in expected:
        clip = clip_map[item["clip"]]
        frame_index = item["frame"]
        if frame_index < 0 or frame_index >= len(clip["frames"]):
            raise ValueError("source pose frame outside clip")
        minimum, maximum = posed_bounds(body, joints, binds, clip["frames"][frame_index])
        # Blender's report is Z-up/front=-Y. glTF/USD is Y-up/front=+Z.
        source = np.asarray(item["bounds"], dtype=float)
        expected_min = np.array([source[0, 0], source[2, 0], -source[1, 1]]) * scale
        expected_max = np.array([source[0, 1], source[2, 1], -source[1, 0]]) * scale
        removed = root_offsets[item["clip"]][frame_index]
        expected_min[[0, 2]] -= removed
        expected_max[[0, 2]] -= removed
        error = max(float(np.max(abs(minimum - expected_min))),
                    float(np.max(abs(maximum - expected_max))))
        if error > 8e-6:
            raise ValueError(f"{item['clip']} frame {item['frame']} scaled Blender pose mismatch: {error:.6f}m")
        audit.append({"clip": item["clip"], "frame": item["frame"],
                      "boundsMin": rounded(minimum), "boundsMax": rounded(maximum),
                      "scaledBlenderMaximumErrorMetres": error})
    return audit


def audit_usd(path, expected_paths, expected_rest, expected_bind, body, asset_hash,
              weld_uv_topology=False):
    stage = Usd.Stage.Open(str(path))
    if stage is None or str(stage.GetDefaultPrim().GetPath()) != ROOT:
        raise ValueError("USDZ lost Tripo SkelRoot")
    if UsdGeom.GetStageUpAxis(stage) != UsdGeom.Tokens.y or UsdGeom.GetStageMetersPerUnit(stage) != 1:
        raise ValueError("USDZ unit/axis changed")
    skel = UsdSkel.Skeleton(stage.GetPrimAtPath(ROOT + "/Skeleton"))
    if list(skel.GetJointsAttr().Get() or []) != expected_paths:
        raise ValueError("USDZ joint order differs from motion")
    for kind, attribute, expected in (("rest", skel.GetRestTransformsAttr(), expected_rest),
                                      ("bind", skel.GetBindTransformsAttr(), expected_bind)):
        actual = np.asarray(attribute.Get())
        if actual.shape != (52, 4, 4) or not np.isfinite(actual).all():
            raise ValueError(f"USDZ {kind} transform array invalid")
        # OpenUSD matrices expose row-major values, while usd_matrix writes
        # the transpose of our column-vector numpy matrices.
        if max(np.max(abs(a.T - e)) for a, e in zip(actual, expected)) > 1e-8:
            raise ValueError(f"USDZ {kind} transform differs from source")
    for name in ("Idle", "Run"):
        animation = UsdSkel.Animation(stage.GetPrimAtPath(ROOT + "/" + name))
        if not animation or list(animation.GetJointsAttr().Get() or []) != expected_paths:
            raise ValueError(f"USDZ {name} animation joint order differs from motion")
    mesh = UsdGeom.Mesh(stage.GetPrimAtPath(ROOT + "/Body"))
    if not mesh:
        raise ValueError("USDZ lost body mesh")
    if len([prim for prim in stage.Traverse() if prim.GetTypeName() == "Mesh"]) != 1:
        raise ValueError("USDZ introduced an extra draw mesh")
    face_counts = np.asarray(mesh.GetFaceVertexCountsAttr().Get(), dtype=np.int64)
    if (len(face_counts) != body["triangles"]
            or not np.array_equal(face_counts, np.full(body["triangles"], 3, dtype=np.int64))):
        raise ValueError("USDZ triangle count changed")
    usd_body = weld_body_uv_topology(body) if weld_uv_topology else body
    points = np.asarray(mesh.GetPointsAttr().Get(), dtype=float)
    indices = np.asarray(mesh.GetFaceVertexIndicesAttr().Get(), dtype=np.int64)
    if (len(points) != len(usd_body["points"])
            or not np.array_equal(indices, usd_body["indices"])):
        raise ValueError("USDZ authored point count or triangle mapping changed")
    source_indices = np.asarray(body["indices"], dtype=np.int64)
    if (not np.allclose(points[indices], body["points"][source_indices], atol=1e-6, rtol=0)
            or not np.allclose(np.asarray(usd_body["points"]), points, atol=1e-6, rtol=0)):
        raise ValueError("USDZ changed per-corner body positions")
    normals = np.asarray(mesh.GetNormalsAttr().Get())
    if (normals.shape != points.shape or mesh.GetNormalsInterpolation() != UsdGeom.Tokens.vertex
            or not np.allclose(normals[indices], body["normals"][source_indices], atol=1e-6, rtol=0)
            or np.max(abs(np.linalg.norm(normals, axis=1) - 1)) > 1e-4):
        raise ValueError("USDZ lost smooth vertex normals")
    uv = UsdGeom.PrimvarsAPI(mesh).GetPrimvar("st")
    if not uv:
        raise ValueError("USDZ lost body UVs")
    uv_values = np.asarray(uv.Get())
    if weld_uv_topology:
        if (uv.GetInterpolation() != UsdGeom.Tokens.faceVarying
                or uv_values.shape != (len(indices), 2)
                or not np.allclose(uv_values, body["uv"][source_indices], atol=1e-6, rtol=0)):
            raise ValueError("USDZ changed per-corner face-varying UVs")
    else:
        if (uv.GetInterpolation() != UsdGeom.Tokens.vertex
                or uv_values.shape != body["uv"].shape
                or not np.allclose(uv_values, body["uv"], atol=1e-6, rtol=0)
                or not np.allclose(uv_values[indices], body["uv"][source_indices], atol=1e-6, rtol=0)):
            raise ValueError("USDZ lost body UVs")
    binding = UsdSkel.BindingAPI(mesh.GetPrim())
    joint_values = np.asarray(binding.GetJointIndicesPrimvar().Get(), dtype=np.int64).reshape(len(points), -1)
    weight_values = np.asarray(binding.GetJointWeightsPrimvar().Get(), dtype=float).reshape(len(points), -1)
    if (joint_values.shape != usd_body["joints"].shape
            or weight_values.shape != usd_body["weights"].shape
            or not np.array_equal(joint_values[indices], body["joints"][source_indices])
            or not np.allclose(weight_values[indices], body["weights"][source_indices], atol=1e-6, rtol=0)
            or not np.array_equal(joint_values, usd_body["joints"])
            or not np.allclose(weight_values, usd_body["weights"], atol=1e-6, rtol=0)):
        raise ValueError("USDZ changed per-corner skin joint IDs or weights")
    if list(binding.GetSkeletonRel().GetTargets()) != [Sdf.Path(ROOT + "/Skeleton")]:
        raise ValueError("USDZ lost skeleton binding")
    bound, _ = UsdShade.MaterialBindingAPI(mesh.GetPrim()).ComputeBoundMaterial()
    if str(bound.GetPath()) != ROOT + "/BodyMaterial":
        raise ValueError("USDZ lost one body PBR material")
    return {"vertices": body["vertices"], "sourceVertices": body["vertices"],
            "authoredUSDPointCount": len(points), "triangles": body["triangles"],
            "drawCalls": 1, "jointCount": len(expected_paths), "sha256": asset_hash}


def build(args):
    output = args.output.resolve()
    derived = (REPO / ".codex-derived").resolve()
    if output.exists() or not output.is_relative_to(derived):
        raise ValueError("output must be a NEW directory under .codex-derived")
    inputs = (args.near_glb, args.low_glb, args.motion_glb, args.source_fbx)
    if args.source_archive:
        inputs += (args.source_archive,)
    if args.source_report:
        inputs += (args.source_report,)
    inputs += (args.source_glb, args.source_jpeg, args.kits_report)
    for path in inputs:
        if not path.is_file():
            raise ValueError(f"missing input: {path}")
    hashes = {name: sha(path) for name, path in (("nearGLB", args.near_glb), ("lowGLB", args.low_glb),
                                                 ("motionGLB", args.motion_glb), ("sourceFBX", args.source_fbx))}
    if args.source_archive:
        hashes["sourceArchive"] = sha(args.source_archive)
    if args.source_report:
        hashes["sourceReport"] = sha(args.source_report)
        source_report = json.loads(args.source_report.read_text())
        reported_motion_hash = (source_report.get("outputs", {}).get("motionGLBSHA256")
                                or source_report.get("outputs", {}).get("glbSHA256"))
        if reported_motion_hash != hashes["motionGLB"]:
            raise ValueError("pose reference report is not bound to motion GLB hash")
    hashes.update({"sourceGLB": sha(args.source_glb), "sourceJPEG": sha(args.source_jpeg),
                   "kitsReport": sha(args.kits_report)})
    specs = []
    for label, path, limit in (("near", args.near_glb, 8200), ("low", args.low_glb, 2200)):
        document, binary = glb(path)
        skin = inspect_skin(document, binary)
        body_unscaled = mesh_data(document, binary, skin, 1)
        if body_unscaled["triangles"] > limit:
            raise ValueError(f"{label} exceeds {limit} triangles")
        if not 8 <= body_unscaled["vertices"] <= 12000:
            raise ValueError(f"{label} vertex count is outside Tripo contact profile")
        specs.append((label, document, binary, skin, body_unscaled))
    near_height = float(np.ptp(specs[0][4]["points"][:, 1]))
    if not .5 <= near_height <= 2.5:
        raise ValueError("near GLB has implausible native height")
    scale = args.height / near_height
    near_names = [specs[0][1]["nodes"][node]["name"] for node in specs[0][3]["order"]]
    for label, document, _, skin, _ in specs[1:]:
        if [document["nodes"][node]["name"] for node in skin["order"]] != near_names:
            raise ValueError(f"{label} skin differs from near skin")
    motion_doc, motion_bin = glb(args.motion_glb)
    atlas_audit = atlas_provenance(args.source_glb, args.source_jpeg, args.kits_report,
                                   motion_doc, motion_bin,
                                   [(label, document, binary) for label, document, binary, _, _ in specs])
    motion_skin = inspect_skin(motion_doc, motion_bin)
    if [motion_doc["nodes"][node]["name"] for node in motion_skin["order"]] != near_names:
        raise ValueError("motion skin differs from near skin")
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="replayxi-tripo-native-") as temporary:
        work = Path(temporary)
        _, near_rest, near_binds = skeleton(specs[0][1], specs[0][3], scale)
        joints, motion_rests, _ = skeleton(motion_doc, motion_skin, scale)
        if any(np.max(abs(a - b)) > 2e-4 for a, b in zip(near_rest, motion_rests)):
            raise ValueError("motion and near GLB rest transforms differ")
        motion_skin["rootRestXZ"] = [0.0, 0.0]
        clips, root_offsets = motion_clips(motion_doc, motion_bin, motion_skin, scale)
        pose_audit = (validate_pose_reference(args.source_report,
                     mesh_data(motion_doc, motion_bin, motion_skin, scale), joints, near_binds,
                     clips, root_offsets, scale)
                     if args.source_report else [])
        source_commit = "tripo-fbx-" + hashes["sourceFBX"][:32]
        bodies = {}
        skeletons = {}
        for label, document, binary, skin, _ in specs:
            body = mesh_data(document, binary, skin, scale, args.normal_mode)
            this_joints, rests, binds = skeleton(document, skin, scale)
            if [j["name"] for j in this_joints] != [j["name"] for j in joints]:
                raise ValueError("LOD joint paths differ")
            if any(np.max(abs(a - b)) > 2e-4 for a, b in zip(rests, near_rest)):
                raise ValueError("LOD rest skeleton differs")
            skeletons[label] = (rests, binds)
            layer = work / f"{label}.usdc"
            write_usd(layer, joints, rests, binds, body, clips, hashes["sourceFBX"],
                      args.weld_uv_topology)
            name = "ReplayXITripoAthlete.usdz" if label == "near" else "ReplayXITripoLow.usdz"
            package = work / name
            subprocess.run(["usdzip", "--arkitAsset", str(layer), str(package)], check=True, capture_output=True)
            normalize_usdz_timestamps(package)
            subprocess.run(["usdchecker", "--arkit", str(package)], check=True, capture_output=True)
            shutil.copyfile(package, output / name)
            bodies[label] = body
        near = bodies["near"]; low = bodies["low"]
        minimum = near["points"].min(axis=0); maximum = near["points"].max(axis=0)
        number, feet = anchors_and_contacts(near, joints, near_binds, specs[0][3]["semantic"], minimum, maximum)
        number_audit = lift_number_anchors(near, joints, near_binds, clips, number)
        geometry = {"vertices": near["vertices"], "triangles": near["triangles"], "jointCount": 52,
                    "materialCount": 1, "boundsMin": rounded(minimum), "boundsMax": rounded(maximum),
                    "nominalHeight": float(maximum[1] - minimum[1]), "restMinY": float(minimum[1]),
                    "pelvisRestHeight": float(near_binds[0][1, 3])}
        motion = {"schemaVersion": 1, "sourceCommit": source_commit, "joints": joints,
                  "semanticJoints": specs[0][3]["semantic"], "clips": clips, "geometry": geometry,
                  "footContacts": feet, "numberAnchors": number, "bodyMaterialSlot": 0,
                  "headMaterialSlot": 0, "rootMotion": "X/Z removed; vertical motion retained; metres/Y-up/+Z forward"}
        motion_path = output / "ReplayXITripoMotion.json"
        motion_path.write_text(json.dumps(motion, separators=(",", ":"), allow_nan=False) + "\n")
        if motion_path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError("motion exceeds 4 MB runtime payload limit")
        motion_hash = sha(motion_path)
        paths = [j["name"] for j in joints]
        report_contact = {}
        for label, filename in (("near", "ReplayXITripoContactSurface.json"),
                                ("low", "ReplayXITripoLowContactSurface.json")):
            body = bodies[label]
            mini = body["points"].min(axis=0); maxi = body["points"].max(axis=0)
            asset_name = "ReplayXITripoAthlete.usdz" if label == "near" else "ReplayXITripoLow.usdz"
            contact = contact_vertices(body, paths, specs[0][3]["semantic"], mini, maxi,
                                       sha(output / asset_name), motion_hash,
                                       geometry["restMinY"] + geometry["nominalHeight"] - .19)
            contact_path = output / filename
            contact_path.write_text(json.dumps(contact, separators=(",", ":"), allow_nan=False) + "\n")
            if contact_path.stat().st_size > 256 * 1024:
                raise ValueError("contact surface exceeds 256 KB")
            head_path = specs[0][3]["semantic"]["head"]
            head_indices = {index for index, path in enumerate(paths)
                            if path == head_path or path.startswith(head_path + "/")}
            floor = geometry["restMinY"] + geometry["nominalHeight"] - .19
            source_candidates = [index for index, (point, row, mass) in enumerate(zip(
                body["points"], body["joints"], body["weights"]))
                if point[1] >= floor and sum(float(weight) for joint, weight in zip(row, mass)
                                             if int(joint) in head_indices) >= .8]
            reserved = [vertex for vertex in contact["vertices"]
                        if vertex["position"][1] >= floor
                        and sum(weight for joint, weight in zip(vertex["joints"], vertex["weights"])
                                if joint in head_indices) >= .8]
            if len(reserved) != min(96, len(source_candidates)):
                raise ValueError("weighted header probe reservation changed")
            reserved_points = np.asarray([vertex["position"] for vertex in reserved])
            report_contact[label] = {"totalVertices": len(contact["vertices"]),
                                     "weightedHeadSourceCandidates": len(source_candidates),
                                     "weightedHeadProbes": len(reserved),
                                     "headProbeBoundsMin": rounded(reserved_points.min(axis=0)),
                                     "headProbeBoundsMax": rounded(reserved_points.max(axis=0))}
        report = {"sourceCommit": source_commit, "sourceHashes": hashes,
                  "atlasProvenance": atlas_audit,
                  "contactSummary": report_contact,
                  "heightScale": scale, "geometry": geometry,
                  "normalMode": args.normal_mode,
                  "numberPanel": number_audit,
                  "poseBounds": pose_audit,
                  "clips": [{"id": clip["id"], "durationSeconds": clip["durationSeconds"],
                             "frames": len(clip["frames"])} for clip in clips],
                  "assets": {}, "files": {}}
        for label, name in (("near", "ReplayXITripoAthlete.usdz"), ("low", "ReplayXITripoLow.usdz")):
            rests, binds = skeletons[label]
            report["assets"][label] = audit_usd(output / name, paths, rests, binds,
                                                 bodies[label], sha(output / name),
                                                 args.weld_uv_topology)
        report["usdTopologyMode"] = (
            "welded-position-skin-faceVarying-uv" if args.weld_uv_topology
            else "source-vertex-topology")
        for path in sorted(output.iterdir()):
            report["files"][path.name] = {"bytes": path.stat().st_size, "sha256": sha(path)}
        (output / "ReplayXITripoBuildReport.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--near-glb", type=Path, required=True)
    parser.add_argument("--low-glb", type=Path, required=True)
    parser.add_argument("--motion-glb", type=Path, required=True)
    parser.add_argument("--source-fbx", type=Path, required=True)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--source-report", type=Path, required=True)
    parser.add_argument("--source-glb", type=Path, required=True)
    parser.add_argument("--source-jpeg", type=Path, required=True)
    parser.add_argument("--kits-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--height", type=float, default=1.82)
    parser.add_argument("--normal-mode", choices=("source", "area-weighted"), default="source")
    parser.add_argument("--weld-uv-topology", action="store_true",
                        help="weld exact position+skin duplicates and store UVs face-varying in USD")
    arguments = parser.parse_args()
    print(json.dumps(build(arguments), indent=2, sort_keys=True))
