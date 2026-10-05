# Player A integration — 5 Oct 2026

One new fictional identity is now used by selected players on **both teams**. The other four concepts remain image references. No Tripo credits were spent in this integration; the shared-credit reserve still blocks more paid jobs.

## Shipped

- Separate 52-joint body, face and hair. Same 1.82 m baseline scale for both teams.
- 10,289-triangle near mesh; 2,744-triangle distance mesh.
- Home, away and keeper kits, three shared 1024px atlases.
- Existing idle/run retargeted to the new T-rest; native kicking, head aim, arm, goalkeeper and impact adapters retained.
- Explicit hand weights prevent folded wrists/fingers. Two-sided cloth closes native backface pinholes without duplicate geometry.
- Own hash-bound motion and contact surfaces. A 12 mm proxy margin covers the measured small floor-sampling gap.
- Atomic admission: an incomplete/corrupt new asset set falls back to the existing player. No save-format, annotation, replay-time or track changes.
- Production selection uses the existing deterministic `.deep` appearance slot, independent of name/ID. This is fictional casting, not a claim about a real player's ancestry or likeness.

## Checks

36 focused native tests passed on visionOS 26.5 Simulator. They cover both LODs/teams, actual weighted-mesh grounding, kicking/header/keeper contact, impacts, rewind, scene selection, fallback, head/arm behaviour and warm cache reuse. Six native captures were inspected. Unsigned visionOS Release build passed.

The original contact test picked the wrong foot. That assertion was corrected. Run-flight phases may lift both feet: the test now verifies actual source flight before allowing 16 cm clearance; walk/stance remains bounded at 8 cm. The 5 mm penetration limit was not relaxed.

Base decoded texture cost rises by 12 MiB to 96 MiB. These are base RGBA levels, not total GPU memory or measured headset FPS. No new per-frame asset loads or texture preparation were observed. Physical-headset QA is still needed.

Evidence lives in `Assets/ReplayXI/PlayerDiversity171/Audit/`; final native previews are in its `Preview/` folder. `Blender/PlayerA-Rig.blend` is editable and its file-backed textures are packed. The original HD GLB stays unchanged.

## Rebuild

Use fresh output dirs beneath `.codex-derived`. The scripts refuse to overwrite an existing build folder.

1. Run Blender 5.2.1 in background/factory mode with `Scripts/blender/build_diversity172_trest.py -- --output-dir <rig-dir>`. This reads the pinned HD source and the existing Tripo motion `.blend`; it produces near/low/motion GLBs and an editable rig.
2. Run `Scripts/blender/render_diversity172_poses.py -- --blend <rig-dir>/PlayerA-Rig.blend --output-dir <pose-dir>`. Also use `--lod low` with a separate output dir. Inspect rest, idle, run, head turn and arm raise.
3. Run `Scripts/blender/bake_replayxi_diversity172_kits.py -- --near-glb <rig-dir>/PlayerA-Near.glb --output <kits-dir>`.
4. Run `Scripts/blender/preview_replayxi_diversity172_kits.py -- --near-glb <rig-dir>/PlayerA-Near.glb --kits <kits-dir>`. Run `audit_replayxi_diversity172_skin_pixels.py` with the same inputs and `--output-report <kits-dir>/PlayerASkinPixelsAudit.json`. Inspect matched source/kit renders before recording visual approval in the kit report.
5. With Blender's bundled Python, run `Scripts/build_replayxi_diversity172.py --near-glb <rig-dir>/PlayerA-Near.glb --low-glb <rig-dir>/PlayerA-Low.glb --motion-glb <rig-dir>/PlayerA-Motion.glb --kits-report <kits-dir>/PlayerAKitsReport.json --output <native-dir>`. Keep source normals; area-weighted normals increased the measured disagreements.
6. Verify the USD, decoded-pixel and source audits. Copy only the eight runtime files to `ReplayXI/Resources/Players`, update `ReplayTripoDiversityAssets.swift` from `runtimeManifest`, then repeat native tests and visual checks. Keep the two-sided material setting specific to this body.

Local tools: `/Applications/Blender.app/Contents/MacOS/Blender`, `/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13`, `swiftc`, `/usr/bin/usdzip`, `/usr/bin/usdchecker`. No network or Tripo call is needed to rebuild.

## Limits

This is one added identity, not five new 3D models or EAFC-quality animation. The low LOD remains coarse up close. New facial animation, measured mocap and the separate slow-run clip have not been authored for this rig. Existing football pose adapters supply the other actions. Further paid generation remains paused below the shared-credit reserve.
