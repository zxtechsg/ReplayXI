#!/usr/bin/env python3
"""Offline appearance/gait candidates. Never edits a source or spends credits.

Use isolated background Blender with --mode palette|gait --output-dir NEW_DIR.
Appearance variants are fictional, not race labels or athlete likenesses.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "Assets/ReplayXI/TripoFootballer/ReplayXI_Footballer_P2_Source.glb"
MOTION = REPO / "Assets/ReplayXI/TripoFootballer/Blender/ReplayXITripoFootballMotion.blend"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def palette(output):
    if sha(SOURCE) != "e4fbdbcf98c631d283733ff9f339dd2bf01877bf8ab81756b6fe274a25c10eb5":
        raise ValueError("Source changed")
    # Reuse the existing inspected clothing shader. Only its bake resolution
    # and source colour routing change in this isolated candidate scene.
    sys.path.insert(0, str(Path(__file__).parent))
    import prepare_tripo_kit_candidate as kits
    original_argv = sys.argv
    sys.argv = [original_argv[0], "--", "--output-dir", str(output)]
    kits.main()
    sys.argv = original_argv
    obj = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    material = obj.data.materials[0]
    nodes, links = material.node_tree.nodes, material.node_tree.links
    source = next(node for node in nodes if node.type == "TEX_IMAGE" and node.image)
    tint = next(node for node in nodes if node.type == "MIX_RGB")
    separate = next(node for node in nodes if node.type == "SEPARATE_COLOR")
    surface = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
    emission = next(node for node in nodes if node.type == "EMISSION")
    # Source-position gate excludes boots, shirt, shorts and socks. Source
    # chroma excludes teeth/eyes and pale cloth even inside overlapping UV islands.
    attr = obj.data.attributes.new("ReplayXI_SkinRegion", "FLOAT", "POINT")
    zs = [vertex.co.z for vertex in obj.data.vertices]
    bottom, height = min(zs), max(zs) - min(zs)
    for vertex in obj.data.vertices:
        h = (vertex.co.z - bottom) / height
        attr.data[vertex.index].value = float(.34 < h < .50 or .52 < h < .97)
    region = nodes.new("ShaderNodeAttribute"); region.attribute_name = attr.name
    ratio = nodes.new("ShaderNodeMath"); ratio.operation = "DIVIDE"
    links.new(separate.outputs["Blue"], ratio.inputs[0]); links.new(separate.outputs["Red"], ratio.inputs[1])
    warmth = nodes.new("ShaderNodeMapRange"); warmth.clamp = True
    warmth.inputs["From Min"].default_value = .86
    warmth.inputs["From Max"].default_value = .72
    links.new(ratio.outputs[0], warmth.inputs["Value"])
    factor = nodes.new("ShaderNodeMath"); factor.operation = "MULTIPLY"
    links.new(warmth.outputs[0], factor.inputs[0]); links.new(region.outputs["Fac"], factor.inputs[1])
    skin = nodes.new("ShaderNodeMixRGB"); skin.blend_type = "MULTIPLY"
    links.new(factor.outputs[0], skin.inputs[0]); links.new(source.outputs["Color"], skin.inputs[1])
    # Preserve the original clothing mask; colour changes never bleed into kits.
    links.new(skin.outputs[0], tint.inputs[1])
    links.new(emission.outputs[0], surface.inputs["Surface"])
    profiles = [("Light", (1.07, 1.03, 1.02, 1)),
                ("Warm", (.58, .48, .40, 1)), ("Deep", (.18, .135, .105, 1))]
    reports = []
    for profile, colour in profiles:
        skin.inputs[2].default_value = colour
        for kit, kit_colour in [("Home", (1, 1, 1, 1)), ("Away", (.72, .035, .022, 1)),
                                ("Keeper", (.95, .48, .018, 1))]:
            tint.inputs[2].default_value = kit_colour
            atlas = bpy.data.images.new(f"ReplayXITripo{kit}{profile}", width=1024, height=1024, alpha=False)
            atlas.colorspace_settings.name = "sRGB"
            bake = nodes.new("ShaderNodeTexImage"); bake.image = atlas; nodes.active = bake
            bpy.ops.object.bake(type="EMIT")
            destination = output / f"ReplayXITripo{kit}{profile}.png"
            atlas.filepath_raw = str(destination); atlas.file_format = "PNG"; atlas.save()
            nodes.remove(bake)
            reports.append({"profile": profile, "kit": kit, "file": destination.name,
                            "sha256": sha(destination), "size": 1024})
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "TripoAppearance170.blend"), compress=True)
    return {"textures": reports, "additionalBaseRGBABytes": 9 * 1024 * 1024 * 4,
            "limits": "Shared original face and rig; fictional skin palettes, not ethnicity or athlete likeness."}


def gait(output):
    source_hash = sha(MOTION)
    bpy.ops.wm.open_mainfile(filepath=str(MOTION), load_ui=False)
    mesh = bpy.data.objects.get("ReplayXI_Tripo_FBX_Candidate")
    rig = next(mod.object for mod in mesh.modifiers if mod.type == "ARMATURE")
    original = bpy.data.actions["ReplayXI_Tripo_FBX_Run"]
    idle = bpy.data.actions["ReplayXI_Tripo_FBX_Idle"]
    samples = []
    rig.animation_data.action = original
    first, last = map(round, original.frame_range)
    for frame in range(first, last + 1):
        bpy.context.scene.frame_set(frame)
        samples.append({bone.name: (bone.location.copy(), bone.rotation_quaternion.copy(), bone.scale.copy())
                        for bone in rig.pose.bones})
    action = bpy.data.actions.new("ReplayXI_Tripo_RecoveryRun170")
    rig.animation_data.action = action
    # Keep leg timing and existing skin/feet unchanged. The reference shows
    # supporting players recovering with lower, less clenched arms than sprinters.
    # Blend shoulder/elbow toward relaxed idle, not a rest-pose A-pose.
    rig.animation_data.action = idle; bpy.context.scene.frame_set(1)
    relaxed = {bone.name: bone.rotation_quaternion.copy() for bone in rig.pose.bones}
    rig.animation_data.action = action
    arm_bones = {f"mixamorig:{side}{part}" for side in ("Left", "Right")
                 for part in ("Shoulder", "Arm", "ForeArm", "Hand")}
    for offset, sample in enumerate(samples):
        frame = first + offset
        for bone in rig.pose.bones:
            position, rotation, scale = sample[bone.name]
            bone.location = position; bone.scale = scale; bone.rotation_mode = "QUATERNION"
            weight = .48 if bone.name.endswith("ForeArm") else .35
            bone.rotation_quaternion = rotation.slerp(relaxed[bone.name], weight) if bone.name in arm_bones else rotation
            for channel in ("location", "rotation_quaternion", "scale"):
                bone.keyframe_insert(channel, frame=frame, group=bone.name)
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(track)
    for label, clip in (("idle", idle), ("run", action)):
        track = rig.animation_data.nla_tracks.new(); track.name = label
        track.strips.new(label, 1, clip)
    output.mkdir(parents=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig, mesh): obj.hide_set(False); obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    glb = output / "ReplayXITripoRecovery170.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                             export_skins=True, export_animations=True, export_animation_mode="NLA_TRACKS",
                             export_nla_strips=True, export_def_bones=True, export_yup=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "TripoRecovery170.blend"), compress=True)
    if sha(MOTION) != source_hash: raise ValueError("Source changed")
    sys.path.insert(0, str(REPO / "Scripts"))
    import build_replayxi_tripo_athlete as native
    document, binary = native.glb(glb)
    binding = native.inspect_skin(document, binary); binding["rootRestXZ"] = [0.0, 0.0]
    clips, offsets = native.motion_clips(document, binary, binding, 1.82)
    base_path = REPO / "ReplayXI/Resources/Players/ReplayXITripoMotion.json"
    base = json.loads(base_path.read_text())
    names = [document["nodes"][index]["name"] for index in binding["order"]]
    if names != [joint["sourceName"] for joint in base["joints"]]: raise ValueError("Joint order differs")
    recovery = next(clip for clip in clips if clip["id"] == "run")
    base_run = next(clip for clip in base["clips"] if clip["id"] == "run")
    if len(recovery["frames"]) != len(base_run["frames"]): raise ValueError("Gait phase differs")
    # Re-export/height conversion introduces sub-millimetre TRS differences.
    # Verify their bound before retaining the canonical source channels.
    # then retain the canonical source channels exactly. Only baked arm
    # rotations are new; contacts and lower-body source channels stay bit-exact.
    maximum_drift = 0
    for new, original in zip(recovery["frames"], base_run["frames"], strict=True):
        if new["time"] != original["time"]: raise ValueError("Gait timing differs")
        for channel in ("translations", "scales"):
            for a, b in zip(new[channel], original[channel], strict=True):
                delta = max(abs(x - y) for x, y in zip(a, b, strict=True))
                maximum_drift = max(maximum_drift, delta)
                if delta > .0005: raise ValueError("Unexpected export/height-conversion drift")
            new[channel] = original[channel]
        for index, name in enumerate(names):
            if name not in arm_bones:
                a, b = new["rotations"][index], original["rotations"][index]
                delta = min(max(abs(x - y) for x, y in zip(a, b, strict=True)),
                            max(abs(x + y) for x, y in zip(a, b, strict=True)))
                maximum_drift = max(maximum_drift, delta)
                if delta > .0001: raise ValueError("Unexpected non-arm rotation change")
                new["rotations"][index] = original["rotations"][index]
    supplemental = {"schemaVersion": 1, "baseMotionSHA256": sha(base_path),
                    "sourceCommit": base["sourceCommit"], "sourceClipSHA256": sha(glb),
                    "jointCount": 52, "units": "metres", "phaseOffsetRadians": 0,
                    "clip": recovery}
    destination = output / "ReplayXITripoRecoveryMotion.json"
    destination.write_text(json.dumps(supplemental, separators=(",", ":"), allow_nan=False) + "\n")
    return {"sourceBlendSHA256": source_hash, "sourceClipSHA256": sha(glb),
            "payloadSHA256": sha(destination), "payloadBytes": destination.stat().st_size,
            "frames": len(supplemental["clip"]["frames"]),
            "maximumCanonicalizedExportDrift": maximum_drift,
            "limits": "Hand-authored relaxed recovery arms; not measured motion capture. Lower-body source unchanged."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("palette", "gait"), required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    output = args.output_dir.resolve()
    if not bpy.app.background or bpy.data.filepath or output.exists() or not output.is_relative_to(REPO / ".codex-derived"):
        raise ValueError("Use factory-startup background Blender and new derived output")
    result = palette(output) if args.mode == "palette" else gait(output)
    (output / "polish170-report.json").write_text(json.dumps(result, indent=2) + "\n")
    print("REPLAYXI_POLISH170 " + json.dumps(result))


if __name__ == "__main__": main()
