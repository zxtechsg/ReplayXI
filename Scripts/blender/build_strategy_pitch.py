#!/usr/bin/env python3
"""Original 105 x 68 m pitch, painted markings and netted goals.

Run only in isolated background Blender. Two meshes / four materials; no
downloaded assets. Dimensions reference IFAB Law 1. Output must be a new folder.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector


class Mesh:
    def __init__(self):
        self.vertices, self.faces, self.materials, self.uvs = [], [], [], []

    def face(self, points, material=0, uvs=None):
        base = len(self.vertices)
        self.vertices.extend(tuple(point) for point in points)
        self.faces.append(tuple(range(base, base + len(points))))
        self.materials.append(material)
        self.uvs.append(uvs or [(0, 0)] * len(points))

    def line(self, a, b, width=0.12):
        a, b = Vector((*a, 0.012)), Vector((*b, 0.012))
        direction = (b - a).normalized()
        side = Vector((-direction.y, direction.x, 0)) * width / 2
        self.face([a - side, b - side, b + side, a + side])

    def arc(self, centre, radius, start, end, segments=64):
        for step in range(segments):
            angles = [start + (end - start) * n / segments for n in (step, step + 1)]
            self.line(*[(centre[0] + radius * math.cos(a),
                         centre[1] + radius * math.sin(a)) for a in angles])

    def disc(self, centre, radius=0.11):
        c = Vector((*centre, 0.014))
        for index in range(24):
            angles = [math.tau * n / 24 for n in (index, index + 1)]
            self.face([c, *[c + Vector((radius * math.cos(a), radius * math.sin(a), 0))
                            for a in angles]])

    def tube(self, start, end, radius, material=0, sides=12):
        a, b = Vector(start), Vector(end)
        along = (b - a).normalized()
        reference = Vector((0, 0, 1)) if abs(along.z) < 0.9 else Vector((1, 0, 0))
        u = along.cross(reference).normalized() * radius
        v = along.cross(u).normalized() * radius
        offsets = [u * math.cos(math.tau * n / sides) + v * math.sin(math.tau * n / sides)
                   for n in range(sides)]
        for index in range(sides):
            p, q = offsets[index], offsets[(index + 1) % sides]
            self.face([a + p, a + q, b + q, b + p], material)
        if sides > 4:  # Only frame tubes need end caps; net joins are subpixel.
            self.face([a + offset for offset in reversed(offsets)], material)
            self.face([b + offset for offset in offsets], material)

    def cord(self, start, end, sag=(0, 0, 0)):
        midpoint = (Vector(start) + Vector(end)) / 2 + Vector(sag)
        self.tube(start, midpoint, 0.0045, material=1, sides=4)
        self.tube(midpoint, end, 0.0045, material=1, sides=4)

    def object(self, name, scene, materials):
        data = bpy.data.meshes.new(name + "Mesh")
        data.from_pydata(self.vertices, [], self.faces)
        data.materials.clear()
        for material in materials:
            data.materials.append(material)
        uv_layer = data.uv_layers.new(name="UVMap")
        for polygon, material, uvs in zip(data.polygons, self.materials, self.uvs):
            polygon.material_index = material
            for loop, uv in zip(polygon.loop_indices, uvs):
                uv_layer.data[loop].uv = uv
        data.update()
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        return obj


def material(name, colour, roughness=0.8):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return result


def turf_material(name, colour, image_values, output):
    result = material(name, colour, 0.95)
    image = bpy.data.images.new(name + "Grain", width=512, height=512, alpha=False)
    rgba = np.ones((512, 512, 4), dtype=np.float32)
    rgba[:, :, :3] = np.clip(image_values[:, :, None] * np.array(colour), 0, 1)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(output / (name + ".png"))
    image.file_format = "PNG"
    image.save()
    node = result.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    node.extension = "REPEAT"
    result.node_tree.links.new(node.outputs["Color"],
                              result.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    return result


def add_goal(mesh, sign):
    goal_y, back_y = sign * 52.5, sign * 54.7
    # Cylinder centres preserve 7.32 m inside width / 2.44 m underside height.
    for x in (-3.72, 3.72):
        mesh.tube((x, goal_y, 0.06), (x, goal_y, 2.50), 0.06, sides=16)
        mesh.tube((x, back_y, 0.06), (x, back_y, 2.34), 0.032)
        mesh.tube((x, goal_y, 0.04), (x, back_y, 0.04), 0.032)
        mesh.tube((x, goal_y, 2.50), (x, back_y, 2.34), 0.032)
    mesh.tube((-3.72, goal_y, 2.50), (3.72, goal_y, 2.50), 0.06, sides=16)
    mesh.tube((-3.72, back_y, 2.34), (3.72, back_y, 2.34), 0.032)
    mesh.tube((-3.72, back_y, 0.04), (3.72, back_y, 0.04), 0.032)

    width_steps, height_steps, depth_steps = 42, 14, 13
    for index in range(width_steps + 1):
        x = -3.68 + 7.36 * index / width_steps
        mesh.cord((x, back_y, 0.06), (x, back_y, 2.34), (0, sign * 0.05, 0))
        mesh.cord((x, goal_y, 2.46), (x, back_y, 2.34), (0, 0, -0.025))
    for index in range(height_steps + 1):
        z = 0.06 + 2.28 * index / height_steps
        mesh.cord((-3.68, back_y, z), (3.68, back_y, z), (0, sign * 0.05, -0.012))
        for x in (-3.68, 3.68):
            mesh.cord((x, goal_y, z), (x, back_y, z), (math.copysign(0.025, x), 0, 0))
    for index in range(depth_steps + 1):
        t = index / depth_steps
        y, z = goal_y + (back_y - goal_y) * t, 2.46 - 0.12 * t
        mesh.cord((-3.68, y, z), (3.68, y, z), (0, 0, -0.025))
        for x in (-3.68, 3.68):
            mesh.cord((x, y, 0.06), (x, y, z), (math.copysign(0.025, x), 0, 0))


def build(output):
    if not bpy.app.background:
        raise RuntimeError("Use background Blender; never replace a live user scene")
    if output.exists():
        raise RuntimeError("Output exists; choose a new directory")
    output.mkdir(parents=True)
    scene = bpy.data.scenes.new("ReplayXI Original Strategy Pitch")
    bpy.context.window.scene = scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1

    rng = np.random.default_rng(39017)
    grain = rng.uniform(0.76, 1.16, (512, 512)).astype(np.float32)
    # Directional grain suggests trimmed blades; no heavy geometry/alpha cards.
    grain = (grain + np.roll(grain, 1, axis=0) + np.roll(grain, 2, axis=0)) / 3
    grass = [turf_material("TurfLight", (0.18, 0.34, 0.13), grain, output),
             turf_material("TurfDark", (0.145, 0.285, 0.10), grain, output)]
    white = material("WarmWhitePaintAndFrame", (0.93, 0.94, 0.88), 0.68)
    net = material("WovenGoalNet", (0.60, 0.65, 0.60), 0.92)

    turf = Mesh()
    for stripe in range(20):
        low, high = -52.5 + stripe * 5.25, -52.5 + (stripe + 1) * 5.25
        points = [(-34, low, 0), (34, low, 0), (34, high, 0), (-34, high, 0)]
        turf.face(points, stripe % 2, [(x / 2, y / 2) for x, y, _ in points])
    # A narrow runoff apron supports the goals outside the actual touch/goal
    # lines; annotation coordinates remain bounded to the 68 x 105 m field.
    for x0, x1, y0, y1 in [(-36, -34, -55.5, 55.5), (34, 36, -55.5, 55.5),
                           (-34, 34, -55.5, -52.5), (-34, 34, 52.5, 55.5)]:
        points = [(x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0)]
        turf.face(points, 1, [(x / 2, y / 2) for x, y, _ in points])
    turf_object = turf.object("field-surface", scene, grass)
    paint = Mesh()
    for a, b in [((-34, -52.5), (34, -52.5)), ((34, -52.5), (34, 52.5)),
                 ((34, 52.5), (-34, 52.5)), ((-34, 52.5), (-34, -52.5)),
                 ((-34, 0), (34, 0))]:
        paint.line(a, b)
    paint.arc((0, 0), 9.15, 0, math.tau, 96)
    paint.disc((0, 0))
    for sign in (-1, 1):
        y = sign * 52.5
        for half_width, depth in ((20.16, 16.5), (9.16, 5.5)):
            inside = y - sign * depth
            paint.line((-half_width, y), (-half_width, inside))
            paint.line((half_width, y), (half_width, inside))
            paint.line((-half_width, inside), (half_width, inside))
        paint.disc((0, y - sign * 11))
        angle = math.acos(5.5 / 9.15)
        facing = -sign * math.pi / 2
        paint.arc((0, y - sign * 11), 9.15, facing - angle, facing + angle, 40)
        for x in (-34, 34):
            # Quarter circle pointing into this corner of the field.
            start = (0 if x < 0 else math.pi / 2) if sign < 0 else (
                3 * math.pi / 2 if x < 0 else math.pi)
            paint.arc((x, y), 1, start, start + math.pi / 2, 16)
        add_goal(paint, sign)
    paint_object = paint.object("pitch-markings-and-goals", scene, [white, net])
    objects = [turf_object, paint_object]
    for obj in objects:
        obj.select_set(True)
        obj["provenance"] = "Original Replay XI geometry; no third-party assets"
    bpy.context.view_layer.objects.active = turf_object
    package = output / "ReplayXIStrategyPitch.usdz"
    bpy.ops.wm.usd_export(filepath=str(package), selected_objects_only=True,
                          export_animation=False, export_materials=True,
                          generate_preview_surface=True)
    triangles = sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in objects)
    assert triangles < 16000, triangles
    assert package.stat().st_size < 4_000_000
    report = {"schemaVersion": 1, "provenance": "Original Blender geometry and procedural turf",
              "pitchDimensionsMetres": [68, 105], "insideGoalWidthMetres": 7.32,
              "undersideCrossbarHeightMetres": 2.44, "meshCount": 2,
              "materialCount": 4, "triangleCount": triangles,
              "textureCount": 2, "textureResolution": [512, 512],
              "textureRepeatMetres": 2, "assetBytes": package.stat().st_size,
              "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
              "dimensionsSource": "https://www.theifab.com/laws/latest/the-field-of-play/"}
    (output / "ReplayXIStrategyPitch.json").write_text(json.dumps(report, indent=2) + "\n")

    scene.world = bpy.data.worlds.new("Soft Stadium Daylight")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.15, 0.19, 0.24, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sun_data = bpy.data.lights.new("Stadium Sun", "SUN")
    sun_data.energy = 2
    sun_data.angle = 0.35
    sun = bpy.data.objects.new("Stadium Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (0.45, -0.5, -0.4)
    camera_data = bpy.data.cameras.new("Review Camera")
    camera = bpy.data.objects.new("Review Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1440
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    for label, location, target, lens in [
        ("overview", (95, -125, 120), (0, 0, 0), 48),
        ("goal", (12, -36, 4.5), (0, -52.5, 1.1), 42),
    ]:
        camera.location = location
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.lens = lens
        scene.render.filepath = str(output / (label + ".png"))
        bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "ReplayXIStrategyPitch.blend"))
    print(json.dumps(report))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    build(arguments.output.resolve())
