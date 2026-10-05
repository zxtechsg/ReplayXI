#!/usr/bin/env python3
"""Render front and side stills of the baked Player A kit candidates."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def point_at(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--near-glb", type=Path, required=True)
    parser.add_argument("--kits", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if not bpy.app.background or not args.near_glb.is_file():
        raise ValueError("requires background Blender and near GLB")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(args.near_glb))
    meshes = [obj for obj in bpy.context.scene.objects
              if obj.type == "MESH" and len(obj.data.materials) == 1]
    if len(meshes) != 1:
        raise ValueError("expected one textured mesh")
    mesh = meshes[0]
    material = mesh.data.materials[0]
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    source_link = next(iter(bsdf.inputs["Base Color"].links))
    source_node = source_link.from_node
    if source_node.type != "TEX_IMAGE":
        raise ValueError("expected image-driven basecolor")
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (.15, .15, .15)
    camera_data = bpy.data.cameras.new("QA Camera")
    camera = bpy.data.objects.new("QA Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.20
    light_data = bpy.data.lights.new("Softbox", "AREA")
    light = bpy.data.objects.new("Softbox", light_data)
    scene.collection.objects.link(light)
    light.location = (0, -1.5, 1.8)
    light_data.energy = 500
    light_data.shape = "DISK"
    light_data.size = 2.2
    target = args.kits / "preview"
    target.mkdir(exist_ok=True)
    original_image = source_node.image
    for view, location in (("front", (0, -2, .5)), ("side", (2, 0, .5))):
        camera.location = location
        point_at(camera, (0, 0, .49))
        scene.render.filepath = str(target / f"Original-{view}.png")
        bpy.ops.render.render(write_still=True)
    for name in ("Home", "Away", "Keeper"):
        image = args.kits / f"ReplayXITripoPlayerA{name}.png"
        if not image.is_file():
            raise ValueError(f"missing kit: {image}")
        source_node.image = bpy.data.images.load(str(image), check_existing=False)
        for view, location in (("front", (0, -2, .5)), ("side", (2, 0, .5))):
            camera.location = location
            point_at(camera, (0, 0, .49))
            scene.render.filepath = str(target / f"{name}-{view}.png")
            bpy.ops.render.render(write_still=True)
    source_node.image = original_image


if __name__ == "__main__":
    main()
