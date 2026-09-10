"""Blender-only 2-second synthetic assembly QA. Never run in the live GUI.

blender --background --factory-startup --python-exit-code 2 --python \
  Scripts/blender/test_match_replay_scene.py -- --player-library /path/library.blend \
  --output /path/SYNTHETIC-TEST-ONLY.blend
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
from build_match_replay import SceneBuilder, evaluate_scene_frame, export_inspection_glb, validate_manifest
from test_replayxi_blender_match_assembly import synthetic_test_manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--player-library", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--render", type=Path)
    parser.add_argument("--glb-output", type=Path)
    arguments = sys.argv[sys.argv.index("--") + 1:]
    args = parser.parse_args(arguments)
    if args.output.exists() or args.render and args.render.exists():
        raise RuntimeError("Choose new QA output paths; no existing files are overwritten")
    original_scene = bpy.context.scene
    original_objects = {obj.name: tuple(obj.location) for obj in original_scene.objects}
    document = validate_manifest(synthetic_test_manifest())
    # Fractional sample times catch NLA insertion overlap at non-integral frames.
    for frame, time in zip(document["players"][0]["keyframes"], (0.05, 0.55, 1.05)):
        frame["time"] = time
    document["players"][1]["keyframes"] = document["players"][1]["keyframes"][:1]
    document["players"][5]["keyframes"][-1]["facingDegrees"] = 180
    builder = SceneBuilder(bpy, document, 30, args.player_library.resolve())
    manifest_text = builder.finish("TEST-ONLY-NO-MATCH-REFERENCE")
    scene = builder.scene
    assert bpy.context.scene is original_scene, "The user's active scene changed"
    assert original_objects == {obj.name: tuple(obj.location) for obj in original_scene.objects}
    assert len([obj for obj in scene.objects if obj.type == "CAMERA"]) == 23
    assert len(builder.roots) == 22
    numbers = [obj for obj in scene.objects if obj.type == "FONT" and "number" in obj.name.lower()]
    assert len(numbers) == 44, f"Expected two editable numbers on each player, got {len(numbers)}"
    camera = scene.objects["POV_home-6"]
    start_camera_angle = tuple(camera.rotation_euler)
    evaluate_scene_frame(bpy, scene, 1)
    start_location = tuple(builder.roots["home-6"].location)
    assert scene.objects["Mark_qa-pass"].hide_render
    evaluate_scene_frame(bpy, scene, 31)
    assert tuple(camera.rotation_euler) == start_camera_angle
    assert abs(builder.roots["home-6"].location.x - start_location[0] - 2) < 0.0001, (
        start_location, tuple(builder.roots["home-6"].location), bpy.context.scene.name,
        scene.name, str(builder.roots["home-6"].animation_data.action)
    )
    assert not scene.objects["Mark_qa-pass"].hide_render
    endpoint = scene.objects["Mark_qa-pass"].data.splines[0].points[0].co
    assert abs(endpoint.x - 2) < 0.0001 and abs(endpoint.y + 8) < 0.0001
    assert abs(endpoint.z - 0.555) < 0.0001
    for obj in scene.objects:
        if obj.type == "ARMATURE":
            assert len(obj.data.bones) == 80
            assert obj.animation_data and (obj.animation_data.nla_tracks or obj.animation_data.action)
            for bone in obj.pose.bones:
                assert all(math.isfinite(value) for row in bone.matrix for value in row)
    evaluate_scene_frame(bpy, scene, 50)
    assert tuple(camera.rotation_euler) == start_camera_angle, "Recorded body turning forced the POV camera to turn"
    assert scene.objects["Mark_qa-pass"].hide_render
    evaluate_scene_frame(bpy, scene, 31)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.data.libraries.write(str(args.output.resolve()), {scene, manifest_text, *builder.related_texts},
                             path_remap="RELATIVE", fake_user=True)
    if args.glb_output:
        export_inspection_glb(builder, args.glb_output, 1)
    if args.render:
        args.render.parent.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(args.render.resolve())
        scene.render.image_settings.file_format = "PNG"
        scene.render.resolution_x, scene.render.resolution_y = 1280, 720
        bpy.ops.render.render(write_still=True, scene=scene.name)
    print(json.dumps({"passed": True, "artifact": str(args.output), "status": scene["replayStatus"],
                      "players": 22, "cameras": 23, "editableJerseyNumbers": len(numbers),
                      "independentPOVRotation": True, "timedTrackedAnnotations": True,
                      "existingScenePreserved": True}))


main()
