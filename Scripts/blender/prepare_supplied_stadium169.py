#!/usr/bin/env python3
"""Inspect or prepare a supplied stadium in a fresh background Blender.

blender --factory-startup --background --python-exit-code 1 --python this_file -- \
  --input stadium.obj.zip --expected-input-sha256 SHA --output-dir NEW_DERIVED_DIR \
  --inspect-only

Then inspect Inspection.blend and supply --calibration measured.json instead
of --inspect-only. Calibration is in Blender WORLD coordinates after Y-up
source import (Z-up), not raw OBJ/GLB coordinates. Opening sizes are AFTER
the specified rotation. Never infer them from the stadium's outside bounds.

Example schema (numbers below are illustrative, NOT asset calibration):
{
  "sourceSHA256": "...",
  "sourceOpeningCenter": [0, 0, 0],
  "rotationDegreesXYZ": [0, 0, 0],
  "sourceOpeningSize": [1, 1],
  "safetyMarginMetres": [2, 3.5],
  "scaleMode": "uniform",
  "removeObjects": [],
  "removeMaterials": [],
  "removeInteriorBelowMetres": null,
  "notes": "How the actual opening and pitch level were measured",
  "authoredPalette": "replay-navy-teal-steel-v1"
}

Uniform scaling fits BOTH 68x105m pitch dimensions plus margins. Explicit
"nonuniform" permits separate horizontal scales; height uses the larger scale.
Named removal is exact. Optional interior removal deletes whole triangles that
overlap the clear opening and lie entirely below the supplied height. It is
never inferred from colour or names. Any remaining overlap blocks export.
For the reviewed untextured OBJ only, --bake-atlas makes one 2K colour map with
authored colours, local AO and a soft diffuse directional factor (not dynamic
lighting). It uses32 Cycles samples,16 AO rays,8 CPU threads; original UVs are
archived and mesh position/index identity is asserted. --render-inspection
adds top/front/rear views and four unlit head-height views for comparison.
No remeshing, network or live-scene edits. Output is candidate-only; native bounds/material/render admission is
still required. Source archives and bundled app resources remain unchanged.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import time
import zipfile

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector
from pxr import Usd, UsdGeom

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "Scripts"))
from replayxi_usdz_archive import normalize_usdz_timestamps, validated_archive_names

MAX_TRIANGLES = 25_000
MAX_TEXTURE = 2048
MAX_MATERIALS = 4


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, document):
    path.write_text(json.dumps(document, indent=2, allow_nan=False) + "\n")


def finite(values, count, name):
    if not isinstance(values, list) or len(values) != count or any(
            not isinstance(v, (float, int)) or isinstance(v, bool) or not math.isfinite(v) for v in values):
        raise ValueError(f"{name}: expected {count} finite numbers")
    return [float(v) for v in values]


def glb_header(path):
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF" or struct.unpack_from("<II", data, 4) != (2, len(data)):
        raise ValueError("Input is not a complete GLB 2.0 file")
    size, kind = struct.unpack_from("<I4s", data, 12)
    if kind != b"JSON" or 20 + size > len(data):
        raise ValueError("GLB JSON chunk is invalid")
    document = json.loads(data[20:20 + size])
    if document.get("skins") or document.get("animations"):
        raise ValueError("Stadium must be static: skeletons and animation require separate review")
    if any(buffer.get("uri") for buffer in document.get("buffers", [])) or any(
            image.get("uri") for image in document.get("images", [])):
        raise ValueError("Use a self-contained GLB with embedded buffers/images; no external URI loading")
    return document


def bounds(objects):
    points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
    if not points or any(not math.isfinite(value) for point in points for value in point):
        raise ValueError("Missing or nonfinite geometry")
    return {"min": [min(p[i] for p in points) for i in range(3)],
            "max": [max(p[i] for p in points) for i in range(3)]}


def triangle_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def image_nodes(material):
    if not material or not material.use_nodes:
        return []
    return [node for node in material.node_tree.nodes if node.type == "TEX_IMAGE" and node.image]


def inspect(objects):
    return [{"name": obj.name, "triangles": triangle_count(obj), "vertices": len(obj.data.vertices),
             "boundsBlenderWorld": bounds([obj]), "uvLayers": [uv.name for uv in obj.data.uv_layers],
             "materials": [{"name": material.name,
                            "images": [{"name": n.image.name, "size": list(n.image.size),
                                        "colourSpace": n.image.colorspace_settings.name}
                                       for n in image_nodes(material)]}
                           for material in obj.data.materials if material]}
            for obj in objects]


def connected_parts(obj):
    """Topological components before any UV-seam welding; bounds aid inspection."""
    parents = list(range(len(obj.data.vertices)))
    edges = np.empty(len(obj.data.edges) * 2, dtype=np.int32)
    obj.data.edges.foreach_get("vertices", edges)

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for a, b in edges.reshape(-1, 2):
        a, b = root(int(a)), root(int(b))
        if a != b:
            parents[b] = a
    groups = {}
    for vertex in obj.data.vertices:
        identifier = root(vertex.index)
        point = obj.matrix_world @ vertex.co
        record = groups.setdefault(identifier, {"representativeVertex": identifier, "vertices": 0,
                                                "min": list(point), "max": list(point), "triangles": 0})
        record["vertices"] += 1
        for axis in range(3):
            record["min"][axis] = min(record["min"][axis], point[axis])
            record["max"][axis] = max(record["max"][axis], point[axis])
    obj.data.calc_loop_triangles()
    for triangle in obj.data.loop_triangles:
        groups[root(triangle.vertices[0])]["triangles"] += 1
    ordered = sorted(groups.values(), key=lambda record: record["triangles"], reverse=True)
    return {"object": obj.name, "componentCount": len(ordered), "largestComponents": ordered[:32],
            "qualification": "Index-connected components; texture/normal seams can split a visual surface"}


def render_inspection(scene, objects, output):
    limits = bounds(objects)
    centre = Vector([(limits["min"][i] + limits["max"][i]) / 2 for i in range(3)])
    span = max(limits["max"][i] - limits["min"][i] for i in range(3))
    world = bpy.data.worlds.new("InspectionWorld169")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.22, 0.25, 0.30, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.65
    scene.world = world
    lamp_data = bpy.data.lights.new("InspectionSun169", "SUN")
    lamp_data.energy = 2.5
    lamp = bpy.data.objects.new("InspectionSun169", lamp_data)
    lamp.rotation_euler = (0.4, -0.6, -0.5)
    scene.collection.objects.link(lamp)
    camera_data = bpy.data.cameras.new("InspectionCamera169")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = span * 1.45
    camera_data.clip_start = max(span / 1_000_000, 0.001)
    camera_data.clip_end = span * 20
    camera = bpy.data.objects.new("InspectionCamera169", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    for label, offset in [("top", (0, 0, 2.5)), ("front", (1.2, -1.7, 1.1)), ("rear", (-1.2, 1.7, 1.1))]:
        camera.location = centre + Vector(offset) * span
        camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(output / f"inspection-{label}.png")
        bpy.ops.render.render(write_still=True)
    # Preview-only entities are not kept in the inspectable asset scene.
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.objects.remove(lamp, do_unlink=True)


def select_only(objects):
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in objects:
        obj.hide_set(False)
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def render_inside_preview(scene, objects, output):
    """Four fixed eye-height views; diagnostic floor only, never exported.

    Emission imitates the app's stable unlit palette. The original material
    data is copied before editing, and camera/ground are removed afterwards.
    """
    original_materials = [(obj, list(obj.data.materials)) for obj in objects]
    copies = {}
    for obj, slots in original_materials:
        for index, material in enumerate(slots):
            key = material.as_pointer()
            if key not in copies:
                copy = material.copy()
                shader = copy.node_tree.nodes.get("Principled BSDF")
                colour = tuple(shader.inputs["Base Color"].default_value) if shader else tuple(copy.diffuse_color)
                linked_image = None
                if shader and shader.inputs["Base Color"].is_linked:
                    source_node = shader.inputs["Base Color"].links[0].from_node
                    if source_node.type == "TEX_IMAGE":
                        linked_image = source_node.image
                copy.node_tree.nodes.clear()
                emission = copy.node_tree.nodes.new("ShaderNodeEmission")
                emission.inputs[0].default_value = colour
                if linked_image:
                    texture = copy.node_tree.nodes.new("ShaderNodeTexImage")
                    texture.image = linked_image
                    copy.node_tree.links.new(texture.outputs["Color"], emission.inputs[0])
                out = copy.node_tree.nodes.new("ShaderNodeOutputMaterial")
                copy.node_tree.links.new(emission.outputs[0], out.inputs[0])
                copies[key] = copy
            obj.data.materials[index] = copies[key]
    world = bpy.data.worlds.new("InsidePreviewWorld169")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.07, 0.12, 0.19, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    previous_world = scene.world
    scene.world = world
    floor_mesh = bpy.data.meshes.new("PreviewFloorOnly")
    floor_mesh.from_pydata([(-160, -160, -0.04), (160, -160, -0.04), (160, 160, -0.04), (-160, 160, -0.04)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("PreviewFloorOnly", floor_mesh)
    scene.collection.objects.link(floor)
    ground = bpy.data.materials.new("PreviewFloorOnly")
    ground.use_nodes = True
    ground.node_tree.nodes.clear()
    emission = ground.node_tree.nodes.new("ShaderNodeEmission")
    emission.inputs[0].default_value = (0.025, 0.075, 0.055, 1)
    out = ground.node_tree.nodes.new("ShaderNodeOutputMaterial")
    ground.node_tree.links.new(emission.outputs[0], out.inputs[0])
    floor_mesh.materials.append(ground)
    data = bpy.data.cameras.new("InsidePreviewCamera169")
    data.type = "PERSP"
    data.angle = math.radians(76)
    data.clip_start = 0.05
    data.clip_end = 500
    camera = bpy.data.objects.new("InsidePreviewCamera169", data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    camera.location = (0, 0, 1.7)
    for label, target in [("north", (0, 70, 7)), ("south", (0, -70, 7)), ("west", (-60, 0, 7)), ("east", (60, 0, 7))]:
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(output / f"inside-unlit-{label}.png")
        bpy.ops.render.render(write_still=True)
    for obj, materials in original_materials:
        obj.data.materials.clear()
        for material in materials:
            obj.data.materials.append(material)
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.objects.remove(floor, do_unlink=True)
    scene.world = previous_world


def overlaps_opening(points, half_width, half_length):
    """2D separating-axis test, including triangles whose vertices miss the hole."""
    corners = [(-half_width, -half_length), (half_width, -half_length),
               (half_width, half_length), (-half_width, half_length)]
    axes = [(1, 0), (0, 1)]
    for a, b in zip(points, points[1:] + points[:1]):
        axes.append((-(b[1] - a[1]), b[0] - a[0]))
    for x, y in axes:
        length = math.hypot(x, y)
        if length < 1e-12:
            continue
        x, y = x / length, y / length
        a = [p[0] * x + p[1] * y for p in points]
        b = [p[0] * x + p[1] * y for p in corners]
        if max(a) <= min(b) + 1e-5 or max(b) <= min(a) + 1e-5:
            return False
    return True


def calibration(path, expected):
    document = json.loads(path.read_text())
    if document.get("sourceSHA256") != expected:
        raise ValueError("Calibration must name the exact inspected source hash")
    centre = finite(document.get("sourceOpeningCenter"), 3, "sourceOpeningCenter")
    angles = finite(document.get("rotationDegreesXYZ"), 3, "rotationDegreesXYZ")
    opening = finite(document.get("sourceOpeningSize"), 2, "sourceOpeningSize")
    margin = finite(document.get("safetyMarginMetres"), 2, "safetyMarginMetres")
    if min(opening) <= 0 or margin[0] < 2 or margin[1] < 3.5:
        raise ValueError("Opening must be positive; margins must cover at least the clear 72x112m rectangle")
    if not isinstance(document.get("notes"), str) or not document["notes"].strip():
        raise ValueError("Calibration needs measurement notes")
    for key in ("removeObjects", "removeMaterials"):
        if not isinstance(document.get(key), list) or any(not isinstance(n, str) or not n for n in document[key]):
            raise ValueError(f"{key}: supply exact names, or []")
    cut = document.get("removeInteriorBelowMetres")
    if cut is not None and (isinstance(cut, bool) or not isinstance(cut, (float, int)) or not math.isfinite(cut)):
        raise ValueError("removeInteriorBelowMetres must be null or a finite explicit height")
    target = [68 + 2 * margin[0], 105 + 2 * margin[1]]
    horizontal = [target[i] / opening[i] for i in range(2)]
    if document.get("scaleMode") == "uniform":
        scale = [max(horizontal)] * 3
    elif document.get("scaleMode") == "nonuniform":
        scale = horizontal + [max(horizontal)]
    else:
        raise ValueError("scaleMode must explicitly be uniform or nonuniform")
    rotation = Euler([math.radians(v) for v in angles], "XYZ").to_matrix().to_4x4()
    transform = Matrix.Diagonal(Vector((*scale, 1))) @ rotation @ Matrix.Translation(-Vector(centre))
    return document, transform, target, scale


def clean_and_transform(objects, document, transform, target):
    removals = []
    available_objects = {obj.name for obj in objects}
    available_materials = {mat.name for obj in objects for mat in obj.data.materials if mat}
    if set(document["removeObjects"]) - available_objects or set(document["removeMaterials"]) - available_materials:
        raise ValueError("An explicit removal name is absent from the inspected asset")
    retained = []
    for obj in objects:
        if obj.name in document["removeObjects"]:
            removals.append({"object": obj.name, "reason": "explicit object", "triangles": triangle_count(obj)})
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        if obj.modifiers or obj.data.shape_keys or obj.animation_data:
            raise ValueError(f"{obj.name}: unsupported modifiers, shape keys or animation")
        world = transform @ obj.matrix_world
        obj.data = obj.data.copy()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data.transform(world)
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
        removed = []
        for face in mesh.faces:
            material = obj.data.materials[face.material_index] if face.material_index < len(obj.data.materials) else None
            named = material and material.name in document["removeMaterials"]
            cut = document.get("removeInteriorBelowMetres")
            interior = cut is not None and max(v.co.z for v in face.verts) <= cut and overlaps_opening(
                [tuple(v.co) for v in face.verts], target[0] / 2, target[1] / 2)
            if named or interior:
                removed.append(face)
        removals.append({"object": obj.name, "reason": "explicit material or low interior policy",
                         "triangles": len(removed)})
        bmesh.ops.delete(mesh, geom=removed, context="FACES")
        bmesh.ops.delete(mesh, geom=[v for v in mesh.verts if not v.link_faces], context="VERTS")
        mesh.normal_update()
        mesh.to_mesh(obj.data)
        mesh.free()
        obj.data.update()
        if not obj.data.polygons:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        if len(obj.data.uv_layers) != 1:
            raise ValueError(f"{obj.name}: require one original UV layer; multi-UV consolidation needs manual review")
        obj.data.uv_layers.active.name = "UVMap"
        retained.append(obj)
    if not retained:
        raise ValueError("Removal policy deleted all stadium geometry")
    return retained, removals


def validate_opening(obj, target):
    obj.data.calc_loop_triangles()
    collisions = [face.index for face in obj.data.loop_triangles if overlaps_opening(
        [tuple(obj.data.vertices[i].co) for i in face.vertices], target[0] / 2, target[1] / 2)]
    if collisions:
        print(json.dumps({"openingIntrusions": [[list(obj.data.vertices[v].co)
                                                for v in obj.data.loop_triangles[i].vertices]
                                               for i in collisions[:24]]}))
        raise ValueError(f"{len(collisions)} triangles span the clear pitch opening; inspect/calibrate/remove explicitly")


def simplify(objects, target):
    select_only(objects)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "ReplayXIStadium"
    # Remove only unused slots; actual source materials/images are preserved.
    bpy.ops.object.material_slot_remove_unused()
    if not 1 <= len(obj.data.materials) <= MAX_MATERIALS or any(not mat for mat in obj.data.materials):
        raise ValueError("Material budget exceeded or missing material")
    validate_opening(obj, target)
    before = triangle_count(obj)
    ratios = []
    for _ in range(3):
        count = triangle_count(obj)
        if count <= MAX_TRIANGLES:
            break
        modifier = obj.modifiers.new("OfflineStadiumLOD", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = MAX_TRIANGLES / count * 0.97
        modifier.use_collapse_triangulate = True
        ratios.append(modifier.ratio)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    if triangle_count(obj) > MAX_TRIANGLES:
        raise ValueError("Decimation could not meet 25K triangles")
    validate_opening(obj, target)
    return obj, {"trianglesBefore": before, "trianglesAfter": triangle_count(obj), "ratios": ratios,
                 "method": "Blender collapse decimation; original UV/material data retained; visual QA still required"}


def author_supplied_materials(objects, document):
    """Explicit palette for the supplied OBJ whose referenced MTL was absent.

    No Tripo mesh, image, or material is used. Geometry and group names select
    palette roles; sloped seating is observed in Layer0_001 at low elevation.
    """
    if document.get("authoredPalette") != "replay-navy-teal-steel-v1":
        raise ValueError("OBJ without MTL requires the explicit reviewed authoredPalette")
    roles = [("Structure", (0.045, 0.080, 0.125, 1)),
             ("Seating", (0.060, 0.34, 0.36, 1)),
             ("Steel", (0.33, 0.41, 0.47, 1)),
             ("Fixtures", (0.64, 0.74, 0.76, 1))]
    materials = []
    for name, colour in roles:
        material = bpy.data.materials.new("SuppliedStadium" + name)
        material.use_nodes = True
        material.diffuse_color = colour
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = colour
        shader.inputs["Roughness"].default_value = 0.85
        material.use_backface_culling = False
        materials.append(material)
    counts = [0] * 4
    for obj in objects:
        obj.data.materials.clear()
        for material in materials:
            obj.data.materials.append(material)
        obj.data.update()
        for face in obj.data.polygons:
            centre = face.center
            if obj.name.startswith("Group_61_"):
                role = 3  # Observed repeated roof-line floodlight fixtures.
            elif obj.name.startswith("bars_") or obj.name.startswith("Group_6_") or obj.name in {"Group_028", "Group_030", "Group_032", "Group_7_003", "Group_7_004"}:
                role = 2  # Trusses, roof panels, and main-stand envelope.
            elif obj.name == "Layer0_001" and 0 < centre.z < 12 and abs(face.normal.z) > 0.25:
                role = 1  # Original raked/horizontal terrace faces, not new geometry.
            else:
                role = 0
            face.material_index = role
            counts[role] += max(1, len(face.vertices) - 2)
    return {"reason": "Supplied ZIP has no MTL or images; these are authored colours, not recovered source materials",
            "palette": document["authoredPalette"],
            "roles": [{"name": name, "linearRGBA": list(colour), "trianglesBeforeReduction": count}
                      for (name, colour), count in zip(roles, counts)]}


def resize_textures(obj, output):
    directory = output / "textures"
    directory.mkdir()
    copies, report = {}, []
    for material in obj.data.materials:
        for node in image_nodes(material):
            source = node.image
            key = source.as_pointer()
            if key in copies:
                node.image = copies[key]
                continue
            width, height = source.size
            if width < 1 or height < 1:
                raise ValueError(f"Missing image pixels: {source.name}")
            if source.source not in {"FILE", "GENERATED"}:
                raise ValueError(f"Unsupported image source: {source.source}")
            image = source.copy()
            ratio = min(1, MAX_TEXTURE / max(width, height))
            dimensions = [max(1, round(width * ratio)), max(1, round(height * ratio))]
            if dimensions != [width, height]:
                image.scale(*dimensions)
            name = f"SuppliedStadiumTexture{len(copies):02d}.png"
            path = directory / name
            image.filepath_raw = str(path)
            image.file_format = "PNG"
            image.save()
            node.image = image
            copies[key] = image
            report.append({"sourceImage": source.name, "sourceSize": [width, height], "outputSize": dimensions,
                           "colourSpace": source.colorspace_settings.name, "output": f"textures/{name}",
                           "sha256": digest(path), "operation": "resize" if ratio < 1 else "lossless PNG export"})
    if not report:
        raise ValueError("No original textures survived; manual material review is required")
    return report


def geometry_fingerprint(obj):
    """No materials/UVs: assert the bake never changes source geometry."""
    vertices = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
    obj.data.vertices.foreach_get("co", vertices)
    obj.data.calc_loop_triangles()
    indices = np.array([t.vertices[:] for t in obj.data.loop_triangles], dtype=np.int32)
    return hashlib.sha256(vertices.tobytes() + indices.tobytes()).hexdigest()


def bake_supplied_atlas(scene, obj, output):
    """Bounded CPU Cycles bake, retaining exact mesh and archiving source UVs.

    Authored colour × soft diffuse directional factor × local AO. Lighting is
    deliberately frozen in the colour map for the app's unlit material. No
    baked geometry, atlas, or lighting is represented as an original texture.
    """
    started = time.monotonic()
    before = geometry_fingerprint(obj)
    obj.data = obj.data.copy()
    original_uv = np.empty(len(obj.data.loops) * 2, dtype=np.float32)
    obj.data.uv_layers.active.data.foreach_get("uv", original_uv)
    np.savez_compressed(output / "original-uv.npz", uv=original_uv.reshape(-1, 2))
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    obj.data.uv_layers.new(name="UVMap")
    select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004,
                             area_weight=0.5, correct_aspect=True, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("Stadium bake: smart UV complete", flush=True)

    atlas = bpy.data.images.new("SuppliedStadiumBakedColour", width=2048, height=2048, alpha=False, float_buffer=False)
    atlas.colorspace_settings.name = "sRGB"
    light_direction = Vector((-0.35, -0.5, 0.8)).normalized()
    for material in obj.data.materials:
        nodes, links = material.node_tree.nodes, material.node_tree.links
        colour = tuple(nodes.get("Principled BSDF").inputs["Base Color"].default_value)
        nodes.clear()
        geometry = nodes.new("ShaderNodeNewGeometry")
        split = nodes.new("ShaderNodeSeparateXYZ")
        links.new(geometry.outputs["Normal"], split.inputs[0])
        negative = nodes.new("ShaderNodeMath")
        negative.operation = "LESS_THAN"
        links.new(split.outputs["Z"], negative.inputs[0])
        negative.inputs[1].default_value = 0
        sign = nodes.new("ShaderNodeMath")
        sign.operation = "MULTIPLY_ADD"
        links.new(negative.outputs[0], sign.inputs[0])
        sign.inputs[1].default_value = -2
        sign.inputs[2].default_value = 1
        oriented = nodes.new("ShaderNodeVectorMath")
        oriented.operation = "SCALE"
        links.new(geometry.outputs["Normal"], oriented.inputs[0])
        links.new(sign.outputs[0], oriented.inputs[3])
        # Source has reversed open terrace faces. Flip the shading normal only
        # toward the upper hemisphere; winding/positions remain byte-identical.
        ao = nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.only_local = True
        ao.inputs["Distance"].default_value = 4
        links.new(oriented.outputs[0], ao.inputs["Normal"])
        ao_floor = nodes.new("ShaderNodeMath")
        ao_floor.operation = "MULTIPLY_ADD"
        links.new(ao.outputs["AO"], ao_floor.inputs[0])
        ao_floor.inputs[1].default_value = 0.65
        ao_floor.inputs[2].default_value = 0.35
        directional = nodes.new("ShaderNodeVectorMath")
        directional.operation = "DOT_PRODUCT"
        links.new(oriented.outputs[0], directional.inputs[0])
        directional.inputs[1].default_value = light_direction
        soft = nodes.new("ShaderNodeMath")
        soft.operation = "MULTIPLY_ADD"
        links.new(directional.outputs["Value"], soft.inputs[0])
        soft.inputs[1].default_value = 0.25
        soft.inputs[2].default_value = 0.78
        shade = nodes.new("ShaderNodeMath")
        shade.operation = "MULTIPLY"
        links.new(soft.outputs[0], shade.inputs[0])
        links.new(ao_floor.outputs[0], shade.inputs[1])
        tinted = nodes.new("ShaderNodeVectorMath")
        tinted.operation = "SCALE"
        tinted.inputs[0].default_value = colour[:3]
        links.new(shade.outputs[0], tinted.inputs[3])
        emission = nodes.new("ShaderNodeEmission")
        links.new(tinted.outputs[0], emission.inputs[0])
        out = nodes.new("ShaderNodeOutputMaterial")
        links.new(emission.outputs[0], out.inputs[0])
        target = nodes.new("ShaderNodeTexImage")
        target.image = atlas
        nodes.active = target
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 8
    scene.render.bake.margin = 8
    scene.render.bake.use_clear = True
    scene.render.bake.use_selected_to_active = False
    print("Stadium bake: 2048px, 32 Cycles samples, 16 AO rays, 8 CPU threads", flush=True)
    bpy.ops.object.bake(type="EMIT", use_clear=True, margin=8)
    directory = output / "textures"
    directory.mkdir()
    atlas.filepath_raw = str(directory / "SuppliedStadiumBakedColour.png")
    atlas.file_format = "PNG"
    atlas.save()
    material = bpy.data.materials.new("SuppliedStadiumBakedColour")
    material.use_nodes = True
    material.use_backface_culling = False
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (1, 1, 1, 1)
    shader.inputs["Roughness"].default_value = 0.85
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = atlas
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    after = geometry_fingerprint(obj)
    if before != after:
        raise ValueError("Atlas preparation changed mesh geometry")
    return [{"output": "textures/SuppliedStadiumBakedColour.png", "outputSize": [2048, 2048],
             "colourSpace": "sRGB", "sha256": digest(Path(atlas.filepath_raw)),
             "operation": "Authored palette, soft diffuse directional factor and local AO baked to colour; not a supplied texture"}], {
                 "engine": "CPU Cycles emission bake of authored shading", "samples": 32, "aoRays": 16,
                 "cpuThreads": 8, "aoDistanceMetres": 4, "aoFloor": 0.35,
                 "softDirectionalFactor": "0.78 + 0.25 * dot(upperHemisphereNormal, normalized(-0.35,-0.5,0.8))",
                 "uv": "Smart project 66 degrees, areaWeight0.5, islandMargin0.004, 8px bake padding",
                 "originalUVBackup": "original-uv.npz", "originalUVSHA256": digest(output / "original-uv.npz"),
                 "geometrySHA256Before": before, "geometrySHA256After": after,
                 "elapsedSeconds": round(time.monotonic() - started, 3)}


def audit_usdz(package, target, texture_count):
    normalize_usdz_timestamps(package)
    with zipfile.ZipFile(package) as archive:
        names = validated_archive_names(archive.infolist())
        textures = [n for n in names if Path(n).suffix.lower() in {".png", ".jpg", ".jpeg"}]
        if len(textures) < texture_count:
            raise ValueError("USDZ contains fewer image dependencies than preserved source images")
        for name in textures:
            if name.endswith(".png"):
                image_header = archive.read(name)[:24]
                if image_header[:8] != b"\x89PNG\r\n\x1a\n":
                    raise ValueError("Packaged PNG signature differs from expected image")
                if not all(0 < size <= MAX_TEXTURE for size in struct.unpack(">II", image_header[16:24])):
                    raise ValueError("Packaged PNG exceeds the 2K texture budget")
    stage = Usd.Stage.Open(str(package))
    if not stage or UsdGeom.GetStageUpAxis(stage) != "Y" or abs(UsdGeom.GetStageMetersPerUnit(stage) - 1) > 1e-8:
        raise ValueError("USDZ must explicitly use Y-up and metre units")
    meshes = [UsdGeom.Mesh(p) for p in stage.Traverse() if p.GetTypeName() == "Mesh"]
    materials = [p for p in stage.Traverse() if p.GetTypeName() == "Material"]
    if len(meshes) != 1 or not 1 <= len(materials) <= MAX_MATERIALS:
        raise ValueError("USDZ mesh/material counts differ from candidate")
    if any(p.GetTypeName() in {"Skeleton", "SkelRoot", "SkelAnimation", "Camera", "DistantLight", "SphereLight"}
           for p in stage.Traverse()):
        raise ValueError("Unexpected animation, camera or light in USDZ")
    cache = UsdGeom.XformCache()
    all_points, triangles = [], 0
    for mesh in meshes:
        transform = cache.GetLocalToWorldTransform(mesh.GetPrim())
        points = [transform.Transform(p) for p in mesh.GetPointsAttr().Get()]
        counts, indices = list(mesh.GetFaceVertexCountsAttr().Get()), list(mesh.GetFaceVertexIndicesAttr().Get())
        if not points or not all(n == 3 for n in counts) or len(indices) != len(counts) * 3:
            raise ValueError("USDZ topology is not the bounded triangulated candidate")
        if not UsdGeom.PrimvarsAPI(mesh).GetPrimvar("st").Get():
            raise ValueError("USDZ lost the original UV layer")
        for index in range(0, len(indices), 3):
            face = [points[i] for i in indices[index:index + 3]]
            if overlaps_opening([(p[0], p[2]) for p in face], target[0] / 2, target[1] / 2):
                raise ValueError("USDZ transform/export intrudes into the clear pitch opening")
        triangles += len(counts)
        if not mesh.GetDoubleSidedAttr().Get():
            raise ValueError("Stadium mesh must be explicitly double-sided for inward visibility")
        all_points.extend(points)
    if triangles > MAX_TRIANGLES or package.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("USDZ exceeds triangle or package budget")
    check = subprocess.run(["/usr/bin/usdchecker", "--arkit", "-t", str(package)],
                           capture_output=True, text=True, timeout=60, check=True)
    return {"upAxis": "Y", "metresPerUnit": 1, "meshCount": len(meshes), "materialCount": len(materials),
            "triangles": triangles, "boundsYUp": {"min": [min(p[i] for p in all_points) for i in range(3)],
                                                  "max": [max(p[i] for p in all_points) for i in range(3)]},
            "packagedImages": textures, "sha256": digest(package), "bytes": package.stat().st_size,
            "usdchecker": check.stdout.strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--expected-input-sha256", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--render-inspection", action="store_true", help="Three bounded source views; never app assets")
    parser.add_argument("--bake-atlas", action="store_true", help="Explicit 2K authored shading bake for supplied untextured OBJ only")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--inspect-only", action="store_true")
    mode.add_argument("--calibration", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not bpy.app.background or bpy.data.filepath or "--factory-startup" not in sys.argv:
        raise RuntimeError("Use a separate --factory-startup --background Blender process")
    source, output = args.input.resolve(), args.output_dir.resolve()
    if not source.is_file() or source.suffix.lower() not in {".glb", ".zip"} or source.stat().st_size > 256 * 1024 * 1024:
        raise ValueError("Input must be an existing GLB or single-OBJ ZIP under 256MB")
    source_digest = digest(source)
    if source_digest != args.expected_input_sha256.lower():
        raise ValueError("Input hash differs from expected asset")
    if output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Output must be a NEW directory under .codex-derived")
    header = glb_header(source) if source.suffix.lower() == ".glb" else None
    settings = calibration(args.calibration, source_digest) if args.calibration else None
    required = {"convert_orientation", "export_global_forward_selection", "export_global_up_selection",
                "export_textures_mode", "triangulate_meshes", "rename_uvmaps", "convert_scene_units"}
    if required - set(bpy.ops.wm.usd_export.get_rna_type().properties.keys()):
        raise RuntimeError("Installed Blender lacks the reviewed USD export API")

    scene = bpy.data.scenes.new("Supplied Stadium Candidate169")
    bpy.context.window.scene = scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1
    output.mkdir(parents=True)
    if header is not None:
        bpy.ops.import_scene.gltf(filepath=str(source))
    else:
        with zipfile.ZipFile(source) as archive:
            entries = archive.infolist()
            if len(entries) != 1 or entries[0].filename != "3d-model.obj" or entries[0].file_size > 32 * 1024 * 1024:
                raise ValueError("Supplied ZIP must contain only the reviewed 3d-model.obj under 32MB")
            original = archive.read(entries[0])
        # Keep an exact extracted source copy. Import copy removes absent MTL
        # references, so the importer cannot read any external file by accident.
        (output / "source.obj").write_bytes(original)
        lines = original.decode("utf-8").splitlines()
        import_path = output / "import.obj"
        import_path.write_text("\n".join(line for line in lines if not line.startswith("mtllib ")) + "\n")
        bpy.ops.wm.obj_import(filepath=str(import_path), forward_axis="NEGATIVE_Z", up_axis="Y",
                              use_split_objects=True, use_split_groups=True)
    objects = [obj for obj in scene.objects if obj.type == "MESH" and len(obj.data.vertices)]
    if not objects:
        raise ValueError("Source has no visible mesh")
    inspection = {"schemaVersion": 1, "source": str(source), "sourceSHA256": source_digest,
                  "sourceKind": "Supplied OBJ ZIP; no MTL or textures" if header is None else "Supplied GLB",
                  "coordinateFrame": "Blender world Z-up after Y-up import", "meshes": inspect(objects),
                  "sourceImageCount": len(header.get("images", [])) if header else 0,
                  "sourceMaterialCount": len(header.get("materials", [])) if header else 0,
                  "totalTriangles": sum(triangle_count(obj) for obj in objects), "bounds": bounds(objects)}
    write_json(output / "inspection.json", inspection)
    if args.inspect_only:
        inspection["connectedParts"] = [connected_parts(obj) for obj in objects]
        write_json(output / "inspection.json", inspection)
        if args.render_inspection:
            render_inspection(scene, objects, output)
        bpy.data.libraries.write(str(output / "Inspection.blend"), {scene}, fake_user=True, compress=True)
        print(json.dumps({"inspection": str(output / "inspection.json"), "prepared": False}))
        return
    try:
        document, transform, target, scale = settings
        objects, removals = clean_and_transform(objects, document, transform, target)
        authored = author_supplied_materials(objects, document) if header is None else None
        obj, reduction = simplify(objects, target)
        textures = resize_textures(obj, output) if header is not None else []
        bake = None
        if args.bake_atlas:
            if header is not None:
                raise ValueError("Authored atlas only supports the reviewed untextured supplied OBJ")
            textures, bake = bake_supplied_atlas(scene, obj, output)
        select_only([obj])
        package = output / "ReplayXIStadium.usdz"
        bpy.ops.wm.usd_export(filepath=str(package), selected_objects_only=True, export_animation=False,
                              export_materials=True, generate_preview_surface=True, export_uvmaps=True,
                              rename_uvmaps=True, triangulate_meshes=True, export_textures_mode="NEW",
                              convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                              export_global_up_selection="Y", convert_scene_units="METERS",
                              root_prim_path="/ReplayXIStadium")
        audited = audit_usdz(package, target, len(textures))
        if digest(source) != source_digest:
            raise ValueError("Source changed during preparation")
        bpy.data.libraries.write(str(output / "Candidate.blend"), {scene}, fake_user=True, compress=True)
        if args.render_inspection:
            render_inspection(scene, [obj], output)
            render_inside_preview(scene, [obj], output)
        report = {"schemaVersion": 1, "candidateOnly": True, "source": inspection,
                  "calibration": document, "calibrationSHA256": digest(args.calibration),
                  "scaleMetresPerSourceUnit": scale, "minimumClearOpeningMetres": target,
                  "measuredOpeningAfterScale": [document["sourceOpeningSize"][i] * scale[i] for i in range(2)],
                  "removals": removals, "decimation": reduction, "textures": textures, "authoredMaterials": authored, "bake": bake, "asset": audited,
                  "remainingAdmission": "Review native Y-up bounds, materials/textures, opening and rendered appearance before bundling. No performance/headset claim."}
        write_json(output / "manifest.json", report)
        print(json.dumps({"manifest": str(output / "manifest.json"), "candidateOnly": True, "asset": audited}))
    except Exception as error:
        write_json(output / "failure.json", {"candidateAdmitted": False, "error": str(error),
                                              "partialOutputs": "Inspection only; do not bundle without manifest.json and native admission"})
        raise


if __name__ == "__main__":
    main()
