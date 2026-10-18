#!/usr/bin/env python3
"""Original local seed; fresh background Blender only. No app resources touched."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--skip-previews", action="store_true", help="Export and audit only; no duplicate renders")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    repo = Path(__file__).resolve().parents[2]
    output = args.output_dir.resolve()
    allowed = repo / ".replayxi-world-staging" / "Chisel179"
    if not bpy.app.background or "--factory-startup" not in sys.argv or bpy.data.filepath:
        raise RuntimeError("Use fresh --factory-startup --background Blender")
    if output.exists() or not output.is_relative_to(allowed):
        raise ValueError("Output must be a new directory inside Chisel179 staging")
    output.mkdir(parents=True)
    scene = bpy.data.scenes.new("Original Chisel Stadium179")
    bpy.context.window.scene = scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1

    def material(name, colour, roughness=0.75):
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*colour, 1)
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (*colour, 1)
        shader.inputs["Roughness"].default_value = roughness
        mat.use_backface_culling = False
        return mat

    mats = [material("Navy seating and fascia", (0.035, 0.075, 0.14)),
            material("Warm ivory seating and roof", (0.76, 0.78, 0.73)),
            material("Cool concrete terraces", (0.24, 0.29, 0.32)),
            material("Dark steel structure", (0.07, 0.105, 0.13), 0.6)]
    vertices, faces, slots = [], [], []

    def quad(points, slot):
        start = len(vertices)
        vertices.extend(tuple(p) for p in points)
        faces.extend(((start, start + 1, start + 2), (start, start + 2, start + 3)))
        slots.extend((slot, slot))

    def box(centre, size, slot, tangent=(1, 0, 0), outward=(0, 1, 0)):
        c, a, b = Vector(centre), Vector(tangent) * size[0] / 2, Vector(outward) * size[1] / 2
        z = Vector((0, 0, size[2] / 2))
        p = [c - a - b - z, c + a - b - z, c + a + b - z, c - a + b - z,
             c - a - b + z, c + a - b + z, c + a + b + z, c - a + b + z]
        for ids in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                    (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            quad([p[i] for i in ids], slot)

    def beam(a, b, width, slot=3):
        direction = Vector(b) - Vector(a)
        side = direction.cross(Vector((0, 0, 1)))
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side.normalize()
        other = direction.normalized().cross(side).normalized()
        p = [Vector(a) + sx * side * width / 2 + sy * other * width / 2
             for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        q = [v + direction for v in p]
        for ids in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
                    (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            quad([(p + q)[i] for i in reversed(ids)], slot)

    # Blender XY is pitch ground, Z is up; exported glTF becomes Y-up.
    # Four separate stands retain the characteristic open-corner English bowl.
    stands = [("West", (-1, 0, 0), (0, 1, 0), 36, 112, 98),
              ("East", (1, 0, 0), (0, -1, 0), 36, 112, 98),
              ("North", (0, 1, 0), (1, 0, 0), 56, 72, 64),
              ("South", (0, -1, 0), (-1, 0, 0), 56, 72, 64)]
    seat_count = 0
    for name, out, tan, inner, length, columns in stands:
        out, tan = Vector(out), Vector(tan)

        def point(u, d, h):
            return tan * u + out * (inner + d) + Vector((0, 0, h))

        # Twenty-four rising terraces, front perimeter apron, rear concourse.
        rows, tread, rise = 24, 0.84, 0.66
        box(point(0, 1.0, -0.08), (length, 1.6, 0.16), 2, tan, out)
        for row in range(rows):
            d, h = 1.8 + row * tread, (row + 1) * rise
            box(point(0, d + tread / 2, h - 0.16), (length, tread, 0.32), 2, tan, out)
            # Low-poly individual seat backs. Concrete tread supplies the pan.
            for col in range(columns):
                u = (col + 0.5) * length / columns - length / 2
                # Five broad radial aisles; solid bays remain strongly legible.
                if any(abs(u - aisle * length / 6) < 0.85 for aisle in (-2, -1, 0, 1, 2)):
                    continue
                width = min(0.69, length / columns * 0.72)
                seat_mat = 1 if ((col // 12 + row // 8) % 4 == 1) else 0
                quad([point(u - width / 2, d + 0.60, h + 0.05),
                      point(u + width / 2, d + 0.60, h + 0.05),
                      point(u + width / 2, d + 0.73, h + 0.53),
                      point(u - width / 2, d + 0.73, h + 0.53)], seat_mat)
                seat_count += 1
        rear = 1.8 + rows * tread
        box(point(0, rear + 1.6, rows * rise - 0.18), (length, 3.2, 0.36), 2, tan, out)
        box(point(0, rear + 3.0, 8.0), (length, 0.32, 16), 0, tan, out)
        # Long ivory upper fascia and a strong navy leading edge.
        roof_h = 22.6 if name in {"West", "East"} else 21.2
        roof_front, roof_back = 1.2, rear + 3.8
        roof_points = [point(-length / 2 - 0.8, roof_front, roof_h),
                       point(length / 2 + 0.8, roof_front, roof_h),
                       point(length / 2 + 0.8, roof_back, roof_h - 1.1),
                       point(-length / 2 - 0.8, roof_back, roof_h - 1.1)]
        quad(roof_points, 1)
        box(point(0, roof_front + 0.18, roof_h - 0.32), (length + 1.6, 0.36, 0.64), 0, tan, out)
        box(point(0, roof_back, roof_h - 1.3), (length + 1.6, 0.25, 0.65), 1, tan, out)
        bay_count = round(length / 9)
        for index in range(bay_count + 1):
            u = -length / 2 + index * length / bay_count
            beam(point(u, rear + 2.9, 0), point(u, rear + 2.9, roof_h - 1.1), 0.34)
            beam(point(u, roof_front, roof_h - 0.2), point(u, roof_back, roof_h - 1.3), 0.22)
            beam(point(u, roof_front + 0.3, roof_h - 0.3), point(u, rear + 2.9, roof_h - 4.0), 0.18)
            # Three diagonals make each roof cantilever read as a real truss.
            for segment in range(3):
                da = roof_front + (roof_back - roof_front) * segment / 3
                db = roof_front + (roof_back - roof_front) * (segment + 1) / 3
                beam(point(u, da, roof_h - 0.35 - segment * 0.3),
                     point(u, db, roof_h - 2.0 - segment * 0.5), 0.09)
            # Open lower arcade: gaps reveal the darker rear wall.
            box(point(u, rear + 3.25, 4.5), (0.42, 0.3, 9), 1, tan, out)
        # Restrained front safety rail, kept fully outside the clear opening.
        beam(point(-length / 2, 1.2, 1.05), point(length / 2, 1.2, 1.05), 0.07)
        for index in range(round(length / 6) + 1):
            u = -length / 2 + index * length / round(length / 6)
            beam(point(u, 1.2, 0), point(u, 1.2, 1.05), 0.055)

    # Four slim service towers frame the open corners without closing the bowl.
    for x in (-59, 59):
        for y in (-79, 79):
            box((x, y, 8.3), (4.0, 4.0, 16.6), 0)
            box((x, y, 17.0), (4.8, 4.8, 0.8), 1)

    mesh = bpy.data.meshes.new("Original stadium179 mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.clear()
    for mat in mats:
        mesh.materials.append(mat)
    for poly, slot in zip(mesh.polygons, slots):
        poly.material_index = slot
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for loop_index, value in zip(poly.loop_indices, ((0, 0), (1, 0), (1, 1))):
            uv.data[loop_index].uv = value
    mesh.update()
    stadium = bpy.data.objects.new("Original generic English football stadium", mesh)
    scene.collection.objects.link(stadium)
    stadium["provenance"] = "Original procedural architecture authored locally for Chisel179; no reused stadium assets"
    stadium["clearOpeningMetres"] = "72 x 112; X width, native Z length; pitch Y=0"

    def clear_triangle(points):
        planar = [(p[0], p[1]) for p in points]
        axes = [(1, 0), (0, 1)]
        axes += [(-(planar[(i + 1) % 3][1] - planar[i][1]),
                   planar[(i + 1) % 3][0] - planar[i][0]) for i in range(3)]
        for a, b in axes:
            size = math.hypot(a, b)
            if size < 1e-9:
                continue
            a, b = a / size, b / size
            radius = abs(a) * 36 + abs(b) * 56
            projections = [p[0] * a + p[1] * b for p in planar]
            if min(projections) >= radius - 1e-5 or max(projections) <= -radius + 1e-5:
                return True
        return False

    intrusions = sum(not clear_triangle([vertices[i] for i in face]) for face in faces)
    if intrusions or len(faces) > 25_000:
        raise ValueError(f"Invalid seed: {len(faces)} triangles; {intrusions} pitch intrusions")

    def camera(name, location, target, lens=24):
        data = bpy.data.cameras.new(name)
        data.lens = lens
        data.clip_start, data.clip_end = 0.05, 600
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
        return obj

    cameras = [camera("Pitch North native -Z", (0, 0, 1.7), (0, 70, 5.5)),
               camera("Pitch East native +X", (0, 0, 1.7), (60, 0, 5.5)),
               camera("Pitch South native +Z", (0, 0, 1.7), (0, -70, 5.5)),
               camera("Pitch West native -X", (0, 0, 1.7), (-60, 0, 5.5)),
               camera("Elevated overview", (122, -154, 125), (0, 0, 2), 30)]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [stadium] + cameras:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = stadium
    glb = output / "OriginalStadium179.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True, use_active_scene=True,
                              export_yup=True, export_apply=True, export_cameras=True,
                              export_materials="EXPORT", export_animations=False,
                              export_extras=True)
    blob = glb.read_bytes()
    json_size, json_kind = struct.unpack_from("<I4s", blob, 12)
    document = json.loads(blob[20:20 + json_size])
    if (json_kind != b"JSON" or len(document.get("meshes", [])) != 1
            or len(document.get("materials", [])) != 4 or len(document.get("cameras", [])) != 5
            or len(document.get("meshes", [{}])[0].get("primitives", [])) != 4):
        raise ValueError("GLB export leaked another scene or lost expected geometry/cameras")
    native_vertices = [(p[0], p[2], -p[1]) for p in vertices]
    report = {"candidateOnly": True, "source": "Original local procedural architecture; no existing asset reused",
              "style": "Generic modern English football stadium; navy and ivory seating; no brands or crowds",
              "glb": str(glb), "sha256": hashlib.sha256(glb.read_bytes()).hexdigest(),
              "bytes": glb.stat().st_size, "triangles": len(faces), "meshCount": 1,
              "materialCount": len(mats), "individualSeatBacks": seat_count, "cameraCount": len(cameras),
              "upAxis": "Y", "metresPerUnit": 1, "clearOpeningMetres": [72, 112],
              "pitchFootprintMetres": [68, 105], "pitchIntrudingTriangles": intrusions,
              "nativeBounds": {"min": [min(p[i] for p in native_vertices) for i in range(3)],
                               "max": [max(p[i] for p in native_vertices) for i in range(3)]},
              "pitchHelperExported": False, "liveBlenderModified": False,
              "generationSpend": 0, "notes": "Seed geometry only; no texture/AO bake or native admission yet"}
    (output / "stats.json").write_text(json.dumps(report, indent=2) + "\n")
    print("SEED_GLB_READY " + json.dumps(report), flush=True)
    if args.skip_previews:
        return

    # Preview-only pitch and white lines, deliberately created after GLB export.
    grass = material("PREVIEW ONLY pitch", (0.045, 0.22, 0.095))
    white = material("PREVIEW ONLY markings", (0.88, 0.9, 0.83))
    bpy.ops.mesh.primitive_plane_add(size=2, location=(0, 0, -0.02))
    pitch = bpy.context.object
    pitch.name = "PREVIEW ONLY pitch helper not in GLB"
    pitch.scale = (34, 52.5, 1)
    pitch.data.materials.append(grass)

    def line(points, name, cyclic=False):
        curve = bpy.data.curves.new(name, "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth, curve.bevel_resolution = 0.055, 0
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for dst, p in zip(spline.points, points):
            dst.co = (*p, 1)
        spline.use_cyclic_u = cyclic
        obj = bpy.data.objects.new("PREVIEW ONLY " + name, curve)
        scene.collection.objects.link(obj)
        curve.materials.append(white)

    line([(-34, -52.5, 0.015), (34, -52.5, 0.015), (34, 52.5, 0.015), (-34, 52.5, 0.015)], "touchlines", True)
    line([(-34, 0, 0.015), (34, 0, 0.015)], "halfway")
    line([(9.15 * math.cos(a * math.tau / 64), 9.15 * math.sin(a * math.tau / 64), 0.015)
          for a in range(64)], "centre circle", True)
    for sign in (-1, 1):
        line([(-20.16, sign * 52.5, 0.015), (-20.16, sign * 36, 0.015),
              (20.16, sign * 36, 0.015), (20.16, sign * 52.5, 0.015)], "penalty area")
    world = bpy.data.worlds.new("Overcast stadium daylight")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.52, 0.61, 0.72, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.75
    scene.world = world
    data = bpy.data.lights.new("Preview daylight", "SUN")
    data.energy, data.angle = 2.0, math.radians(15)
    sun = bpy.data.objects.new("Preview daylight", data)
    sun.rotation_euler = (math.radians(28), math.radians(-18), math.radians(-30))
    scene.collection.objects.link(sun)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 12
    scene.cycles.use_denoising = True
    scene.render.threads_mode, scene.render.threads = "FIXED", 8
    scene.render.resolution_x, scene.render.resolution_y = 1440, 960
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.camera = cameras[-1]
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "OriginalStadium179.blend"))
    for name, selected in (("overview", cameras[-1]), ("pitch-level", cameras[0])):
        scene.camera = selected
        scene.render.filepath = str(output / (name + ".png"))
        bpy.ops.render.render(write_still=True)
    print("SEED_PREVIEWS_READY " + str(output), flush=True)


if __name__ == "__main__":
    main()
