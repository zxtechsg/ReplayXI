#!/usr/bin/env python3
"""Build an original 32-panel ball in isolated background Blender, without downloads.

Exports a two-material, single-mesh USDZ, editable .blend and validation report.
Usage: blender --background --factory-startup --python-exit-code 2 --python
Scripts/blender/build_strategy_ball.py -- --output /new/output/directory
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector


def build(output):
    if not bpy.app.background:
        raise RuntimeError("Use an isolated background Blender process, not a live user scene")
    if output.exists():
        raise RuntimeError("Output exists; choose a new directory")
    output.mkdir(parents=True)
    scene = bpy.data.scenes.new("ReplayXI Original Strategy Ball")
    bpy.context.window.scene = scene

    ico = bmesh.new()
    bmesh.ops.create_icosphere(ico, subdivisions=1, radius=1)
    ico.verts.ensure_lookup_table()
    directions = [vertex.co.copy().normalized() for vertex in ico.verts]
    triangles = [tuple(vertex.index for vertex in face.verts) for face in ico.faces]
    ico.free()
    assert len(directions) == 12 and len(triangles) == 20
    neighbours = [set() for _ in directions]
    for face in triangles:
        for a, b in zip(face, face[1:] + face[:1]):
            neighbours[a].add(b)
            neighbours[b].add(a)

    def truncated(a, b):
        return (directions[a] * 2 + directions[b]).normalized()

    panels = []
    for a, b, c in triangles:
        panels.append(([truncated(a, b), truncated(b, a), truncated(b, c),
                        truncated(c, b), truncated(c, a), truncated(a, c)], 0))
    for index, normal in enumerate(directions):
        around = [truncated(index, neighbour) for neighbour in sorted(neighbours[index])]
        tangent = (around[0] - normal * around[0].dot(normal)).normalized()
        bitangent = normal.cross(tangent)
        around.sort(key=lambda point: math.atan2(point.dot(bitangent), point.dot(tangent)))
        panels.append((around, 1))

    vertices, faces, materials = [], [], []

    def triangle(a, b, c, material):
        if (b - a).cross(c - a).dot(a + b + c) < 0:
            b, c = c, b
        start = len(vertices)
        vertices.extend([tuple(a), tuple(b), tuple(c)])
        faces.append((start, start + 1, start + 2))
        materials.append(material)

    # Curved, inset panels leave real recessed seams over a dark spherical core.
    for corners, material in panels:
        centre = sum(corners, Vector()).normalized()
        rim = []
        for a, b in zip(corners, corners[1:] + corners[:1]):
            for step in range(4):
                edge = (a * (1 - step / 4) + b * (step / 4)).normalized()
                rim.append((edge * 0.975 + centre * 0.025).normalized() * 0.11)
        for a, b in zip(rim, rim[1:] + rim[:1]):
            # Two radial rings keep triangle chords outside the recessed core;
            # a single wide fan intersects it and creates visible black patches.
            inner_a = (centre + a.normalized()).normalized() * 0.11
            inner_b = (centre + b.normalized()).normalized() * 0.11
            triangle(centre * 0.11, inner_a, inner_b, material)
            triangle(inner_a, a, b, material)
            triangle(inner_a, b, inner_b, material)

    # Core fills the seams. Pole triangles are explicit (no degenerate quads).
    rows, columns = 10, 24
    def sphere(row, col):
        phi, theta = math.pi * row / rows, math.tau * col / columns
        return Vector((math.sin(phi) * math.cos(theta), math.sin(phi) * math.sin(theta),
                       math.cos(phi))) * 0.1093
    for row in range(rows):
        for col in range(columns):
            a, b = sphere(row, col), sphere(row, col + 1)
            c, d = sphere(row + 1, col + 1), sphere(row + 1, col)
            if row > 0:
                triangle(a, b, c, 1)
            if row < rows - 1:
                triangle(a, c, d, 1)

    mesh = bpy.data.meshes.new("Original32PanelBallMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    ball = bpy.data.objects.new("ReplayXI_StrategyBall", mesh)
    scene.collection.objects.link(ball)
    for name, colour, roughness in [
        ("WarmWhiteLeather", (0.92, 0.93, 0.91, 1), 0.63),
        ("GraphitePanelsAndSeams", (0.009, 0.015, 0.021, 1), 0.76),
    ]:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = colour
        bsdf.inputs["Roughness"].default_value = roughness
        mesh.materials.append(material)
    for polygon, material_index in zip(mesh.polygons, materials):
        polygon.material_index = material_index
        polygon.use_smooth = True
    # Split vertices are intentional; exact radial normals preserve the sphere.
    mesh.normals_split_custom_set_from_vertices([Vector(vertex).normalized() for vertex in vertices])
    ball["provenance"] = "Original procedural Blender geometry; no third-party assets"
    ball["panelCount"] = 32
    ball["nominalDiameterMetres"] = 0.22
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1
    bpy.context.view_layer.objects.active = ball
    ball.select_set(True)

    package = output / "ReplayXIStrategyBall.usdz"
    bpy.ops.wm.usd_export(filepath=str(package), selected_objects_only=True,
                          export_animation=False, export_materials=True,
                          generate_preview_surface=True)
    assert package.is_file() and package.stat().st_size > 0
    assert len(mesh.polygons) <= 3_000
    assert len(mesh.materials) == 2
    assert len(panels) == 32
    assert all(math.isfinite(value) for vertex in vertices for value in vertex)
    assert all(polygon.area > 0 for polygon in mesh.polygons)

    # Studio preview elements are not included in the exported game asset.
    world = bpy.data.worlds.new("BallPreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.14, 0.17, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    scene.world = world
    for name, position, power, size in [
        ("Key", (0.4, -0.5, 0.6), 30, 0.5),
        ("Fill", (-0.5, -0.2, 0.2), 12, 0.4),
        ("Rim", (0.2, 0.4, 0.5), 22, 0.3),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size = power, "DISK", size
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = position
        light.rotation_euler = (-light.location).to_track_quat("-Z", "Y").to_euler()
    camera = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    scene.collection.objects.link(camera)
    camera.location = (0.34, -0.48, 0.27)
    camera.rotation_euler = (-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type, camera.data.ortho_scale = "ORTHO", 0.285
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output / "ReplayXIStrategyBall.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "ReplayXIStrategyBall.blend"))
    bpy.ops.render.render(write_still=True)
    report = {"schemaVersion": 1, "provenance": ball["provenance"],
              "panels": len(panels), "triangles": len(mesh.polygons),
              "materials": len(mesh.materials), "modelEntities": 1,
              "nominalDiameterMetres": 0.22, "packageBytes": package.stat().st_size,
              "sha256": hashlib.sha256(package.read_bytes()).hexdigest()}
    (output / "ReplayXIStrategyBall.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    build(args.output.resolve())
