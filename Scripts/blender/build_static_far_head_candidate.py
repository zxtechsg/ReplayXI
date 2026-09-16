#!/usr/bin/env python3
"""Loop114 static far-face feasibility; factory-startup Blender, derived only.

The admitted MIT static head supplies local geometry, material and UV layout.
No bones, provider changes or source replacement. Four native procedural head
turns are applied identically to source/candidate for a bounded close-up audit.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import zipfile

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree
from pxr import Usd, UsdGeom, UsdShade, Vt

REPOSITORY = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY / "Scripts"))
from replayxi_usdz_archive import normalize_usdz_timestamps, validated_archive_names

SOURCE = REPOSITORY / "ReplayXI/Resources/Players/ReplayXIAthleteHead.usdz"
SOURCE_HASH = "7446de58f31366aacf733060a12748b62c3dfb75a46994ba3ed32576355c1f20"
POSES = Path("/private/tmp/replayxi-window80-after-01/63C43612-0281-4DD4-8E47-C5C280E827AB.json")
POSES_HASH = "5e1b700b790bda11c496146d7088390aba44ffafad7fa50822f9a374fbd2785f"
ROOT = "/ReplayXIAthleteHead"
AXIS = Matrix.Rotation(math.pi / 2, 4, "X")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_hashes():
    paths = sorted((REPOSITORY / "ReplayXI/Resources/Players").glob("*"))
    return {str(path.relative_to(REPOSITORY)): sha(path) for path in paths if path.is_file()}


def linked(name, data):
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def vertex_uvs(mesh):
    uvs = defaultdict(set)
    for loop in mesh.loops:
        uvs[loop.vertex_index].add(tuple(mesh.uv_layers.active.data[loop.index].uv))
    return uvs


def seam_signatures(mesh, indices):
    uvs = vertex_uvs(mesh)
    return Counter((tuple(mesh.vertices[index].co), tuple(sorted(uvs[index]))) for index in indices)


def packed_mesh(mesh):
    mesh.calc_loop_triangles()
    lookup, points, normals, uv, indices = {}, [], [], [], []
    for triangle in mesh.loop_triangles:
        for loop_index in triangle.loops:
            loop = mesh.loops[loop_index]
            point = tuple(mesh.vertices[loop.vertex_index].co)
            normal = tuple(mesh.corner_normals[loop_index].vector)
            texcoord = tuple(mesh.uv_layers.active.data[loop_index].uv)
            key = point, normal, texcoord
            if key not in lookup:
                lookup[key] = len(points)
                points.append(point)
                normals.append(normal)
                uv.append(texcoord)
            indices.append(lookup[key])
    return {"positions": points, "normals": normals, "uvs": uv, "triangleIndices": indices}


def surface_distances(source, target):
    source.calc_loop_triangles()
    target.calc_loop_triangles()
    tree = BVHTree.FromPolygons([vertex.co for vertex in target.vertices],
        [tuple(triangle.vertices) for triangle in target.loop_triangles], all_triangles=True)
    values = sorted(tree.find_nearest(vertex.co)[3] for vertex in source.vertices)
    return {"maximumMetres": values[-1], "p95Metres": values[int((len(values) - 1) * .95)]}


def material(texture_dir):
    value = bpy.data.materials.new("Original_Static_Head_Material")
    value.use_nodes = True
    shader = value.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = .73
    shader.inputs["Metallic"].default_value = 0
    colour = value.node_tree.nodes.new("ShaderNodeTexImage")
    colour.image = bpy.data.images.load(str(texture_dir / "head_colour.png"))
    colour.image.colorspace_settings.name = "sRGB"
    normal = value.node_tree.nodes.new("ShaderNodeTexImage")
    normal.image = bpy.data.images.load(str(texture_dir / "head_normal.png"))
    normal.image.colorspace_settings.name = "Non-Color"
    normal_map = value.node_tree.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 1
    value.node_tree.links.new(colour.outputs["Color"], shader.inputs["Base Color"])
    value.node_tree.links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    value.node_tree.links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = args.output.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise ValueError("Use factory-startup background Blender")
    if output.exists() or not output.is_relative_to(REPOSITORY / ".codex-derived"):
        raise ValueError("Choose a new derived folder")
    if sha(SOURCE) != SOURCE_HASH or sha(POSES) != POSES_HASH:
        raise ValueError("Source head/native pose identity changed")
    protected_before = protected_hashes()
    stage = Usd.Stage.Open(str(SOURCE))
    source_mesh = UsdGeom.Mesh(stage.GetPrimAtPath(ROOT + "/Face"))
    points = np.asarray(source_mesh.GetPointsAttr().Get())
    normals = np.asarray(source_mesh.GetNormalsAttr().Get())
    uv = np.asarray(UsdGeom.PrimvarsAPI(source_mesh).GetPrimvar("st").Get())
    indices = np.asarray(source_mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1, 3)
    if points.shape != (1724, 3) or indices.shape != (3128, 3):
        raise ValueError("Admitted static head topology changed")
    if UsdGeom.Xformable(stage.GetDefaultPrim()).GetOrderedXformOps():
        raise ValueError("Static source has an unexpected root transform")
    original_material = stage.GetPrimAtPath(ROOT + "/Material").GetPrimStack()[0].GetAsText()
    output.mkdir(parents=True)
    staging = output / "stage"
    staging.mkdir()
    with zipfile.ZipFile(SOURCE) as archive:
        for name in validated_archive_names(archive.infolist()):
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(name))
    scene = bpy.data.scenes.new("Low114_Static_Face")
    bpy.context.window.scene = scene
    mesh = bpy.data.meshes.new("Original_Static_Head")
    mesh.from_pydata(points.tolist(), [], indices.tolist())
    mesh.update()
    uvlayer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uvlayer.data[loop.index].uv = uv[loop.vertex_index]
    for face in mesh.polygons:
        face.use_smooth = True
    mesh.normals_split_custom_set_from_vertices(normals.tolist())
    source = linked("Original_Head", mesh)
    source.data.materials.append(material(staging / "0"))
    candidate = source.copy()
    candidate.data = source.data.copy()
    candidate.name = "Low114_Head"
    scene.collection.objects.link(candidate)
    protected = set(np.flatnonzero(points[:, 1] < -.12).tolist())
    coincident = defaultdict(list)
    for index, point in enumerate(points):
        coincident[tuple(point)].append(index)
    # The scalp's UV centreline consists of distinct coincident vertices.
    # Preserve each side, rather than independently collapsing them into a slit.
    scalp_seams = {index for point, group_indices in coincident.items()
                   if point[1] > 0 and len({tuple(uv[index]) for index in group_indices}) > 1
                   for index in group_indices}
    protected.update(scalp_seams)
    for axis in range(3):
        protected.add(int(np.argmin(points[:, axis])))
        protected.add(int(np.argmax(points[:, axis])))
    protected_points = {tuple(mesh.vertices[index].co) for index in protected}
    expected_seams = seam_signatures(mesh, protected)
    group = candidate.vertex_groups.new(name="Decimation_Allowed")
    group_name = group.name
    group.add([index for index in range(len(points)) if index not in protected], 1, "REPLACE")
    modifier = candidate.modifiers.new("Low114_Reduce", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = .24
    modifier.use_collapse_triangulate = True
    modifier.vertex_group = group_name
    modifier.vertex_group_factor = 1
    bpy.context.view_layer.objects.active = candidate
    candidate.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    candidate.vertex_groups.remove(candidate.vertex_groups[group_name])
    candidate.select_set(False)
    retained = [vertex.index for vertex in candidate.data.vertices if tuple(vertex.co) in protected_points]
    if expected_seams - seam_signatures(candidate.data, retained):
        raise ValueError("Protected neckline/orientation extrema changed position or UV")
    packed = packed_mesh(candidate.data)
    positions = np.asarray(packed["positions"])
    if len(positions) > 500 or len(packed["triangleIndices"]) // 3 > 900:
        raise ValueError(f"Static far-face geometry budget exceeded: {len(positions)} vertices")
    for field in ("positions", "normals", "uvs"):
        if not np.isfinite(np.asarray(packed[field])).all():
            raise ValueError("Nonfinite candidate attribute")
    if np.max(abs(np.linalg.norm(packed["normals"], axis=1) - 1)) > .00001:
        raise ValueError("Candidate normals are not unit length")
    layer = staging / "candidate.usda"
    extracted = Usd.Stage.Open(str(staging / "head.usdc"))
    extracted.GetRootLayer().Export(str(layer))
    candidate_stage = Usd.Stage.Open(str(layer))
    target = UsdGeom.Mesh(candidate_stage.GetPrimAtPath(ROOT + "/Face"))
    target.GetPointsAttr().Set(Vt.Vec3fArray(packed["positions"]))
    target.GetNormalsAttr().Set(Vt.Vec3fArray(packed["normals"]))
    target.GetFaceVertexCountsAttr().Set([3] * (len(packed["triangleIndices"]) // 3))
    target.GetFaceVertexIndicesAttr().Set(packed["triangleIndices"])
    target.GetExtentAttr().Set(Vt.Vec3fArray([positions.min(axis=0).tolist(), positions.max(axis=0).tolist()]))
    UsdGeom.PrimvarsAPI(target).GetPrimvar("st").Set(Vt.Vec2fArray(packed["uvs"]))
    candidate_stage.GetRootLayer().Save()
    package = output / "ReplayXIFar114Head.usdz"
    subprocess.run(["/usr/bin/usdzip", "--arkitAsset", str(layer), str(package)], check=True, capture_output=True)
    normalize_usdz_timestamps(package)
    check = subprocess.run(["/usr/bin/usdchecker", "--arkit", "-t", str(package)], check=True, capture_output=True, text=True)
    reopened = Usd.Stage.Open(str(package))
    if (len([prim for prim in reopened.Traverse() if prim.GetTypeName() == "Mesh"]) != 1
            or any(prim.GetTypeName() in ("Skeleton", "SkelRoot", "SkelAnimation") for prim in reopened.Traverse())
            or reopened.GetPrimAtPath(ROOT + "/Material").GetPrimStack()[0].GetAsText() != original_material):
        raise ValueError("Static geometry/material contract was not preserved")
    material_targets = UsdShade.MaterialBindingAPI(reopened.GetPrimAtPath(ROOT + "/Face")).ComputeBoundMaterial()
    if str(material_targets[0].GetPath()) != ROOT + "/Material":
        raise ValueError("Candidate material binding changed")
    texture_hashes = {}
    with zipfile.ZipFile(SOURCE) as original_zip, zipfile.ZipFile(package) as candidate_zip:
        for name in ("0/head_colour.png", "0/head_normal.png"):
            before, after = original_zip.read(name), candidate_zip.read(name)
            if before != after:
                raise ValueError("Static head texture changed")
            texture_hashes[name] = hashlib.sha256(before).hexdigest()
    fixture = {"schemaVersion": 1, "candidateOnly": True, "assetSHA256": sha(package),
        "assetBytes": package.stat().st_size, "sourceAssetSHA256": SOURCE_HASH,
        "vertices": len(positions), "triangles": len(packed["triangleIndices"]) // 3,
        "materials": 1, "skeletons": 0, "upAxis": "Y", "metresPerUnit": 1,
        "localBoundsMin": positions.min(axis=0).tolist(), "localBoundsMax": positions.max(axis=0).tolist(),
        "runtimePlacementContract": {"headRootLocalY": .125, "meshScale": [1.07, 1, 1]},
        "mesh": packed, "textureHashes": texture_hashes}
    (output / "native-admission-fixture.json").write_text(json.dumps(fixture, separators=(",", ":"), allow_nan=False) + "\n")
    licence = REPOSITORY / "ReplayXI/Resources/Players/LICENSE-ROCKETBOX-MIT.txt"
    (output / licence.name).write_bytes(licence.read_bytes())
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 640, 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world = bpy.data.worlds.new("Low114_World")
    scene.world.color = (.14, .14, .14)
    scene.view_settings.view_transform = "AgX"
    camera = linked("Low114_Camera", bpy.data.cameras.new("Low114_Camera"))
    camera.location = (.26, -.75, .26)
    camera.rotation_euler = (Vector((0, 0, .12)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = .42
    scene.camera = camera
    for name, location, energy, size in [
            ("Key", (-.4, -.5, .8), 50, .7), ("Fill", (.5, -.2, .4), 30, .5), ("Rim", (.1, .5, .6), 60, .6)]:
        light = linked(name, bpy.data.lights.new(name, "AREA"))
        light.location = location
        light.rotation_euler = (Vector((0, 0, .12)) - light.location).to_track_quat("-Z", "Y").to_euler()
        light.data.energy, light.data.size = energy, size
    rows = json.loads(POSES.read_text())["report"]
    selected = [rows[0], rows[26], next(row for row in rows if row["window"] == "standing"),
                next(row for row in rows if row["window"] == "running")]
    render_report = []
    for index, row in enumerate(selected):
        inverse_heading = Quaternion((0, 1, 0), -math.radians(row["facingDegrees"]))
        x, y, z, w = row["proceduralHead"]
        head = inverse_heading @ Quaternion((w, x, y, z))
        x, y, z, w = row["proceduralNeck"]
        neck = inverse_heading @ Quaternion((w, x, y, z))
        transform = AXIS @ Matrix.Translation(neck @ Vector((0, .125, 0))) @ head.to_matrix().to_4x4() @ Matrix.Diagonal((1.07, 1, 1, 1))
        for obj in (source, candidate):
            obj.matrix_world = transform
        bpy.context.view_layer.update()
        name = f"{row['window']}-{index}"
        if args.render:
            for label, visible, hidden in (("source", source, candidate), ("candidate", candidate, source)):
                visible.hide_render, hidden.hide_render = False, True
                scene.render.filepath = str(output / f"{name}-{label}.png")
                bpy.ops.render.render(write_still=True)
        render_report.append({"name": name, "nativeTime": row["time"], "actorFacingRemovedDegrees": row["facingDegrees"],
                              "nativeHeadQuaternion": row["proceduralHead"], "nativeNeckQuaternion": row["proceduralNeck"]})
    protected_after = protected_hashes()
    if protected_before != protected_after:
        raise ValueError("A shipping player resource changed")
    report = {"candidateOnly": True, "blenderVersion": bpy.app.version_string,
        "assetSHA256": sha(package), "assetBytes": package.stat().st_size,
        "sourceVertices": 1724, "sourceTriangles": 3128,
        "candidateVertices": len(positions), "candidateTriangles": len(packed["triangleIndices"]) // 3,
        "protectedNeckAndExtremaVertices": len(protected), "protectedScalpSeamVertices": len(scalp_seams),
        "collapseRatio": .24, "protectedPositionsAndUVsExact": True,
        "sourceBoundsMin": points.min(axis=0).tolist(), "sourceBoundsMax": points.max(axis=0).tolist(),
        "candidateBoundsMin": positions.min(axis=0).tolist(), "candidateBoundsMax": positions.max(axis=0).tolist(),
        "sourceToCandidateSurface": surface_distances(source.data, candidate.data),
        "candidateToSourceSurface": surface_distances(candidate.data, source.data),
        "materialBlockAndTexturesExact": True, "skeletons": 0, "models": 1, "materials": 1,
        "usdChecker": check.stdout + check.stderr, "poseAttachmentSHA256": POSES_HASH,
        "nativePoseViews": render_report, "protectedSourceHashesBefore": protected_before,
        "protectedSourceHashesAfter": protected_after,
        "limits": ["Derived only; no native candidate import", "Static rigid head, not facial animation",
                   "Blender PBR close-up, not native renderer/headset performance",
                   "Four actual orientations; actor heading removed for readable local comparison",
                   "Head/neck crop, not final far-body collar/LOD transition QA",
                   "Existing textured-head placement .125Y/1.07X required; old far ellipsoid .170Y is not interchangeable"]}
    (output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print("LOW114_HEAD", str(package), "vertices", len(positions), "triangles", len(packed["triangleIndices"]) // 3)


if __name__ == "__main__":
    main()
