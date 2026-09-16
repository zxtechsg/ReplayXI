#!/usr/bin/env python3
"""Render actual native far-player mesh QA attachments in isolated Blender.

Geometry and base tints are exported by ReplayFarAthleteVisualAuditTests.
Blender lighting/smoothing are illustrative, not the visionOS renderer.
No app assets or existing .blend files are read or overwritten.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from native_mesh_audit import blender_texture_coordinate, blender_texture_pixels, read_samples
from prepare_football_player import USD_TO_BLENDER, flat_material, link_object

REPOSITORY = Path(__file__).resolve().parents[2]


def native_material(name, source):
    material = flat_material(name, source["tint"])
    texture = source.get("texture")
    if texture is None:
        return material
    image = bpy.data.images.new(name, width=texture["width"], height=texture["height"], alpha=True)
    # Preserve the actual RealityKit gamut; the _srgb format suffix alone does
    # not mean sRGB primaries. Blender's OCIO config performs the colour conversion.
    image.colorspace_settings.name = texture["colourSpace"]
    image.pixels.foreach_set(blender_texture_pixels(texture))
    image.update()
    nodes, links = material.node_tree.nodes, material.node_tree.links
    sample = nodes.new("ShaderNodeTexImage")
    sample.image = image
    sample.interpolation, sample.extension = "Linear", "EXTEND"
    tint = nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1
    tint.inputs[2].default_value = source["tint"]
    links.new(sample.outputs["Color"], tint.inputs[1])
    links.new(tint.outputs["Color"], nodes.get("Principled BSDF").inputs["Base Color"])
    return material


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--meshes", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use an isolated factory-startup background process")
    output = args.output.resolve()
    if not output.is_relative_to((REPOSITORY / ".codex-derived").resolve()) or output.exists():
        raise ValueError("Choose a new directory under .codex-derived")
    samples = read_samples(args.meshes)

    scene = bpy.data.scenes.new("ReplayXI_Native_Mesh_QA")
    bpy.context.window.scene = scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 640, 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.world = bpy.data.worlds.new("Native_Mesh_QA_World")
    scene.world.color = (0.16, 0.16, 0.16)
    stage = bpy.data.collections.new("Native_Mesh_QA_Stage")
    scene.collection.children.link(stage)
    camera = link_object(stage, "Native_Mesh_Camera", bpy.data.cameras.new("Native_Mesh_Camera"))
    camera.location = (2.4, -4.6, 1.8)
    camera.rotation_euler = (Vector((0, 0, 0.92)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.30
    scene.camera = camera
    for name, location, energy, size in [
        ("Key", (-3, -4, 5), 450, 4), ("Fill", (3, -1, 3), 220, 3), ("Rim", (1, 3, 4), 420, 3)
    ]:
        light = link_object(stage, name, bpy.data.lights.new(name, "AREA"))
        light.location = location
        light.rotation_euler = (Vector((0, 0, 1)) - light.location).to_track_quat("-Z", "Y").to_euler()
        light.data.energy, light.data.size, light.data.shape = energy, size, "DISK"
    floor = bpy.data.meshes.new("Native_Mesh_Floor")
    floor.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    floor.materials.append(flat_material("Native_Mesh_Grass", (0.035, 0.11, 0.065, 1)))
    link_object(stage, "Native_Mesh_Floor", floor)

    output.mkdir(parents=True)
    report = []
    for sample in samples:
        collection = bpy.data.collections.new(sample["name"])
        scene.collection.children.link(collection)
        for index, source in enumerate(sample["meshes"]):
            mesh = bpy.data.meshes.new(f"{sample['name']}-{index}")
            points = [USD_TO_BLENDER @ Vector(point) for point in source["positions"]]
            triangles = [source["indices"][i:i + 3] for i in range(0, len(source["indices"]), 3)]
            mesh.from_pydata(points, [], triangles)
            if source.get("uvs") is not None:
                layer = mesh.uv_layers.new(name="NativeUV")
                for polygon in mesh.polygons:
                    for loop_index in polygon.loop_indices:
                        uv = source["uvs"][mesh.loops[loop_index].vertex_index]
                        layer.data[loop_index].uv = blender_texture_coordinate(uv)
            mesh.materials.append(native_material(f"{sample['name']}-tint-{index}", source))
            for polygon in mesh.polygons:
                polygon.use_smooth = True
            link_object(collection, f"Native_Mesh_{index}", mesh)
        scene.render.filepath = str(output / f"{sample['name']}.png")
        bpy.ops.render.render(write_still=True)
        collection.hide_render = True
        report.append({
            "name": sample["name"], "minimumY": sample["minimumY"],
            "vertices": sum(len(mesh["positions"]) for mesh in sample["meshes"]),
            "triangles": sum(len(mesh["indices"]) // 3 for mesh in sample["meshes"]),
            "texturedMeshes": sum(mesh.get("texture") is not None for mesh in sample["meshes"]),
            "image": scene.render.filepath,
        })
    (output / "report.json").write_text(json.dumps({
        "source": "actual native player-local static meshes and bounded material texture readback",
        "limit": "Illustrative Blender shading; not final app lighting or headset QA",
        "samples": report,
    }, indent=2) + "\n")
    print("REPLAYXI_NATIVE_MESH_QA " + json.dumps(report))


if __name__ == "__main__":
    main()
