#!/usr/bin/env python3
"""Bake compact home/away atlases for the pinned Tripo source, offline only.

Blender --factory-startup --background --python this_file -- --output-dir NEW_DIR
No paid generation, source edits, runtime replacement or skeleton changes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "Assets/ReplayXI/TripoFootballer/ReplayXI_Footballer_P2_Source.glb"
SOURCE_HASH = "e4fbdbcf98c631d283733ff9f339dd2bf01877bf8ab81756b6fe274a25c10eb5"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise RuntimeError("Use isolated factory-startup background Blender")
    if output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Output must be a NEW derived directory")
    if digest(SOURCE) != SOURCE_HASH:
        raise ValueError("Source hash changed")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    meshes = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
    if len(meshes) != 1 or len(meshes[0].data.materials) != 1:
        raise ValueError("Expected the pinned single-mesh single-atlas source")
    obj = meshes[0]
    mat = obj.data.materials[0]
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    source = next(node for node in nodes if node.type == "TEX_IMAGE" and node.image)
    surface = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    surface.inputs["Roughness"].default_value = .78
    # White clothing only, gated by source-space height so eyes/hair/skin
    # cannot be recoloured merely because they contain bright texels.
    attr = obj.data.attributes.new("ReplayXI_KitRegion", "FLOAT", "POINT")
    z = [vertex.co.z for vertex in obj.data.vertices]
    low, height = min(z), max(z) - min(z)
    for vertex in obj.data.vertices:
        h = (vertex.co.z - low) / height
        attr.data[vertex.index].value = float(.48 <= h <= .855 or .055 <= h <= .34)
    region = nodes.new("ShaderNodeAttribute")
    region.attribute_name = attr.name
    separate = nodes.new("ShaderNodeSeparateColor")
    links.new(source.outputs["Color"], separate.inputs["Color"])
    ratio = nodes.new("ShaderNodeMath")
    ratio.operation = "DIVIDE"
    links.new(separate.outputs["Blue"], ratio.inputs[0])
    links.new(separate.outputs["Red"], ratio.inputs[1])
    whiteness = nodes.new("ShaderNodeMapRange")
    whiteness.clamp = True
    whiteness.inputs["From Min"].default_value = .85
    whiteness.inputs["From Max"].default_value = .94
    links.new(ratio.outputs[0], whiteness.inputs["Value"])
    brightness = nodes.new("ShaderNodeMapRange")
    brightness.clamp = True
    brightness.inputs["From Min"].default_value = .14
    brightness.inputs["From Max"].default_value = .25
    links.new(separate.outputs["Red"], brightness.inputs["Value"])
    clothing = nodes.new("ShaderNodeMath")
    clothing.operation = "MULTIPLY"
    links.new(whiteness.outputs[0], clothing.inputs[0])
    links.new(brightness.outputs[0], clothing.inputs[1])
    factor = nodes.new("ShaderNodeMath")
    factor.operation = "MULTIPLY"
    links.new(clothing.outputs[0], factor.inputs[0])
    links.new(region.outputs["Fac"], factor.inputs[1])
    tint = nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    links.new(factor.outputs[0], tint.inputs[0])
    links.new(source.outputs["Color"], tint.inputs[1])
    links.new(tint.outputs[0], surface.inputs["Base Color"])
    out_node = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
    emission = nodes.new("ShaderNodeEmission")
    links.new(tint.outputs[0], emission.inputs["Color"])
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.margin = 8
    output.mkdir(parents=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    reports = []
    for kit, colour in (("home", (1, 1, 1, 1)), ("away", (.72, .035, .022, 1)),
                        ("keeper", (.95, .48, .018, 1))):
        tint.inputs[2].default_value = colour
        atlas = bpy.data.images.new("ReplayXI_Tripo_" + kit, width=2048, height=2048, alpha=False)
        atlas.colorspace_settings.name = "sRGB"
        bake_node = nodes.new("ShaderNodeTexImage")
        bake_node.image = atlas
        nodes.active = bake_node
        links.new(emission.outputs[0], out_node.inputs["Surface"])
        bpy.ops.object.bake(type="EMIT")
        target = output / f"{kit}_colour_2048.png"
        atlas.filepath_raw = str(target)
        atlas.file_format = "PNG"
        atlas.save()
        nodes.remove(bake_node)
        reports.append({"kit": kit, "texture": target.name, "sha256": digest(target),
                        "size": [2048, 2048]})
    links.new(surface.outputs[0], out_node.inputs["Surface"])
    # Save the inspectable working shader, not a claimed production material.
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "TripoKitCandidate.blend"), compress=True)
    if digest(SOURCE) != SOURCE_HASH:
        raise ValueError("Source changed during baking")
    report = {"candidateOnly": True, "sourceSHA256": SOURCE_HASH,
              "textures": reports, "sameGeometryForBothTeams": True,
              "limits": "Check collar, sleeve and sock boundaries before runtime use. No licence expansion is implied."}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_KITS " + json.dumps(report))


if __name__ == "__main__":
    main()
