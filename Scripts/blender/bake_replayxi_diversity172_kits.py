#!/usr/bin/env python3
"""Bake Player A kit atlases from its rigged mesh in isolated background Blender.

The source image supplies face, skin, hair, boots, and cloth detail. Geometric
height bands select clothing; source chroma protects exposed skin at sleeves,
short hems, and sock tops. Output remains a candidate until visual QA.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "Assets/ReplayXI/PlayerDiversity171/Source/player-a-hd-source.glb"
SOURCE_SHA = "2b25690666877f3e090d5ce4e5d8e30702d6d02f497e5511de4ba9d3df1dcfc3"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scalar(nodes, links, operation, a, b):
    node = nodes.new("ShaderNodeMath")
    node.operation = operation
    for index, value in enumerate((a, b)):
        if hasattr(value, "is_output"):
            links.new(value, node.inputs[index])
        else:
            node.inputs[index].default_value = value
    return node.outputs[0]


def band(nodes, links, value, start, full_start, full_end, end):
    rise = nodes.new("ShaderNodeMapRange")
    rise.clamp = True
    rise.inputs["From Min"].default_value = start
    rise.inputs["From Max"].default_value = full_start
    links.new(value, rise.inputs["Value"])
    fall = nodes.new("ShaderNodeMapRange")
    fall.clamp = True
    fall.inputs["From Min"].default_value = full_end
    fall.inputs["From Max"].default_value = end
    fall.inputs["To Min"].default_value = 1
    fall.inputs["To Max"].default_value = 0
    links.new(value, fall.inputs["Value"])
    return scalar(nodes, links, "MULTIPLY", rise.outputs[0], fall.outputs[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--near-glb", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = args.output.resolve()
    if not bpy.app.background or bpy.data.filepath:
        raise ValueError("requires isolated factory-startup background Blender")
    if output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("output must be a new .codex-derived directory")
    if sha(SOURCE) != SOURCE_SHA or not args.near_glb.is_file():
        raise ValueError("pinned source or near rig missing/changed")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(args.near_glb))
    meshes = [obj for obj in bpy.context.scene.objects
              if obj.type == "MESH" and len(obj.data.materials) == 1]
    if len(meshes) != 1:
        raise ValueError("expected one body mesh and one material")
    obj = meshes[0]
    obj.data.shape_keys and obj.shape_key_clear()
    material = obj.data.materials[0]
    if not material.use_nodes:
        raise ValueError("basecolor texture shader missing")
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    source_links = list(bsdf.inputs["Base Color"].links) if bsdf else []
    if len(source_links) != 1 or source_links[0].from_node.type != "TEX_IMAGE":
        raise ValueError("basecolor must come directly from source atlas")
    image = source_links[0].from_node
    source_color = source_links[0].from_socket
    zs = [vertex.co.z for vertex in obj.data.vertices]
    bottom, height = min(zs), max(zs) - min(zs)
    if not .5 <= height <= 2.5:
        raise ValueError("implausible rest height")
    # In imported Blender space, the character stands along +Z. Soft 1%-2%
    # transitions follow mesh cloth boundaries and avoid hard vertex seams.
    normalized = obj.data.attributes.new("ReplayXI_NormalizedHeight", "FLOAT", "POINT")
    neck_protection = obj.data.attributes.new("ReplayXI_NeckProtection", "FLOAT", "POINT")
    for vertex in obj.data.vertices:
        fraction = (vertex.co.z - bottom) / height
        normalized.data[vertex.index].value = fraction
        neck_protection.data[vertex.index].value = float(
            not (fraction >= .835 and abs(vertex.co.x) < .09))
    h = nodes.new("ShaderNodeAttribute")
    h.attribute_name = normalized.name
    neck = nodes.new("ShaderNodeAttribute")
    neck.attribute_name = neck_protection.name
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(source_color, split.inputs["Color"])
    blue_red = scalar(nodes, links, "DIVIDE", split.outputs["Blue"],
                      scalar(nodes, links, "MAXIMUM", split.outputs["Red"], .025))
    neutral = nodes.new("ShaderNodeMapRange")
    neutral.clamp = True
    neutral.inputs["From Min"].default_value = .86
    neutral.inputs["From Max"].default_value = .95
    links.new(blue_red, neutral.inputs["Value"])
    navy = nodes.new("ShaderNodeMapRange")
    navy.clamp = True
    navy.inputs["From Min"].default_value = .95
    navy.inputs["From Max"].default_value = 1.15
    links.new(blue_red, navy.inputs["Value"])
    shirt = scalar(nodes, links, "MULTIPLY", band(nodes, links, h.outputs["Fac"], .49, .51, .855, .87),
                   neutral.outputs[0])
    shirt = scalar(nodes, links, "MULTIPLY", shirt, neck.outputs["Fac"])
    shorts = scalar(nodes, links, "MULTIPLY", band(nodes, links, h.outputs["Fac"], .345, .365, .51, .53),
                    navy.outputs[0])
    socks = scalar(nodes, links, "MULTIPLY", band(nodes, links, h.outputs["Fac"], .065, .085, .28, .305),
                   neutral.outputs[0])
    # Multiply preserves folds/highlights in original cloth. Skin/hair/boots
    # remain source pixels wherever the geometry/chroma mask is zero.
    tinted = source_color
    mixes = []
    for mask in (shirt, shorts, socks):
        node = nodes.new("ShaderNodeMixRGB")
        node.blend_type = "MULTIPLY"
        node.use_clamp = False
        links.new(mask, node.inputs[0])
        links.new(tinted, node.inputs[1])
        tinted = node.outputs[0]
        mixes.append(node)
    output_node = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
    emission = nodes.new("ShaderNodeEmission")
    links.new(tinted, emission.inputs["Color"])
    links.new(emission.outputs[0], output_node.inputs["Surface"])
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.margin = 8
    scene.render.image_settings.color_mode = "RGB"
    output.mkdir(parents=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    reports = []
    palettes = {
        "Home": ((1.75, 1.75, 1.75, 1), (.4, .7, 1.0, 1), (1.7, 1.7, 1.7, 1)),
        "Away": ((1.5, .05, .035, 1), (.45, .25, .28, 1), (1.5, .05, .035, 1)),
        "Keeper": ((1.85, 1.2, .18, 1), (.45, .45, .35, 1), (1.85, 1.2, .18, 1)),
    }
    for kit, colours in palettes.items():
        for node, colour in zip(mixes, colours):
            node.inputs[2].default_value = colour
        atlas = bpy.data.images.new("ReplayXITripoPlayerA" + kit, width=1024, height=1024, alpha=False)
        # The imported source atlas is sRGB; this choice preserves untouched
        # face/skin/hair texels under the same renderer and lighting.
        atlas.colorspace_settings.name = "sRGB"
        bake = nodes.new("ShaderNodeTexImage")
        bake.image = atlas
        nodes.active = bake
        bpy.ops.object.bake(type="EMIT")
        target = output / f"ReplayXITripoPlayerA{kit}.png"
        atlas.filepath_raw = str(target)
        atlas.file_format = "PNG"
        atlas.save()
        nodes.remove(bake)
        reports.append({"kit": kit.lower(), "texture": target.name, "sha256": sha(target),
                        "size": [1024, 1024]})
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "PlayerAKitBake.blend"), compress=True)
    if sha(SOURCE) != SOURCE_SHA:
        raise ValueError("source changed during bake")
    report = {"sourceSHA256": SOURCE_SHA, "nearGLBSHA256": sha(args.near_glb),
              "sameGeometryForBothTeams": True, "textures": reports,
              "mask": {"shirtHeight": [.49, .87], "shortsHeight": [.345, .53],
                       "socksHeight": [.065, .305], "sourceChromaProtected": True,
                       "minimumBlueToRedRatio": .86,
                       "protectedNeck": {"minimumHeight": .835, "halfWidthMetres": .09}},
              "visualQA": "pending"}
    (output / "PlayerAKitsReport.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("REPLAYXI_PLAYER_A_KITS " + json.dumps(report))


if __name__ == "__main__":
    main()
