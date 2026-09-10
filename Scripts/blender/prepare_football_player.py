#!/usr/bin/env python3
"""Build a self-contained MIT Rocketbox player library in an isolated Blender.

Run with Blender --factory-startup --background --python this_file -- ... .
The FBX-derived, audited glTF supplies geometry; the USD-order motion contract
supplies named rest joints and sampled idle/run poses. No FBX import heuristics
or animation retargeting are needed. Outputs must stay under .codex-derived.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import zipfile

import bpy
from mathutils import Matrix, Quaternion, Vector

SCRIPTS = Path(__file__).resolve().parents[1]
REPOSITORY = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))
from build_replayxi_rocketbox_pilot import (  # noqa: E402
    EXPECTED_ASSIMP_EXPORTS, MODEL_RELATIVE, read_accessor, sha256_file,
)
from fetch_replayxi_rocketbox_pilot import PILOT_ASSETS, audit_directory  # noqa: E402

USD_TO_BLENDER = Matrix.Rotation(math.pi / 2, 4, "X")
ACTION_NAMES = {"idle": "ReplayXI_Idle", "run": "ReplayXI_Run_InPlace"}
KIT_COLOURS = {"Home": (0.035, 0.08, 0.13, 1),
               "Away": (0.97, 0.97, 0.98, 1),
               "Keeper": (0.035, 0.08, 0.13, 1)}


def matrix(translation, rotation, scale):
    x, y, z, w = rotation
    return Matrix.LocRotScale(Vector(translation), Quaternion((w, x, y, z)),
                              Vector(scale))


def rest_matrices(joints):
    local, world = [], []
    for index, joint in enumerate(joints):
        parent = joint["parentIndex"]
        if parent >= index or parent < -1:
            raise ValueError("Motion joints must be parent-first with valid indices")
        transform = matrix(joint["translation"], joint["rotation"], joint["scale"])
        local.append(transform)
        world.append(world[parent] @ transform if parent >= 0 else transform)
    return local, world


def link_object(collection, name, data=None):
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    return obj


def load_image(path, non_colour=False):
    image = bpy.data.images.load(str(path), check_existing=True)
    image.colorspace_settings.name = "Non-Color" if non_colour else "sRGB"
    image.pack()
    return image


def textured_material(name, colour, normal, roughness):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Specular IOR Level"].default_value = 0.23
    base = nodes.new("ShaderNodeTexImage")
    base.image = load_image(colour)
    material.node_tree.links.new(base.outputs["Color"], shader.inputs["Base Color"])
    bump = nodes.new("ShaderNodeTexImage")
    bump.image = load_image(normal, non_colour=True)
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.55
    material.node_tree.links.new(bump.outputs["Color"], normal_map.inputs["Color"])
    material.node_tree.links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
    return material


def flat_material(name, colour, roughness=0.8):
    material = bpy.data.materials.new(name)
    material.diffuse_color = colour
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = colour
    shader.inputs["Roughness"].default_value = roughness
    return material


def create_armature(collection, root, motion, world_rest):
    data = bpy.data.armatures.new("ReplayXI_Rocketbox_Skeleton")
    rig = link_object(collection, "ReplayXI_Home_Rig", data)
    rig.parent = root
    rig.show_in_front = True
    rig["replayxi_kind"] = "player_rig"
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bones = []
    for index, joint in enumerate(motion["joints"]):
        bone = data.edit_bones.new(joint["sourceName"])
        bone.length = 0.055  # Display length only; never changes skin transforms.
        # A new edit bone has zero length. Set a length BEFORE assigning its
        # matrix, otherwise Blender silently loses its intended orientation.
        bone.matrix = USD_TO_BLENDER @ world_rest[index]
        parent = joint["parentIndex"]
        if parent >= 0:
            bone.parent = bones[parent]
        bone.use_connect = False
        bones.append(bone)
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def create_meshes(collection, root, rig, model, payload):
    source_joints = [model["nodes"][node]["name"]
                     for node in model["skins"][0]["joints"]]
    result = []
    for index, primitive in enumerate(model["meshes"][0]["primitives"]):
        name = "Body" if index == 0 else "Head"
        attributes = primitive["attributes"]
        points = read_accessor(model, payload, attributes["POSITION"])
        indices = [value[0] for value in read_accessor(model, payload, primitive["indices"])]
        uv = read_accessor(model, payload, attributes["TEXCOORD_0"])
        normals = read_accessor(model, payload, attributes["NORMAL"])
        joints = read_accessor(model, payload, attributes["JOINTS_0"])
        weights = read_accessor(model, payload, attributes["WEIGHTS_0"])
        mesh = bpy.data.meshes.new(f"ReplayXI_{name}_SharedMesh")
        mesh.from_pydata([tuple(value / 100 for value in point) for point in points], [],
                         [indices[offset:offset + 3] for offset in range(0, len(indices), 3)])
        mesh.update()
        uv_layer = mesh.uv_layers.new(name="UVMap")
        for loop in mesh.loops:
            u, v = uv[loop.vertex_index]
            uv_layer.data[loop.index].uv = (u, 1 - v)
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        # Keep source split normals: flattened shading was a preview issue, not
        # a reason to discard the carefully authored lip/eyelid/cloth normals.
        mesh.normals_split_custom_set_from_vertices(normals)
        obj = link_object(collection, f"ReplayXI_Home_{name}", mesh)
        # Parenting to the rig is required by glTF skin export and gives copied
        # instances an unambiguous owning armature (the modifier agrees).
        obj.parent = rig
        obj["replayxi_kind"] = name.lower()
        for source_name in source_joints:
            obj.vertex_groups.new(name=source_name)
        for vertex_index, (bone_indices, bone_weights) in enumerate(zip(joints, weights)):
            total = sum(bone_weights)
            if not math.isfinite(total) or abs(total - 1) > 0.001:
                raise ValueError(f"Invalid skin weights at {name} vertex {vertex_index}")
            for bone_index, weight in zip(bone_indices, bone_weights):
                if weight > 0:
                    obj.vertex_groups[int(bone_index)].add([vertex_index], weight / total, "REPLACE")
        modifier = obj.modifiers.new("ReplayXI_Skin", "ARMATURE")
        modifier.object = rig
        modifier.use_deform_preserve_volume = False  # Source skin is linear blend.
        result.append(obj)
    return result


def action_curves(action):
    """Blender 4.4+ layered actions; retained fallback supports older Blender."""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    return [curve for layer in action.layers for strip in layer.strips
            for bag in strip.channelbags for curve in bag.fcurves]


def create_actions(rig, motion):
    rig.animation_data_create()
    rest_local = []
    for joint in motion["joints"]:
        bone = rig.data.bones[joint["sourceName"]]
        rest_local.append(bone.parent.matrix_local.inverted() @ bone.matrix_local
                          if bone.parent else bone.matrix_local.copy())
    actions = {}
    for clip in motion["clips"]:
        action = bpy.data.actions.new(ACTION_NAMES[clip["id"]])
        action.use_fake_user = True
        rig.animation_data.action = action
        for frame in clip["frames"]:
            frame_number = 1 + frame["time"] * clip["fps"]
            for index, joint in enumerate(motion["joints"]):
                target = matrix(frame["translations"][index], frame["rotations"][index],
                                frame["scales"][index])
                if joint["parentIndex"] < 0:
                    target = USD_TO_BLENDER @ target
                bone = rig.pose.bones[joint["sourceName"]]
                bone.rotation_mode = "QUATERNION"
                bone.matrix_basis = rest_local[index].inverted() @ target
                for channel in ("location", "rotation_quaternion", "scale"):
                    bone.keyframe_insert(channel, frame=frame_number, group=bone.name)
        for curve in action_curves(action):
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"
        action["replayxi_clip_id"] = clip["id"]
        action["replayxi_duration_seconds"] = clip["durationSeconds"]
        action["replayxi_fps"] = clip["fps"]
        action["replayxi_in_place"] = True
        actions[clip["id"]] = action
    rig.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(1)
    return actions


def attach_number(collection, root, rig, motion, world_rest, side, material):
    anchor = motion["numberAnchors"]
    chest_index = next(index for index, joint in enumerate(motion["joints"])
                       if joint["name"] == anchor["joint"])
    bone_name = motion["joints"][chest_index]["sourceName"]
    data = bpy.data.curves.new(f"ReplayXI_Number{side.title()}", "FONT")
    data.body = "7"
    data.align_x = "CENTER"
    data.align_y = "CENTER"
    data.size = 0.11 if side == "front" else 0.23
    data.extrude = 0.0003
    data.resolution_u = 4
    data.materials.append(material)
    obj = link_object(collection, f"ReplayXI_Home_Number{side.title()}", data)
    obj["replayxi_kind"] = "jersey_number"
    obj["replayxi_side"] = side
    obj["replayxi_chest_anchor"] = anchor[side]
    rest_bone = rig.data.bones[bone_name]
    position = USD_TO_BLENDER @ (world_rest[chest_index] @ Vector((*anchor[side], 1)))
    desired = Matrix.Translation(position.to_3d()) @ Matrix.Rotation(math.pi / 2, 4, "X")
    if side == "back":
        # Rotate around world Z, keeping text upright and its outward face +Y.
        desired = Matrix.Translation(position.to_3d()) @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X")
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    # Blender BONE parenting includes the bone-tail offset. Cancel the bind
    # parent exactly; subsequent poses follow the chest without drifting.
    bind_parent = rest_bone.matrix_local @ Matrix.Translation((0, rest_bone.length, 0))
    obj.matrix_parent_inverse = bind_parent.inverted()
    obj.matrix_basis = desired
    return obj


def duplicate_kit(source, kit, materials, number_material):
    collection = bpy.data.collections.new(f"ReplayXI_{kit}")
    bpy.context.scene.collection.children.link(collection)
    copies = {}
    for original in source.objects:
        obj = original.copy()
        obj.name = original.name.replace("_Home_", f"_{kit}_")
        if original.type == "FONT":
            obj.data = original.data.copy()  # Each player must own editable digits.
            obj.data.materials.clear()
            obj.data.materials.append(number_material)
        collection.objects.link(obj)
        copies[original] = obj
    for original, obj in copies.items():
        if original.parent in copies:
            obj.parent = copies[original.parent]
        # Reparenting an object copy can invalidate Blender's cached bone
        # transform. Restore the explicit local and parent-inverse matrices.
        obj.matrix_parent_inverse = original.matrix_parent_inverse.copy()
        obj.matrix_basis = original.matrix_basis.copy()
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE" and modifier.object in copies:
                modifier.object = copies[modifier.object]
        kind = obj.get("replayxi_kind")
        if kind in {"body", "head"}:
            obj.material_slots[0].link = "OBJECT"
            obj.material_slots[0].material = materials[kind]
    return collection


def verify_deformation(rig, mesh_objects, number_objects, motion, world_rest, actions):
    """Compare evaluated Blender skin and attached numbers against exact LBS."""
    report = {"maximumSkinPositionErrorMetres": 0.0,
              "maximumNumberAnchorErrorMetres": 0.0, "checkedPoses": [],
              "runVertexDisplacementMetres": 0.0}
    inverse_rest = [(USD_TO_BLENDER @ value).inverted() for value in world_rest]
    chest_index = next(index for index, joint in enumerate(motion["joints"])
                       if joint["name"] == motion["numberAnchors"]["joint"])
    joint_map = {joint["sourceName"]: index for index, joint in enumerate(motion["joints"])}
    previous_run = None
    for clip in motion["clips"]:
        rig.animation_data.action = actions[clip["id"]]
        for sample_index in sorted({0, len(clip["frames"]) // 3, len(clip["frames"]) - 1}):
            frame = clip["frames"][sample_index]
            bpy.context.scene.frame_set(1 + round(frame["time"] * clip["fps"]))
            bpy.context.view_layer.update()
            current = []
            for index, joint in enumerate(motion["joints"]):
                local = matrix(frame["translations"][index], frame["rotations"][index], frame["scales"][index])
                current.append(current[joint["parentIndex"]] @ local if joint["parentIndex"] >= 0 else USD_TO_BLENDER @ local)
            graph = bpy.context.evaluated_depsgraph_get()
            run_points = []
            for obj in mesh_objects:
                evaluated = obj.evaluated_get(graph)
                result = evaluated.to_mesh()
                try:
                    for vertex in obj.data.vertices:
                        if vertex.index % 37:
                            continue
                        position = Vector((0, 0, 0))
                        for group in vertex.groups:
                            index = joint_map[obj.vertex_groups[group.group].name]
                            position += (current[index] @ inverse_rest[index] @ vertex.co) * group.weight
                        actual = result.vertices[vertex.index].co
                        error = (actual - position).length
                        report["maximumSkinPositionErrorMetres"] = max(report["maximumSkinPositionErrorMetres"], error)
                        if not all(math.isfinite(value) for value in actual):
                            raise RuntimeError("Skin deformation contains a non-finite vertex")
                        run_points.append(actual.copy())
                finally:
                    evaluated.to_mesh_clear()
            for obj in number_objects:
                side = obj["replayxi_side"]
                expected = rig.matrix_world @ current[chest_index] @ Vector((*motion["numberAnchors"][side], 1))
                actual = obj.evaluated_get(graph).matrix_world.translation
                error = (expected.to_3d() - actual).length
                report["maximumNumberAnchorErrorMetres"] = max(report["maximumNumberAnchorErrorMetres"], error)
            if clip["id"] == "run":
                if previous_run:
                    report["runVertexDisplacementMetres"] = max(report["runVertexDisplacementMetres"],
                        max((one - two).length for one, two in zip(previous_run, run_points)))
                previous_run = run_points
            report["checkedPoses"].append(f"{clip['id']}:{sample_index}")
    if report["maximumSkinPositionErrorMetres"] > 0.0005:
        raise RuntimeError(f"Blender skin differs from reference LBS: {report}")
    if report["maximumNumberAnchorErrorMetres"] > 0.0005:
        raise RuntimeError(f"Jersey number slipped from its chest anchor: {report}")
    if report["runVertexDisplacementMetres"] < 0.15:
        raise RuntimeError("Run clip did not visibly deform the player")
    rig.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(1)
    return report


def render_preview(output, rig, actions):
    """Temporary QA scene content is added only after the clean library save."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 800
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.world.color = (0.15, 0.15, 0.15)
    scene.view_settings.view_transform = "AgX"
    qa = bpy.data.collections.new("ReplayXI_QA_Only")
    scene.collection.children.link(qa)
    camera = link_object(qa, "QA_Camera", bpy.data.cameras.new("QA_Camera"))
    camera.location = (2.4, -4.6, 1.9)
    camera.rotation_euler = (Vector((0, 0, 0.95)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 62
    scene.camera = camera
    for name, location, energy, size in [
            ("Key", (-3, -4, 5), 450, 4), ("Fill", (3, -1, 3), 220, 3),
            ("Rim", (1, 3, 4), 420, 3)]:
        light = link_object(qa, name, bpy.data.lights.new(name, "AREA"))
        light.location = location
        light.rotation_euler = (Vector((0, 0, 1)) - light.location).to_track_quat("-Z", "Y").to_euler()
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
    floor = bpy.data.meshes.new("QA_Floor")
    floor.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    floor.materials.append(flat_material("QA_Grass", (0.027, 0.08, 0.053, 1)))
    link_object(qa, "QA_Floor", floor)
    for clip_id, frame in [("idle", 1), ("run", 7)]:
        rig.animation_data.action = actions[clip_id]
        scene.frame_set(frame)
        scene.render.filepath = str(output / f"ReplayXIFootballPlayer-{clip_id}.png")
        bpy.ops.render.render(write_still=True)


def export_glbs(output):
    """Safe-mode MCP can import these binary glTF files without Python access."""
    artifacts = {}
    layer = bpy.context.scene.view_layers[0].layer_collection
    for child in layer.children:
        child.exclude = False
    for kit in KIT_COLOURS:
        bpy.ops.object.select_all(action="DESELECT")
        collection = bpy.data.collections[f"ReplayXI_{kit}"]
        for obj in collection.objects:
            obj.select_set(True)
        rig = next(obj for obj in collection.objects if obj.type == "ARMATURE")
        bpy.context.view_layer.objects.active = rig
        path = output / f"ReplayXIFootballPlayer{kit}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB",
            use_selection=True, export_animations=True, export_animation_mode="ACTIONS",
            export_anim_single_armature=True, export_skins=True, export_yup=True,
            export_extras=True, export_cameras=False, export_lights=False)
        payload = path.read_bytes()
        magic, version, byte_count, json_length, chunk_type = struct.unpack_from("<IIIII", payload)
        if (magic, version, byte_count, chunk_type) != (0x46546C67, 2, len(payload), 0x4E4F534A):
            raise RuntimeError("GLB exporter returned an invalid header")
        manifest = json.loads(payload[20:20 + json_length])
        clips = [animation.get("name", "") for animation in manifest.get("animations", [])]
        if len(manifest.get("skins", [])) != 1 or len(manifest["skins"][0]["joints"]) != 80:
            raise RuntimeError(f"{kit} GLB lost the full body skin")
        if len(clips) != 2 or not all(any(name.startswith(action) for name in clips)
                                    for action in ACTION_NAMES.values()):
            raise RuntimeError(f"{kit} GLB lost idle/run actions: {clips}")
        if len(manifest.get("meshes", [])) != 4:
            raise RuntimeError(f"{kit} GLB lost body, head or a jersey number")
        artifacts[kit.lower()] = {"path": str(path), "bytes": len(payload), "clips": clips,
                                  "sha256": hashlib.sha256(payload).hexdigest()}
    bpy.ops.object.select_all(action="DESELECT")
    for kit in ("Away", "Keeper"):
        layer.children[f"ReplayXI_{kit}"].exclude = True
    return artifacts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--staged", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output.resolve()
    if not output.is_relative_to((REPOSITORY / ".codex-derived").resolve()):
        raise ValueError("Generated Blender artifacts must stay under .codex-derived")
    if bpy.data.filepath:
        raise RuntimeError("Refusing to modify an open .blend; run --factory-startup --background")
    errors = audit_directory(args.source, PILOT_ASSETS)
    if errors:
        raise RuntimeError("Rocketbox source audit failed: " + "; ".join(errors))
    if sha256_file(args.source / "model.gltf") != EXPECTED_ASSIMP_EXPORTS["model.gltf"]:
        raise RuntimeError("Geometry manifest differs from audited Assimp export")
    model = json.loads((args.source / "model.gltf").read_text())
    motion_path = args.staged / "ReplayXIRocketboxMotion.json"
    motion = json.loads(motion_path.read_text())
    if motion["schemaVersion"] != 1 or len(motion["joints"]) != 80:
        raise RuntimeError("Unsupported Rocketbox motion contract")
    payload = (args.source / "model.bin").read_bytes()
    if len(payload) != model["buffers"][0]["byteLength"]:
        raise RuntimeError("Geometry buffer is incomplete")
    output.mkdir(parents=True, exist_ok=True)
    texture_dir = output / "Textures"
    texture_dir.mkdir(exist_ok=True)
    with zipfile.ZipFile(args.staged / "ReplayXIRocketboxAthlete.usdz") as package:
        for name in ("body_normal.png", "head_normal.png"):
            (texture_dir / name).write_bytes(package.read(f"0/{name}"))
    # This only clears the factory-startup file of this isolated background job.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if not collection.objects:
            bpy.data.collections.remove(collection)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 83
    collection = bpy.data.collections.new("ReplayXI_Home")
    scene.collection.children.link(collection)
    root = link_object(collection, "ReplayXI_Home_Root")
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.25
    root["replayxi_kind"] = "player_root"
    root["replayxi_forward"] = "-Y"
    root.location.z = -motion["geometry"]["restMinY"]
    local_rest, world_rest = rest_matrices(motion["joints"])
    rig = create_armature(collection, root, motion, world_rest)
    meshes = create_meshes(collection, root, rig, model, payload)
    head_texture = REPOSITORY / "ReplayXI/Resources/Players/ReplayXIAthleteSkin0.png"
    head_material = textured_material("ReplayXI_Head_Skin0", head_texture,
                                      texture_dir / "head_normal.png", 0.73)
    all_materials = {}
    for kit in KIT_COLOURS:
        all_materials[kit] = {
            "body": textured_material(f"ReplayXI_{kit}_Kit_Skin0",
                args.staged / f"ReplayXIRocketbox{kit}Skin0.png", texture_dir / "body_normal.png", 0.80),
            "head": head_material,
            "number": flat_material(f"ReplayXI_{kit}_Number", KIT_COLOURS[kit]),
        }
    for obj in meshes:
        obj.data.materials.append(all_materials["Home"][obj["replayxi_kind"]])
    numbers = [attach_number(collection, root, rig, motion, world_rest, side,
                             all_materials["Home"]["number"]) for side in ("front", "back")]
    actions = create_actions(rig, motion)
    verification = verify_deformation(rig, meshes, numbers, motion, world_rest, actions)
    for kit in ("Away", "Keeper"):
        duplicate_kit(collection, kit, all_materials[kit], all_materials[kit]["number"])
    # A single visible template prevents overlapping players on first open.
    # Collections themselves stay render-enabled for safe appending elsewhere.
    for kit in ("Away", "Keeper"):
        scene.view_layers[0].layer_collection.children[f"ReplayXI_{kit}"].exclude = True
    notice = (args.staged / "LICENSE-ROCKETBOX-MIT.txt").read_text()
    bpy.data.texts.new("LICENSE-ROCKETBOX-MIT.txt").write(notice)
    bpy.data.texts.new("REPLAYXI_PLAYER_README").write(
        "MIT Microsoft Rocketbox; original neutral kits. Z-up metres, forward -Y.\n"
        "Append ReplayXI_Home/Away/Keeper collection; duplicate ALL objects and remap parents/skin modifiers.\n"
        "Mesh and armature datablocks may be shared. Copy FONT data before setting each jersey number.\n"
        "ReplayXI_Idle: frames1-83; ReplayXI_Run_InPlace: frames1-19; 30fps.\n"
        "Template root Z includes sole grounding offset; keep it when placing on pitch.\n")
    library = output / "ReplayXIFootballPlayers.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(library), compress=True)
    glbs = export_glbs(output)
    report = {
        "schemaVersion": 1, "library": str(library), "glbPreviews": glbs,
        "blenderVersion": bpy.app.version_string,
        "source": "Microsoft Rocketbox Sports_Male_02", "license": "MIT",
        "sourceCommit": motion["sourceCommit"], "sourceFbxSha256": sha256_file(args.source / MODEL_RELATIVE),
        "motionJsonSha256": hashlib.sha256(motion_path.read_bytes()).hexdigest(),
        "units": "metres", "up": "+Z", "forward": "-Y", "fps": 30,
        "nominalHeightMetres": motion["geometry"]["nominalHeight"],
        "rootSoleOffsetMetres": -motion["geometry"]["restMinY"],
        "collections": {kit.lower(): f"ReplayXI_{kit}" for kit in KIT_COLOURS},
        "actions": {clip["id"]: {"name": ACTION_NAMES[clip["id"]], "frameStart": 1,
            "frameEnd": 1 + round(clip["durationSeconds"] * clip["fps"]),
            "durationSeconds": clip["durationSeconds"], "inPlace": True}
            for clip in motion["clips"]},
        "semanticBoneNames": {key: next(joint["sourceName"] for joint in motion["joints"]
                                if joint["name"] == value) for key, value in motion["semanticJoints"].items()},
        "geometry": motion["geometry"], "verification": verification,
        "jerseyNumbers": {"kind": "FONT", "boneParent": "Bip01 Spine2",
                          "frontSizeMetres": 0.11, "backSizeMetres": 0.23,
                          "duplicateFontDataPerPlayer": True},
        "appendGuidance": "Copy collection objects; remap parents and ARMATURE modifiers; preserve matrix_parent_inverse for bone-parented numbers. Share mesh/armature data; copy FONT data. Preserve root Z offset. Choose and assign the correct action slot on each rig before NLA use.",
        "limitations": ["One audited body type", "Generic human run, not football motion capture",
                        "Idle/run only; no tackling or kicking clip", "No physics ragdoll"]}
    (output / "ReplayXIFootballPlayers.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_PLAYER_LIBRARY " + json.dumps(report))
    if args.render:
        render_preview(output, rig, actions)


if __name__ == "__main__":
    main()
