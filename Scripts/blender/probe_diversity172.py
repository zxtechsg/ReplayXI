#!/usr/bin/env python3
"""Read-only geometry and rig probe for Player Diversity 172."""
from pathlib import Path
import bpy

repo = Path(__file__).resolve().parents[2]
for label, path in (
    ("NEW", repo / "Assets/ReplayXI/PlayerDiversity171/Source/player-a-hd-source.glb"),
    ("OLD", repo / "Assets/ReplayXI/TripoFootballer/Blender/ReplayXITripoFootballMotion.blend"),
):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    else:
        bpy.ops.import_scene.gltf(filepath=str(path))
    print("PROBE", label, "objects", [(o.name, o.type) for o in bpy.data.objects])
    print("PROBE", label, "images", [(i.name, i.size[:]) for i in bpy.data.images])
    print("PROBE", label, "actions", [(a.name, tuple(a.frame_range)) for a in bpy.data.actions])
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            w = [o.matrix_world @ v.co for v in o.data.vertices]
            bounds = [(min(p[i] for p in w), max(p[i] for p in w)) for i in range(3)]
            groups = [(g.name, len(g.vertices) if hasattr(g, "vertices") else None) for g in o.vertex_groups]
            print("PROBE", label, "mesh", o.name, len(o.data.vertices), len(o.data.loop_triangles), bounds,
                  "materials", [m.name if m else None for m in o.data.materials], "uv", [u.name for u in o.data.uv_layers],
                  "groups", len(groups), "mods", [(m.type, m.object.name if m.type == "ARMATURE" and m.object else "") for m in o.modifiers])
        if o.type == "ARMATURE":
            print("PROBE", label, "rig", o.name, len(o.data.bones), o.data.pose_position,
                  "matrix", [list(row) for row in o.matrix_world],
                  "hips", [(b.name, tuple(b.head_local), tuple(b.tail_local)) for b in o.data.bones if b.name in ("mixamorig:Hips", "mixamorig:LeftUpLeg", "mixamorig:RightUpLeg", "mixamorig:Head", "mixamorig:LeftArm", "mixamorig:LeftHand")],
                  "action", o.animation_data.action.name if o.animation_data and o.animation_data.action else None)
            if label == "OLD" and o.name == "Armature":
                for b in o.data.bones:
                    print("BONE", b.name, b.parent.name if b.parent else "", *[round(x, 5) for x in b.head_local], *[round(x, 5) for x in b.tail_local])
